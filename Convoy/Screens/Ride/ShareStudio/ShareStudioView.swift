// ShareStudioView.swift — turn a finished ride into a ready-to-post card.
// Opens on Convoy Classic, ready to share in one tap. Swipe for the next design (neighbours sit behind,
// smaller and faded). Format chips re-flow the card; Customize changes stats/title/privacy; "Your photo"
// lets the rider drag the route & stats over their own shot. Exports a PNG (1080 px wide).
import SwiftUI
import PhotosUI
import Photos

struct ShareStudioView: View {
    let data: RideCardData
    /// The recorded ride (needed to post the card to the Crew feed). nil for previews.
    var log: RideLog? = nil
    var onClose: () -> Void
    @Environment(AppState.self) private var app

    @State private var design: CardDesign? = .satellite
    @State private var format: CardFormat = .story
    @State private var options = CardOptions()
    @State private var photo: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var pickingPhoto = false
    @State private var filmPhotos: [UIImage] = []
    @State private var filmItems: [PhotosPickerItem] = []
    @State private var pickingFilm = false
    @State private var postingCard = false
    @State private var customizing = false
    @State private var sharing = false
    @State private var adjusting = false
    @State private var moveTarget: MoveTarget = .stats
    @State private var dragStart: CGSize?
    @State private var satellite = SatelliteLoader()
    @State private var toast: String?

    enum MoveTarget: String, CaseIterable { case stats = "Stats", route = "Route" }

    private var current: CardDesign { design ?? .classic }
    private var needsPhoto: Bool { (current == .photo && photo == nil) || (current == .filmStrip && filmPhotos.isEmpty) }
    /// Rides under 100 m aren't counted and can't be posted (the server refuses them).
    private var canPost: Bool { log.map { $0.rejectedReason == nil && $0.distanceM >= 100 } ?? false }

    var body: some View {
        GeometryReader { geo in
            let cardW = cardWidth(in: geo.size)
            ZStack {
                backdrop
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 8)
                    carousel(cardW: cardW, screenW: geo.size.width)
                    Spacer(minLength: 8)
                    caption
                    if adjusting { adjustBar } else { formatChips.padding(.top, 14) }
                    actions.padding(.top, 16)
                }
                .padding(.bottom, 12)
                if let toast { toastView(toast) }
            }
        }
        .environment(\.colorScheme, .dark)
        .task(id: format) { await satellite.load(path: data.displayPath(trim: options.trimEnds), focus: data.endCoord, size: format.canvas) }
        .onChange(of: options.trimEnds) { _, _ in
            Task { await satellite.load(path: data.displayPath(trim: options.trimEnds), focus: data.endCoord, size: format.canvas) }
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: photoItem) { _, item in Task { await loadPhoto(item) } }
        .photosPicker(isPresented: $pickingFilm, selection: $filmItems, maxSelectionCount: 3, matching: .images,
                      preferredItemEncoding: .compatible)
        .onChange(of: filmItems) { _, items in Task { await loadFilm(items) } }
        .sheet(isPresented: $postingCard) {
            if let log {
                PostCardSheet(log: log, image: render(), onPosted: { showToast("Posted to your Crew feed with this card") })
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color(hex: 0x141416))
            }
        }
        .sheet(isPresented: $customizing) {
            CardCustomizeSheet(options: $options, design: current, data: data, photo: photo,
                               onChangePhoto: { customizing = false; if current == .filmStrip { pickingFilm = true } else { pickingPhoto = true } },
                               onAdjust: { customizing = false; withAnimation(.snappy) { adjusting = true } })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: 0x141416))
        }
        .sheet(isPresented: $sharing) {
            CardShareSheet(format: format, trim: $options.trimEnds,
                           canPost: canPost, alreadyPosted: log?.postId != nil,
                           onPost: { sharing = false; Task { try? await Task.sleep(for: .milliseconds(350)); postingCard = true } },
                           render: { render() }, renderSticker: { render(design: .sticker) },
                           onSaved: { showToast("Saved to Photos · \(format.pixelLabel)") },
                           onCopied: { showToast("Sticker copied — paste it onto your Story") })
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: 0x17171A))
        }
    }

    // MARK: Layout

    private func cardWidth(in size: CGSize) -> CGFloat {
        let maxH = max(300, size.height - 330)
        let maxW = size.width - 120
        let c = format.canvas
        return min(maxW, maxH * c.width / c.height)
    }

    private var backdrop: some View {
        ZStack {
            Color(hex: 0x0B0B0D)
            card(current).scaleEffect(1.6).blur(radius: 60).opacity(0.55)
            Color.black.opacity(0.35)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            RoundIconButton(symbol: "xmark", dark: false) { onClose() }
            Spacer()
            Text("Share ride").cvText(17, .semibold, inter: true)
            Spacer()
            RoundIconButton(symbol: "arrow.down.to.line", dark: false) { Task { await quickSave() } }
                .disabled(needsPhoto).opacity(needsPhoto ? 0.4 : 1)
                .accessibilityLabel("Save image")
        }
        .padding(.horizontal, 20).padding(.top, 4)
    }

    private func carousel(cardW: CGFloat, screenW: CGFloat) -> some View {
        let c = format.canvas
        let cardH = cardW * c.height / c.width
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(CardDesign.allCases) { d in
                    card(d, preview: true)
                        .scaleEffect(cardW / c.width, anchor: .topLeading)
                        .frame(width: cardW, height: cardH, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                        .overlay { if d == .photo && photo == nil { choosePhotoOverlay } }
                        .overlay { if d == .filmStrip && filmPhotos.isEmpty { chooseFilmOverlay } }
                        .overlay { if adjusting && d == current { adjustOverlay(cardW: cardW) } }
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                        .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                            view.scaleEffect(phase.isIdentity ? 1 : 0.84).opacity(phase.isIdentity ? 1 : 0.38)
                        }
                        .id(d)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $design)
        .scrollIndicators(.hidden)
        .scrollDisabled(adjusting)
        .contentMargins(.horizontal, (screenW - cardW) / 2, for: .scrollContent)
        .frame(height: cardH + 10)
        .onChange(of: design) { _, _ in UISelectionFeedbackGenerator().selectionChanged(); adjusting = false }
    }

    private func card(_ d: CardDesign, preview: Bool = false) -> RideCardCanvas {
        RideCardCanvas(design: d, data: data, options: options, format: format, photo: photo,
                       satellite: satellite.image, filmPhotos: filmPhotos, previewChecker: preview)
    }

    private var chooseFilmOverlay: some View {
        VStack(spacing: 10) {
            Button { pickingFilm = true } label: {
                Label("Add ride photos", systemImage: "film.stack")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.onAccent)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(.white, in: Capsule())
            }
            Text("Pick up to 3 photos from this ride.").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.75))
        }
        .padding(12)
    }

    private var choosePhotoOverlay: some View {
        VStack(spacing: 10) {
            Button { pickingPhoto = true } label: {
                Label("Choose a photo", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.onAccent)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(.white, in: Capsule())
            }
            Text("From this ride or your library.\nRoute & stats sit on top — move them anywhere.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(12)
    }

    private var caption: some View {
        VStack(spacing: 5) {
            Text(current.title).cvText(16, .bold, inter: true)
            Text(adjusting ? "Drag on the card to move the \(moveTarget.rawValue.lowercased())" : current.subtitle)
                .cvText(12, color: CV.text.opacity(0.55), inter: true)
            HStack(spacing: 5) {
                ForEach(CardDesign.allCases) { d in
                    Capsule().fill(d == current ? Color(hex: 0xFF3B30) : Color.white.opacity(0.25))
                        .frame(width: d == current ? 16 : 5, height: 5)
                }
            }
            .padding(.top, 6)
            .animation(.snappy, value: current)
        }
    }

    private var formatChips: some View {
        HStack(spacing: 8) {
            ForEach(CardFormat.allCases) { f in
                Button {
                    withAnimation(.snappy) { format = f }
                } label: {
                    Text(f.title).cvText(12, .semibold, color: format == f ? CV.onAccent : CV.text.opacity(0.8), inter: true)
                        .padding(.horizontal, 11).frame(height: 32)
                        .background(format == f ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(format == f ? 0 : 0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if needsPhoto {
                secondary("Library", "photo.on.rectangle") { if current == .filmStrip { pickingFilm = true } else { pickingPhoto = true } }
            } else if adjusting {
                secondary("Auto layout", "arrow.counterclockwise") { withAnimation(.snappy) { options.autoLayout() } }
            } else {
                secondary("Customize", "slider.horizontal.3") { customizing = true }
            }
            Button {
                if adjusting { withAnimation(.snappy) { adjusting = false } } else { sharing = true }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: adjusting ? "checkmark" : "square.and.arrow.up").font(.system(size: 14, weight: .bold))
                    Text(adjusting ? "Done" : "Share").cvText(16, .bold, color: CV.onAccent, inter: true)
                }
                .foregroundStyle(CV.onAccent)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(Color(hex: 0xF3EEE2), in: Capsule())
            }
            .buttonStyle(PressScale())
            .disabled(needsPhoto).opacity(needsPhoto ? 0.45 : 1)
        }
        .padding(.horizontal, 20)
    }

    private func secondary(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(title).cvText(15, .semibold, inter: true)
            }
            .foregroundStyle(CV.text)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(Color.white.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(PressScale())
    }

    // MARK: Adjust (photo cards)

    private var adjustBar: some View {
        HStack(spacing: 8) {
            ForEach(MoveTarget.allCases, id: \.self) { t in
                Button { moveTarget = t } label: {
                    Label(t.rawValue, systemImage: t == .stats ? "textformat.size" : "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(moveTarget == t ? CV.onAccent : CV.text)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(moveTarget == t ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 20).overlay(Color.white.opacity(0.2))
            ForEach(CardAccent.allCases) { a in
                Button { options.accent = a } label: {
                    Circle().fill(a.color).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.white, lineWidth: options.accent == a ? 2.5 : 0.5).padding(-3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Colour \(a.rawValue)")
            }
        }
        .padding(.top, 14)
    }

    private func adjustOverlay(cardW: CGFloat) -> some View {
        let scale = format.canvas.width / cardW
        return RoundedRectangle(cornerRadius: 18).strokeBorder(Color(hex: 0xFF3B30), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .contentShape(Rectangle())
            .gesture(DragGesture()
                .onChanged { v in
                    let base = dragStart ?? (moveTarget == .stats ? options.statsOffset : options.routeOffset)
                    if dragStart == nil { dragStart = base }
                    let new = CGSize(width: base.width + v.translation.width * scale, height: base.height + v.translation.height * scale)
                    if moveTarget == .stats { options.statsOffset = new } else { options.routeOffset = new }
                }
                .onEnded { _ in dragStart = nil })
    }

    // MARK: Actions

    private func render(design d: CardDesign? = nil) -> UIImage? {
        CardExporter.render(RideCardCanvas(design: d ?? current, data: data, options: options, format: format,
                                           photo: photo, satellite: satellite.image, filmPhotos: filmPhotos),
                            scale: format.exportScale, transparent: (d ?? current).isTransparent)
    }

    private func quickSave() async {
        guard let img = render() else { return }
        if await CardExporter.saveToPhotos(img) { showToast("Saved to Photos · \(format.pixelLabel)") }
        else { showToast("Allow Photos access in Settings to save cards") }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        photo = img.downsized(maxSide: 2400)
        withAnimation(.snappy) { design = .photo; adjusting = false }
    }

    private func loadFilm(_ items: [PhotosPickerItem]) async {
        var imgs: [UIImage] = []
        for item in items.prefix(3) {
            if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { imgs.append(img.downsized(maxSide: 1600)) }
        }
        guard !imgs.isEmpty else { return }
        filmPhotos = imgs
        withAnimation(.snappy) { design = .filmStrip }
    }

    private func showToast(_ t: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = t }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeOut(duration: 0.25)) { if toast == t { toast = nil } }
        }
    }

    private func toastView(_ t: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Hue.sage)
                Text(t).cvText(13, .semibold, inter: true).lineLimit(2)
                Spacer(minLength: 4)
                Button("Done") { withAnimation { toast = nil } }
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0xFF3B30))
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(Color(hex: 0x1C1C20), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            .padding(.horizontal, 16).padding(.top, 58)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Customize sheet

private struct CardCustomizeSheet: View {
    @Binding var options: CardOptions
    let design: CardDesign
    let data: RideCardData
    let photo: UIImage?
    var onChangePhoto: () -> Void
    var onAdjust: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Customize").cvText(22, .bold, inter: true)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(Color(hex: 0xFF3B30))
                }

                if design == .filmStrip {
                    section("PHOTOS") {
                        Button(action: onChangePhoto) {
                            Label("Choose up to 3 photos", systemImage: "film.stack")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.text)
                                .padding(.horizontal, 14).frame(height: 36)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if design == .photo {
                    section("PHOTO") {
                        HStack(spacing: 10) {
                            Button(action: onChangePhoto) {
                                Label(photo == nil ? "Choose photo" : "Change photo", systemImage: "photo")
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.text)
                                    .padding(.horizontal, 14).frame(height: 36)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            if photo != nil {
                                Button("Auto layout") { withAnimation(.snappy) { options.autoLayout() } }
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.text)
                                    .padding(.horizontal, 14).frame(height: 36)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                                Button(action: onAdjust) {
                                    Label("Move route & stats", systemImage: "hand.draw")
                                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.onAccent)
                                        .padding(.horizontal, 14).frame(height: 36)
                                        .background(Color(hex: 0xF3EEE2), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(PhotoLayout.allCases) { l in
                                    Button { options.photoLayout = l; options.autoLayout() } label: {
                                        VStack(spacing: 6) {
                                            RideCardCanvas(design: .photo, data: data, options: { var o = options; o.photoLayout = l; o.autoLayout(); return o }(),
                                                           format: .story, photo: photo)
                                                .scaleEffect(64 / 360, anchor: .topLeading)
                                                .frame(width: 64, height: 114, alignment: .topLeading)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(options.photoLayout == l ? Color(hex: 0xFF3B30) : Color.white.opacity(0.12),
                                                                  lineWidth: options.photoLayout == l ? 2 : 1))
                                            Text(l.title).cvText(11, options.photoLayout == l ? .bold : .regular, inter: true)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                section("STATS ON THE CARD") {
                    FlowChips(items: CardStat.allCases) { s in
                        let on = options.stats.contains(s)
                        let available = data.isAvailable(s)
                        Button {
                            if on { options.stats.removeAll { $0 == s } } else if options.stats.count < 4 { options.stats.append(s) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: on ? "checkmark" : s.symbol).font(.system(size: 10, weight: .bold))
                                Text(s.label).font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(on ? CV.onAccent : CV.text.opacity(available ? 0.85 : 0.35))
                            .padding(.horizontal, 12).frame(height: 34)
                            .background(on ? AnyShapeStyle(Color(hex: 0xF3EEE2)) : AnyShapeStyle(Color.white.opacity(0.07)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                    }
                    if CardStat.allCases.contains(where: { !data.isAvailable($0) }) {
                        Text("Speeds that weren't recorded on this ride can't be added.").cvText(11, color: CV.muted, inter: true)
                    }
                    Text("Up to 4 stats.").cvText(11, color: CV.muted, inter: true)
                }

                section("TITLE") {
                    TextField("", text: $options.title, prompt: Text("Add a title (optional)").foregroundColor(CV.text.opacity(0.35)))
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(CV.text)
                        .padding(.horizontal, 14).frame(height: 46)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                }

                section("SHOW") {
                    VStack(spacing: 0) {
                        toggle("Route line", "point.topleft.down.to.point.bottomright.curvepath", Hue.periwinkle, $options.showRoute)
                        toggle("Title", "textformat", Hue.sky, $options.showTitle)
                        toggle("Date", "calendar", Hue.honey, $options.showDate)
                        toggle("Crew", "person.3.fill", Hue.lavender, $options.showCrew, detail: data.crewName.map { "\($0) · \(data.riderCount) riders" })
                        toggle("Convoy mark", "seal.fill", Color(hex: 0xFF3B30), $options.showMark)
                    }
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                }

                section("PRIVACY") {
                    toggle("Hide start & finish", "lock.fill", Hue.teal, $options.trimEnds, detail: "Trims 500 m off both ends of the route")
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                }

                if design == .photo || design == .sticker {
                    section("COLOUR") {
                        HStack(spacing: 14) {
                            ForEach(CardAccent.allCases) { a in
                                Button { options.accent = a } label: {
                                    Circle().fill(a.color).frame(width: 30, height: 30)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: options.accent == a ? 3 : 0.5).padding(-4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
        .environment(\.colorScheme, .dark)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).cvText(11, .semibold, color: CV.text.opacity(0.5), tracking: 1.1, inter: true)
            content()
        }
    }

    private func toggle(_ title: String, _ icon: String, _ hue: Color, _ value: Binding<Bool>, detail: String? = nil) -> some View {
        Toggle(isOn: value) {
            HStack(spacing: 12) {
                IconBadge(symbol: icon, color: hue, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).cvText(15, .medium, inter: true)
                    if let detail { Text(detail).cvText(11, color: CV.muted, inter: true) }
                }
            }
        }
        .tint(Hue.sage)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// Simple wrapping layout for chips.
struct FlowChips<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder var content: (Item) -> Content
    var body: some View {
        FlowLayout(spacing: 8) { ForEach(items, id: \.self) { content($0) } }
    }
}

// MARK: - Share sheet

private struct CardShareSheet: View {
    let format: CardFormat
    @Binding var trim: Bool
    var canPost = false
    var alreadyPosted = false
    var onPost: () -> Void = {}
    let render: () -> UIImage?
    let renderSticker: () -> UIImage?
    var onSaved: () -> Void
    var onCopied: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Share").cvText(20, .bold, inter: true).padding(.top, 22)
            Toggle(isOn: $trim) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Hue.teal)
                    Text("Start & finish trimmed (500 m)").cvText(14, .medium, inter: true)
                }
            }
            .tint(Hue.sage)
            .padding(.horizontal, 14).frame(height: 50)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))

            if canPost {
                row(alreadyPosted ? "Use this card on your Crew post" : "Post this card to your Crew feed",
                    "person.3.fill", Hue.lavender) { onPost() }
            }
            row("Share to Instagram, WhatsApp…", "square.and.arrow.up", Hue.periwinkle) {
                guard let img = render() else { return }
                dismiss()
                ShareSheetPresenter.present(items: [img])
            }
            row("Save image · \(format.pixelLabel)", "arrow.down.to.line", Hue.sage) {
                guard let img = render() else { return }
                busy = true
                Task {
                    let ok = await CardExporter.saveToPhotos(img)
                    busy = false
                    dismiss()
                    if ok { onSaved() }
                }
            }
            row("Copy as sticker (transparent)", "square.on.square.dashed", Hue.honey) {
                guard let img = renderSticker() else { return }
                CardExporter.copyToPasteboard(img)
                dismiss()
                onCopied()
            }
            Text("Only the artwork is shared — never the app around it. Sticker = route + stats on a transparent background.")
                .cvText(11, color: CV.muted, lineHeight: 15, inter: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .disabled(busy)
        .environment(\.colorScheme, .dark)
    }

    private func row(_ title: String, _ icon: String, _ hue: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(symbol: icon, color: hue, size: 34)
                Text(title).cvText(15, .medium, inter: true)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.text.opacity(0.3))
            }
            .padding(.horizontal, 12).frame(height: 54)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Post the card to the Crew feed

private struct PostCardSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let log: RideLog
    let image: UIImage?
    var onPosted: () -> Void
    @State private var caption = ""
    @State private var posting = false
    @State private var error: String?

    private var alreadyPosted: Bool { (RideRecorder.shared.logs.first { $0.id == log.id }?.postId ?? log.postId) != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(alreadyPosted ? "Update your Crew post" : "Post to your Crew feed").cvText(22, .bold, inter: true)
                    .padding(.top, 20)
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity).frame(maxHeight: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                if !alreadyPosted {
                    TextField("", text: $caption, prompt: Text("How was the ride?").foregroundColor(CV.text.opacity(0.35)), axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 15)).foregroundStyle(CV.text)
                        .padding(14)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                        .onChange(of: caption) { _, v in if v.count > 500 { caption = String(v.prefix(500)) } }
                }
                Label("Visible to everyone on Convoy. Riders can like and comment.", systemImage: "globe")
                    .font(.system(size: 12)).foregroundStyle(CV.muted)
                if let error { Text(error).cvText(13, .semibold, color: CV.danger, inter: true) }
                Button(action: post) {
                    HStack(spacing: 8) {
                        if posting { ProgressView().tint(CV.onAccent) }
                        Text(alreadyPosted ? "Use this card" : "Post to Crew feed").cvText(16, .bold, color: CV.onAccent, inter: true)
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Color(hex: 0xF3EEE2), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(posting || image == nil)
            }
            .padding(.horizontal, 20)
        }
        .environment(\.colorScheme, .dark)
    }

    private func post() {
        guard let png = image?.pngData() else { return }
        posting = true; error = nil
        Task {
            defer { posting = false }
            do {
                var l = RideRecorder.shared.logs.first { $0.id == log.id } ?? log
                if l.postId == nil {
                    l = try await app.social.share(l, caption: caption.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                try await app.social.attachCard(to: l, png: png)
                dismiss()
                onPosted()
            } catch {
                self.error = SocialError.from(error).message
            }
        }
    }
}

// MARK: - Export

@MainActor
enum CardExporter {
    static func render(_ view: RideCardCanvas, scale: CGFloat, transparent: Bool) -> UIImage? {
        let r = ImageRenderer(content: view)
        r.scale = scale
        r.isOpaque = !transparent
        return r.uiImage
    }

    /// Saves a PNG to Photos (asks for add-only access the first time).
    static func saveToPhotos(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited, let png = image.pngData() else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
            }
            return true
        } catch { return false }
    }

    static func copyToPasteboard(_ image: UIImage) {
        guard let png = image.pngData() else { return }
        UIPasteboard.general.setData(png, forPasteboardType: "public.png")
    }
}

enum ShareSheetPresenter {
    @MainActor static func present(items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }
}

extension UIImage {
    func downsized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let k = maxSide / longest
        let target = CGSize(width: size.width * k, height: size.height * k)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

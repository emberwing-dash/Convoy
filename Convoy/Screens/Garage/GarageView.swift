import SwiftUI

// MARK: - Enums

enum GarageTopTab: String, CaseIterable { case bike = "Bike", gear = "Gear" }

enum GarageSubTab: String, CaseIterable {
    case info = "Overview", docs = "Docs", service = "Service", accessories = "Accessories", costs = "Costs"
    var icon: String {
        switch self {
        case .info: "square.grid.2x2.fill"
        case .docs: "checkmark.shield.fill"
        case .service: "wrench.and.screwdriver.fill"
        case .accessories: "puzzlepiece.extension.fill"
        case .costs: "indianrupeesign.circle.fill"
        }
    }
}

private let panel = CV.surface
private let amber = CV.warning

// ───────────────────────────────────────────────
// MARK: - GarageNav (kept for DocumentView etc.)
// ───────────────────────────────────────────────

struct GarageNav<T: View>: View {
    @Environment(AppState.self) private var app
    let title: String
    @ViewBuilder var trailing: T
    var body: some View {
        ZStack {
            Text(title).cvText(17, .semibold, inter: true)
            HStack { CircleBackButton { app.pop() }; Spacer(); trailing }.padding(.horizontal, 20)
        }.padding(.top, 4).frame(maxHeight: .infinity, alignment: .top)
    }
}

// ───────────────────────────────────────────────
// MARK: - GarageView
//
// A showroom for your bike. The whole screen takes on the bike's paint colour: the spotlight
// behind it, the stat icons, the selected section and the main buttons. Pick a different
// paint under "Paint" and the screen follows.
// ───────────────────────────────────────────────

struct GarageView: View {
    @Environment(AppState.self) private var app
    @State private var store = GarageStore.shared

    @State private var topTab: GarageTopTab = .bike
    @State private var subTab: GarageSubTab = .info
    @State private var selectedBikeIndex = 0
    @State private var tint: BikeTint = .fallback
    @State private var scrollY: CGFloat = 0

    // sheets / alerts
    @State private var showAddBike   = false
    @State private var showAddGear   = false
    @State private var showAddAccessory = false
    @State private var showEditBike  = false
    @State private var showUploadDoc: DocType? = nil
    @State private var showReportImage = false
    @State private var showDeleteConfirm = false

    private var bike: GarageBike? {
        guard !store.bikes.isEmpty else { return nil }
        return store.bikes[min(max(0, selectedBikeIndex), store.bikes.count - 1)]
    }

    /// The colour the screen is wearing right now.
    private var activeTint: BikeTint { topTab == .bike && bike != nil ? tint : .fallback }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GeometryReader { g in
                        Color.clear.onChange(of: g.frame(in: .named("garageScroll")).minY) { _, y in scrollY = y }
                    }
                    .frame(height: 0)

                    header.padding(.horizontal, 20).padding(.top, 8)
                    topToggle.padding(.horizontal, 20).padding(.top, 16)

                    if topTab == .bike {
                        if let b = bike {
                            if store.bikes.count > 1 { bikeSwitcher.padding(.top, 16) }
                            showroom(b).padding(.horizontal, 20).padding(.top, 10)
                            statsRow(b).padding(.horizontal, 20).padding(.top, 6)
                            sectionPicker.padding(.top, 22)
                            VStack(spacing: 14) {
                                switch subTab {
                                case .info:        infoTab(b)
                                case .docs:        docsTab(b)
                                case .service:     serviceTab(b)
                                case .accessories: accessoriesTab(b)
                                case .costs:       costsTab(b)
                                }
                            }
                            .padding(.horizontal, 20).padding(.top, 16)
                        } else {
                            emptyShowroom.padding(.horizontal, 20).padding(.top, 18)
                        }
                    } else {
                        gearTab.padding(.horizontal, 20).padding(.top, 20)
                    }
                }
                .padding(.bottom, 60)
            }
            .coordinateSpace(name: "garageScroll")
            .scrollIndicators(.hidden)

            Color.clear.frame(height: 0)
                .background(Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    .overlay(alignment: .bottom) { Rectangle().fill(CV.separator).frame(height: 0.5) }
                    .ignoresSafeArea(edges: .top))
                .opacity(scrollY < -16 ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: scrollY < -16)
                .allowsHitTesting(false)
        }
        .background(alignment: .top) { backdrop }
        .animation(.easeInOut(duration: 0.6), value: activeTint)
        .task(id: bike.map { "\($0.id)|\($0.color ?? "")" }) {
            guard let b = bike else { return }
            let t = await BikePaint.tint(for: b)
            withAnimation(.easeInOut(duration: 0.6)) { tint = t }
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .sheet(isPresented: $showAddBike) {
            AddBikeFlowView { b in store.addBike(b); selectedBikeIndex = 0 }
        }
        .sheet(isPresented: $showAddGear) {
            QuickGearAddSheet { g in store.addGear(g) }
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showAddAccessory) {
            if let b = bike {
                AddAccessorySheet(bikeId: b.id) { a in store.addAccessory(a) }
            }
        }
        .sheet(isPresented: $showEditBike) {
            if let b = bike {
                EditBikeDetailsSheet(bike: b) { u in
                    store.updateBike(u)
                } onDelete: {
                    withAnimation(.snappy(duration: 0.25)) {
                        store.removeBike(id: b.id)
                        if selectedBikeIndex >= store.bikes.count {
                            selectedBikeIndex = max(0, store.bikes.count - 1)
                        }
                    }
                }
            }
        }
        .sheet(item: $showUploadDoc) { dt in
            if let b = bike {
                UploadDocSheet(bikeId: b.id, docType: dt) { d in store.addDoc(d) }
            }
        }
        .alert("Report Motorcycle Image", isPresented: $showReportImage) {
            Button("Submit Correct Photo") {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Thanks! We'll update the photo for \(bike?.displayName ?? "this bike").")
        }
        .confirmationDialog("Delete Motorcycle", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete \(bike?.displayName ?? "Bike")", role: .destructive) {
                if let b = bike {
                    withAnimation(.snappy(duration: 0.25)) {
                        store.removeBike(id: b.id)
                        if selectedBikeIndex >= store.bikes.count {
                            selectedBikeIndex = max(0, store.bikes.count - 1)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove \(bike?.displayName ?? "this motorcycle") from your garage? This action cannot be undone.")
        }
    }

    // MARK: Backdrop ───────────────────────

    /// A showroom spotlight in the bike's colour.
    private var backdrop: some View {
        ZStack(alignment: .top) {
            TopoBackground(glow: false)
            ZStack {
                LinearGradient(colors: [activeTint.deep, activeTint.deep.opacity(0.5), .clear],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [activeTint.color.opacity(0.28), .clear],
                               center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 260)
            }
            .frame(height: 640)
            .offset(y: min(0, scrollY) * 0.5)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Header ─────────────────────────

    private var header: some View {
        HStack(spacing: 12) {
            if !app.path.isEmpty {
                CircleBackButton { app.pop() }
            }
            Text("Garage").cvText(30, .bold, tracking: -0.6, inter: true)
            Spacer()
            Button {
                if topTab == .bike { showAddBike = true } else { showAddGear = true }
            } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .bold)).foregroundStyle(CV.text)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .environment(\.colorScheme, .dark)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(topTab == .bike ? "Add a bike" : "Add gear")
        }
    }

    // MARK: Bike / Gear Toggle ─────────────

    private var topToggle: some View {
        HStack(spacing: 4) {
            pill(.bike, icon: "motorcycle")
            pill(.gear, icon: "shield.lefthalf.filled")
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private func pill(_ tab: GarageTopTab, icon: String) -> some View {
        let on = topTab == tab
        return Button {
            withAnimation(.snappy(duration: 0.25)) { topTab = tab }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(tab.rawValue).cvText(15, .semibold, color: on ? activeTint.onColor : CV.text.opacity(0.7), inter: true)
            }
            .foregroundStyle(on ? activeTint.onColor : CV.text.opacity(0.7))
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(on ? activeTint.color : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Bike switcher (2+ bikes) ───────

    private var bikeSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(store.bikes.enumerated()), id: \.element.id) { i, b in
                    let on = i == selectedBikeIndex
                    Button { withAnimation(.snappy(duration: 0.25)) { selectedBikeIndex = i } } label: {
                        HStack(spacing: 8) {
                            SmallBikeThumb(make: b.make, model: b.model, year: b.year, imageURL: b.imageURL)
                                .frame(width: 40, height: 26)
                            Text(b.nickname ?? b.model).cvText(13, on ? .bold : .medium,
                                                               color: on ? CV.text : CV.text.opacity(0.65), inter: true)
                                .lineLimit(1)
                        }
                        .padding(.leading, 8).padding(.trailing, 14).frame(height: 42)
                        .background(on ? activeTint.color.opacity(0.22) : Color.white.opacity(0.06), in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? activeTint.color.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation(.snappy(duration: 0.25)) {
                                store.removeBike(id: b.id)
                                if selectedBikeIndex >= store.bikes.count {
                                    selectedBikeIndex = max(0, store.bikes.count - 1)
                                }
                            }
                        } label: { Label("Remove from Garage", systemImage: "trash") }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Showroom ───────────────────────

    private func showroom(_ b: GarageBike) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(b.make.uppercased()).cvText(13, .bold, color: activeTint.color, tracking: 1.6, inter: true)
            Text(b.model).cvText(36, .bold, tracking: -1, inter: true)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.top, 2)
            HStack(spacing: 6) {
                tag("\(b.year)")
                if let cc = b.engineCC { tag("\(cc)cc") }
                if let c = b.category { tag(c) }
                if let n = b.nickname { tag("“\(n)”") }
            }
            .padding(.top, 8)

            // The bike on a lit floor.
            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(RadialGradient(colors: [activeTint.color.opacity(0.45), .clear],
                                         center: .center, startRadius: 0, endRadius: 150))
                    .frame(width: 320, height: 60)
                    .offset(y: 6)
                Ellipse()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 230, height: 18)
                    .blur(radius: 10)
                    .offset(y: -6)
                BikeImageView(make: b.make, model: b.model, year: b.year, height: 210, imageURL: b.imageURL)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
                    .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity).frame(height: 240)
            .contextMenu {
                Button { showReportImage = true } label: { Label("Report wrong photo", systemImage: "exclamationmark.bubble") }
            }

            // Paint row
            HStack(spacing: 10) {
                Circle().fill(activeTint.color).frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
                Text(b.color ?? "Paint from photo").cvText(13, .semibold, color: CV.text.opacity(0.85), inter: true)
                    .lineLimit(1)
                Spacer()
                Button { showReportImage = true } label: {
                    Text("Wrong photo?").cvText(12, .medium, color: CV.muted, inter: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
    }

    private func tag(_ t: String) -> some View {
        Text(t).cvText(12, .semibold, color: CV.text.opacity(0.85), inter: true)
            .padding(.horizontal, 10).frame(height: 26)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: Stats ──────────────────────────

    private func statsRow(_ b: GarageBike) -> some View {
        HStack(spacing: 10) {
            statTile("bolt.fill", fmt(b.powerBHP), "bhp", "Power")
            statTile("arrow.triangle.2.circlepath", fmt(b.torqueNM), "Nm", "Torque")
            if let ts = b.topSpeedKMH {
                statTile("speedometer", "\(ts)", "km/h", "Top speed")
            } else {
                statTile("scalemass.fill", b.weightKG.map { "\($0)" } ?? "—", "kg", "Weight")
            }
        }
    }

    private func statTile(_ icon: String, _ val: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            IconBadge(symbol: icon, size: 32)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(val).cvText(22, .bold, tracking: -0.4, inter: true).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                if val != "—" { Text(unit).cvText(11, .semibold, color: CV.muted, inter: true) }
            }
            Text(label).cvText(12, color: CV.muted, inter: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CV.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    // MARK: Section picker ─────────────────

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GarageSubTab.allCases, id: \.self) { t in
                    let on = subTab == t
                    Button { withAnimation(.snappy(duration: 0.2)) { subTab = t } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: t.icon).font(.system(size: 12, weight: .semibold))
                            Text(t.rawValue).cvText(14, .semibold, color: on ? activeTint.onColor : CV.text.opacity(0.75), inter: true)
                        }
                        .foregroundStyle(on ? activeTint.onColor : CV.text.opacity(0.75))
                        .padding(.horizontal, 14).frame(height: 38)
                        .background(on ? activeTint.color : Color.white.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // ─────────────────────────────────────────
    // MARK: ■ Overview
    // ─────────────────────────────────────────

    @ViewBuilder private func infoTab(_ b: GarageBike) -> some View {
        // Specs: only what we actually know.
        let specs: [(String, String, String)] = [
            b.category.map { ("square.grid.2x2.fill", "Category", $0) },
            b.engineCC.map { ("engine.combustion.fill", "Engine", "\($0)cc" + (b.fuelType.map { " · \($0)" } ?? "")) },
            b.mileageKMPL.map { ("fuelpump.fill", "Mileage", "\(fmt($0)) kmpl") },
            b.tankL.map { ("drop.fill", "Tank", "\(fmt($0)) L") },
            b.weightKG.map { ("scalemass.fill", "Kerb weight", "\($0) kg") },
            b.topSpeedKMH.map { ("speedometer", "Top speed", "\($0) km/h") },
        ].compactMap { $0 }

        if !specs.isEmpty {
            card(title: "Specifications") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(specs, id: \.1) { s in
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: s.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(activeTint.color)
                            Text(s.1).cvText(11, .medium, color: CV.muted, inter: true)
                            Text(s.2).cvText(14, .semibold, inter: true).lineLimit(2).minimumScaleFactor(0.85)
                        }
                        .padding(12).frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }

        // Your bike
        card(title: "Your bike", trailing: ("Edit", { showEditBike = true })) {
            VStack(spacing: 0) {
                infoRow("calendar", "Year", "\(b.year)")
                divider
                Button { showEditBike = true } label: {
                    infoRow("gauge.with.needle.fill", "Odometer", b.odometer.map { "\($0.formatted()) km" } ?? "Add", missing: b.odometer == nil)
                }.buttonStyle(.plain)
                divider
                Button { showEditBike = true } label: {
                    infoRow("rectangle.and.text.magnifyingglass", "Registration", b.regNumber ?? "Add", missing: b.regNumber == nil)
                }.buttonStyle(.plain)
            }
        }

        // Paint — pick yours and the whole screen follows.
        let named = b.availableColors.filter { BikePaint.color(named: $0) != nil }
        let options = named.isEmpty ? ["Red", "Blue", "Black", "White", "Silver", "Green", "Yellow", "Orange"] : named
        card(title: "Paint") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    paintOption(label: "From photo", swatchColor: nil, selected: b.color == nil) {
                        var u = b; u.color = nil; store.updateBike(u)
                    }
                    ForEach(options, id: \.self) { name in
                        paintOption(label: name, swatchColor: BikePaint.color(named: name).map { Color(uiColor: $0) },
                                    selected: b.color == name) {
                            var u = b; u.color = name; store.updateBike(u)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, -16)
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }

        if let lin = b.lineage {
            card(title: "Lineage") {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.backward.circle.fill").font(.system(size: 18)).foregroundStyle(activeTint.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replaces").cvText(11, .medium, color: CV.muted, inter: true)
                        Text(lin).cvText(15, .semibold, inter: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }

        if let about = b.aboutGeneration {
            card(title: "About this generation") {
                Text(about).cvText(14, color: CV.text.opacity(0.8), lineHeight: 21, inter: true)
            }
        }

        VStack(spacing: 10) {
            Button { showEditBike = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil").font(.system(size: 14, weight: .bold))
                    Text("Edit details").cvText(16, .semibold, color: activeTint.onColor, inter: true)
                }
                .foregroundStyle(activeTint.onColor)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(activeTint.color, in: Capsule())
            }
            .buttonStyle(.plain)

            Button { showDeleteConfirm = true } label: {
                Text("Remove from garage").cvText(15, .semibold, color: CV.danger, inter: true)
                    .frame(maxWidth: .infinity).frame(height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func paintOption(label: String, swatchColor: Color?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if let c = swatchColor {
                        Circle().fill(c)
                        // A soft highlight so swatches read like paint, not flat dots.
                        Circle().fill(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .topLeading, endPoint: .center))
                    } else {
                        Circle().fill(AngularGradient(colors: [Color(hex: 0xE53935), Color(hex: 0xF5C518), Color(hex: 0x3FB65A),
                                                               Color(hex: 0x2F7BFF), Color(hex: 0x8E5BE8), Color(hex: 0xE53935)],
                                                      center: .center))
                        Image(systemName: "photo").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 2)
                    }
                }
                .frame(width: 40, height: 40)
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? CV.text : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1))
                Text(label).cvText(11, .medium, color: selected ? CV.text : CV.muted, inter: true)
                    .lineLimit(2).multilineTextAlignment(.center).frame(width: 62)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) paint\(selected ? ", selected" : "")")
    }

    private var divider: some View { Rectangle().fill(CV.separator).frame(height: 1).padding(.leading, 40) }

    private func infoRow(_ icon: String, _ label: String, _ value: String, missing: Bool = false) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: icon, size: 30)
            Text(label).cvText(14, color: CV.muted, inter: true)
            Spacer()
            Text(value).cvText(15, .semibold, color: missing ? activeTint.color : CV.text, inter: true)
            if missing { Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(activeTint.color) }
        }
        .frame(height: 46)
        .contentShape(Rectangle())
    }

    /// Standard card with a title and an optional trailing action.
    private func card<C: View>(title: String, trailing: (String, () -> Void)? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).cvText(17, .semibold, inter: true)
                Spacer()
                if let trailing {
                    Button(trailing.0, action: trailing.1).cvText(14, .semibold, color: activeTint.color, inter: true).buttonStyle(.plain)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CV.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func fmt(_ d: Double?) -> String {
        guard let d else { return "—" }
        return d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
    }

    // ─────────────────────────────────────────
    // MARK: ■ Docs
    // ─────────────────────────────────────────

    private static let requiredDocs: [(String, DocType, String, Color)] = [
        ("Insurance", .insurance, "shield.fill", CV.text),
        ("PUC certificate", .puc, "leaf.fill", CV.text),
        ("Registration (RC)", .rc, "doc.text.fill", CV.text),
    ]

    @ViewBuilder private func docsTab(_ b: GarageBike) -> some View {
        let dd = store.docs(for: b.id)
        let valid = Self.requiredDocs.filter { r in dd.contains { $0.type == r.1 && !$0.isExpired } }.count
        let expired = Self.requiredDocs.filter { r in dd.contains { $0.type == r.1 && $0.isExpired } }.count
        let fraction = Double(valid) / Double(Self.requiredDocs.count)

        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 8)
                Circle().trim(from: 0, to: fraction)
                    .stroke(valid == 3 ? CV.success : activeTint.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(valid)/3").cvText(17, .bold, inter: true).monospacedDigit()
            }
            .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text(valid == 3 ? "All papers in order" : "Paperwork").cvText(18, .bold, inter: true)
                Text(expired > 0 ? "\(expired) expired · renew soon"
                     : valid == 3 ? "Insurance, PUC and RC are valid"
                     : "\(3 - valid) of 3 still to add")
                    .cvText(13, color: expired > 0 ? CV.danger : CV.muted, inter: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(CV.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))

        ForEach(Self.requiredDocs, id: \.0) { r in docRow(r.0, r.1, r.2, r.3, dd) }
    }

    private func docRow(_ title: String, _ type: DocType, _ icon: String, _ color: Color, _ docs: [BikeDocument]) -> some View {
        let d = docs.first(where: { $0.type == type })
        let status: (String, Color) = {
            guard let d else { return ("Not added", CV.muted) }
            if d.noExpiry { return ("No expiry", CV.success) }
            if d.isExpired { return ("Expired", CV.danger) }
            if d.isExpiringSoon { return ("\(d.daysUntilExpiry ?? 0) days left", CV.warning) }
            return ("Valid till \(d.expiryDate?.formatted(.dateTime.day().month(.abbreviated).year()) ?? "")", CV.success)
        }()
        return HStack(spacing: 14) {
            IconBadge(symbol: icon, color: color, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).cvText(15, .semibold, inter: true)
                HStack(spacing: 5) {
                    Circle().fill(status.1).frame(width: 6, height: 6)
                    Text(status.0).cvText(12, .medium, color: status.1, inter: true)
                }
            }
            Spacer()
            Button { showUploadDoc = type } label: {
                Text(d == nil ? "Add" : "Update").cvText(13, .semibold, color: activeTint.color, inter: true)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(activeTint.color.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(CV.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    // ─────────────────────────────────────────
    // MARK: ■ Service
    // ─────────────────────────────────────────

    @ViewBuilder private func serviceTab(_ b: GarageBike) -> some View {
        let items = store.services(for: b.id).sorted { $0.date > $1.date }
        if items.isEmpty {
            emptyBlock("wrench.and.screwdriver", "No service history yet",
                       "Oil changes, tune-ups and repairs you log will show up here.")
        } else {
            if let last = items.first, last.nextDueKM != nil || last.nextDueDate != nil {
                // Only what was actually logged with the last service.
                HStack(spacing: 14) {
                    IconBadge(symbol: "calendar.badge.clock", color: Hue.honey, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next service").cvText(16, .bold, inter: true)
                        Text([last.nextDueKM.map { "at \($0.formatted()) km" },
                              last.nextDueDate.map { "by \($0.formatted(.dateTime.day().month(.abbreviated).year()))" }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .cvText(13, color: CV.muted, inter: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(CV.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            card(title: "History") {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                        HStack(spacing: 12) {
                            Circle().fill(i == 0 ? activeTint.color : Color.white.opacity(0.2)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.title).cvText(15, .semibold, inter: true)
                                Text(s.date.formatted(date: .abbreviated, time: .omitted)
                                     + (s.odometerKM.map { " · \($0.formatted()) km" } ?? ""))
                                    .cvText(12, color: CV.muted, inter: true)
                            }
                            Spacer()
                            if let c = s.cost { Text("₹\(Int(c).formatted())").cvText(14, .semibold, inter: true) }
                        }
                        .padding(.vertical, 10)
                        if i < items.count - 1 { divider }
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────
    // MARK: ■ Accessories
    // ─────────────────────────────────────────

    @ViewBuilder private func accessoriesTab(_ b: GarageBike) -> some View {
        let items = store.accessories(for: b.id)
        if items.isEmpty {
            VStack(spacing: 12) {
                IconBadge(symbol: "puzzlepiece.extension.fill", color: Hue.lavender, size: 64)
                Text("No accessories yet").cvText(17, .bold, inter: true)
                Text("Phone mounts, lights, crash guards, exhausts…").cvText(13, color: CV.muted, inter: true)
                    .multilineTextAlignment(.center)
                Button { showAddAccessory = true } label: {
                    Text("Add accessory").cvText(15, .semibold, color: activeTint.onColor, inter: true)
                        .padding(.horizontal, 22).frame(height: 44)
                        .background(activeTint.color, in: Capsule())
                }
                .buttonStyle(.plain).padding(.top, 4)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 26)
            .background(CV.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            card(title: "Installed", trailing: ("Add", { showAddAccessory = true })) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, acc in
                        HStack(spacing: 12) {
                            IconBadge(symbol: "puzzlepiece.extension.fill", color: Hue.lavender, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(acc.name).cvText(15, .semibold, inter: true)
                                if let br = acc.brand { Text(br).cvText(12, color: CV.muted, inter: true) }
                            }
                            Spacer()
                            if let c = acc.cost { Text("₹\(Int(c).formatted())").cvText(14, .semibold, inter: true) }
                        }
                        .padding(.vertical, 8)
                        if i < items.count - 1 { divider }
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────
    // MARK: ■ Costs
    // ─────────────────────────────────────────

    @ViewBuilder private func costsTab(_ b: GarageBike) -> some View {
        let items = store.costs(for: b.id)
        let total = items.reduce(0) { $0 + $1.amount }
        let byCat = Dictionary(grouping: items, by: \.category).mapValues { $0.reduce(0) { $0 + $1.amount } }
            .sorted { $0.value > $1.value }

        VStack(alignment: .leading, spacing: 6) {
            Text("Total spent").cvText(13, color: CV.muted, inter: true)
            Text("₹\(Int(total).formatted())").cvText(38, .bold, tracking: -1, inter: true).monospacedDigit()
            if !byCat.isEmpty {
                // Share of spend by category.
                GeometryReader { g in
                    HStack(spacing: 3) {
                        ForEach(Array(byCat.enumerated()), id: \.offset) { i, e in
                            Capsule().fill(activeTint.color.opacity(1 - Double(i) * 0.2))
                                .frame(width: max(6, g.size.width * e.value / max(total, 1) - 3))
                        }
                    }
                }
                .frame(height: 8).padding(.top, 8)
                HStack(spacing: 14) {
                    ForEach(Array(byCat.prefix(4).enumerated()), id: \.offset) { i, e in
                        HStack(spacing: 5) {
                            Circle().fill(activeTint.color.opacity(1 - Double(i) * 0.2)).frame(width: 7, height: 7)
                            Text(e.key).cvText(12, color: CV.muted, inter: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(CV.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))

        if items.isEmpty {
            emptyBlock("indianrupeesign.circle", "No expenses yet", "Fuel, servicing and parts you log add up here.")
        } else {
            card(title: "Expenses") {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.category).cvText(15, .semibold, inter: true)
                                Text(c.date.formatted(date: .abbreviated, time: .omitted)).cvText(12, color: CV.muted, inter: true)
                            }
                            Spacer()
                            Text("₹\(Int(c.amount).formatted())").cvText(15, .semibold, inter: true)
                        }
                        .padding(.vertical, 9)
                        if i < items.count - 1 { Rectangle().fill(CV.separator).frame(height: 1) }
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────
    // MARK: ■ Gear
    // ─────────────────────────────────────────

    private var gearTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Riding gear").cvText(22, .bold, tracking: -0.4, inter: true)
                Text("\(store.gearItems.count)").cvText(15, .semibold, color: CV.muted, inter: true)
                Spacer()
            }
            if store.gearItems.isEmpty {
                emptyBlock("shield.lefthalf.filled", "No gear yet", "Helmets, jackets, gloves and boots — with warranty reminders.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(store.gearItems) { g in gearCard(g) }
                }
            }
        }
    }

    private func gearCard(_ g: GearItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBadge(symbol: g.type.sfIcon, color: Hue.teal, size: 46)
                Spacer()
                Text(g.condition.rawValue).cvText(11, .semibold, color: CV.text.opacity(0.8), inter: true)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name).cvText(15, .semibold, inter: true).lineLimit(2)
                Text([g.type.rawValue, g.size.map { "Size \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .cvText(12, color: CV.muted, inter: true).lineLimit(1)
            }
            Spacer(minLength: 0)
            if g.hasWarranty, let exp = g.warrantyExpiry {
                let days = Calendar.current.dateComponents([.day], from: .now, to: exp).day ?? 0
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 11))
                    Text(days < 0 ? "Warranty ended" : days > 365 ? "Warranty · \(days / 365)y left" : "Warranty · \(days)d left")
                        .cvText(11, .semibold, color: days < 0 ? CV.muted : CV.success, inter: true)
                }
                .foregroundStyle(days < 0 ? CV.muted : CV.success)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(CV.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: Empty states ───────────────────

    private func emptyBlock(_ icon: String, _ title: String, _ sub: String) -> some View {
        VStack(spacing: 10) {
            IconBadge(symbol: icon, size: 60)
            Text(title).cvText(16, .semibold, inter: true)
            Text(sub).cvText(13, color: CV.muted, inter: true).multilineTextAlignment(.center).padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 26)
        .background(CV.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// No bikes yet: an empty, lit showroom floor waiting for one.
    private var emptyShowroom: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(RadialGradient(colors: [CV.accent.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 150))
                    .frame(width: 300, height: 56)
                Image(systemName: "motorcycle")
                    .font(.system(size: 110, weight: .thin))
                    .foregroundStyle(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                                    startPoint: .top, endPoint: .bottom))
                    .padding(.bottom, 18)
            }
            .frame(height: 200)

            Text("Your garage is empty").cvText(22, .bold, inter: true).padding(.top, 6)
            Text("Add your bike to see its specs, keep papers on hand and track what you spend.")
                .cvText(14, color: CV.muted, lineHeight: 20, inter: true)
                .multilineTextAlignment(.center).padding(.horizontal, 20).padding(.top, 6)
            Button { showAddBike = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                    Text("Add your bike").cvText(16, .semibold, color: CV.onAccent, inter: true)
                }
                .foregroundStyle(CV.onAccent)
                .padding(.horizontal, 28).frame(height: 52)
                .background(CV.accent, in: Capsule())
            }
            .buttonStyle(.plain).padding(.top, 20)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}

// FlowLayout is defined in RoutesViews.swift — reused here for colour chips.

// ───────────────────────────────────────────────
// MARK: - Add Bike Flow  (matches ref: Select → Confirm)
// ───────────────────────────────────────────────

struct AddBikeFlowView: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (GarageBike) -> Void

    @State private var search = ""
    @State private var picked: CatalogBike?
    @State private var nickname = ""

    private var filtered: [CatalogBike] {
        guard !search.isEmpty else { return popularBikesCatalog }
        // "Hero MotoCorp" tapped → search "Hero MotoCorp" but make is "Hero"
        // "Harley-Davidson" → make may be "Harley Davidson"
        let s = search
            .replacingOccurrences(of: "Hero MotoCorp", with: "Hero", options: .caseInsensitive)
            .replacingOccurrences(of: "Harley-Davidson", with: "Harley", options: .caseInsensitive)
        return popularBikesCatalog.filter {
            $0.make.localizedCaseInsensitiveContains(s) ||
            $0.model.localizedCaseInsensitiveContains(s) ||
            "\($0.engineCC)".contains(s)
        }
    }

    var body: some View {
        ZStack {
            CV.bg.ignoresSafeArea()
            if let b = picked { confirmView(b) } else { selectView }
        }
    }

    private var selectView: some View {
        VStack(spacing: 0) {
            // Compact Header — no xmark, just Cancel aligned left
            HStack {
                Button("Cancel") { dismiss() }
                    .cvText(15, .semibold, color: CV.accentLight, inter: true)
                Spacer()
                Text("Select Your Bike")
                    .cvText(17, .bold, color: CV.text, inter: true)
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 6)

            // Search bar immediately below header — no extra top gap
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(CV.muted)
                TextField("Try \"Duke 390\", \"Royal Enfield\", \"150cc\"", text: $search).foregroundStyle(CV.text)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(CV.muted)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let brands = ["Honda", "KTM", "Hero MotoCorp",
                                  "Bajaj", "Triumph", "Ducati",
                                  "TVS", "BMW", "Kawasaki",
                                  "Royal Enfield", "Yamaha", "Harley-Davidson"]
                    Text("POPULAR BRANDS").cvText(11, .bold, color: CV.text.opacity(0.5), tracking: 0.8, inter: true)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(brands, id: \.self) { b in
                            Button {
                                if search == b { search = "" } else { search = b }
                            } label: {
                                VStack(spacing: 6) {
                                    brandLogoView(b)
                                    Text(b).cvText(12, .semibold, color: CV.text, inter: true).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity).frame(height: 84)
                                .background(search == b ? CV.accentSoft : CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(search == b ? CV.accent : Color.white.opacity(0.08), lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }

                    Text("POPULAR IN INDIA").cvText(11, .bold, color: CV.text.opacity(0.5), tracking: 0.8, inter: true)
                    ForEach(filtered) { b in
                        Button { withAnimation { picked = b } } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CV.bg2).frame(width: 58, height: 48)
                                    SmallBikeThumb(make: b.make, model: b.model, year: b.year, imageURL: b.imageURL)
                                        .frame(width: 54, height: 38)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(b.make).cvText(12, color: CV.muted, inter: true)
                                    Text(b.model).cvText(16, .bold, color: CV.text, inter: true)
                                    Text(b.categoryAndCC).cvText(12, color: CV.muted, inter: true)
                                }; Spacer()
                            }
                            .padding(14).background(CV.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20).padding(.bottom, 30)
            }.scrollIndicators(.hidden)
        }
        .padding(.top, 12)
        .frame(maxHeight: .infinity, alignment: .top)
    }


    @ViewBuilder
    private func brandLogoView(_ brand: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 44, height: 44)
            if let localAsset = BikeLibrary.localLogoAsset(for: brand) {
                Image(localAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            } else if let remoteURL = URL(string: "https://raw.githubusercontent.com/CodeBreakerYT/Convoy-dataset/HEAD/logo/\(brand.lowercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "").png") {
                CachedImage(url: remoteURL) {
                    Image(systemName: "motorcycle")
                        .font(.system(size: 20))
                        .foregroundStyle(CV.accent)
                }
                .frame(width: 32, height: 32)
            } else {
                Image(systemName: "motorcycle")
                    .font(.system(size: 20))
                    .foregroundStyle(CV.accent)
            }
        }
    }

    private func chip(_ t: String) -> some View {
        Text(t).cvText(13, .semibold, color: CV.text, inter: true)
            .padding(.horizontal, 14).frame(height: 36)
            .background(CV.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func confirmView(_ b: CatalogBike) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }.cvText(15, .semibold, color: CV.muted, inter: true)
                Spacer(); Text("Confirm Bike").cvText(17, .bold, color: CV.text, inter: true); Spacer()
                Color.clear.frame(width: 50, height: 1)
            }.padding(.horizontal, 20).padding(.top, 16)

            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    // Show real motorcycle image from API
                    BikeImageView(make: b.make, model: b.model, year: b.year, height: 140, imageURL: b.imageURL)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)

                    VStack(spacing: 6) {
                        Text("\(b.make) \(b.model)").cvText(22, .bold, color: CV.text, inter: true).multilineTextAlignment(.center)
                        HStack(spacing: 6) {
                            Image(systemName: "bicycle")
                            Text("\(b.category)  \(b.engineCC)cc")
                        }.cvText(14, color: CV.muted, inter: true)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 32)
                .background(CV.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nickname (optional)").cvText(14, .bold, color: CV.text, inter: true)
                    TextField("e.g., My Daily Rider", text: $nickname)
                        .padding(.horizontal, 16).frame(height: 52)
                        .background(CV.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(CV.text)
                }

                Button {
                    let g = GarageBike(make: b.make, model: b.model, year: b.year ?? 2024,
                                       nickname: nickname.isEmpty ? nil : nickname,
                                       category: b.category, engineCC: b.engineCC,
                                       fuelType: b.fuelType, powerBHP: b.powerBHP,
                                       torqueNM: b.torqueNM, weightKG: b.weightKG,
                                       tankL: b.tankL, mileageKMPL: b.mileageKMPL,
                                       topSpeedKMH: b.topSpeedKMH,
                                       aboutGeneration: b.aboutGeneration,
                                       lineage: b.lineage, availableColors: b.availableColors,
                                       imageURL: b.imageURL)
                    onAdd(g); dismiss()
                } label: {
                    HStack(spacing: 8) { Image(systemName: "plus.circle.fill"); Text("Add to Garage") }
                        .cvText(16, .bold, color: CV.onAccent, inter: true)
                        .foregroundStyle(CV.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(CV.accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }.buttonStyle(.plain)

                Button { withAnimation { picked = nil } } label: {
                    HStack(spacing: 6) { Image(systemName: "chevron.left"); Text("Choose a different bike") }
                        .cvText(15, .semibold, color: CV.accentLight, inter: true)
                }.buttonStyle(.plain)

                Spacer()
            }.padding(.horizontal, 20).padding(.top, 24)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// ───────────────────────────────────────────────
// MARK: - Quick Gear Add Sheet (matches ref purple modal)
// ───────────────────────────────────────────────

struct QuickGearAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (GearItem) -> Void

    @State private var gearType: GearType = .helmet
    @State private var name = ""
    @State private var amount = ""
    @State private var qty = 1
    @State private var brand = ""
    @State private var size = ""
    @State private var condition: GearCondition = .new
    @State private var hasWarranty = false
    @State private var purchaseDate = Date()

    private let purple = CV.accent

    var body: some View {
        CV.bg.ignoresSafeArea()
            .overlay(alignment: .top) {
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { dismiss() }.cvText(16, .semibold, color: CV.accentLight, inter: true)
                    Spacer(); Text("Quick Gear Add").cvText(17, .bold, color: CV.text, inter: true); Spacer()
                    Color.clear.frame(width: 50, height: 1)
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 14) {
                            ZStack { Circle().fill(purple).frame(width: 52, height: 52)
                                Image(systemName: "figure.walk").font(.system(size: 24, weight: .bold)).foregroundStyle(CV.onAccent)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Add Riding Gear").cvText(20, .bold, color: CV.text, inter: true)
                                Text("Add to your gear collection").cvText(13, color: CV.muted, inter: true)
                            }
                        }.padding(.top, 8)

                        Text("Gear Type").cvText(14, .bold, color: CV.text, inter: true)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                            ForEach(GearType.allCases, id: \.self) { t in
                                let on = gearType == t
                                Button { gearType = t } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: t.sfIcon).font(.system(size: 20))
                                        Text(t.rawValue).cvText(12, .semibold, inter: true)
                                    }
                                    .foregroundStyle(on ? CV.onAccent : CV.text.opacity(0.8))
                                    .frame(maxWidth: .infinity).frame(height: 72)
                                    .background(on ? purple : CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }

                        gearField("Item Name", "e.g., AGV K6 Helmet", $name)

                        HStack(spacing: 12) {
                            gearField("Amount", "₹ Optional", $amount, kbd: .numberPad)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Qty").cvText(14, .bold, color: CV.text, inter: true)
                                Text("\(qty)").cvText(17, .bold, color: CV.text, inter: true)
                                    .frame(maxWidth: .infinity).frame(height: 52)
                                    .background(CV.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }.frame(width: 90)
                        }

                        gearField("Brand (Optional)", "e.g., AGV, Alpinestars", $brand)

                        HStack(spacing: 12) {
                            gearField("Size", "L, XL, 42", $size)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Condition").cvText(14, .bold, color: CV.text, inter: true)
                                Menu {
                                    ForEach(GearCondition.allCases, id: \.self) { c in Button(c.rawValue) { condition = c } }
                                } label: {
                                    HStack {
                                        Text(condition.rawValue).cvText(15, .bold, color: CV.text, inter: true)
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 13)).foregroundStyle(CV.muted)
                                    }.padding(.horizontal, 16).frame(height: 52)
                                    .background(CV.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "shield.lefthalf.filled").font(.system(size: 20)).foregroundStyle(purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Has Warranty").cvText(15, .bold, color: CV.text, inter: true)
                                Text("Track warranty expiration").cvText(12, color: CV.muted, inter: true)
                            }; Spacer()
                            Toggle("", isOn: $hasWarranty).labelsHidden().tint(CV.success)
                        }.padding(16).background(CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Button {
                            let g = GearItem(type: gearType,
                                             name: name.isEmpty ? gearType.rawValue : name,
                                             brand: brand.isEmpty ? nil : brand,
                                             size: size.isEmpty ? nil : size,
                                             condition: condition,
                                             cost: Double(amount),
                                             quantity: qty,
                                             hasWarranty: hasWarranty,
                                             purchaseDate: purchaseDate)
                            onSave(g); dismiss()
                        } label: {
                            HStack(spacing: 8) { Image(systemName: "bag.fill"); Text("Add to My Gear") }
                                .cvText(16, .bold, color: CV.onAccent, inter: true)
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(CV.accent, in: Capsule())
                        }.buttonStyle(.plain).padding(.top, 8).padding(.bottom, 30)
                    }.padding(.horizontal, 20)
                }.scrollIndicators(.hidden)
            } // VStack
        } // overlay
    }

    private func gearField(_ label: String, _ ph: String, _ text: Binding<String>, kbd: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).cvText(14, .bold, color: CV.text, inter: true)
            TextField(ph, text: text).keyboardType(kbd)
                .padding(.horizontal, 16).frame(height: 52)
                .background(CV.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(CV.text)
        }
    }
}

// ───────────────────────────────────────────────
// MARK: - Edit / Upload / Add-Accessory Sheets
// ───────────────────────────────────────────────

struct EditBikeDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var bike: GarageBike
    var onSave: (GarageBike) -> Void
    var onDelete: () -> Void = {}
    @State private var nick: String; @State private var reg: String; @State private var odo: String

    init(bike: GarageBike, onSave: @escaping (GarageBike) -> Void, onDelete: @escaping () -> Void = {}) {
        self.bike = bike
        self.onSave = onSave
        self.onDelete = onDelete
        _nick = State(initialValue: bike.nickname ?? "")
        _reg  = State(initialValue: bike.regNumber ?? "")
        _odo  = State(initialValue: bike.odometer.map { "\($0)" } ?? "")
    }

    var body: some View {
        ZStack {
            CV.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Button("Cancel") { dismiss() }.cvText(15, color: CV.muted, inter: true); Spacer()
                    Text("Edit Details").cvText(17, .bold, color: CV.text, inter: true); Spacer()
                    Button("Save") {
                        var u = bike; u.nickname = nick.isEmpty ? nil : nick
                        u.regNumber = reg.isEmpty ? nil : reg; u.odometer = Int(odo)
                        onSave(u); dismiss()
                    }.cvText(15, .bold, color: CV.accentLight, inter: true)
                }.padding(.horizontal, 20).padding(.top, 16)
                VStack(spacing: 16) {
                    editField("NICKNAME", $nick, "e.g., Daily Commute")
                    editField("REGISTRATION NUMBER", $reg, "e.g., KA 01 RK 3500")
                    editField("ODOMETER (KM)", $odo, "e.g., 18420", kbd: .numberPad)
                }.padding(.horizontal, 20).padding(.top, 10)

                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                        Text("Delete Motorcycle")
                    }
                    .cvText(14, .bold, color: CV.danger, inter: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(CV.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()
            }
        }
    }
    private func editField(_ lbl: String, _ txt: Binding<String>, _ ph: String, kbd: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lbl).cvText(11, .bold, color: CV.text.opacity(0.5), tracking: 0.6, inter: true)
            TextField(ph, text: txt).keyboardType(kbd)
                .padding(.horizontal, 16).frame(height: 50)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(CV.text)
        }
    }
}

struct UploadDocSheet: View {
    @Environment(\.dismiss) private var dismiss
    let bikeId: UUID; let docType: DocType; var onAdd: (BikeDocument) -> Void
    @State private var noExpiry = false
    @State private var expiry = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

    var body: some View {
        ZStack {
            CV.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Button("Cancel") { dismiss() }.cvText(15, color: CV.muted, inter: true); Spacer()
                    Text("Upload \(docType.rawValue)").cvText(17, .bold, color: CV.text, inter: true); Spacer()
                    Button("Save") {
                        onAdd(BikeDocument(bikeId: bikeId, type: docType,
                                           expiryDate: noExpiry ? nil : expiry, noExpiry: noExpiry))
                        dismiss()
                    }.cvText(15, .bold, color: CV.accentLight, inter: true)
                }.padding(.horizontal, 20).padding(.top, 16)
                VStack(spacing: 16) {
                    Toggle("No Expiration Date", isOn: $noExpiry).cvText(15, .semibold, color: CV.text, inter: true).tint(CV.success)
                    if !noExpiry { DatePicker("Expiry Date", selection: $expiry, displayedComponents: .date).cvText(15, .semibold, color: CV.text, inter: true) }
                }.padding(20).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous)).padding(.horizontal, 20)
                Spacer()
            }
        }
    }
}

struct AddAccessorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let bikeId: UUID; var onAdd: (AccessoryItem) -> Void
    @State private var name = ""; @State private var brand = ""; @State private var cost = ""

    var body: some View {
        ZStack {
            CV.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Button("Cancel") { dismiss() }.cvText(15, color: CV.muted, inter: true); Spacer()
                    Text("Add Accessory").cvText(17, .bold, color: CV.text, inter: true); Spacer()
                    Button("Add") {
                        onAdd(AccessoryItem(bikeId: bikeId, name: name.isEmpty ? "Accessory" : name,
                                            brand: brand.isEmpty ? nil : brand, cost: Double(cost)))
                        dismiss()
                    }.cvText(15, .bold, color: CV.accentLight, inter: true)
                }.padding(.horizontal, 20).padding(.top, 16)
                VStack(spacing: 14) {
                    accField("NAME", $name, "e.g., Bobo Phone Mount")
                    accField("BRAND", $brand, "e.g., Bobo, Maddog")
                    accField("COST (₹)", $cost, "e.g., 2500", kbd: .numberPad)
                }.padding(.horizontal, 20)
                Spacer()
            }
        }
    }
    private func accField(_ l: String, _ t: Binding<String>, _ p: String, kbd: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l).cvText(11, .bold, color: CV.text.opacity(0.5), tracking: 0.6, inter: true)
            TextField(p, text: t).keyboardType(kbd).padding(.horizontal, 16).frame(height: 50)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous)).foregroundStyle(CV.text)
        }
    }
}

// ───────────────────────────────────────────────
// MARK: - DocumentView  (kept for .document(name) route)
// ───────────────────────────────────────────────

struct DocumentView: View {
    @Environment(AppState.self) private var app
    let name: String
    @State private var reminder = true

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            Text("IL").cvText(18, .bold, color: CV.ink, inter: true)
                                .frame(width: 44, height: 44)
                                .background(Color(hex: 0xF5EDDE), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ICICI Lombard").cvText(18, .bold, inter: true)
                                Text("Comprehensive · Two-wheeler").cvText(12, color: CV.text.opacity(0.55), inter: true)
                            }; Spacer()
                            Text("● Active").cvText(12, .semibold, color: CV.green, inter: true)
                                .padding(.horizontal, 10).frame(height: 25).background(CV.green.opacity(0.18), in: Capsule())
                        }
                        Text("POLICY NUMBER").cvText(11, .semibold, color: CV.text.opacity(0.5), tracking: 0.5, inter: true).padding(.top, 22)
                        HStack {
                            Text("3005 / 2918 / 4471 / 00").cvText(17, .bold, inter: true); Spacer()
                            Text("Copy").cvText(13, .semibold, color: CV.text.opacity(0.6), inter: true)
                        }.padding(.top, 4)
                        HStack {
                            Text("15 Mar 2026").cvText(12, color: CV.text.opacity(0.55), inter: true); Spacer()
                            Text("14 Mar 2027").cvText(12, color: CV.text.opacity(0.55), inter: true)
                        }.padding(.top, 18)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15))
                                Capsule().fill(CV.text).frame(width: g.size.width * 0.59)
                                Circle().fill(CV.text).frame(width: 12, height: 12).offset(x: g.size.width * 0.59 - 6)
                            }
                        }.frame(height: 12).padding(.top, 6)
                        HStack { Text("151 days left").cvText(14, .semibold, inter: true); Spacer()
                            Text("Renews 14 Mar 2027").cvText(12, color: CV.text.opacity(0.55), inter: true) }.padding(.top, 8)
                    }
                    .padding(18)
                    .background(LinearGradient(colors: [CV.accent.opacity(0.18), panel], startPoint: .topTrailing, endPoint: .bottomLeading),
                                in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.top, 62)

                    Text("WHAT'S COVERED").cvText(12, .semibold, color: CV.text.opacity(0.5), tracking: 0.5, inter: true).padding(.top, 20).padding(.leading, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) { covChip("Own damage"); covChip("Third party") }
                        HStack(spacing: 8) { covChip("Zero depreciation"); covChip("Roadside assist") }
                    }.padding(.top, 8)

                    HStack(spacing: 12) {
                        IconBadge(symbol: "bell.fill", color: Hue.honey, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Renewal reminder").cvText(15, .semibold, inter: true)
                            Text("30 days before · 12 Feb 2027").cvText(12, color: CV.text.opacity(0.55), inter: true)
                        }; Spacer()
                        Toggle("", isOn: $reminder).labelsHidden().tint(CV.green)
                    }
                    .padding(.horizontal, 16).frame(height: 68)
                    .background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                    .padding(.top, 14)
                }.padding(.horizontal, 20).padding(.bottom, 110)
            }.scrollIndicators(.hidden)
            GarageNav(title: name) { Color.clear.frame(width: 44) }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                ShareLink(item: "\(name) · Classic 350 · KA 01 RK 3500") {
                    Text("Share").cvText(15, .semibold, inter: true).frame(width: 120, height: 52)
                        .background(panel, in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                }
                PrimaryButton(title: "View PDF").frame(height: 52)
            }.padding(.horizontal, 20).padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar).background(SwipeBackEnabler())
    }

    private func covChip(_ t: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(CV.green)
            Text(t).cvText(14, .medium, inter: true)
        }
        .padding(.horizontal, 14).frame(height: 34)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

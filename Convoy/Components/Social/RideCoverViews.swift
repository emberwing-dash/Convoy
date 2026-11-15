// RideCoverViews.swift — destination photo for a ride (Home, Ride Details, Crew feed) and the admin's picker.
import SwiftUI
import PhotosUI

/// Shows a cover: the photo at full resolution, or a sharp satellite view of the destination.
/// While loading it shows a shimmer, never a blurry stretched thumbnail.
struct RideCoverImage: View {
    let cover: RideCover?
    let destination: Coord?
    var height: CGFloat
    /// Used to find the destination when no coordinates were saved with the ride.
    var placeName: String? = nil
    /// Called with the photo once it has loaded (Home uses it to tint its background).
    var onImage: ((UIImage) -> Void)? = nil
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CV.bg2
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                } else if !failed {
                    Skeleton(corner: 0)
                } else {
                    // Nothing to show at all: a calm gradient rather than an error icon.
                    LinearGradient(colors: [CV.elevated, CV.bg2], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .task(id: taskKey(geo.size)) { await load(size: geo.size) }
        }
        .frame(height: height)
        .clipped()
        // A scaled-to-fill photo still takes taps outside its clipped frame, which made it
        // swallow nearby buttons (Home's "See all"). Limit hit-testing to the visible area.
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.25), value: image != nil)
    }

    private func taskKey(_ size: CGSize) -> String {
        "\(cover?.url?.absoluteString ?? cover?.source.rawValue ?? "none")|\(destination?.lat ?? 0)|\(placeName ?? "")|\(Int(size.width))"
    }

    private func load(size: CGSize) async {
        guard size.width > 0 else { return }
        failed = false
        if let url = cover?.url, cover?.source != .satellite {
            if let img = await CoverImageLoader.shared.image(url) { image = img; onImage?(img); return }
        }
        var dest = destination
        if dest == nil, let name = placeName { dest = await RideCoverService.shared.coordinate(named: name) }
        if let d = dest, let img = await CoverImageLoader.shared.satelliteImage(d, size: size) {
            image = img; onImage?(img); return
        }
        image = nil
        failed = true
    }
}

/// Small credit chip required by the photo licence; opens the source page.
struct CoverCreditChip: View {
    let cover: RideCover?
    var body: some View {
        if let cover, let line = cover.creditLine {
            Group {
                if let page = cover.pageURL {
                    Link(destination: page) { label(line) }
                } else {
                    label(line)
                }
            }
        } else if cover?.source == .satellite || cover == nil {
            label("Satellite view")
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).cvText(10, .medium, color: .white.opacity(0.9), inter: true).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.black.opacity(0.45), in: Capsule())
    }
}

// MARK: - Admin picker

struct CoverPickerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ride: Ride
    @State private var photos: [PlacePhoto] = []
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var pickerItem: PhotosPickerItem?

    private var current: RideCover? { RideCoverService.shared.cover(for: ride) }
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RideCoverImage(cover: current, destination: ride.plan.endCoord, height: 180,
                           placeName: RideCoverService.destinationName(ride))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(alignment: .bottomTrailing) { CoverCreditChip(cover: current).padding(8) }

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Use your own photo").cvText(15, .bold, color: .white, inter: true)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(CV.accent, in: Capsule())
                    }
                    .disabled(saving)

                    Text("Photos of \(placeName)").cvText(13, .semibold, color: CV.muted, inter: true)
                    if loading {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(0..<4, id: \.self) { _ in Skeleton(corner: 14).frame(height: 110) }
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(photos) { p in tile(cover: p.cover, preview: p.gridURL, label: p.credit) }
                            tile(cover: .satellite, preview: nil, label: "Satellite view")
                        }
                        if photos.isEmpty {
                            Text("No free photos of this place were found, so the satellite view is used.")
                                .cvText(12, color: CV.muted, inter: true)
                        }
                    }
                    if let error { Text(error).cvText(13, .semibold, color: CV.accent, inter: true) }
                    Text("Photos come from Wikimedia Commons under free licences; the photographer is credited on the image.")
                        .cvText(11, color: CV.dim, inter: true)
                }
                .padding(20)
            }
            .background(CV.bg2.ignoresSafeArea())
            .navigationTitle("Ride cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(CV.accent) } }
            .overlay { if saving { ProgressView().tint(CV.accent).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
        .presentationDragIndicator(.visible)
        .task {
            if let d = await RideCoverService.shared.destination(for: ride) {
                photos = await PlacePhotoService.shared.photos(name: RideCoverService.destinationName(ride), coord: d)
            }
            loading = false
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await uploadPicked(item) }
        }
    }

    private var placeName: String {
        let n = ride.plan.to.components(separatedBy: ",").first ?? ride.place
        return n.isEmpty ? "the destination" : n
    }

    private func tile(cover: RideCover, preview: URL?, label: String) -> some View {
        let selected = current?.url == cover.url && current?.source == cover.source
        var shown = cover
        if let preview { shown.url = preview }
        return Button { choose(cover) } label: {
            RideCoverImage(cover: shown, destination: ride.plan.endCoord, height: 110,
                           placeName: RideCoverService.destinationName(ride))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(label).cvText(10, .medium, color: .white, inter: true).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.black.opacity(0.5), in: Capsule()).padding(6)
                }
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? CV.accent : Color.white.opacity(0.1), lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.plain)
        .disabled(saving)
    }

    private func choose(_ cover: RideCover) {
        saving = true; error = nil
        Task {
            defer { saving = false }
            do { try await RideCoverService.shared.set(cover, ride: ride, app: app); dismiss() }
            catch { self.error = SocialError.from(error).message }
        }
    }

    private func uploadPicked(_ item: PhotosPickerItem) async {
        saving = true; error = nil
        defer { saving = false; pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else {
            error = "That photo couldn't be opened."; return
        }
        do { try await RideCoverService.shared.upload(img, ride: ride, app: app); dismiss() }
        catch { self.error = SocialError.from(error).message }
    }
}

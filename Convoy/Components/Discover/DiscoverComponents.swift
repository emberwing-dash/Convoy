// DiscoverComponents.swift — building blocks for Discover v2 (Figma "06 · Discover v2" → Components).
import SwiftUI
import MapKit

extension CV {
    /// Raised card surface used across Discover.
    static let surface = Color(hex: 0x1A1A1D)
    static let hairline = Color.white.opacity(0.08)
}

// MARK: - Photos & map fallbacks

/// A real photo of the place, or — when there is none — its map. Never a stock image.
struct DiscoverImage: View {
    var photo: PhotoRef?
    var coord: Coord?
    var path: [Coord] = []

    var body: some View {
        Color.clear.overlay {
            switch photo?.source {
            case .asset(let name)?:
                if let image = UIImage(named: name) { Image(uiImage: image).resizable().scaledToFill() }
                else { MapThumb(center: coord, path: path) }   // asset not shipped in this build
            case .remote(let url)?:
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { CV.surface }
            case nil: MapThumb(center: coord, path: path)
            }
        }
        .clipped()
    }
}

/// Shipping art for Discover surfaces that have no licensed photo yet:
/// Convoy contour lines over a dark gradient with a coloured glow. Never pretends to be a place.
struct BrandedArt: View {
    enum Style { case hero, routes, scenic, places, surprise }
    var style: Style

    var body: some View {
        let (top, glow, symbol): (UInt32, UInt32, String?) = switch style {
        case .hero: (0x2B0F09, 0xFF5A1F, nil)
        case .routes: (0x241312, 0xFF3B30, "point.topleft.down.to.point.bottomright.curvepath")
        case .scenic: (0x0F2119, 0x2FB86A, "mountain.2")
        case .places: (0x161B26, 0x5E7CE2, "mappin.and.ellipse")
        case .surprise: (0x231229, 0xB45CE0, "sparkles")
        }
        ZStack {
            LinearGradient(colors: [Color(hex: top), CV.bg], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: glow).opacity(style == .hero ? 0.55 : 0.4), .clear],
                           center: style == .hero ? UnitPoint(x: 0.72, y: 0.3) : UnitPoint(x: 0.85, y: 0.1),
                           startRadius: 0, endRadius: style == .hero ? 340 : 170)
            Image("contour").resizable().scaledToFill().opacity(0.5).blendMode(.screen)
            if let symbol {
                Image(systemName: symbol).font(.system(size: 92, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.09))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 14).padding(.trailing, -6)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Landing artwork: the first licensed asset that ships in this build, else `BrandedArt`.
/// Licensed files go in the main asset catalog under the `discover_*` names (docs/DISCOVER_ASSETS.md).
struct LandingArt: View {
    let assets: [String]
    let fallback: BrandedArt.Style
    var body: some View {
        Color.clear.overlay {
            if let image = assets.lazy.compactMap({ UIImage(named: $0) }).first {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                BrandedArt(style: fallback)
            }
        }
        .clipped()
    }
}

/// Dark map snapshot with an optional route line and a red pin. Cached per content.
struct MapThumb: View {
    var center: Coord?
    var path: [Coord] = []
    var pin = true
    @State private var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CV.surface
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .task(id: key(geo.size)) { await render(geo.size) }
        }
    }

    private func key(_ s: CGSize) -> String {
        "\(center?.lat ?? 0),\(center?.lon ?? 0)|\(path.count)|\(path.first?.lat ?? 0)|\(Int(s.width))x\(Int(s.height))|\(pin)"
    }

    private func render(_ size: CGSize) async {
        guard size.width > 1, size.height > 1 else { return }
        if let hit = Self.cache.object(forKey: key(size) as NSString) { image = hit; return }
        let pts = path.isEmpty ? center.map { [$0.cl] } ?? [] : path.map(\.cl)
        guard let first = pts.first else { return }
        let opts = MKMapSnapshotter.Options()
        if pts.count > 1, var region = RoutePlanner.region(for: pts, padding: 1.4) {
            region.span.latitudeDelta = max(region.span.latitudeDelta, 0.05)
            region.span.longitudeDelta = max(region.span.longitudeDelta, 0.05)
            opts.region = region
        } else {
            opts.region = MKCoordinateRegion(center: first, span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12))
        }
        opts.size = size; opts.scale = 2
        opts.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        opts.preferredConfiguration = {
            let c = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            c.pointOfInterestFilter = .excludingAll
            return c
        }()
        guard let snap = try? await MKMapSnapshotter(options: opts).start() else { return }
        let out = UIGraphicsImageRenderer(size: size).image { ctx in
            snap.image.draw(at: .zero)
            let red = UIColor(CV.red)
            if pts.count > 1 {
                let line = UIBezierPath()
                for (i, c) in pts.enumerated() { i == 0 ? line.move(to: snap.point(for: c)) : line.addLine(to: snap.point(for: c)) }
                red.setStroke(); line.lineWidth = 3; line.lineJoinStyle = .round; line.stroke()
            }
            if pin {
                let p = snap.point(for: pts.count > 1 ? pts[pts.count - 1] : first)
                let r = CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)
                UIColor.white.setFill(); ctx.cgContext.fillEllipse(in: r.insetBy(dx: -2, dy: -2))
                red.setFill(); ctx.cgContext.fillEllipse(in: r)
            }
        }
        Self.cache.setObject(out, forKey: key(size) as NSString)
        image = out
    }
}

/// "▣ Photo · author · licence · source" — always shown with a photo.
struct Attribution: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "photo")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 10))
            .foregroundStyle(CV.muted.opacity(0.8))
            .lineLimit(1)
    }
}

// MARK: - Small controls

/// Dark translucent tag on photos ("Historical", "Coastal · Scenic").
struct PhotoTag: View {
    let text: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
            Text(text)
        }
        .cvText(11, .medium, inter: true)
        .padding(.horizontal, 8).frame(height: 20)
        .background(.black.opacity(0.55), in: Capsule())
    }
}

struct BookmarkButton: View {
    let saved: Bool
    var size: CGFloat = 15
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(CV.cream)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(saved ? "Remove from saved" : "Save")
        .sensoryFeedback(.selection, trigger: saved)
    }
}

struct Chip: View {
    let title: String
    var selected = false
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title)
                .cvText(13, .medium, color: selected ? CV.ink : CV.cream, inter: true)
                .padding(.horizontal, 14).frame(height: 34)
                .background(selected ? CV.cream : CV.glassFill, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? .clear : CV.glassStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Horizontal single-select chips that bleed to the screen edge.
struct ChipBar<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let title: (T) -> String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Chip(title: title(item), selected: item == selection) {
                        withAnimation(.snappy) { selection = item }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }
}

/// "➤ From Chennai ⌄" — opens the origin picker.
struct OriginPill: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill").font(.system(size: 11, weight: .semibold))
                Text(title).cvText(13, .medium, inter: true).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(CV.cream)
            .padding(.horizontal, 12).frame(height: 34)
            .background(.black.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var seeAll: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).cvText(19, .semibold, inter: true)
                if let subtitle { Text(subtitle).cvText(12, color: CV.dim, inter: true) }
            }
            Spacer()
            if let seeAll {
                Button("See all", action: seeAll).cvText(13, .medium, color: CV.muted, inter: true).buttonStyle(.plain)
            }
        }
    }
}

/// Small grey mono label ("STOPS ON THE WAY").
struct Eyebrow: View {
    let text: String
    var color: Color = CV.dim
    var body: some View { Text(text.uppercased()).cvText(11, .medium, color: color, tracking: 1.2, inter: true) }
}

/// Pill button in the three Discover styles.
struct DiscoverButton: View {
    enum Style { case primary, secondary, accent }
    let title: String
    var symbol: String? = nil
    var style: Style = .primary
    var height: CGFloat = 52
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 14, weight: .semibold)) }
                Text(title).cvText(16, .semibold, color: fg, inter: true)
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(bg, in: Capsule())
            .overlay(Capsule().strokeBorder(style == .secondary ? CV.glassStroke : .clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    private var fg: Color { style == .primary ? CV.ink : CV.cream }
    private var bg: Color { switch style { case .primary: CV.cream; case .secondary: CV.surface; case .accent: CV.red } }
}

// MARK: - Cards & rows

/// Tall photo tile: Routes / Scenic / Places / Surprise me, scenic collections.
struct CategoryTile: View {
    let title: String
    let subtitle: String
    var symbol: String? = nil
    var photo: PhotoRef?
    var art: LandingArt? = nil
    var height: CGFloat = 150
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Group { if let art { art } else { DiscoverImage(photo: photo) } }
                .frame(maxWidth: .infinity).frame(height: height)
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom))
                .overlay(alignment: .topLeading) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.cream)
                            .frame(width: 30, height: 30).background(.black.opacity(0.5), in: Circle()).padding(10)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).cvText(18, .bold, inter: true)
                        Text(subtitle).cvText(12, color: CV.cream.opacity(0.8), inter: true).lineLimit(2)
                    }
                    .multilineTextAlignment(.leading)
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScale())
    }
}

/// Photo card for a place: tag, bookmark, name, region and the ride line.
struct PlaceCard: View {
    let place: DiscoverPlace
    let rideLine: String
    var width: CGFloat? = 140
    var height: CGFloat = 196
    var saved = false
    var onSave: () -> Void = {}
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            DiscoverImage(photo: place.photos.first, coord: place.coord)
                .frame(width: width, height: height)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).cvText(15, .semibold, inter: true).lineLimit(2)
                        Text(place.region.components(separatedBy: ",")[0]).cvText(11, color: CV.cream.opacity(0.65), inter: true).lineLimit(1)
                        Text(rideLine).cvText(11, .semibold, inter: true).lineLimit(1)
                    }
                    .multilineTextAlignment(.leading)
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CV.hairline, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScale())
        .overlay(alignment: .topLeading) { PhotoTag(text: place.category.label).padding(8).allowsHitTesting(false) }
        .overlay(alignment: .topTrailing) { BookmarkButton(saved: saved, action: onSave).padding(2) }
        .accessibilityElement(children: .combine)
    }
}

/// Wide card for a route: photo, title, from → to, stats.
struct RouteCard: View {
    let route: DiscoverRoute
    var width: CGFloat? = 260
    var photoHeight: CGFloat = 130
    var saved = false
    var onSave: () -> Void = {}
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                DiscoverImage(photo: route.photos.first, coord: route.end.coord, path: route.geometry)
                    .frame(height: photoHeight).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.title).cvText(16, .semibold, inter: true).lineLimit(1)
                    Text(route.fromTo).cvText(12, color: CV.muted, inter: true).lineLimit(1)
                    RouteStats(route: route).padding(.top, 8)
                }
                .padding(14)
            }
            .frame(width: width)
            .background(CV.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(CV.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScale())
        .overlay(alignment: .topLeading) {
            if !route.tags.isEmpty { PhotoTag(text: route.tags.prefix(2).joined(separator: " · ")).padding(10).allowsHitTesting(false) }
        }
        .overlay(alignment: .topTrailing) { BookmarkButton(saved: saved, action: onSave).padding(4) }
    }
}

/// "⇄ 152 km  ◷ 3h 15m  ⌖ 4 stops" — only real road estimates, otherwise just the stop count.
struct RouteStats: View {
    let route: DiscoverRoute
    var body: some View {
        HStack(spacing: 12) {
            if let e = route.estimate {
                stat("point.topleft.down.to.point.bottomright.curvepath", e.distanceText)
                stat("clock", e.durationText)
            }
            stat("mappin.and.ellipse", "\(route.stops.count + 1) stops")
        }
    }
    private func stat(_ s: String, _ t: String) -> some View {
        HStack(spacing: 4) { Image(systemName: s).font(.system(size: 11)); Text(t).cvText(12, .semibold, inter: true) }
            .foregroundStyle(CV.cream)
    }
}

extension DiscoverRoute {
    /// "152 km · 3h 15m · Day ride" for rows; nothing invented when there is no estimate.
    var rowLine: String {
        guard let e = estimate else { return "\(stops.count + 1) stops" }
        return [e.distanceText, e.durationText, e.tripLength.rawValue].joined(separator: " · ")
    }
}

/// Compact row: thumbnail, title, subtitle, detail line, chevron.
struct RouteRow: View {
    let title: String
    let subtitle: String
    var detail: String? = nil
    var photo: PhotoRef?
    var coord: Coord?
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                DiscoverImage(photo: photo, coord: coord)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).cvText(15, .semibold, inter: true).lineLimit(1)
                    Text(subtitle).cvText(12, color: CV.muted, inter: true).lineLimit(1)
                    if let detail { Text(detail).cvText(12, .medium, inter: true).lineLimit(1) }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.dim)
            }
            .padding(10)
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScale())
    }
}

/// Icon-circle row used in lists (origin picker, search places, nearby, hand-off).
struct ListRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let row = HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.cream)
                .frame(width: 36, height: 36).background(CV.glassFill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).cvText(15, .semibold, inter: true).lineLimit(1)
                if let subtitle { Text(subtitle).cvText(12, color: CV.muted, inter: true).lineLimit(1) }
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        if let action { Button(action: action) { row }.buttonStyle(.plain) } else { row }
    }
}

extension ListRow where Trailing == EmptyView {
    init(symbol: String, title: String, subtitle: String? = nil, action: (() -> Void)? = nil) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, action: action) { EmptyView() }
    }
}

/// Square icon tile for Places → Browse by type.
struct TypeTile: View {
    let category: PlaceCategory
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: category.symbol).font(.system(size: 18, weight: .medium))
                Text(category.plural).cvText(12, .medium, inter: true).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(CV.cream)
            .frame(maxWidth: .infinity).frame(height: 80)
            .glassRounded(16)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressScale())
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).cvText(16, .semibold, inter: true).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).cvText(11, color: CV.muted, inter: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .glassRounded(14)
    }
}

/// Start → stops → finish with road km from the start where known.
struct StopTimeline: View {
    let route: DiscoverRoute
    var body: some View {
        let all = [route.start] + route.stops + [route.end]
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(all.enumerated()), id: \.offset) { i, s in
                let last = i == all.count - 1
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle().fill(i == 0 ? CV.cream : last ? CV.red : CV.dim).frame(width: 10, height: 10).padding(.top, 4)
                        if !last { Rectangle().fill(CV.dim.opacity(0.5)).frame(width: 1.5).frame(maxHeight: .infinity) }
                    }
                    .frame(width: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).cvText(14, .semibold, inter: true)
                        Text(i == 0 ? "Start" : last ? "Finish" : s.category?.label ?? "Stop").cvText(11, color: CV.dim, inter: true)
                    }
                    .padding(.bottom, last ? 0 : 16)
                    Spacer()
                    if let km = i == 0 ? 0 : last ? route.estimate.map({ $0.distanceM / 1000 }) : s.km {
                        Text("\(Int(km.rounded())) km").cvText(12, color: CV.muted, inter: true)
                    }
                }
            }
        }
    }
}

/// Floating "Trip · 3 stops — Plan ride" bar.
struct TripBar: View {
    let places: [DiscoverPlace]
    var open: () -> Void
    var plan: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    HStack(spacing: -14) {
                        ForEach(places.prefix(3)) { p in
                            DiscoverImage(photo: p.photos.first, coord: p.coord)
                                .frame(width: 36, height: 36).clipShape(Circle())
                                .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Trip · \(places.count) \(places.count == 1 ? "stop" : "stops")").cvText(14, .semibold, inter: true)
                        Text(places.map(\.name).joined(separator: " · ")).cvText(11, color: CV.muted, inter: true).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: plan) {
                Text("Plan ride").cvText(14, .semibold, color: CV.ink, inter: true)
                    .padding(.horizontal, 16).frame(height: 40).background(CV.cream, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8).padding(.trailing, 6).frame(height: 56)
        .background(.black.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }
}

// MARK: - Screen chrome & states

/// Back button + trailing actions, then the large title and subtitle.
struct DiscoverHeader<Trailing: View>: View {
    @Environment(AppState.self) private var app
    let title: String
    var subtitle: String? = nil
    var eyebrow: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CircleBackButton { app.pop() }
                Spacer()
                trailing
            }
            .padding(.bottom, 18)
            if let eyebrow { Eyebrow(text: eyebrow, color: CV.red).padding(.bottom, 6) }
            Text(title).cvText(32, .bold, tracking: -0.6, inter: true)
            if let subtitle { Text(subtitle).cvText(14, color: CV.muted, inter: true).padding(.top, 4) }
        }
    }
}

extension DiscoverHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, eyebrow: String? = nil) {
        self.init(title: title, subtitle: subtitle, eyebrow: eyebrow) { EmptyView() }
    }
}

/// Icon, title, message and up to two actions (D16b, D17b, D17d, D05b).
struct DiscoverStateView: View {
    let symbol: String
    let title: String
    let message: String
    var primary: (String, () -> Void)? = nil
    var secondary: (String, () -> Void)? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(CV.cream)
                .frame(width: 44, height: 60).background(CV.glassFill, in: Capsule())
            Text(title).cvText(18, .semibold, inter: true).multilineTextAlignment(.center).padding(.top, 6)
            Text(message).cvText(13, color: CV.muted, inter: true).multilineTextAlignment(.center)
            VStack(spacing: 10) {
                if let primary { DiscoverButton(title: primary.0, height: 46, action: primary.1) }
                if let secondary { DiscoverButton(title: secondary.0, style: .secondary, height: 46, action: secondary.1) }
            }
            .frame(maxWidth: 230).padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 40)
    }
}

/// "ⓘ note" footnote / banner.
struct InfoNote: View {
    let text: String
    var symbol = "info.circle"
    var action: (String, () -> Void)? = nil
    var boxed = false
    var body: some View {
        HStack(alignment: boxed ? .center : .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12))
            Text(text).cvText(12, color: CV.muted, inter: true).fixedSize(horizontal: false, vertical: true)
            if let action {
                Spacer(minLength: 4)
                Button(action.0, action: action.1).cvText(13, .semibold, color: CV.red, inter: true).buttonStyle(.plain)
            }
        }
        .foregroundStyle(CV.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(boxed ? 12 : 0)
        .background { if boxed { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CV.surface) } }
    }
}

/// D17c · offline / stale-cache banner. Renders nothing when online with fresh data.
struct OfflineBanner: View {
    private var store: DiscoverStore { .shared }
    var body: some View {
        if let note = store.offlineNote { InfoNote(text: note, symbol: "wifi.slash", boxed: true) }
    }
}

/// "Plan this ride" — disabled with its reason when the existing planner can't route (offline).
struct PlanRideButton: View {
    private var store: DiscoverStore { .shared }
    var title = "Plan this ride"
    var compact = false
    var action: () -> Void
    var body: some View {
        if store.canPlan {
            DiscoverButton(title: title, action: action)
        } else {
            DiscoverButton(title: compact ? "Offline" : "Planning needs a connection", symbol: "wifi.slash", style: .secondary) {}
                .disabled(true).opacity(0.6)
                .accessibilityHint("Connect to the internet to plan this ride")
        }
    }
}

/// Shimmering placeholder block (D17a).
struct Skeleton: View {
    var corner: CGFloat = 16
    @State private var phase = false
    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(CV.surface.opacity(phase ? 1 : 0.55))
            .animation(.easeInOut(duration: 0.9).repeatForever(), value: phase)
            .onAppear { phase = true }
            .accessibilityHidden(true)
    }
}

/// Subtle press feedback for cards.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Scroll container for Discover screens: dark background, 20pt gutters, room for the tab bar / trip bar.
struct DiscoverScroll<Content: View>: View {
    var bottomInset: CGFloat = 40
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 20)
                .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        .background(CV.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }
}

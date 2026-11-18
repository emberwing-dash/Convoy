// RideCards.swift — the shareable ride cards. Each is laid out on a fixed canvas (see CardFormat) so
// the exported PNG is pixel-exact, and reflows for 9:16, 4:5, 1:1 and 16:9.
import SwiftUI

/// One card, at its canvas size. Used for the live preview (scaled) and for export.
struct RideCardCanvas: View {
    let design: CardDesign
    let data: RideCardData
    let options: CardOptions
    let format: CardFormat
    var photo: UIImage? = nil
    var satellite: UIImage? = nil
    var filmPhotos: [UIImage] = []
    /// The studio shows a checkerboard behind the transparent sticker; exports don't.
    var previewChecker = false

    var body: some View {
        Group {
            switch design {
            case .classic: ClassicCard(data: data, o: options, f: format)
            case .satellite: SatelliteCard(data: data, o: options, f: format, image: satellite)
            case .photo: PhotoCard(data: data, o: options, f: format, photo: photo)
            case .gauge: GaugeCard(data: data, o: options, f: format)
            case .crew: CrewCard(data: data, o: options, f: format)
            case .pass: PassCard(data: data, o: options, f: format)
            case .sticker: StickerCard(data: data, o: options, f: format, checker: previewChecker)
            case .routeSheet: RouteSheetCard(data: data, o: options, f: format)
            case .filmStrip: FilmStripCard(data: data, o: options, f: format, photos: filmPhotos)
            }
        }
        .frame(width: format.canvas.width, height: format.canvas.height)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Shared pieces

struct ConvoyMark: View {
    var color: Color = .white
    var size: CGFloat = 15
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(hex: 0xFF3B30)).frame(width: size * 0.45, height: size * 0.45)
            Text("convoy").font(.system(size: size, weight: .heavy)).foregroundStyle(color)
        }
    }
}

private let routeRed = Color(hex: 0xFF3B30)
/// Route line colour on every card: start → finish in blue.
let routeBlue = Color(hex: 0x2F80FF)

private extension View {
    /// Card type: bold, tight, slightly rounded numbers like an activity sticker.
    func cardNumber(_ size: CGFloat, _ color: Color = .white) -> some View {
        self.font(.system(size: size, weight: .bold, design: .default)).monospacedDigit()
            .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.5)
    }
    func cardLabel(_ size: CGFloat, _ color: Color = .white.opacity(0.72), tracking: CGFloat = 0) -> some View {
        self.font(.system(size: size, weight: .semibold)).tracking(tracking).foregroundStyle(color).lineLimit(1)
    }
}

/// Small header: "SUN 12 OCT · NANDI HILLS".
private func headerLine(_ data: RideCardData, _ o: CardOptions, color: Color = .white.opacity(0.55)) -> some View {
    let parts = [o.showDate ? data.dateLine : nil, o.showTitle && !o.title.isEmpty ? o.title.uppercased() : nil]
        .compactMap { $0 }
    return Text(parts.joined(separator: " · ")).cardLabel(10, color, tracking: 1.4)
}

/// Stacked "label / big value" stats.
private struct StackedStats: View {
    let data: RideCardData
    let stats: [CardStat]
    var color: Color = .white
    var size: CGFloat = 34
    var spacing: CGFloat = 12
    var body: some View {
        VStack(spacing: spacing) {
            ForEach(stats) { s in
                VStack(spacing: 2) {
                    Text(s.label).cardLabel(size * 0.36, color.opacity(0.75))
                    Text(data.value(s)).cardNumber(size, color)
                }
            }
        }
    }
}

/// Two-column grid of stats.
private struct GridStats: View {
    let data: RideCardData
    let stats: [CardStat]
    var color: Color = .white
    var size: CGFloat = 20
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 14) {
            ForEach(stats) { s in
                VStack(spacing: 2) {
                    Text(s.label).cardLabel(size * 0.5, color.opacity(0.7))
                    Text(data.value(s)).cardNumber(size, color)
                }
            }
        }
    }
}

/// "62.4  1:41  37" row with tiny labels, for the bottom of image cards.
private struct RowStats: View {
    let data: RideCardData
    let stats: [CardStat]
    var color: Color = .white
    var size: CGFloat = 26
    var body: some View {
        HStack(alignment: .bottom, spacing: 22) {
            ForEach(stats.prefix(3)) { s in
                VStack(alignment: .leading, spacing: 1) {
                    Text(data.number(s)).cardNumber(size, color)
                    Text(s.shortLabel).cardLabel(size * 0.28, color.opacity(0.7), tracking: 0.8)
                }
            }
        }
    }
}

private struct RouteArt: View {
    let coords: [Coord]
    var color: Color = routeBlue
    var width: CGFloat = 3.5
    var glow = false
    var ends = false
    var body: some View {
        ZStack {
            if glow {
                RouteLine(coords: coords).stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: width * 3, lineCap: .round, lineJoin: .round))
                    .blur(radius: 6)
            }
            RouteLine(coords: coords).stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            if ends { RouteEnds(coords: coords, color: color) }
        }
    }
}

// MARK: - 1. Convoy Classic

private struct ClassicCard: View {
    let data: RideCardData, o: CardOptions, f: CardFormat

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2B2B30), Color(hex: 0x141416), Color(hex: 0x0E0E10)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [routeBlue.opacity(0.18), .clear], center: .bottom, startRadius: 0, endRadius: 320)
            if f == .wide {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        headerLine(data, o)
                        StackedStats(data: data, stats: o.stats, size: 30, spacing: 8)
                        Spacer(minLength: 0)
                        if o.showMark { ConvoyMark() }
                    }
                    if o.showRoute { RouteArt(coords: data.displayPath(trim: o.trimEnds), glow: true, ends: true).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
                .padding(28)
            } else {
                VStack(spacing: 0) {
                    headerLine(data, o).padding(.top, f.isCompact ? 22 : 30)
                    Spacer(minLength: 10)
                    StackedStats(data: data, stats: o.stats, size: f.isCompact ? 28 : 36, spacing: f.isCompact ? 6 : 14)
                    Spacer(minLength: 10)
                    if o.showRoute {
                        RouteArt(coords: data.displayPath(trim: o.trimEnds), glow: true, ends: true)
                            .frame(height: f == .story ? 130 : 70).padding(.horizontal, 40)
                    }
                    Spacer(minLength: 8)
                    if o.showMark { ConvoyMark().padding(.bottom, f.isCompact ? 18 : 28) }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - 2. Satellite

private struct SatelliteCard: View {
    let data: RideCardData, o: CardOptions, f: CardFormat
    let image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0x24301F), Color(hex: 0x111511)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 8) {
                    if data.path.count > 1 || data.endCoord != nil { ProgressView().tint(.white) }
                    Text(data.path.count > 1 || data.endCoord != nil ? "Loading satellite view…" : "No GPS track for this ride").cardLabel(11)
                }
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.28),
                                   .init(color: .clear, location: 0.62), .init(color: .black.opacity(0.8), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                if o.showDate { Text(data.dateLine).cardLabel(10, .white.opacity(0.75), tracking: 1.4) }
                if o.showTitle, !o.title.isEmpty {
                    Text(o.title)
                        .font(.system(size: f.isCompact ? 26 : 32, weight: .heavy)).tracking(-0.8).foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.6).padding(.top, 2)
                }
                Spacer(minLength: 0)
                RowStats(data: data, stats: o.stats, size: f.isCompact ? 22 : 28)
                if o.showMark { ConvoyMark(size: 13).padding(.top, 10) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .padding(.bottom, 16)   // keep clear of the Apple Maps attribution (bottom-left of the imagery)
        }
    }
}

// MARK: - 3. Your photo

private struct PhotoCard: View {
    let data: RideCardData, o: CardOptions, f: CardFormat
    let photo: UIImage?

    private var text: Color { o.accent.color }

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: f.canvas.width, height: f.canvas.height).clipped()
            } else {
                LinearGradient(colors: [Color(hex: 0x2C3A4A), Color(hex: 0x10151B)], startPoint: .top, endPoint: .bottom)
            }
            // A soft scrim so white text reads on bright photos.
            if o.accent != .ink {
                LinearGradient(colors: [.black.opacity(0.28), .clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
            }
            layout
            if o.showMark {
                VStack { Spacer(); ConvoyMark(color: text).padding(.bottom, f.isCompact ? 16 : 24) }
            }
        }
    }

    @ViewBuilder
    private var layout: some View {
        let path = data.displayPath(trim: o.trimEnds)
        switch o.photoLayout {
        case .stacked:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                StackedStats(data: data, stats: o.stats, color: text, size: f.isCompact ? 28 : 36, spacing: f.isCompact ? 6 : 12)
                    .shadow(color: .black.opacity(o.accent == .ink ? 0 : 0.35), radius: 8)
                    .offset(o.statsOffset)
                Spacer(minLength: 0)
                if o.showRoute { RouteArt(coords: path).frame(height: f == .story ? 110 : 64).padding(.horizontal, 60).offset(o.routeOffset) }
                Spacer(minLength: 50)
            }
        case .grid:
            VStack(spacing: 0) {
                GridStats(data: data, stats: o.stats, color: text, size: f.isCompact ? 17 : 21)
                    .padding(.horizontal, 34).padding(.top, f.isCompact ? 24 : 54)
                    .offset(o.statsOffset)
                Spacer(minLength: 0)
                if o.showRoute { RouteArt(coords: path).frame(height: 80).padding(.horizontal, 70).offset(o.routeOffset) }
                Spacer(minLength: 50)
            }
        case .bigNumber:
            VStack(alignment: .leading, spacing: 0) {
                if o.showTitle, !o.title.isEmpty {
                    Text(o.title).font(.system(size: 24, weight: .heavy)).foregroundStyle(text)
                        .lineLimit(2).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                if o.showRoute { RouteArt(coords: path).frame(height: 70).padding(.trailing, 120).offset(o.routeOffset) }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(data.kmText).font(.system(size: f.isCompact ? 72 : 96, weight: .heavy)).tracking(-3).foregroundStyle(text)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("KM").font(.system(size: 18, weight: .heavy)).foregroundStyle(routeRed)
                }
                .offset(o.statsOffset)
                Text(o.stats.filter { $0 != .distance }.prefix(2).map { data.value($0) }.joined(separator: " · ").uppercased())
                    .cardLabel(11, text.opacity(0.8), tracking: 1)
                    .padding(.bottom, 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(26)
        case .routeStats:
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                if o.showRoute { RouteArt(coords: path, width: 4, glow: true, ends: true)
                    .frame(height: f == .story ? 220 : 120).padding(.horizontal, 44).offset(o.routeOffset) }
                RowStats(data: data, stats: o.stats, color: text, size: 26).offset(o.statsOffset)
                Spacer(minLength: 54)
            }
        }
    }
}

// MARK: - 4. Speedometer

private struct GaugeCard: View {
    let data: RideCardData, o: CardOptions, f: CardFormat

    private var maxScale: Double { max(140, (data.maxKmh / 20).rounded(.up) * 20) }

    var body: some View {
        ZStack {
            Color(hex: 0x0D0D0F)
            RadialGradient(colors: [routeRed.opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 10, endRadius: 280)
            if f == .wide {
                HStack(spacing: 30) {
                    dial.frame(width: 250, height: 250)
                    VStack(alignment: .leading, spacing: 14) { title; odometer; footer }
                }
                .padding(28)
            } else {
                VStack(alignment: .leading, spacing: f.isCompact ? 10 : 18) {
                    title
                    dial.frame(height: f == .story ? 280 : (f.isCompact ? 170 : 210)).frame(maxWidth: .infinity)
                    odometer.frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                    footer
                }
                .padding(26)
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            if o.showDate { Text(data.dateLine).cardLabel(10, .white.opacity(0.55), tracking: 1.4) }
            if o.showTitle, !o.title.isEmpty {
                Text(o.title).font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    private var dial: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 + size * 0.06)
            let r = size * 0.44
            let start = 135.0, sweep = 270.0
            let frac = min(1, data.avgKmh / maxScale)
            ZStack {
                Path { p in p.addArc(center: center, radius: r, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false) }
                    .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                Path { p in p.addArc(center: center, radius: r, startAngle: .degrees(start), endAngle: .degrees(start + sweep * frac), clockwise: false) }
                    .stroke(routeRed, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                ForEach(0..<8) { i in
                    let a = (start + sweep * Double(i) / 7) * .pi / 180
                    let inner = CGPoint(x: center.x + cos(a) * r * 0.78, y: center.y + sin(a) * r * 0.78)
                    let outer = CGPoint(x: center.x + cos(a) * r * 0.9, y: center.y + sin(a) * r * 0.9)
                    Path { p in p.move(to: inner); p.addLine(to: outer) }.stroke(Color.white.opacity(0.6), lineWidth: 2)
                    Text("\(Int(maxScale / 7 * Double(i)))").cardLabel(size * 0.045, .white.opacity(0.5))
                        .position(x: center.x + cos(a) * r * 0.64, y: center.y + sin(a) * r * 0.64)
                }
                let na = (start + sweep * frac) * .pi / 180
                Path { p in
                    p.move(to: center)
                    p.addLine(to: CGPoint(x: center.x + cos(na) * r * 0.72, y: center.y + sin(na) * r * 0.72))
                }.stroke(routeRed, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                Circle().strokeBorder(routeRed, lineWidth: 4).background(Circle().fill(Color(hex: 0x0D0D0F)))
                    .frame(width: 18, height: 18).position(center)
                VStack(spacing: 0) {
                    Text(data.avgText).cardNumber(size * 0.17)
                    Text("AVG KM/H").cardLabel(size * 0.04, .white.opacity(0.6), tracking: 1)
                }
                .position(x: center.x, y: center.y + r * 0.55)
            }
        }
    }

    /// Distance on an odometer: "0 6 2 [4] KM".
    private var odometer: some View {
        let tenths = Int((data.distanceKm * 10).rounded())
        let digits = Array(String(format: "%04d", min(tenths, 99_999)))
        return HStack(spacing: 4) {
            ForEach(Array(digits.enumerated()), id: \.offset) { i, d in
                Text(String(d)).font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(i == digits.count - 1 ? .black : .white)
                    .frame(width: 32, height: 44)
                    .background(i == digits.count - 1 ? routeRed : Color(hex: 0x1E1E22), in: RoundedRectangle(cornerRadius: 6))
            }
            Text("KM").cardLabel(12, .white.opacity(0.6)).padding(.leading, 4)
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text(data.clockText).font(.system(size: 34, weight: .light, design: .monospaced)).foregroundStyle(.white)
                Text("RIDING").cardLabel(10, .white.opacity(0.5), tracking: 1.2)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 5) {
                if data.maxKmh > 0 { fact("bolt.fill", Color(hex: 0xF4C26B), "TOP \(data.topText) KM/H") }
                if o.showCrew { fact("person.3.fill", Color(hex: 0x6FCF97), "\(data.riderCount) RIDER\(data.riderCount == 1 ? "" : "S")") }
                if o.showMark { ConvoyMark(size: 13).padding(.top, 4) }
            }
        }
    }

    private func fact(_ icon: String, _ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(c)
            Text(t).cardLabel(10, .white.opacity(0.8), tracking: 0.8)
        }
    }
}

// MARK: - 5. Crew

private struct CrewCard: View {
    let data: RideCardData, o: CardOptions, f: CardFormat

    private var riders: [RiderRef] {
        data.riders.isEmpty ? [RiderRef(id: UUID(), name: data.riderName, username: nil, avatarBase64: nil)] : data.riders
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3A0E0C), Color(hex: 0x120707), .black], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text([o.showCrew ? data.crewName?.uppercased() : nil, o.showDate ? data.dateLine : nil].compactMap { $0 }.joined(separator: " · "))
                    .cardLabel(10, .white.opacity(0.6), tracking: 1.4)
                Text(data.riderCount == 1 ? "One rider.\nOne road." : "\(data.riderWord) riders.\nOne road.")
                    .font(.system(size: f.isCompact ? 26 : 34, weight: .heavy)).tracking(-0.8).foregroundStyle(.white)
                    .lineSpacing(-4).padding(.top, 4)
                road.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, f.isCompact ? 8 : 16)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(data.kmText).font(.system(size: 52, weight: .heavy)).tracking(-2).foregroundStyle(.white)
                    Text("KM").font(.system(size: 13, weight: .heavy)).foregroundStyle(routeRed)
                }
                Text(([o.showTitle && !o.title.isEmpty ? o.title.uppercased() : nil, data.timeText.uppercased()] as [String?]).compactMap { $0 }.joined(separator: " · "))
                    .cardLabel(10, .white.opacity(0.6), tracking: 1)
                if o.showMark { ConvoyMark(size: 13).padding(.top, 12) }
            }
            .padding(24)
        }
    }

    /// A road from above with riders in formation on either side of the centre line.
    private var road: some View {
        GeometryReader { geo in
            let w = min(120, geo.size.width * 0.34)
            let shown = Array(riders.prefix(f.isCompact ? 4 : 6))
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x16161A)).frame(width: w)
                Path { p in p.move(to: CGPoint(x: geo.size.width / 2, y: 8)); p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height - 8)) }
                    .stroke(Color(hex: 0xF4C26B).opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                ForEach(Array(shown.enumerated()), id: \.offset) { i, r in
                    riderTag(r, index: i)
                        .position(slot(i, count: shown.count, roadWidth: w, size: geo.size))
                }
            }
        }
    }

    /// Riders alternate left and right of the centre line, top to bottom.
    private func slot(_ i: Int, count: Int, roadWidth w: CGFloat, size: CGSize) -> CGPoint {
        let left = i % 2 == 0
        let rows = CGFloat(max(count, 1)) + 0.4
        let y: CGFloat = size.height * (CGFloat(i) + 0.7) / rows
        let lane: CGFloat = w * 0.24 + 34
        let x: CGFloat = size.width / 2 + (left ? -lane : lane)
        return CGPoint(x: x, y: y)
    }

    private func riderTag(_ r: RiderRef, index i: Int) -> some View {
        let left = i % 2 == 0
        let first = r.name.components(separatedBy: " ").first ?? r.name
        return HStack(spacing: 6) {
            if !left { avatar(r, lead: i == 0) }
            Text(first)
                .font(.system(size: 13, weight: .semibold, design: .serif)).italic()
                .foregroundStyle(Color.white.opacity(0.9))
            if left { avatar(r, lead: i == 0) }
        }
        .fixedSize()
    }

    private func avatar(_ r: RiderRef, lead: Bool) -> some View {
        AvatarChip(data: r.avatarData, name: r.name, size: 30)
            .overlay(Circle().strokeBorder(lead ? routeRed : .white.opacity(0.7), lineWidth: 2))
    }
}

// MARK: - 6. Ride pass

private struct PassCard: View {
    let data: RideCardData, o: CardOptions, f: CardFormat
    private let paper = Color(hex: 0xF3EEE2), ink = Color(hex: 0x16140F)

    var body: some View {
        ZStack {
            Color(hex: 0x0D0D0F)
            RadialGradient(colors: [routeRed.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 300)
            VStack(spacing: 10) {
                ticket
                    .frame(maxWidth: f == .wide ? 300 : .infinity)
                if o.showMark { ConvoyMark(size: 13) }
            }
            .padding(.horizontal, f == .wide ? 0 : 26).padding(.vertical, f.isCompact ? 22 : 28)
        }
    }

    private var ticket: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: f.isCompact ? 6 : 12) {
                Text("CONVOY · RIDE PASS · Nº \(String(format: "%02d", max(1, data.rideNumber)))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(ink.opacity(0.6))
                place(RideCardData.code(data.startName), data.startName, data.startTimeText)
                if !f.isCompact {
                    RouteLine(coords: data.displayPath(trim: o.trimEnds)).stroke(routeBlue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(height: 36).padding(.horizontal, 40)
                }
                place(RideCardData.code(data.endName.isEmpty ? data.place : data.endName), data.endName.isEmpty ? data.place : data.endName, data.endTimeText)
                Rectangle().fill(ink.opacity(0.15)).frame(height: 1)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(Array(o.stats.prefix(4).enumerated()), id: \.offset) { i, s in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.label.uppercased()).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(ink.opacity(0.55))
                            Text(data.value(s)).font(.system(size: 18, weight: .bold)).foregroundStyle(i == 0 ? routeRed : ink)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(paper)
            // Perforation
            HStack(spacing: 0) {
                Circle().fill(Color(hex: 0x0D0D0F)).frame(width: 18, height: 18).offset(x: -9)
                Spacer()
                Circle().fill(Color(hex: 0x0D0D0F)).frame(width: 18, height: 18).offset(x: 9)
            }
            .frame(height: 0).zIndex(1)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nº \(String(format: "%02d", max(1, data.rideNumber)))").font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                    Text("\(data.dateLine) · FINISHED").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                barcode.frame(width: 70, height: 30)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(routeRed)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func place(_ code: String, _ name: String, _ time: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(code).font(.system(size: f.isCompact ? 34 : 44, weight: .heavy)).tracking(-1).foregroundStyle(ink)
            Text("\(name.uppercased()) · \(time)").font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(ink.opacity(0.6)).lineLimit(1)
        }
    }

    private var barcode: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { i in
                    Rectangle().fill(.white).frame(width: [1.0, 2, 3, 1, 2, 1, 3, 2][i % 8], height: geo.size.height)
                }
            }
        }
    }
}

// MARK: - 7. Sticker (transparent)

private struct StickerCard: View {
    let data: RideCardData, o: CardOptions, f: CardFormat
    var checker: Bool

    var body: some View {
        ZStack {
            if checker { Checkerboard() }
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 0)
                if o.showRoute {
                    RouteArt(coords: data.displayPath(trim: o.trimEnds), width: 5, glow: true, ends: true)
                        .frame(height: f == .story ? 220 : 120)
                        .shadow(color: .black.opacity(0.35), radius: 6)
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(data.kmText).font(.system(size: f.isCompact ? 60 : 78, weight: .heavy)).tracking(-2)
                    Text("KM").font(.system(size: 16, weight: .heavy))
                }
                .foregroundStyle(o.accent == .ink ? .black : .white)
                .shadow(color: .black.opacity(0.35), radius: 6)
                Text([o.showTitle && !o.title.isEmpty ? o.title.uppercased() : nil, o.showDate ? data.dateShort : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .cardLabel(11, (o.accent == .ink ? Color.black : .white).opacity(0.85), tracking: 1)
                if o.showMark { ConvoyMark(color: o.accent == .ink ? .black : .white, size: 13).padding(.top, 6) }
                Spacer(minLength: 0).frame(maxHeight: 30)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 14
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) where (Int(x / s) + Int(y / s)) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.white.opacity(0.06)))
                }
            }
        }
        .background(Color(hex: 0x1A1A1D))
    }
}

// MARK: - 8. Route sheet (start, stops, finish)

private struct RouteSheetCard: View {
    let data: RideCardData, o: CardOptions, f: CardFormat
    private let paper = Color(hex: 0xF1ECE0), ink = Color(hex: 0x16140F)

    private struct Row: Identifiable { let id = UUID(); let km: String; let symbol: String; let name: String; let red: Bool }

    private var rows: [Row] {
        var out = [Row(km: "0.0", symbol: "circle.circle.fill", name: data.startName.isEmpty ? "Start" : data.startName, red: false)]
        let kms = data.stopKms
        let maxStops = f == .story ? 5 : (f.isCompact ? 1 : 3)
        for (i, stop) in data.stops.prefix(maxStops).enumerated() {
            let km = kms[i].map { String(format: "%.1f", $0) } ?? "—"
            out.append(Row(km: km, symbol: StopKind(rawValue: stop.kind)?.symbol ?? "mappin", name: stop.name, red: false))
        }
        out.append(Row(km: data.kmText, symbol: "flag.checkered", name: data.endName.isEmpty ? data.place : data.endName, red: true))
        return out
    }

    var body: some View {
        ZStack {
            paper
            VStack(alignment: .leading, spacing: f.isCompact ? 8 : 14) {
                Text("ROUTE SHEET · Nº \(String(format: "%02d", max(1, data.rideNumber))) · \(data.dateShort)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(ink.opacity(0.6))
                if o.showTitle, !o.title.isEmpty {
                    Text(o.title).font(.system(size: f.isCompact ? 24 : 30, weight: .heavy)).tracking(-0.6)
                        .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.6)
                }
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Rectangle().fill(ink.opacity(0.25)).frame(height: 1) }
                        HStack(spacing: 0) {
                            Text(r.km).font(.system(size: f.isCompact ? 16 : 20, weight: .bold)).foregroundStyle(Color(hex: 0xE5332A))
                                .frame(width: 74, alignment: .leading).padding(.leading, 10)
                            Rectangle().fill(ink.opacity(0.25)).frame(width: 1)
                            Image(systemName: r.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(ink)
                                .frame(width: 46)
                            Rectangle().fill(ink.opacity(0.25)).frame(width: 1)
                            Text(r.name.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(ink)
                                .lineLimit(2).minimumScaleFactor(0.7).padding(.horizontal, 10)
                            Spacer(minLength: 0)
                        }
                        .frame(height: f.isCompact ? 32 : 44)
                    }
                }
                .overlay(Rectangle().strokeBorder(ink.opacity(0.4), lineWidth: 1))
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(data.kmText).font(.system(size: f.isCompact ? 44 : 60, weight: .heavy)).tracking(-2).foregroundStyle(ink)
                    Text("KM").font(.system(size: 13, weight: .heavy)).foregroundStyle(Color(hex: 0xE5332A))
                }
                Text("\(data.clockText) RIDING · \(data.riderCount) RIDER\(data.riderCount == 1 ? "" : "S") · \(data.stops.count) STOP\(data.stops.count == 1 ? "" : "S")")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(ink.opacity(0.6))
                if o.showMark { ConvoyMark(color: ink, size: 13).padding(.top, 4) }
            }
            .padding(f.isCompact ? 20 : 26)
        }
    }
}

// MARK: - 9. Film strip (ride photos)

private struct FilmStripCard: View {
    let data: RideCardData, o: CardOptions, f: CardFormat
    let photos: [UIImage]

    var body: some View {
        ZStack {
            Color.black
            HStack(spacing: 0) {
                sprockets
                VStack(spacing: 6) {
                    let shown = Array(photos.prefix(f.isCompact ? 2 : 3))
                    if shown.isEmpty {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x1C1C20))
                            .overlay(Image(systemName: "photo.on.rectangle.angled").font(.system(size: 28)).foregroundStyle(.white.opacity(0.3)))
                    }
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, img in
                        Color.clear
                            .overlay(Image(uiImage: img).resizable().scaledToFill())
                            .clipped()
                            .overlay(alignment: .bottomLeading) {
                                Text(String(format: "%02d%@", max(1, data.rideNumber), ["A", "B", "C"][i]))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: 0xF4C26B))
                                    .padding(4)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if i == 1 {
                                    Text(data.dateShort.replacingOccurrences(of: ".", with: " "))
                                        .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: 0xFF8A3D))
                                        .shadow(color: .black.opacity(0.6), radius: 2).padding(6)
                                }
                            }
                    }
                    footer.frame(height: f.isCompact ? 70 : 96)
                }
                .padding(.vertical, 10)
                sprockets
            }
        }
    }

    private var sprockets: some View {
        GeometryReader { geo in
            VStack(spacing: 9) {
                ForEach(0..<Int(geo.size.height / 19), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.85)).frame(width: 9, height: 10)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(width: 24)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                if o.showTitle, !o.title.isEmpty {
                    Text(o.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                Text(o.stats.prefix(3).map { data.value($0) }.joined(separator: " · ").uppercased())
                    .cardLabel(10, .white.opacity(0.8), tracking: 0.8)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                if o.showRoute { RouteArt(coords: data.displayPath(trim: o.trimEnds), width: 2.5).frame(width: 70, height: 34) }
                if o.showMark { ConvoyMark(size: 12) }
            }
        }
        .padding(.horizontal, 4)
    }
}

// NavParts.swift
import SwiftUI
import MapKit
import CoreLocation

let navPanel = Color(hex: 0x1A1A1D)
let amberC = Color(hex: 0xFFB020)

enum StopKind: String, CaseIterable, Identifiable {
    case fuel = "Fuel"
    case food = "Food"
    case rest = "Rest"
    case viewpoint = "Viewpoint"
    case mechanic = "Mechanic"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .fuel: "fuelpump"
        case .food: "fork.knife"
        case .rest: "cup.and.saucer"
        case .viewpoint: "mountain.2"
        case .mechanic: "wrench.adjustable"
        }
    }
    var tint: Color {
        switch self {
        case .fuel: Color(hex: 0xFFB020)
        case .food: Color(hex: 0xFF3B30)
        case .rest: Color(hex: 0x30D158)
        case .viewpoint: Color(hex: 0x4C8DFF)
        case .mechanic: Color(hex: 0xA77BFF)
        }
    }
    var title: String {
        switch self {
        case .fuel: "Petrol nearby"
        case .food: "Food nearby"
        case .rest: "Cafes & rest stops"
        case .viewpoint: "Viewpoints nearby"
        case .mechanic: "Mechanics nearby"
        }
    }
    var mapKitQuery: String {
        switch self {
        case .fuel: "petrol pump"
        case .food: "restaurant"
        case .rest: "cafe"
        case .viewpoint: "viewpoint"
        case .mechanic: "mechanic"
        }
    }
}

struct StopPlace: Hashable {
    var name: String
    var address: String
    var coordinate: CLLocationCoordinate2D
    var short: String { name }

    static func == (l: StopPlace, r: StopPlace) -> Bool {
        l.name == r.name &&
        abs(l.coordinate.latitude - r.coordinate.latitude) < 1e-5 &&
        abs(l.coordinate.longitude - r.coordinate.longitude) < 1e-5
    }
    func hash(into h: inout Hasher) {
        h.combine(name)
        h.combine(coordinate.latitude)
        h.combine(coordinate.longitude)
    }
}

@MainActor
final class POIFinder {
    static let shared = POIFinder()

    /// Finds POIs of the given kind near the supplied coordinate.
    func findPlaces(kind: StopKind, near center: CLLocationCoordinate2D,
                    span: MKCoordinateSpan = .init(latitudeDelta: 0.15, longitudeDelta: 0.15)) async -> [StopPlace] {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = kind.mapKitQuery
        req.region = MKCoordinateRegion(center: center, span: span)
        req.resultTypes = .pointOfInterest
        guard let res = try? await MKLocalSearch(request: req).start() else { return [] }
        return res.mapItems.prefix(10).compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            return StopPlace(
                name: name,
                address: item.placemark.title ?? "",
                coordinate: item.placemark.coordinate)
        }
    }
}

// MARK: - Small reusable chrome used by navigation

struct MapCallout: View {
    let text: String
    var selected = false
    var body: some View {
        Text(text).cvText(13, .semibold, color: .white, inter: true)
            .padding(.horizontal, 10).frame(height: 28)
            .background(selected ? CV.red : Color(hex: 0x1A1A1D, opacity: 0.92), in: Capsule())
    }
}

struct YouMarker: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0x0A84FF, opacity: 0.25)).frame(width: 44, height: 44)
            Circle().fill(Color(hex: 0x0A84FF)).frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
    }
}

extension View {
    func navCard(_ radius: CGFloat = 26, fill: Color = Color(hex: 0x1A1A1D).opacity(0.96)) -> some View {
        self
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

struct RingAvatar: View {
    var data: Data?
    var name: String
    var size: CGFloat
    var body: some View {
        AvatarChip(data: data, name: name, size: size)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
    }
}

// MARK: - Nav chrome (kept as-is structurally)

struct AppleMapsTopBanner: View {
    var symbol: String = "arrow.turn.up.left"
    var tint: Color = .white
    var distance: String = ""
    var instruction: String = ""
    var subInstruction: String? = nil
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CV.cream)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }.buttonStyle(.plain)
            }
            ZStack {
                Circle().fill(Color.white.opacity(0.1)).frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                if !distance.isEmpty {
                    Text(distance).font(.system(size: 24, weight: .bold)).foregroundStyle(CV.cream)
                }
                Text(instruction).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CV.cream).lineLimit(1)
                if let sub = subInstruction, !sub.isEmpty {
                    Text(sub).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CV.cream.opacity(0.6)).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(hex: 0x1A1A1D).opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.4), radius: 18, y: 4)
        )
    }
}

struct AppleMapsRightControls: View {
    var isTrackingUser: Bool
    var isVoiceMuted: Bool
    var onRecentre: () -> Void
    var onToggleVoice: () -> Void
    var onSOS: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onRecentre) {
                Image(systemName: isTrackingUser ? "location.fill" : "location")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isTrackingUser ? CV.red : CV.cream)
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            }.buttonStyle(.plain)

            Button(action: onToggleVoice) {
                Image(systemName: isVoiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isVoiceMuted ? CV.cream.opacity(0.5) : CV.cream)
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            }.buttonStyle(.plain)

            Button(action: onSOS) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CV.red)
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Circle())
                    .overlay(Circle().strokeBorder(CV.red.opacity(0.4), lineWidth: 1.5))
            }.buttonStyle(.plain)
        }
    }
}

struct AppleMapsSpeedometer: View {
    var speed: Int
    var speedLimit: Int? = nil
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle().fill(Color(hex: 0x1A1A1D, opacity: 0.95))
                    .frame(width: 64, height: 64)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                VStack(spacing: 0) {
                    Text("\(speed)").cvText(22, .bold, inter: true)
                    Text("km/h").cvText(9, color: CV.cream.opacity(0.6), inter: true)
                }
            }
            if let limit = speedLimit {
                Text("\(limit)").cvText(13, .bold, color: .black, inter: true)
                    .frame(width: 28, height: 28)
                    .background(.white, in: Circle())
                    .overlay(Circle().strokeBorder(CV.red, lineWidth: 2.5))
            }
        }
    }
}

// MARK: - Bottom sheet (no mock data — quickStop is optional and comes from MapKit)

struct AppleMapsBottomSheet: View {
    var arrivalTime: String
    var durationValue: String
    var durationUnit: String
    var distanceValue: String
    var distanceUnit: String
    var destinationName: String
    var quickStop: StopPlace? = nil
    var riderCount: Int = 1
    @Binding var isExpanded: Bool
    var isVoiceMuted: Bool
    var onAddStop: () -> Void
    var onRiders: () -> Void
    var onShareETA: () -> Void
    var onSOS: () -> Void
    var onVoiceToggle: () -> Void
    var onEndRoute: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { isExpanded.toggle() }
            } label: {
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 36, height: 5)
                    .padding(.top, 10).padding(.bottom, 12)
            }.buttonStyle(.plain)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                VStack(spacing: 2) {
                    Text(arrivalTime).font(.system(size: 26, weight: .bold)).foregroundStyle(CV.cream)
                    Text("arrival").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CV.cream.opacity(0.55))
                }.frame(maxWidth: .infinity)
                VStack(spacing: 2) {
                    Text(durationValue).font(.system(size: 26, weight: .bold))
                        .foregroundStyle(isExpanded ? Color(hex: 0x3897F0) : CV.cream)
                    Text(durationUnit).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isExpanded ? Color(hex: 0x3897F0) : CV.cream.opacity(0.55))
                }.frame(maxWidth: .infinity)
                VStack(spacing: 2) {
                    Text(distanceValue).font(.system(size: 26, weight: .bold)).foregroundStyle(CV.cream)
                    Text(distanceUnit).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CV.cream.opacity(0.55))
                }.frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { isExpanded.toggle() }
            }

            if isExpanded {
                VStack(spacing: 12) {
                    // Quick stop from real MapKit (hidden if no nearby POI)
                    if let stop = quickStop {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color(hex: 0xFF9500)).frame(width: 40, height: 40)
                                Image(systemName: "cup.and.saucer.fill")
                                    .font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.name).font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(CV.cream).lineLimit(1)
                                if !stop.address.isEmpty {
                                    Text(stop.address).font(.system(size: 12))
                                        .foregroundStyle(CV.cream.opacity(0.6)).lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(spacing: 0) {
                        actionRow(icon: "plus", iconColor: Color(hex: 0x007AFF),
                                  title: "Add Stop", action: onAddStop)
                        divider
                        actionRow(icon: "person.3.fill", iconColor: Color(hex: 0xAF52DE),
                                  title: "Convoy Riders",
                                  badge: riderCount > 1 ? "\(riderCount) live" : nil,
                                  action: onRiders)
                        divider
                        actionRow(icon: "person.crop.circle.badge.plus", iconColor: Color(hex: 0x34C759),
                                  title: "Share ETA", action: onShareETA)
                        divider
                        actionRow(icon: "exclamationmark.bubble.fill", iconColor: Color(hex: 0xFF3B30),
                                  title: "Report an Incident",
                                  subtitle: "SOS Emergency & Convoy Alert", action: onSOS)
                        divider
                        actionRow(icon: isVoiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                  iconColor: Color(hex: 0x8E8E93),
                                  title: "Voice Controls",
                                  badge: isVoiceMuted ? "Muted" : "On", action: onVoiceToggle)
                    }
                    .background(Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button(action: onEndRoute) {
                        Text("End Route")
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Color(hex: 0xFF3B30),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }.buttonStyle(.plain).padding(.top, 4)
                }
                .padding(.horizontal, 16).padding(.top, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, isExpanded ? 36 : 22)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(Color(hex: 0x1A1A1D).opacity(0.96))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.45), radius: 22, y: -4)
        )
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { v in
                    if v.translation.height < -25 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { isExpanded = true }
                    } else if v.translation.height > 25 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { isExpanded = false }
                    }
                }
        )
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 56)
    }

    private func actionRow(icon: String, iconColor: Color, title: String,
                           subtitle: String? = nil, badge: String? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 34, height: 34)
                    .background(iconColor, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(CV.cream)
                    if let sub = subtitle {
                        Text(sub).font(.system(size: 11)).foregroundStyle(CV.cream.opacity(0.5))
                    }
                }
                Spacer()
                if let badge = badge {
                    Text(badge).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CV.cream.opacity(0.55))
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CV.cream.opacity(0.3))
            }
            .padding(.horizontal, 14).frame(height: 50).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

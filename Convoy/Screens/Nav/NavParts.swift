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

    static func detect(query: String, category: MKPointOfInterestCategory? = nil) -> StopKind {
        if let cat = category {
            if cat == .gasStation || cat == .evCharger { return .fuel }
            if cat == .restaurant || cat == .bakery || cat == .brewery { return .food }
            if cat == .cafe { return .rest }
            if cat == .nationalPark || cat == .beach || cat == .campground { return .viewpoint }
        }
        let q = query.lowercased()
        if q.contains("petrol") || q.contains("fuel") || q.contains("gas") || q.contains("pump") || q.contains("diesel") || q.contains("shell") || q.contains("hp") || q.contains("indian oil") || q.contains("bpcl") {
            return .fuel
        }
        if q.contains("food") || q.contains("hotel") || q.contains("eat") || q.contains("restaurant") || q.contains("dhaba") || q.contains("biryani") || q.contains("burger") || q.contains("pizza") {
            return .food
        }
        if q.contains("cafe") || q.contains("coffee") || q.contains("tea") || q.contains("rest") || q.contains("ccd") || q.contains("starbucks") || q.contains("chai") {
            return .rest
        }
        if q.contains("view") || q.contains("point") || q.contains("scenic") || q.contains("hill") || q.contains("lake") || q.contains("falls") || q.contains("peak") {
            return .viewpoint
        }
        if q.contains("mechanic") || q.contains("puncture") || q.contains("repair") || q.contains("garage") || q.contains("service") || q.contains("tyre") {
            return .mechanic
        }
        return .rest
    }
}

struct StopPlace: Hashable {
    var name: String
    var address: String
    var coordinate: CLLocationCoordinate2D
    var categoryName: String = "Stop"
    var detourText: String? = nil
    var distanceText: String? = nil
    var phone: String? = nil
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

// MARK: - Google Maps-Style Stop Preview Card

struct GoogleMapsStopPreviewCard: View {
    let place: StopPlace
    let kind: StopKind
    var onContinue: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator pill
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 38, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 14) {
                // Category round badge
                ZStack {
                    Circle()
                        .fill(kind.tint)
                        .frame(width: 48, height: 48)
                        .shadow(color: kind.tint.opacity(0.4), radius: 8)
                    Image(systemName: kind.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.black)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(place.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("STOP ADDED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(kind.tint)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(kind.tint.opacity(0.18), in: Capsule())
                    }

                    if !place.address.isEmpty {
                        Text(place.address)
                            .font(.system(size: 12))
                            .foregroundStyle(CV.cream.opacity(0.65))
                            .lineLimit(2)
                    }

                    // Detour & Distance info
                    HStack(spacing: 8) {
                        if let detour = place.detourText {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(detour)
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(CV.green)
                        }

                        if let dist = place.distanceText {
                            Text("•")
                                .foregroundStyle(CV.cream.opacity(0.4))
                            Text(dist)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CV.cream.opacity(0.75))
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            // Bottom Action Buttons
            HStack(spacing: 12) {
                Button(action: onRemove) {
                    Text("Remove Stop")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CV.red)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(CV.red.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onContinue) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Continue Route")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(Color(hex: 0x1A1A1D))
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Color(hex: 0xF5EDDE), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
        .padding(.bottom, 6)
        .background(
            Color(hex: 0x161619).opacity(0.97),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 24, y: -6)
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
<<<<<<< Updated upstream
    var onSiri: (() -> Void)? = nil
=======
    var onAlertCrew: (() -> Void)? = nil
    var onShowNotifications: (() -> Void)? = nil
    var unreadCount: Int = 0
>>>>>>> Stashed changes

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

<<<<<<< Updated upstream
            if let onSiri {
                Button(action: onSiri) {
                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [.purple, .blue, .cyan, .red, .orange, .purple],
                                    center: .center
                                )
                            )
                            .frame(width: 48, height: 48)
                            .blur(radius: 2)

                        Circle()
                            .fill(Color(hex: 0x1A1A1D, opacity: 0.94))
                            .frame(width: 44, height: 44)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
=======
            if let onAlertCrew {
                Button(action: onAlertCrew) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFFB020))
                        .frame(width: 48, height: 48)
                        .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Circle())
                        .overlay(Circle().strokeBorder(Color(hex: 0xFFB020).opacity(0.4), lineWidth: 1.5))
                }.buttonStyle(.plain)
            }

            if let onShowNotifications {
                Button(action: onShowNotifications) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CV.cream)
                            .frame(width: 48, height: 48)
                            .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))

                        if unreadCount > 0 {
                            Circle()
                                .fill(CV.red)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(Color(hex: 0x1A1A1D), lineWidth: 1.5))
                                .offset(x: -3, y: 3)
                        }
                    }
                }.buttonStyle(.plain)
>>>>>>> Stashed changes
            }

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

// MARK: - Ghost / Proposal marker (translucent — visible to leader only)

/// Translucent map annotation shown to the leader for a rider's stop proposal.
struct StopProposalMarker: View {
    let proposal: StopProposal
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0x0A84FF).opacity(0.18))
                    .frame(width: 48, height: 48)
                Circle()
                    .strokeBorder(Color(hex: 0x0A84FF).opacity(0.6), lineWidth: 2)
                    .frame(width: 36, height: 36)
                Image(systemName: "mappin")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0A84FF))
            }
            Text(proposal.riderName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color(hex: 0x0A84FF).opacity(0.75), in: Capsule())
        }
    }
}

// MARK: - Rider warning banner (shown to all riders)

struct RiderWarningBanner: View {
    let warning: RiderWarningEvent
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: warning.type.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(warning.type.color)
                .frame(width: 36, height: 36)
                .background(warning.type.color.opacity(0.2), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(warning.riderName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text(warning.type.label)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: 0x1A1A1D).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(warning.type.color.opacity(0.5), lineWidth: 1.5)
                )
        )
        .shadow(color: warning.type.isCritical ? warning.type.color.opacity(0.4) : .clear,
                radius: 12)
    }
}

// MARK: - Stop Proposal card (shown to leader in a tray)

struct StopProposalCard: View {
    let proposal: StopProposal
    var onApprove: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: 0x0A84FF))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(proposal.riderName) wants to stop")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(proposal.placeName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()

            HStack(spacing: 8) {
                Button(action: onApprove) {
                    Text("Add")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x1A1A1D))
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(Color(hex: 0x0A84FF), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(hex: 0x1C1C1F).opacity(0.96),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color(hex: 0x0A84FF).opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Voice command button

struct VoiceMicButton: View {
    var isListening: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isListening
                          ? CV.red.opacity(0.9)
                          : Color(hex: 0x1A1A1D).opacity(0.9))
                    .frame(width: 52, height: 52)
                    .overlay(Circle().strokeBorder(
                        isListening ? CV.red : Color.white.opacity(0.15), lineWidth: 1.5))
                    .shadow(color: isListening ? CV.red.opacity(0.5) : .clear, radius: 10)

                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                if isListening {
                    Circle()
                        .strokeBorder(CV.red.opacity(0.4), lineWidth: 2)
                        .frame(width: 68, height: 68)
                        .scaleEffect(1.0)
                        .animation(
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: isListening
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Warning picker sheet (rider sends a warning)

struct RiderWarningPicker: View {
    var onSelect: (RiderWarningType) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Send Warning")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            ForEach(RiderWarningType.allCases) { type in
                Button { onSelect(type) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: type.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(type.color)
                            .frame(width: 40, height: 40)
                            .background(type.color.opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(type.label)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        if type.isCritical {
                            Text("URGENT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(type.color)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(type.color.opacity(0.2), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 20).frame(height: 60)
                }
                .buttonStyle(.plain)
                if type != RiderWarningType.allCases.last {
                    Rectangle().fill(Color.white.opacity(0.07))
                        .frame(height: 1).padding(.leading, 74)
                }
            }
            Spacer(minLength: 20)
        }
        .background(Color(hex: 0x1A1A1D))
    }
}

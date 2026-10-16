import SwiftUI

let navPanel = Color(hex: 0x1A1A1D)
let amberC = Color(hex: 0xFFB020)

/// What a stop-type looks like in the "Add a stop" sheet.
enum StopKind: String, CaseIterable, Identifiable {
    case fuel = "Fuel", food = "Food", rest = "Rest", viewpoint = "Viewpoint", mechanic = "Mechanic"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .fuel: "fuelpump"
        case .food: "fork.knife"
        case .rest: "bed.double"
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
        case .fuel: "Fuel nearby"
        case .food: "Food nearby"
        case .rest: "Rest stops nearby"
        case .viewpoint: "Viewpoints nearby"
        case .mechanic: "Mechanics nearby"
        }
    }
    var places: [StopPlace] {
        switch self {
        case .fuel:
            [StopPlace("HP Petrol Bunk · Sahakar Nagar", "1.2 km ahead · +2 min detour", "Open 24 hours"),
             StopPlace("Indian Oil · Yelahanka", "3.4 km ahead · +4 min detour", "Open 24 hours"),
             StopPlace("Shell · Doddaballapur Rd", "6.1 km ahead · +3 min detour", "Open till 11 PM · Premium fuel"),
             StopPlace("Bharat Petroleum · NH 44", "8.0 km ahead · +6 min detour", "Open 24 hours")]
        case .food:
            [StopPlace("Café Coffee Day · Highway", "2.3 km ahead · +3 min detour", "Open now · Coffee & snacks"),
             StopPlace("Nandi Upahara Darshini", "4.8 km ahead · +5 min detour", "Open now · South Indian"),
             StopPlace("Highway Dhaba 7", "7.2 km ahead · +4 min detour", "Open now · North Indian"),
             StopPlace("Kamat Lokaruchi", "11 km ahead · +7 min detour", "Open till 10 PM")]
        case .rest:
            [StopPlace("Rest area · NH 44", "3.0 km ahead · +1 min detour", "Washrooms · Shade"),
             StopPlace("Lay-by · Sultanpet", "5.5 km ahead · +2 min detour", "Parking for 6 bikes"),
             StopPlace("Hotel Nandi Grand", "9.0 km ahead · +6 min detour", "Washrooms · Tea")]
        case .viewpoint:
            [StopPlace("Kanive Basavanna lake", "4.2 km ahead · +3 min detour", "Lake view · Parking"),
             StopPlace("Muddenahalli viewpoint", "6.0 km ahead · +5 min detour", "Sunrise view"),
             StopPlace("Skandagiri lookout", "9.4 km ahead · +12 min detour", "Short walk from parking")]
        case .mechanic:
            [StopPlace("Royal Moto Works", "2.8 km ahead · +3 min detour", "Open till 9 PM"),
             StopPlace("Sri Ganesh Bike Service", "5.0 km ahead · +4 min detour", "Open now · Puncture repair"),
             StopPlace("Hero Service Point", "7.6 km ahead · +6 min detour", "Open till 8 PM")]
        }
    }
}

struct StopPlace: Hashable {
    let name: String, away: String, note: String
    init(_ n: String, _ a: String, _ o: String) { name = n; away = a; note = o }
    var short: String { name.components(separatedBy: " · ")[0] }
    var km: String { away.components(separatedBy: " ahead")[0] }
}

/// Dark rounded panel with a hairline.
extension View {
    func navCard(_ r: CGFloat = 24, fill: Color = navPanel.opacity(0.96)) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
    func navCardBorder() -> some View {
        overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Apple Maps Top Maneuver Banner
struct AppleMapsTopBanner: View {
    var symbol: String = "arrow.turn.up.left"
    var tint: Color = .white
    var distance: String = "50 m"
    var instruction: String = "Turn left"
    var subInstruction: String? = nil
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let onBack = onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CV.cream)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Maneuver symbol (white glyph on subtle circular glow or icon)
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(tint)
            }

            // Maneuver text hierarchy
            VStack(alignment: .leading, spacing: 2) {
                if !distance.isEmpty {
                    Text(distance)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(CV.cream)
                }
                Text(instruction)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CV.cream)
                    .lineLimit(1)

                if let sub = subInstruction, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CV.cream.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(hex: 0x1A1A1D).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 18, y: 4)
        )
    }
}

// MARK: - Apple Maps Right Controls (Recenter, Audio, SOS / Report)
struct AppleMapsRightControls: View {
    var isTrackingUser: Bool
    var isVoiceMuted: Bool
    var onRecentre: () -> Void
    var onToggleVoice: () -> Void
    var onSOS: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Recenter / Route Tracking
            Button(action: onRecentre) {
                Image(systemName: isTrackingUser ? "location.fill" : "location")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isTrackingUser ? CV.red : CV.cream)
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.plain)

            // Voice Guidance toggle
            Button(action: onToggleVoice) {
                Image(systemName: isVoiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isVoiceMuted ? CV.cream.opacity(0.5) : CV.cream)
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.plain)

            // Incident Report / SOS
            Button(action: onSOS) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CV.red)
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Circle())
                    .overlay(Circle().strokeBorder(CV.red.opacity(0.4), lineWidth: 1.5))
                    .shadow(color: CV.red.opacity(0.4), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Apple Maps Speedometer
struct AppleMapsSpeedometer: View {
    var speed: Int
    var speedLimit: Int = 50

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0x1A1A1D, opacity: 0.95))
                    .frame(width: 64, height: 64)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.35), radius: 8, y: 3)
                VStack(spacing: 0) {
                    Text("\(speed)")
                        .cvText(22, .bold, inter: true)
                    Text("km/h")
                        .cvText(9, color: CV.cream.opacity(0.6), inter: true)
                }
            }

            // Speed limit badge
            Text("\(speedLimit)")
                .cvText(13, .bold, color: .black, inter: true)
                .frame(width: 28, height: 28)
                .background(.white, in: Circle())
                .overlay(Circle().strokeBorder(CV.red, lineWidth: 2.5))
                .shadow(color: Color.black.opacity(0.25), radius: 4)
        }
    }
}

// MARK: - Apple Maps Bottom Sheet (Collapsed & Expanded)
struct AppleMapsBottomSheet: View {
    var arrivalTime: String
    var durationValue: String
    var durationUnit: String
    var distanceValue: String
    var distanceUnit: String
    var destinationName: String
    var quickStop: StopPlace? = nil
    var riderCount: Int = 5
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
            // Drag handle pill
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            }
            .buttonStyle(.plain)

            // Header: 3 Stat Columns (Arrival, Duration, Distance)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // Column 1: Arrival Time
                VStack(spacing: 2) {
                    Text(arrivalTime)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(CV.cream)
                    Text("arrival")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CV.cream.opacity(0.55))
                }
                .frame(maxWidth: .infinity)

                // Column 2: Duration
                VStack(spacing: 2) {
                    Text(durationValue)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(isExpanded ? Color(hex: 0x3897F0) : CV.cream)
                    Text(durationUnit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isExpanded ? Color(hex: 0x3897F0) : CV.cream.opacity(0.55))
                }
                .frame(maxWidth: .infinity)

                // Column 3: Remaining Distance
                VStack(spacing: 2) {
                    Text(distanceValue)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(CV.cream)
                    Text(distanceUnit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CV.cream.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            }

            // Expanded Apple Maps Content
            if isExpanded {
                VStack(spacing: 12) {
                    // Quick stop recommendation card (Cafe Coffee Day / nearest stop)
                    if let stop = quickStop {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: 0xFF9500))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "cup.and.saucer.fill")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.short)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(CV.cream)
                                Text(stop.away)
                                    .font(.system(size: 12))
                                    .foregroundStyle(CV.cream.opacity(0.6))
                            }

                            Spacer()

                            Button {
                                if let url = URL(string: "tel://112") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x3897F0))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(0.1), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    // Grouped List of Actions (Apple Maps layout)
                    VStack(spacing: 0) {
                        // 1. Add Stop
                        actionRow(
                            icon: "plus",
                            iconColor: Color(hex: 0x007AFF),
                            title: "Add Stop",
                            action: onAddStop
                        )

                        divider

                        // 2. Convoy Riders
                        actionRow(
                            icon: "person.3.fill",
                            iconColor: Color(hex: 0xAF52DE),
                            title: "Convoy Riders",
                            badge: "\(riderCount) live",
                            action: onRiders
                        )

                        divider

                        // 3. Share ETA
                        actionRow(
                            icon: "person.crop.circle.badge.plus",
                            iconColor: Color(hex: 0x34C759),
                            title: "Share ETA",
                            action: onShareETA
                        )

                        divider

                        // 4. Report an Incident / SOS
                        actionRow(
                            icon: "exclamationmark.bubble.fill",
                            iconColor: Color(hex: 0xFF3B30),
                            title: "Report an Incident",
                            subtitle: "SOS Emergency & Convoy Alert",
                            action: onSOS
                        )

                        divider

                        // 5. Voice Controls
                        actionRow(
                            icon: isVoiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            iconColor: Color(hex: 0x8E8E93),
                            title: "Voice Controls",
                            badge: isVoiceMuted ? "Muted" : "On",
                            action: onVoiceToggle
                        )
                    }
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    // Prominent End Route button
                    Button(action: onEndRoute) {
                        Text("End Route")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(hex: 0xFF3B30), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, isExpanded ? 36 : 22)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(Color(hex: 0x1A1A1D).opacity(0.96))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 22, y: -4)
        )
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    if value.translation.height < -25 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            isExpanded = true
                        }
                    } else if value.translation.height > 25 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            isExpanded = false
                        }
                    }
                }
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 56)
    }

    private func actionRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(iconColor, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(CV.cream)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundStyle(CV.cream.opacity(0.5))
                    }
                }

                Spacer()

                if let b = badge {
                    Text(b)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CV.cream.opacity(0.55))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CV.cream.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legacy TurnBanner
struct TurnBanner: View {
    var symbol = "arrow.turn.up.right"
    var tint: Color = CV.cream
    var big = "180 m"; var title = "Turn right"; var sub = "onto Sahakar Nagar Rd"
    var dim = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .regular)).foregroundStyle(tint).frame(width: 40, height: 40).padding(.leading, 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(big).cvText(34, .bold, inter: true)
                Text(title).cvText(17, .semibold, inter: true)
                Text(sub).cvText(12, color: CV.cream.opacity(0.5), inter: true)
            }
            Spacer()
        }
        .opacity(dim ? 0.45 : 1)
        .frame(width: 353, height: 104, alignment: .leading).navCard(26)
    }
}

// MARK: - Small avatar in a white ring (map markers / alert slots)
struct RingAvatar: View {
    var photo: String; var size: CGFloat
    var body: some View { Avatar(photo: photo, size: size).overlay(Circle().strokeBorder(.white, lineWidth: 2)) }
}

// MARK: - Legacy NavChrome
struct NavChrome: View {
    var arrived = false
    var hideActions = false
    var time = "7:42"
    var line = "58 km left · 1h 32m · Nandi Hills summit"
    var speed: Int = 0
    var onBack: () -> Void
    var onAddStop: () -> Void
    var onRiders: () -> Void
    var onSOS: () -> Void
    var onEnd: () -> Void
    var onRecentre: (() -> Void)? = nil

    var body: some View {
        EmptyView()
    }
}

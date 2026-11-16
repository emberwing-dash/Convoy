// HomeCards.swift
// Building blocks for the Home tab: rider greeting, weather card, quick actions,
// this-month summary and the closing quote. Monochrome surfaces; colour only where it
// carries meaning (the weather symbol, the riding verdict, ahead/behind pace).
import SwiftUI

// MARK: - Greeting

/// "Golden-hour cruising, Susan" — a short riding phrase in grey, the name in white.
/// The phrase follows the time of day and stays the same all day (no flicker on refresh).
struct RiderGreeting: View {
    let name: String

    static func phrase(at date: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        let pool: [String]
        switch hour {
        case 5..<12: pool = ["Rise and ride", "Fresh tank, fresh roads", "Morning miles await", "Kickstand up"]
        case 12..<17: pool = ["Keep the rubber rolling", "Chase the twisties", "Throttle up", "Open roads ahead"]
        case 17..<21: pool = ["Golden-hour cruising", "Sunset on two wheels", "Easy throttle tonight", "Evening miles"]
        default: pool = ["Night roads are calling", "Lights on, mind sharp", "Quiet roads tonight", "Rest up, ride tomorrow"]
        }
        return pool[day % pool.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.phrase())
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CV.muted)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(name)
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(CV.text)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Weather

/// Weather where you are, laid out like an iOS widget: place, big temperature, condition,
/// a riding verdict and three small readings (feels like, wind, rain chance).
struct WeatherCard: View {
    let weather: LiveWeather
    let place: String?
    @State private var spin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill").font(.system(size: 10, weight: .semibold))
                        Text(place ?? "Your location").lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CV.muted)

                    Text("\(Int(weather.temperature.rounded()))°")
                        .font(.system(size: 52, weight: .light))
                        .tracking(-2)
                        .monospacedDigit()
                        .foregroundStyle(CV.text)
                        .padding(.top, 2)

                    HStack(spacing: 6) {
                        Text(weather.condition).foregroundStyle(CV.text)
                        if let hi = weather.high, let lo = weather.low {
                            Text("H \(Int(hi.rounded()))°  L \(Int(lo.rounded()))°").foregroundStyle(CV.muted)
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 12) {
                    icon.font(.system(size: 40))
                    verdictPill
                }
            }

            if weather.feelsLike != nil || weather.windKmh != nil || weather.rainChance != nil {
                HStack(spacing: 0) {
                    if let f = weather.feelsLike { reading("thermometer.medium", "Feels", "\(Int(f.rounded()))°") }
                    if let w = weather.windKmh { reading("wind", "Wind", "\(Int(w.rounded())) km/h") }
                    if let r = weather.rainChance { reading("umbrella", "Rain", "\(r)%") }
                }
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(18)
        .background(CV.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(CV.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var verdictPill: some View {
        let (text, color): (String, Color) = {
            switch weather.verdict {
            case .go: return ("Good to ride", CV.success)
            case .care: return ("Ride with care", CV.warning)
            case .wait: return ("Better wait", CV.danger)
            }
        }()
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.text)
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func reading(_ symbol: String, _ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
            }
            .foregroundStyle(CV.dim)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(CV.text)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var icon: some View {
        let base = Image(systemName: weather.symbol).symbolRenderingMode(.multicolor)
        switch weather.kind {
        case .clear where weather.isDay:
            base.rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear { withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { spin = true } }
        case .drizzle, .rain, .snow, .storm:
            base.symbolEffect(.variableColor.iterative, options: .repeating.speed(0.5))
        default:
            base
        }
    }
}

// MARK: - Quick actions

/// Plan / Join side by side: white primary, glass secondary, icon + two lines each.
struct HomeQuickActions: View {
    var onPlan: () -> Void
    var onJoin: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            tile(icon: "point.topleft.down.to.point.bottomright.curvepath.fill", title: "Plan a ride",
                 subtitle: "Route & crew", primary: true, action: onPlan)
            tile(icon: "qrcode.viewfinder", title: "Join a ride", subtitle: "Enter a code", primary: false, action: onJoin)
        }
    }

    private func tile(icon: String, title: String, subtitle: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(primary ? Color.white : CV.text)
                    .frame(width: 40, height: 40)
                    .background(primary ? CV.onAccent : Color.white.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(primary ? CV.onAccent : CV.text)
                    Text(subtitle).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(primary ? CV.onAccent.opacity(0.55) : CV.muted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background {
                if primary {
                    LinearGradient(colors: [.white, Color(hex: 0xE6E6E6)], startPoint: .top, endPoint: .bottom)
                } else {
                    CV.surface.opacity(0.92)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(primary ? Color.white.opacity(0.5) : CV.stroke, lineWidth: 1))
        }
        .buttonStyle(PressScale())
    }
}

// MARK: - This month

/// This month at a glance, from the rides you've recorded on this phone. Compares your
/// distance with last month at the same point in the month — nothing is estimated.
struct MonthSummaryCard: View {
    let logs: [RideLog]
    var onLeaderboard: () -> Void

    private let cal = Calendar.current
    private var now: Date { .now }

    private var thisMonth: [RideLog] {
        logs.filter { cal.isDate($0.startedAt, equalTo: now, toGranularity: .month) }
    }
    private var lastMonthStart: Date {
        cal.date(byAdding: .month, value: -1, to: cal.dateInterval(of: .month, for: now)!.start)!
    }
    private var lastMonth: [RideLog] {
        logs.filter { cal.isDate($0.startedAt, equalTo: lastMonthStart, toGranularity: .month) }
    }
    /// Last month's distance up to the same day of the month as today.
    private var lastMonthSoFarKm: Double {
        let day = cal.component(.day, from: now)
        return lastMonth.filter { cal.component(.day, from: $0.startedAt) <= day }.reduce(0) { $0 + $1.distanceKm }
    }
    private var km: Double { thisMonth.reduce(0) { $0 + $1.distanceKm } }
    private var lastKm: Double { lastMonth.reduce(0) { $0 + $1.distanceKm } }
    private var movingS: Int { thisMonth.reduce(0) { $0 + $1.movingS } }
    private var topSpeed: Double { thisMonth.map(\.maxSpeedKmh).max() ?? 0 }
    private var longest: Double { thisMonth.map(\.distanceKm).max() ?? 0 }
    private var bestAvg: Double { thisMonth.map(\.avgSpeedKmh).max() ?? 0 }
    private var progress: Double { lastKm > 0 ? min(1, km / lastKm) : (km > 0 ? 1 : 0) }

    private var monthName: String { now.formatted(.dateTime.month(.wide)) }
    private var lastMonthShort: String { lastMonthStart.formatted(.dateTime.month(.abbreviated)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THIS MONTH · \(monthName.uppercased())")
                .font(.system(size: 12, weight: .semibold)).tracking(0.8)
                .foregroundStyle(CV.muted)

            VStack(spacing: 16) {
                HStack(spacing: 18) {
                    ring
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            stat(String(format: km >= 100 ? "%.0f" : "%.1f", km), "km")
                            stat("\(thisMonth.count)", thisMonth.count == 1 ? "ride" : "rides")
                        }
                        Text(Self.duration(movingS) + " riding")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(CV.muted)
                        pacePill
                    }
                    Spacer(minLength: 0)
                }

                Rectangle().fill(CV.separator).frame(height: 1)

                HStack(spacing: 0) {
                    metric("gauge.with.dots.needle.67percent", "Top", topSpeed > 0 ? "\(Int(topSpeed.rounded())) km/h" : "—")
                    metric("arrow.left.and.right", "Longest", longest > 0 ? String(format: "%.0f km", longest) : "—")
                    metric("speedometer", "Best avg", bestAvg > 0 ? "\(Int(bestAvg.rounded())) km/h" : "—")
                }

                Button(action: onLeaderboard) {
                    HStack(spacing: 10) {
                        Image(systemName: "trophy").font(.system(size: 14, weight: .semibold))
                        Text("See this month's leaderboard").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.dim)
                    }
                    .foregroundStyle(CV.text)
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressScale())
            }
            .padding(18)
            .background(CV.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(CV.stroke, lineWidth: 1))
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 8)
            Circle().trim(from: 0, to: progress)
                .stroke(CV.text, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: progress)
            VStack(spacing: 0) {
                Text(lastKm > 0 ? "\(Int((km / lastKm * 100).rounded()))%" : (km > 0 ? "New" : "0%"))
                    .font(.system(size: 18, weight: .bold)).monospacedDigit().foregroundStyle(CV.text)
                Text(lastKm > 0 ? "of \(lastMonthShort)" : "best")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(CV.muted)
            }
        }
        .frame(width: 86, height: 86)
    }

    @ViewBuilder private var pacePill: some View {
        let diff = km - lastMonthSoFarKm
        if km > 0 || lastMonthSoFarKm > 0 {
            let ahead = diff >= 0
            HStack(spacing: 5) {
                Image(systemName: ahead ? "arrow.up.right" : "arrow.down.right").font(.system(size: 11, weight: .bold))
                Text("\(Int(abs(diff).rounded())) km \(ahead ? "ahead of" : "behind") \(lastMonthShort) pace")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(ahead ? CV.success : CV.muted)
            .padding(.horizontal, 10).frame(height: 26)
            .background((ahead ? CV.success : Color.white).opacity(0.1), in: Capsule())
        } else {
            Text("No rides recorded yet")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(CV.muted)
        }
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 30, weight: .bold)).tracking(-0.8).monospacedDigit().foregroundStyle(CV.text)
            Text(unit).font(.system(size: 14, weight: .medium)).foregroundStyle(CV.muted)
        }
    }

    private func metric(_ symbol: String, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(label.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6)
            }
            .foregroundStyle(CV.dim)
            Text(value).font(.system(size: 16, weight: .semibold)).monospacedDigit().foregroundStyle(CV.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func duration(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Quote

/// One riding / travel line per day, quietly closing the Home screen.
struct RideQuoteCard: View {
    /// Shifts the daily pick so two screens don't show the same line on the same day.
    var offset = 0
    static let lines: [String] = [
        "The best roads are the ones you haven't ridden yet.",
        "Two wheels, one road, endless stories.",
        "Collect miles, not things.",
        "Every horizon is an invitation.",
        "The destination is just an excuse for the ride.",
        "Ride together, arrive together.",
        "Good company makes every road shorter.",
        "Wind in your face, worries in the mirror.",
        "Some roads are meant to be ridden, not rushed.",
        "Life is short. Take the long way home.",
    ]

    var line: String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        return Self.lines[(day + offset) % Self.lines.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CV.dim)
            Text(line)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(CV.text.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("— CONVOY")
                .font(.system(size: 11, weight: .semibold)).tracking(1.4)
                .foregroundStyle(CV.dim)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

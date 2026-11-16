// CrewLeaderboardView.swift
import SwiftUI

struct CrewLeaderboardView: View {
    @Environment(AppState.self) private var app
    @State private var category: Category = .distance
    @State private var entries: [LeaderboardEntry] = []
    @State private var crewEntries: [CrewLeaderboardEntry] = []
    @State private var isLoading = false
    @State private var loadError: String?

    enum Category: String, CaseIterable {
        case distance, rides, topSpeed, longest, streak, crew
        var title: String {
            switch self {
            case .distance: "Distance"
            case .rides: "Rides"
            case .topSpeed: "Top speed"
            case .longest: "Longest ride"
            case .streak: "Streak"
            case .crew: "Crew"
            }
        }
        var symbol: String {
            switch self {
            case .distance: "point.topleft.down.to.point.bottomright.curvepath"
            case .rides: "flag.checkered"
            case .topSpeed: "speedometer"
            case .longest: "road.lanes"
            case .streak: "flame"
            case .crew: "person.3"
            }
        }
    }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var currentMonth: Int { Calendar.current.component(.month, from: Date()) }
    private var monthLabel: String {
        Date().formatted(.dateTime.month(.wide).year())
    }

    private var sorted: [LeaderboardEntry] {
        switch category {
        case .distance: return entries.sorted { $0.total_km > $1.total_km }
        case .rides: return entries.sorted { $0.rides_count > $1.rides_count }
        case .topSpeed: return entries.sorted { $0.top_speed_kmh > $1.top_speed_kmh }
        case .longest: return entries.sorted { $0.longest_ride_km > $1.longest_ride_km }
        case .streak: return entries.sorted { $0.streak_days > $1.streak_days }
        case .crew: return []
        }
    }

    private func value(for entry: LeaderboardEntry) -> String {
        switch category {
        case .distance: return String(format: "%.0f km", entry.total_km)
        case .rides: return "\(entry.rides_count) rides"
        case .topSpeed: return String(format: "%.0f km/h", entry.top_speed_kmh)
        case .longest: return String(format: "%.0f km", entry.longest_ride_km)
        case .streak: return "\(entry.streak_days) days"
        case .crew: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            chips.padding(.top, 14)

            if isLoading && entries.isEmpty && crewEntries.isEmpty {
                skeleton.padding(.top, 22)
            } else if category == .crew {
                if crewEntries.isEmpty { emptyState } else { crewList }
            } else if sorted.isEmpty {
                emptyState
            } else {
                podiumAndList
            }
        }
        .task(id: category) {
            if (category == .crew && crewEntries.isEmpty) ||
               (category != .crew && entries.isEmpty) {
                await load()
            }
        }
        .refreshable { await load(force: true) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Top riders").cvText(20, .bold, tracking: -0.3, inter: true)
            Spacer()
            Text(monthLabel).cvText(13, color: CV.muted, inter: true)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Category.allCases, id: \.self) { c in
                    Button {
                        withAnimation(.snappy) { category = c }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: c.symbol).font(.system(size: 11, weight: .semibold))
                            Text(c.title).cvText(13, .medium, inter: true)
                        }
                        .foregroundStyle(category == c ? CV.ink : CV.cream)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(category == c ? CV.cream : Color(hex: 0x1C1C1F),
                                    in: Capsule())
                        .overlay(Capsule().strokeBorder(
                            category == c ? .clear : Color.white.opacity(0.1), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, -20)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    private var podiumAndList: some View {
        let top3 = Array(sorted.prefix(3))
        let rest = Array(sorted.dropFirst(3))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                if top3.count > 1 { podiumColumn(top3[1], rank: 2, height: 68) }
                if top3.count > 0 { podiumColumn(top3[0], rank: 1, height: 90) }
                if top3.count > 2 { podiumColumn(top3[2], rank: 3, height: 52) }
            }
            .frame(maxWidth: .infinity).padding(.top, 12)

            if !rest.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rest.enumerated()), id: \.element.id) { idx, entry in
                        row(entry: entry, rank: idx + 4)
                        if idx < rest.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.06))
                                .frame(height: 1).padding(.leading, 66)
                        }
                    }
                }
                .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
        .padding(.top, 16)
    }

    private func podiumColumn(_ entry: LeaderboardEntry, rank: Int, height: CGFloat) -> some View {
        let medal: Color = rank == 1 ? Color(hex: 0xFFD166)
                          : rank == 2 ? Color(hex: 0xC0C0C0)
                          : Color(hex: 0xCD7F32)
        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AvatarChip(data: entry.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                           name: entry.profiles?.display_name ?? "Rider", size: 52)
                    .overlay(Circle().strokeBorder(medal, lineWidth: rank == 1 ? 2.5 : 1.5))
                Text("\(rank)")
                    .cvText(10, .bold, color: CV.ink, inter: true)
                    .frame(width: 18, height: 18)
                    .background(medal, in: Circle())
                    .offset(x: 4, y: -4)
            }
            Text(entry.profiles?.display_name ?? "Rider")
                .cvText(12, .semibold, color: CV.cream, inter: true)
                .lineLimit(1)
            Text(value(for: entry))
                .cvText(11, .semibold, color: CV.red, inter: true)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(height: height)
                .overlay(
                    Text("\(rank)")
                        .cvText(28, .bold, color: medal, inter: true)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private func row(entry: LeaderboardEntry, rank: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .cvText(14, .semibold, color: CV.muted, inter: true)
                .frame(width: 24)
            AvatarChip(data: entry.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                       name: entry.profiles?.display_name ?? "Rider", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.profiles?.display_name ?? "Rider")
                    .cvText(15, .semibold, color: CV.cream, inter: true).lineLimit(1)
                Text("@\(entry.profiles?.username ?? "rider")")
                    .cvText(12, color: CV.muted, inter: true).lineLimit(1)
            }
            Spacer()
            Text(value(for: entry))
                .cvText(14, .semibold, color: CV.cream, inter: true)
        }
        .padding(.horizontal, 14).frame(height: 64)
    }

    private var crewList: some View {
        VStack(spacing: 0) {
            ForEach(Array(crewEntries.enumerated()), id: \.element.id) { idx, entry in
                HStack(spacing: 12) {
                    Text("\(idx + 1)")
                        .cvText(14, .semibold, color: CV.muted, inter: true)
                        .frame(width: 24)
                    CrewAvatar(data: nil, name: entry.crew_name, size: 40)
                    Text(entry.crew_name)
                        .cvText(15, .semibold, color: CV.cream, inter: true).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f km", entry.total_km))
                        .cvText(14, .semibold, color: CV.cream, inter: true)
                }
                .padding(.horizontal, 14).frame(height: 60)
                if idx < crewEntries.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.06))
                        .frame(height: 1).padding(.leading, 66)
                }
            }
        }
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.top, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "trophy").font(.system(size: 30)).foregroundStyle(CV.red)
            Text("No rankings yet").cvText(16, .semibold, inter: true)
            Text("Complete a ride and this month's top riders will appear here.")
                .cvText(13, color: CV.muted, inter: true).multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.top, 22)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var skeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                Skeleton().frame(height: 64).clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        await MainActor.run { isLoading = true; loadError = nil }
        do {
            if category == .crew {
                let crews = try await SupabaseManager.shared.fetchCrewLeaderboard(
                    year: currentYear, month: currentMonth)
                await MainActor.run { self.crewEntries = crews }
            } else {
                // Refresh server-side rankings first (no-op if cron already did it)
                try? await SupabaseManager.shared.refreshLeaderboard(
                    year: currentYear, month: currentMonth)
                let rows = try await SupabaseManager.shared.fetchLeaderboard(
                    year: currentYear, month: currentMonth)
                await MainActor.run { self.entries = rows }
            }
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                isLoading = false
                loadError = error.localizedDescription
            }
        }
    }
}

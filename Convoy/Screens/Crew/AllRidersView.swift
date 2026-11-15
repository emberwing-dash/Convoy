// AllRidersView.swift — Full community directory of all riders on Convoy.
import SwiftUI

struct AllRidersView: View {
    @Environment(AppState.self) private var app
    @State private var riders: [SuggestedRider] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var searchText = ""

    private var displayedRiders: [SuggestedRider] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "@", with: "")
        if q.isEmpty { return riders }
        return riders.filter { r in
            r.rider.name.lowercased().contains(q) ||
            r.rider.username.lowercased().contains(q) ||
            r.reason.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()

            VStack(spacing: 0) {
                headerView
                    .padding(.top, 56)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                searchBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                if isLoading {
                    loadingSkeleton
                        .padding(.horizontal, 20)
                } else if let error = errorMessage, riders.isEmpty {
                    errorState(error)
                        .padding(.horizontal, 20)
                } else if displayedRiders.isEmpty {
                    emptyState
                        .padding(.horizontal, 20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(displayedRiders) { rider in
                                RiderDirectoryRow(rider: rider)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            CircleBackButton { app.pop() }
                .padding(.leading, 20)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .task {
            await loadRiders()
        }
        .refreshable {
            await loadRiders(force: true)
        }
    }

    // MARK: - Header
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMMUNITY DIRECTORY")
                .cvText(11, .bold, color: CV.red, tracking: 1.6, inter: true)
            HStack {
                Text("All Riders")
                    .cvText(32, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.6, inter: true)
                Spacer()
                if !riders.isEmpty {
                    Text("\(riders.count) riders")
                        .cvText(13, .semibold, color: CV.muted, inter: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
            }
            Text("Connect with fellow motorcycle riders across the Convoy community.")
                .cvText(14, color: CV.muted, inter: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CV.muted)

            TextField("", text: $searchText, prompt: Text("Search by name or @username...").foregroundColor(CV.muted))
                .cvText(15, .medium, color: CV.cream, inter: true)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(CV.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }

    // MARK: - Loading Skeleton
    private var loadingSkeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 140, height: 16)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.04))
                            .frame(width: 90, height: 12)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 80, height: 34)
                }
                .padding(14)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    // MARK: - Error State
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(CV.red)
            Text(message)
                .cvText(14, color: CV.muted, inter: true)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await loadRiders(force: true) }
            }
            .cvText(14, .bold, color: CV.ink, inter: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(CV.cream, in: Capsule())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.slash")
                .font(.system(size: 36))
                .foregroundStyle(CV.muted)
            Text("No riders found")
                .cvText(18, .bold, color: CV.cream, inter: true)
            Text("No riders matched '\(searchText)'. Try another search term.")
                .cvText(14, color: CV.muted, inter: true)
                .multilineTextAlignment(.center)
            Button("Clear search") {
                searchText = ""
            }
            .cvText(13, .semibold, color: CV.red, inter: true)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func loadRiders(force: Bool = false) async {
        isLoading = riders.isEmpty
        errorMessage = nil
        do {
            let list = try await app.social.allRiders(limit: 100)
            // Shuffle riders so everyone gets visibility randomly across visits
            self.riders = list.shuffled()
            self.isLoading = false
        } catch {
            self.errorMessage = SocialError.from(error).message
            self.isLoading = false
        }
    }
}

// MARK: - Rider Directory Row

struct RiderDirectoryRow: View {
    @Environment(AppState.self) private var app
    let rider: SuggestedRider

    var body: some View {
        HStack(spacing: 14) {
            // Tappable profile preview
            Button {
                app.push(.riderProfile(rider.id))
            } label: {
                HStack(spacing: 14) {
                    AvatarChip(data: rider.rider.avatarData, name: rider.rider.name, size: 50)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(rider.rider.name)
                            .cvText(16, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                            .lineLimit(1)

                        Text("@\(rider.rider.username)")
                            .cvText(13, color: CV.muted, inter: true)
                            .lineLimit(1)

                        Text(metaStats)
                            .cvText(11, .medium, color: CV.dim, inter: true)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Perfectly aligned Follow button
            FollowButton(riderId: rider.id, compact: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(hex: 0x18181B).opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var metaStats: String {
        if rider.rides > 0 {
            return "\(RideFormat.km(rider.totalKm)) km · \(rider.rides) ride\(rider.rides == 1 ? "" : "s")"
        }
        return rider.reason.isEmpty ? "Convoy Rider" : rider.reason
    }
}


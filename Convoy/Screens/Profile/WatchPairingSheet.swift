//
//  WatchPairingSheet.swift
//  Convoy
//
//  Shows Apple Watch connection status, live telemetry, and live map location.
//  Location is now fetched from Supabase `watch_locations` table (Watch streams directly).
//

import SwiftUI
import MapKit
import CoreLocation

struct WatchPairingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var watchManager = PhoneWatchConnectivityManager.shared
    
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isPingingWatch: Bool = false
    
    // Supabase-based watch location
    @State private var supabaseWatchLocation: WatchLiveTelemetry? = nil
    @State private var supabaseUserId: String? = nil
    @State private var locationPollTimer: Timer? = nil
    @State private var lastFetchedAt: Date? = nil
    @State private var isWatchSignedIn: Bool = false
    @State private var fetchError: String? = nil
    
    private let supabaseUrl = "https://avykoruhcgwpmvmddlta.supabase.co"
    private let anonKey = "sb_publishable_4cTQxSHnQbUtxLE_n2Rz7A_YDCuQ5-0"
    
    // Prefer Supabase location over WatchConnectivity if available
    private var displayedWatchLocation: WatchLiveTelemetry? {
        supabaseWatchLocation ?? watchManager.lastWatchLocation
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x360808), Color(hex: 0x1A0507), CV.bg],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text("Apple Watch").cvText(17, .semibold, color: CV.cream, inter: true)
                    HStack {
                        CircleBackButton { dismiss() }
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // ── Status Card ──────────────────────────────────────
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(isWatchSignedIn ? Color(hex: 0x1C2E24) : Color(hex: 0x2E1C1F))
                                    .frame(width: 64, height: 64)
                                Image(systemName: "applewatch")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(isWatchSignedIn ? CV.green : Color(hex: 0xFFB020))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("Convoy Watch")
                                        .cvText(17, .bold, color: CV.cream, inter: true)
                                    Circle()
                                        .fill(isWatchSignedIn ? CV.green : Color.gray)
                                        .frame(width: 8, height: 8)
                                }
                                Text(watchStatusSubtitle)
                                    .cvText(13, color: CV.cream.opacity(0.6), inter: true)
                            }
                            
                            Spacer()
                            
                            Button {
                                refreshSupabaseLocation()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(isPingingWatch ? CV.cream.opacity(0.3) : Color(hex: 0xFFB020))
                                    .rotationEffect(.degrees(isPingingWatch ? 360 : 0))
                                    .animation(
                                        isPingingWatch ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                                        value: isPingingWatch
                                    )
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.06), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(18)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        
                        // ── How-to card ──────────────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "applewatch.watchface")
                                    .foregroundStyle(Color(hex: 0xFFB020))
                                Text("HOW TO CONNECT")
                                    .cvText(11, .bold, color: CV.cream.opacity(0.5), tracking: 0.8, inter: true)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                stepRow(number: "1", text: "Open **Convoy** on your Apple Watch")
                                stepRow(number: "2", text: "Tap **\"Let's Ride\"** on the welcome screen")
                                stepRow(number: "3", text: "Tap **\"Let's Ride\"** again to sign in anonymously")
                                stepRow(number: "4", text: "Your watch location will appear live below ↓")
                            }
                            
                            if isWatchSignedIn, let uid = supabaseUserId {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(CV.green)
                                        .font(.system(size: 12))
                                    Text("Watch signed in · ID ends in …\(uid.suffix(8))")
                                        .cvText(11, color: CV.green, inter: true)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(18)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        
                        // ── Live Location Map ─────────────────────────────────
                        if let loc = displayedWatchLocation {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "location.fill")
                                        .foregroundStyle(CV.green)
                                    Text("LIVE WATCH LOCATION")
                                        .cvText(11, .bold, color: CV.cream.opacity(0.5), tracking: 0.8, inter: true)
                                    Spacer()
                                    if let fetched = lastFetchedAt {
                                        Text(relativeTime(fetched))
                                            .cvText(10, color: CV.cream.opacity(0.4), inter: true)
                                    }
                                }
                                
                                Map(position: $mapPosition) {
                                    Annotation("Watch", coordinate: loc.coordinate) {
                                        ZStack {
                                            Circle()
                                                .fill(CV.green.opacity(0.25))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "applewatch")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundStyle(CV.green)
                                        }
                                    }
                                }
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                
                                // Telemetry pills
                                HStack(spacing: 8) {
                                    metricPill("SPEED", String(format: "%.0f km/h", loc.speedKmh))
                                    metricPill("ACCURACY", String(format: "±%.0f m", loc.horizontalAccuracy))
                                    metricPill("HEADING", headingText(loc.heading))
                                }
                            }
                            .padding(18)
                            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        } else {
                            // Waiting state
                            VStack(spacing: 12) {
                                Image(systemName: "location.slash")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundStyle(CV.cream.opacity(0.3))
                                Text("Waiting for Watch Location")
                                    .cvText(14, .semibold, color: CV.cream.opacity(0.5), inter: true)
                                Text("Sign in on the Watch app first, then allow location access.")
                                    .cvText(12, color: CV.cream.opacity(0.35), inter: true)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                                if let err = fetchError {
                                    Text(err)
                                        .cvText(11, color: CV.red, inter: true)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        
                        // ── Last Event ──────────────────────────────────────
                        if !watchManager.lastReceivedAction.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "waveform")
                                        .foregroundStyle(Color(hex: 0xFFB020))
                                    Text("LAST EVENT")
                                        .cvText(11, .bold, color: CV.cream.opacity(0.5), tracking: 0.8, inter: true)
                                }
                                HStack {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(Color(hex: 0xFFB020))
                                    Text(watchManager.lastReceivedAction.isEmpty ? "Connected & listening" : watchManager.lastReceivedAction)
                                        .cvText(13, .semibold, color: CV.cream, inter: true)
                                    Spacer()
                                }
                                .padding(14)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .padding(18)
                            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            watchManager.activateSession()
            // Start polling Supabase for watch location
            startPollingWatchLocation()
        }
        .onDisappear {
            locationPollTimer?.invalidate()
            locationPollTimer = nil
        }
        .onChange(of: displayedWatchLocation) { _, newLoc in
            if let loc = newLoc {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    mapPosition = .region(MKCoordinateRegion(
                        center: loc.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        }
    }
    
    // MARK: - Supabase Polling
    
    private func startPollingWatchLocation() {
        // Fetch immediately
        Task { await fetchWatchLocationFromSupabase() }
        
        // Then poll every 3 seconds
        locationPollTimer?.invalidate()
        locationPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { await fetchWatchLocationFromSupabase() }
        }
    }
    
    @MainActor
    private func fetchWatchLocationFromSupabase() async {
        // Fetch the most recently updated watch location
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/watch_locations?select=user_id,latitude,longitude,speed_kmh,heading,accuracy,updated_at&order=updated_at.desc&limit=1") else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 6
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return }
            
            if http.statusCode == 404 || http.statusCode == 400 {
                // Table doesn't exist yet — watch hasn't streamed any location
                fetchError = "Watch hasn't sent location yet. Open Watch app first."
                return
            }
            
            guard http.statusCode == 200,
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = arr.first,
                  let lat = row["latitude"] as? Double,
                  let lon = row["longitude"] as? Double else {
                return
            }
            
            let uid = row["user_id"] as? String
            let speedKmh = (row["speed_kmh"] as? Double) ?? 0
            let heading = (row["heading"] as? Double) ?? -1
            let accuracy = (row["accuracy"] as? Double) ?? 10
            
            // Parse updated_at to check staleness
            var updatedAt = Date()
            if let updatedStr = row["updated_at"] as? String {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                updatedAt = iso.date(from: updatedStr) ?? Date()
            }
            
            let telemetry = WatchLiveTelemetry(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                altitude: 0,
                speed: speedKmh / 3.6,
                speedKmh: speedKmh,
                course: heading,
                heading: heading >= 0 ? heading : nil,
                horizontalAccuracy: accuracy,
                timestamp: updatedAt
            )
            
            supabaseWatchLocation = telemetry
            supabaseUserId = uid
            isWatchSignedIn = uid != nil
            lastFetchedAt = Date()
            fetchError = nil
            
        } catch {
            fetchError = "Network error: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func refreshSupabaseLocation() {
        isPingingWatch = true
        Task {
            await fetchWatchLocationFromSupabase()
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    isPingingWatch = false
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var watchStatusSubtitle: String {
        if isWatchSignedIn { return "Signed in · Streaming location" }
        return "Open Watch app to sign in"
    }
    
    private func relativeTime(_ date: Date) -> String {
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 5 { return "just now" }
        if secs < 60 { return "\(secs)s ago" }
        return "\(secs / 60)m ago"
    }
    
    private func headingText(_ h: Double?) -> String {
        guard let h = h, h >= 0 else { return "—" }
        let dirs = ["N","NE","E","SE","S","SW","W","NW","N"]
        return dirs[Int((h + 22.5) / 45) % 8]
    }
    
    @ViewBuilder
    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .cvText(11, .bold, color: Color(hex: 0xFFB020), mono: true)
                .frame(width: 18, height: 18)
                .background(Color(hex: 0xFFB020).opacity(0.15), in: Circle())
            // Simple markdown-style bold — just show as plain text since AttributedString needs iOS 15
            Text(text.replacingOccurrences(of: "**", with: ""))
                .cvText(13, color: CV.cream.opacity(0.75), inter: true)
                .lineLimit(3)
            Spacer()
        }
    }
    
    private func metricPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).cvText(9, .bold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
            Text(value).cvText(12, .bold, color: CV.cream, inter: true).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

//
//  WatchSupabaseService.swift
//  ConvoyWatch Watch App
//
//  Handles all Supabase communication from Apple Watch:
//  - Anonymous sign-in (no iPhone required)
//  - Persisting session across launches
//  - Streaming live Watch GPS location to Supabase
//  - Fetching upcoming rides
//

import Foundation
import SwiftUI
import Combine

public struct WatchRideItem: Identifiable, Codable {
    public let id: String
    public let title: String
    public let departsAt: Date
    public let startLocation: String
    public let distanceKm: Double
    public let ridersCount: Int
    
    public init(id: String, title: String, departsAt: Date, startLocation: String, distanceKm: Double, ridersCount: Int) {
        self.id = id
        self.title = title
        self.departsAt = departsAt
        self.startLocation = startLocation
        self.distanceKm = distanceKm
        self.ridersCount = ridersCount
    }
}

@MainActor
public final class WatchSupabaseService: ObservableObject {
    public static let shared = WatchSupabaseService()
    
    private let supabaseUrl = "https://avykoruhcgwpmvmddlta.supabase.co"
    private let anonKey = "sb_publishable_4cTQxSHnQbUtxLE_n2Rz7A_YDCuQ5-0"
    
    // UserDefaults keys
    private let kAccessToken = "watch_supabase_access_token"
    private let kRefreshToken = "watch_supabase_refresh_token"
    private let kUserId = "watch_supabase_user_id"
    private let kRealUserId = "watch_real_user_id"  // Real Supabase profile ID from ConvoyPhone account
    
    @Published public var upcomingRides: [WatchRideItem] = []
    @Published public var isLoading: Bool = false
    
    /// The current anonymous user's Supabase UUID (nil if not signed in)
    public private(set) var currentUserId: String? {
        get { UserDefaults.standard.string(forKey: kUserId) }
        set { UserDefaults.standard.set(newValue, forKey: kUserId) }
    }
    
    /// The REAL profile user ID from the ConvoyPhone account (overrides anon ID for location streaming)
    public private(set) var realUserId: String? {
        get { UserDefaults.standard.string(forKey: kRealUserId) }
        set { UserDefaults.standard.set(newValue, forKey: kRealUserId) }
    }
    
    /// Call after profile lookup — tags location records with the ConvoyPhone user's real UUID
    public func overrideUserId(_ uid: String) {
        self.realUserId = uid
    }
    
    /// The ID to use when streaming location — prefer the real profile ID
    public var locationUserId: String? {
        realUserId ?? currentUserId
    }
    
    public private(set) var accessToken: String? {
        get { UserDefaults.standard.string(forKey: kAccessToken) }
        set { UserDefaults.standard.set(newValue, forKey: kAccessToken) }
    }
    
    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: kRefreshToken) }
        set { UserDefaults.standard.set(newValue, forKey: kRefreshToken) }
    }
    
    private init() {
        loadDefaultRides()
    }
    
    // MARK: - Session
    
    /// True if we have a stored session from a previous launch
    public var hasSavedSession: Bool {
        currentUserId != nil && accessToken != nil
    }
    
    /// Sign in anonymously — creates a new Supabase user with no credentials.
    /// Idempotent: if a session is already stored and the token is still valid, returns the cached user ID.
    public func signInAnonymously() async throws -> String {
        // Try to reuse a saved session first
        if let uid = currentUserId, let token = accessToken {
            // Quickly validate the token hasn't expired by pinging the user endpoint
            if await validateToken(token) {
                return uid
            }
            // Token expired — try refresh
            if let refreshed = await refreshSession() {
                return refreshed
            }
            // Refresh failed — fall through to fresh sign-in
        }
        
        // Fresh anonymous sign-in
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/signup") else {
            throw NSError(domain: "WatchSupabase", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        // Empty body = anonymous sign-in in Supabase
        request.httpBody = "{}".data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "WatchSupabase", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Sign-in failed: \(body)"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userDict = json["user"] as? [String: Any],
              let uid = userDict["id"] as? String,
              let accessTok = json["access_token"] as? String else {
            throw NSError(domain: "WatchSupabase", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected response from Supabase"])
        }
        
        // Persist session
        self.currentUserId = uid
        self.accessToken = accessTok
        self.refreshToken = json["refresh_token"] as? String
        
        print("[WatchSupabase] Signed in anonymously as \(uid)")
        return uid
    }
    
    private func validateToken(_ token: String) async -> Bool {
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/user") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
    
    private func refreshSession() async -> String? {
        guard let refresh = refreshToken,
              let url = URL(string: "\(supabaseUrl)/auth/v1/token?grant_type=refresh_token") else { return nil }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refresh])
        
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userDict = json["user"] as? [String: Any],
              let uid = userDict["id"] as? String,
              let newToken = json["access_token"] as? String else { return nil }
        
        self.currentUserId = uid
        self.accessToken = newToken
        self.refreshToken = json["refresh_token"] as? String
        return uid
    }
    
    /// Clear stored session (sign out)
    public func signOut() {
        UserDefaults.standard.removeObject(forKey: kAccessToken)
        UserDefaults.standard.removeObject(forKey: kRefreshToken)
        UserDefaults.standard.removeObject(forKey: kUserId)
    }
    
    // MARK: - Live Location Streaming
    
    /// Upsert the Watch's current GPS to Supabase `watch_locations` table.
    /// Called from WatchLocationManager on every location update.
    public func streamLocation(lat: Double, lon: Double, speedKmh: Double,
                                heading: Double, accuracy: Double) async {
        guard let uid = locationUserId, let token = accessToken else { return }
        
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/watch_locations") else { return }
        
        let body: [String: Any] = [
            "user_id": uid,
            "latitude": lat,
            "longitude": lon,
            "speed_kmh": speedKmh,
            "heading": heading,
            "accuracy": accuracy,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Upsert (merge by user_id) — creates table row if not exists
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = bodyData
        req.timeoutInterval = 8
        
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                print("[WatchSupabase] streamLocation HTTP \(http.statusCode)")
            }
        } catch {
            print("[WatchSupabase] streamLocation error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Profile Lookup
    
    public func fetchProfile(username: String) async -> [String: Any]? {
        let cleanUsername = username.hasPrefix("@") ? String(username.dropFirst()) : username
        guard let encoded = cleanUsername.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(supabaseUrl)/rest/v1/profiles?username=eq.\(encoded)&select=id,username,display_name,avatar_data&limit=1") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = jsonArray.first {
                return first
            }
        } catch {
            print("[WatchSupabaseService] fetchProfile error: \(error.localizedDescription)")
        }
        return nil
    }
    
    // MARK: - Rides
    
    public func loadDefaultRides() {
        self.upcomingRides = [
            WatchRideItem(
                id: "ride_1",
                title: "Sunday Mountain Blitz",
                departsAt: Date().addingTimeInterval(3600 * 4),
                startLocation: "Highland Peak",
                distanceKm: 42.5,
                ridersCount: 5
            ),
            WatchRideItem(
                id: "ride_2",
                title: "Coastal Sunset Run",
                departsAt: Date().addingTimeInterval(3600 * 28),
                startLocation: "Pacific Marina",
                distanceKm: 68.0,
                ridersCount: 8
            )
        ]
    }
    
    public func fetchUpcomingRides() async {
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/rides?select=id,title,departs,from_location,to_location,distance,route_km&limit=5&order=departs.asc") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        
        do {
            isLoading = true
            let (data, response) = try await URLSession.shared.data(for: request)
            isLoading = false
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return
            }
            
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var fetched: [WatchRideItem] = []
                for item in jsonArray {
                    let id = item["id"] as? String ?? UUID().uuidString
                    let title = item["title"] as? String ?? "Convoy Ride"
                    let start = item["from_location"] as? String ?? "Meeting Point"
                    let dist = (item["route_km"] as? NSNumber)?.doubleValue
                        ?? (Double(item["distance"] as? String ?? "0") ?? 35.0)
                    let riders = (item["pack_size"] as? NSNumber)?.intValue ?? 4
                    
                    let departsDate: Date
                    if let departsStr = item["departs"] as? String {
                        let iso = ISO8601DateFormatter()
                        departsDate = iso.date(from: departsStr) ?? Date().addingTimeInterval(3600)
                    } else {
                        departsDate = Date().addingTimeInterval(3600)
                    }
                    
                    fetched.append(WatchRideItem(
                        id: id,
                        title: title,
                        departsAt: departsDate,
                        startLocation: start,
                        distanceKm: dist,
                        ridersCount: riders
                    ))
                }
                if !fetched.isEmpty {
                    self.upcomingRides = fetched
                }
            }
        } catch {
            isLoading = false
            print("[WatchSupabaseService] fetch error: \(error.localizedDescription)")
        }
    }
}

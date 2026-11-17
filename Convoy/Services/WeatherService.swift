// WeatherService.swift
// Live "right now" weather for the Home header, from Open-Meteo (free, no API key).
import Foundation
import CoreLocation

struct LiveWeather: Equatable, Codable {
    let temperature: Double
    let code: Int
    let isDay: Bool
    // Extra readings for the Home weather card (nil when the service didn't return them).
    var feelsLike: Double? = nil
    var windKmh: Double? = nil
    var rainChance: Int? = nil
    var high: Double? = nil
    var low: Double? = nil

    /// Simple go / careful / wait verdict for riding, from the readings only.
    enum Verdict { case go, care, wait }
    var verdict: Verdict {
        switch kind {
        case .storm, .snow: return .wait
        case .rain, .drizzle, .fog: return .care
        default:
            if (windKmh ?? 0) >= 40 || temperature >= 38 || temperature <= 3 { return .care }
            if (rainChance ?? 0) >= 60 { return .care }
            return .go
        }
    }

    enum Kind { case clear, partly, cloudy, fog, drizzle, rain, snow, storm }

    var kind: Kind {
        switch code {
        case 0: return .clear
        case 1, 2: return .partly
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51...57: return .drizzle
        case 61...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95...99: return .storm
        default: return .cloudy
        }
    }

    var symbol: String {
        switch kind {
        case .clear: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partly: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .storm: return "cloud.bolt.rain.fill"
        }
    }

    var condition: String {
        switch kind {
        case .clear: return isDay ? "Sunny" : "Clear night"
        case .partly: return "Partly cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Foggy"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .storm: return "Thunderstorms"
        }
    }

    /// A short, honest riding hint derived only from the reading above.
    var ridingNote: String {
        switch kind {
        case .storm: return "Storms around, maybe wait"
        case .snow: return "Icy roads, take it slow"
        case .rain, .drizzle: return "Pack your rain gear"
        case .fog: return "Low visibility, lights on"
        default:
            if temperature >= 36 { return "Hot out, stay hydrated" }
            if temperature <= 5 { return "Cold out, layer up" }
            return isDay ? "Great riding weather" : "Calm night for a ride"
        }
    }
}

@MainActor @Observable
final class WeatherService {
    static let shared = WeatherService()

    private(set) var current: LiveWeather?
    private(set) var place: String?

    private var lastFetch: Date?
    private var lastCoord: CLLocationCoordinate2D?
    private let manager = CLLocationManager()
    private var inFlight: Task<Void, Never>?

    private static let cacheKey = "weather_cache_v1"
    private struct Cache: Codable { let weather: LiveWeather; let place: String?; let at: Date; let lat: Double; let lon: Double }

    /// The last reading is kept on the phone so Home shows it the instant the app opens;
    /// a fresh one replaces it in the background. Readings older than 12 hours are dropped.
    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let c = try? JSONDecoder().decode(Cache.self, from: data),
           Date().timeIntervalSince(c.at) < 12 * 3600 {
            current = c.weather
            place = c.place
            lastFetch = c.at
            lastCoord = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
        }
    }

    /// Starts reading the weather as early as possible (app launch, behind the opening animation)
    /// so Home doesn't wait for it. Uses only a position the app is already allowed to read.
    func warmUp() {
        guard inFlight == nil, let c = bestCoordinate(fallback: nil) else { return }
        inFlight = Task { await refresh(near: c); inFlight = nil }
    }

    /// The best place to read the weather for without prompting: the phone's last known
    /// position if location is already allowed, otherwise the given fallback (e.g. a ride's start).
    func bestCoordinate(fallback: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways,
           let loc = LocationService.shared.currentLocation ?? manager.location {
            return loc.coordinate
        }
        return fallback
    }

    func refresh(near coord: CLLocationCoordinate2D, force: Bool = false) async {
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 15 * 60,
           let lc = lastCoord, abs(lc.latitude - coord.latitude) < 0.05, abs(lc.longitude - coord.longitude) < 0.05 {
            return
        }
        // Rounded to ~1 km: enough for weather, and doesn't send a precise position.
        let lat = (coord.latitude * 100).rounded() / 100
        let lon = (coord.longitude * 100).rounded() / 100
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day,apparent_temperature,wind_speed_10m"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
        ]
        guard let url = comps.url,
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return }
        current = LiveWeather(temperature: decoded.current.temperature_2m,
                              code: decoded.current.weather_code,
                              isDay: decoded.current.is_day == 1,
                              feelsLike: decoded.current.apparent_temperature,
                              windKmh: decoded.current.wind_speed_10m,
                              rainChance: decoded.daily?.precipitation_probability_max?.first.flatMap { $0 },
                              high: decoded.daily?.temperature_2m_max?.first.flatMap { $0 },
                              low: decoded.daily?.temperature_2m_min?.first.flatMap { $0 })
        lastFetch = .now
        lastCoord = coord

        if let mark = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coord.latitude, longitude: coord.longitude)).first {
            place = mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea
        }
        if let w = current, let data = try? JSONEncoder().encode(
            Cache(weather: w, place: place, at: .now, lat: coord.latitude, lon: coord.longitude)) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
            let apparent_temperature: Double?
            let wind_speed_10m: Double?
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double?]?
            let temperature_2m_min: [Double?]?
            let precipitation_probability_max: [Int?]?
        }
        let current: Current
        let daily: Daily?
    }
}

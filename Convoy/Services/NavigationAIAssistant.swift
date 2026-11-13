// NavigationAIAssistant.swift
// Powered by Google Gemini 2.5 Flash for natural voice navigation assistance,
// semantic stop identification, and motorcycle convoy hazard alerts.
import Foundation
import CoreLocation

struct NavigationContext: Sendable {
    var destinationName: String
    var remainingDistanceKm: Double
    var currentSpeedKmh: Int
    var isLeader: Bool
    var currentCoord: CLLocationCoordinate2D?
}

enum NavigationAIAction: Sendable {
    case addStop(query: String, spoken: String)
    case proposeStop(query: String, spoken: String)
    case reportWarning(type: RiderWarningType, spoken: String)
    case changeRoute(style: RouteStyle, spoken: String)
    case muteVoice(spoken: String)
    case unmuteVoice(spoken: String)
    case endRide(spoken: String)
    case assistAnswer(spoken: String)
    case fallback(rawQuery: String)
}

@MainActor
final class NavigationAIAssistant {
    static let shared = NavigationAIAssistant()

    // Configured Gemini API Key provided by user
    private let apiKey: String = {
        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return ""
    }()

    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    private init() {}

    func interpret(
        voiceQuery: String,
        context: NavigationContext
    ) async -> NavigationAIAction {
        let trimmed = voiceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .fallback(rawQuery: voiceQuery)
        }

        guard let url = URL(string: "\(endpoint)?key=\(apiKey)") else {
            return .fallback(rawQuery: voiceQuery)
        }

        let sysPrompt = """
        You are Convoy's Copilot AI for motorcycle group navigation.
        The user is riding a motorbike. Give concise, safe spoken responses (under 15 words).
        Interpret the rider's voice query in context:
        - Destination: \(context.destinationName)
        - Remaining distance: \(String(format: "%.1f", context.remainingDistanceKm)) km
        - Current speed: \(context.currentSpeedKmh) km/h
        - Rider is group leader: \(context.isLeader ? "yes" : "no")

        Classify into one JSON object with:
        - "action": "add_stop" (if leader or solo wanting to add a stop),
                    "propose_stop" (if follower wanting to suggest a stop to leader),
                    "report_warning" (rider reporting hazard or condition: traffic, fuel, breakdown, medical, slow_down, wait),
                    "change_route" (scenic, fastest, off_route),
                    "mute_voice", "unmute_voice", "end_ride", or "general_assist"
        - "search_query": place, POI or item to search near route (e.g. "petrol pump", "Starbucks", "viewpoint") or null
        - "warning_type": "traffic", "fuel", "breakdown", "medical", "slow_down", "wait", or null
        - "route_style": "fastest", "scenic", "off_route", or null
        - "spoken_response": Short, friendly spoken audio sentence to read aloud to the rider.
        """

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": sysPrompt]]
            ],
            "contents": [
                ["parts": [["text": trimmed]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.2
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 6.0

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .fallback(rawQuery: voiceQuery)
            }

            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = root["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String,
                  let jsonData = text.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else {
                return .fallback(rawQuery: voiceQuery)
            }

            let action = parsed["action"] as? String ?? "general_assist"
            let searchQuery = parsed["search_query"] as? String
            let warningTypeStr = parsed["warning_type"] as? String
            let routeStyleStr = parsed["route_style"] as? String
            let spoken = parsed["spoken_response"] as? String ?? "Done."

            // If a warning type is present, trigger that warning
            if let wType = warningTypeStr, let parsedWarning = RiderWarningType(rawValue: wType) {
                // If they also asked for a stop (like low on fuel + find pump), we prioritize or do both
                if let query = searchQuery, !query.isEmpty {
                    if context.isLeader {
                        return .addStop(query: query, spoken: spoken)
                    } else {
                        return .proposeStop(query: query, spoken: spoken)
                    }
                }
                return .reportWarning(type: parsedWarning, spoken: spoken)
            }

            switch action {
            case "add_stop":
                let q = searchQuery ?? trimmed
                return .addStop(query: q, spoken: spoken)

            case "propose_stop":
                let q = searchQuery ?? trimmed
                return .proposeStop(query: q, spoken: spoken)

            case "report_warning":
                if let wType = warningTypeStr, let wt = RiderWarningType(rawValue: wType) {
                    return .reportWarning(type: wt, spoken: spoken)
                }
                return .assistAnswer(spoken: spoken)

            case "change_route":
                let style: RouteStyle = {
                    if routeStyleStr == "scenic" { return .scenic }
                    if routeStyleStr == "off_route" { return .offRoute }
                    return .fastest
                }()
                return .changeRoute(style: style, spoken: spoken)

            case "mute_voice":
                return .muteVoice(spoken: spoken)

            case "unmute_voice":
                return .unmuteVoice(spoken: spoken)

            case "end_ride":
                return .endRide(spoken: spoken)

            default:
                return .assistAnswer(spoken: spoken)
            }

        } catch {
            return .fallback(rawQuery: voiceQuery)
        }
    }
}


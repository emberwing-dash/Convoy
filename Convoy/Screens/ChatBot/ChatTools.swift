// ChatTools.swift
import Foundation

/// Tool schemas exposed to Groq + the dispatcher that runs each tool against
/// the app's existing AppState / SupabaseManager / DiscoverStore methods.
///
/// Two categories:
///   - Read-only / navigate → executed immediately, result fed back to model
///   - Write → produces a confirmation card; execution deferred until user taps Confirm
enum ChatTools {

    // MARK: - Schemas sent to Groq

    static let schemas: [[String: Any]] = [
        searchPlacesSchema,
        searchRoutesSchema,
        listMyRidesSchema,
        listMyCrewsSchema,
        findUserSchema,
        planRideSchema,
        joinRideSchema,
        sendFriendRequestSchema,
        createCrewSchema,
        inviteToCrewSchema
    ]

    private static let searchPlacesSchema: [String: Any] = [
        "type": "function",
        "function": [
            "name": "search_places",
            "description": "Find places to ride to — lakes, waterfalls, viewpoints, beaches, cafes, hill roads, hill stations, historical sites. Can filter by category or search by name/region.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Free-text search (place name or region). Optional."],
                    "category": [
                        "type": "string",
                        "enum": ["lake", "waterfall", "viewpoint", "beach", "forest", "cafe", "historical", "hillRoad", "hillStation", "waterfront"],
                        "description": "Restrict results to one category. Optional."
                    ]
                ]
            ]
        ]
    ]

    private static let searchRoutesSchema: [String: Any] = [
        "type": "function",
        "function": [
            "name": "search_routes",
            "description": "Find curated motorcycle routes. Useful when the user asks for route ideas or rides in a region.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Free-text search across route titles, regions, tags. Optional."]
                ]
            ]
        ]
    ]

    private static let listMyRidesSchema: [String: Any] = [
        "type": "function",
        "function": [
            "name": "list_my_rides",
            "description": "List the rides the current user is going on (accepted memberships). Returns title, date, time, place.",
            "parameters": ["type": "object", "properties": [:]]
        ]
    ]

    private static let listMyCrewsSchema: [String: Any] = [
        "type": "function",
        "function": [
            "name": "list_my_crews",
            "description": "List the crews (groups) the user belongs to with member counts.",
            "parameters": ["type": "object", "properties": [:]]
        ]
    ]

    private static let findUserSchema: [String: Any] = [
        "type": "function",
        "function": [
            "name": "find_user",
            "description": "Look up a Convoy user by their @handle. Always use this before referring to a user by name.",
            "parameters": [
                "type": "object",
                "properties": [
                    "username": ["type": "string", "description": "The handle without @ prefix."]
                ],
                "required": ["username"]
            ]
        ]
    ]

    private static let planRideSchema: [String: Any] = [
        "type": "function",
        "function": [
            "name": "plan_ride",
            "description": "Open the ride planner with this destination pre-filled. The user reviews and confirms in the planner. Use whenever the user wants to plan or create a ride.",
            "parameters": [
                "type": "object",
                "properties": [
                    "destination": ["type": "string", "description": "Where the ride ends. City, place, or address — the planner will geocode it."],
                    "from": ["type": "string", "description": "Where the ride starts. Optional; uses the user's Discover origin if not provided."],
                    "stops": ["type": "array", "items": ["type": "string"], "description": "Intermediate stop names, in order. Optional."],
                    "title": ["type": "string", "description": "Optional ride title. Defaults to 'Ride to <destination>'."]
                ],
                "required": ["destination"]
            ]
        ]
    ]

    private static let joinRideSchema: [String: Any] = [
        "type": "function",
        "function": [
            "name": "join_ride",
            "description": "Join a ride using its 6-character code. Sends a join request; the organiser approves.",
            "parameters": [
                "type": "object",
                "properties": [
                    "code": ["type": "string", "description": "The 6-character ride code."]
                ],
                "required": ["code"]
            ]
        ]
    ]

    private static let sendFriendRequestSchema: [String: Any] = [
        "type": "function",
        "function": [
            "name": "send_friend_request",
            "description": "Send a friend request to another Convoy user by @handle.",
            "parameters": [
                "type": "object",
                "properties": [
                    "username": ["type": "string", "description": "The handle without @ prefix."]
                ],
                "required": ["username"]
            ]
        ]
    ]

    private static let createCrewSchema: [String: Any] = [
        "type": "function",
        "function": [
            "name": "create_crew",
            "description": "Create a new crew (group of riders). The user becomes admin.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Crew name, e.g. 'Weekend Riders'."]
                ],
                "required": ["name"]
            ]
        ]
    ]

    private static let inviteToCrewSchema: [String: Any] = [
        "type": "function",
        "function": [
            "name": "invite_to_crew",
            "description": "Invite a Convoy user to one of the caller's crews. Both must be identified.",
            "parameters": [
                "type": "object",
                "properties": [
                    "crew_name": ["type": "string", "description": "Exact crew name, from list_my_crews."],
                    "username": ["type": "string", "description": "Handle without @ prefix."]
                ],
                "required": ["crew_name", "username"]
            ]
        ]
    ]

    // MARK: - Classification

    private static let writeTools: Set<String> = [
        "join_ride", "send_friend_request", "create_crew", "invite_to_crew",
        "plan_ride"
    ]

    /// True if this tool must be confirmed by the user before running.
    static func requiresConfirmation(_ name: String) -> Bool {
        writeTools.contains(name)
    }

    /// When confirmed, does this tool navigate away (closing chat) instead of writing?
    static func isNavigating(_ name: String) -> Bool {
        name == "plan_ride"
    }

    // MARK: - Confirmation card content

    static func confirmationTitle(_ name: String, _ args: [String: Any]) -> String {
        switch name {
        case "join_ride":            return "Join this ride?"
        case "send_friend_request":  return "Send friend request?"
        case "create_crew":          return "Create this crew?"
        case "invite_to_crew":       return "Invite to crew?"
        case "plan_ride":            return "Open ride planner?"
        default:                     return "Confirm action"
        }
    }

    static func confirmationDetail(_ name: String, _ args: [String: Any]) -> String {
        switch name {
        case "join_ride":
            return "Code: \(args["code"] as? String ?? "—")"
        case "send_friend_request":
            return "to @\(args["username"] as? String ?? "—")"
        case "create_crew":
            return "\"\(args["name"] as? String ?? "—")\""
        case "invite_to_crew":
            return "@\(args["username"] as? String ?? "—") → \"\(args["crew_name"] as? String ?? "—")\""
        case "plan_ride":
            let to = args["destination"] as? String ?? "—"
            let from = args["from"] as? String ?? ""
            let stops = (args["stops"] as? [String]) ?? []
            var detail = from.isEmpty ? "to \(to)" : "\(from) → \(to)"
            if !stops.isEmpty { detail += " · \(stops.count) stop\(stops.count == 1 ? "" : "s")" }
            return detail
        default:
            return ""
        }
    }

    static func statusLabel(_ name: String) -> String {
        switch name {
        case "search_places":       return "Searching places…"
        case "search_routes":       return "Searching routes…"
        case "list_my_rides":       return "Looking up rides…"
        case "list_my_crews":       return "Looking up crews…"
        case "find_user":           return "Finding user…"
        case "join_ride":           return "Joining ride…"
        case "send_friend_request": return "Sending request…"
        case "create_crew":         return "Creating crew…"
        case "invite_to_crew":      return "Sending invite…"
        default:                    return "Working…"
        }
    }

    // MARK: - Execute

    /// Executes a tool and returns a JSON-encoded string (Groq requires string content).
    @MainActor
    static func execute(name: String, args: [String: Any], app: AppState) async -> String {
        do {
            switch name {
            case "search_places":
                let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespaces)
                let categoryStr = args["category"] as? String
                let category = categoryStr.flatMap { PlaceCategory(rawValue: $0) }
                return await searchPlaces(query: query, category: category)

            case "search_routes":
                let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespaces)
                return await searchRoutes(query: query)

            case "list_my_rides":
                await app.refreshRides(force: true)
                let rides = app.rides.prefix(6).map { r -> [String: String] in
                    [
                        "title": r.title,
                        "place": r.place,
                        "date": r.displayDate,
                        "time": r.displayTime,
                        "organiser": r.organiser
                    ]
                }
                if rides.isEmpty { return jsonEncode(["note": "No upcoming rides"]) }
                return jsonEncode(["rides": Array(rides)])

            case "list_my_crews":
                await app.loadCrews(force: true)
                let crews = app.crews.map { c -> [String: Any] in
                    ["name": c.name, "member_count": c.memberCount, "code": c.code]
                }
                if crews.isEmpty { return jsonEncode(["note": "No crews yet"]) }
                return jsonEncode(["crews": crews])

            case "find_user":
                let username = args["username"] as? String ?? ""
                guard !username.isEmpty else { return jsonEncode(["error": "Missing username"]) }
                if let p = try await SupabaseManager.shared.fetchProfile(username: username) {
                    return jsonEncode([
                        "user": [
                            "username": p.username,
                            "display_name": p.display_name
                        ]
                    ])
                }
                return jsonEncode(["error": "No user with @\(username)"])

            case "plan_ride":
                let destination = (args["destination"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                guard !destination.isEmpty else { return jsonEncode(["error": "Missing destination"]) }
                let from = (args["from"] as? String) ?? ""
                let stops = (args["stops"] as? [String]) ?? []
                let title = args["title"] as? String
                let seed = PlanSeed(
                    name: title ?? "Ride to \(destination)",
                    start: from,
                    startCoord: nil,
                    destination: destination,
                    destinationCoord: nil,
                    stops: stops.map { .init(name: $0, coord: nil) }
                )
                app.startPlan(seed)
                // Atomically replace the nav stack: closes chat, opens planner.
                app.path = [.planDetails]
                return jsonEncode(["status": "opened_planner", "destination": destination])

            case "join_ride":
                let code = (args["code"] as? String ?? "").uppercased().trimmingCharacters(in: .whitespaces)
                guard code.count == 6 else { return jsonEncode(["error": "Code must be 6 characters"]) }
                let outcome = await app.joinRideByCode(code)
                switch outcome {
                case .joined(let id):
                    await MainActor.run {
                        app.tab = .ride
                        app.popToRoot()
                        app.push(.rideDetails(id))
                    }
                    return jsonEncode(["status": "joined", "note": "You're in. Check the Ride tab."])
                case .requestPending:
                    return jsonEncode(["status": "pending_approval",
                                       "note": "Request sent. The organiser will approve shortly."])
                case .failed:
                    return jsonEncode(["error": "No ride found for code \(code)"])
                }

            case "send_friend_request":
                let username = args["username"] as? String ?? ""
                guard !username.isEmpty else { return jsonEncode(["error": "Missing username"]) }
                let userId: UUID
                if let existing = app.backendUserId {
                    userId = existing
                } else if let restored = await SupabaseManager.shared.getOrRestoreUserId() {
                    userId = restored
                } else {
                    return jsonEncode(["error": "Not signed in"])
                }
                try await SupabaseManager.shared.sendFriendRequest(senderId: userId, receiverUsername: username)
                await app.loadFriends(force: true)
                return jsonEncode(["status": "sent", "to": username])

            case "create_crew":
                let crewName = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                guard !crewName.isEmpty else { return jsonEncode(["error": "Missing crew name"]) }
                let userId: UUID
                if let existing = app.backendUserId {
                    userId = existing
                } else if let restored = await SupabaseManager.shared.getOrRestoreUserId() {
                    userId = restored
                } else {
                    return jsonEncode(["error": "Not signed in"])
                }
                let code = CrewGroup.makeCode(name: crewName)
                let crewId = try await SupabaseManager.shared.createCrew(
                    name: crewName, code: code, creatorId: userId,
                    memberIds: [], avatarData: nil
                )
                await app.loadCrews(force: true)
                return jsonEncode([
                    "status": "created",
                    "name": crewName,
                    "code": code,
                    "id": crewId.uuidString
                ])

            case "invite_to_crew":
                let crewName = (args["crew_name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let username = args["username"] as? String ?? ""
                guard !crewName.isEmpty, !username.isEmpty else {
                    return jsonEncode(["error": "Missing crew name or username"])
                }
                let userId: UUID
                if let existing = app.backendUserId {
                    userId = existing
                } else if let restored = await SupabaseManager.shared.getOrRestoreUserId() {
                    userId = restored
                } else {
                    return jsonEncode(["error": "Not signed in"])
                }
                await app.loadCrews(force: true)
                guard let crew = app.crews.first(where: {
                    $0.name.lowercased() == crewName.lowercased()
                }) else {
                    let names = app.crews.map(\.name).joined(separator: ", ")
                    return jsonEncode(["error": "No crew named '\(crewName)'. You have: \(names.isEmpty ? "none" : names)"])
                }
                try await SupabaseManager.shared.inviteToCrew(
                    crewId: crew.id, receiverUsername: username, invitedBy: userId
                )
                return jsonEncode(["status": "invited", "to": username, "crew": crew.name])

            default:
                return jsonEncode(["error": "Unknown tool \(name)"])
            }
        } catch {
            return jsonEncode(["error": error.localizedDescription])
        }
    }

    // MARK: - Individual implementations

    @MainActor
    private static func searchPlaces(query: String?, category: PlaceCategory?) async -> String {
        let store = DiscoverStore.shared
        await store.loadIfNeeded()

        var results: [DiscoverPlace] = []
        if let q = query, !q.isEmpty {
            results = store.search(q).places
        } else if let c = category {
            results = store.placesNear([c], minimum: 6).items
        } else {
            results = store.placesNear().items
        }

        if results.isEmpty {
            let scope = query ?? category?.label ?? "places"
            return jsonEncode(["error": "No \(scope) found. Try a different name or category."])
        }

        let top = results.prefix(5).map { p -> [String: String] in
            [
                "name": p.name,
                "region": p.region,
                "category": p.category.label,
                "summary": String(p.summary.prefix(140))
            ]
        }
        return jsonEncode(["places": Array(top)])
    }

    @MainActor
    private static func searchRoutes(query: String?) async -> String {
        let store = DiscoverStore.shared
        await store.loadIfNeeded()

        var results: [DiscoverRoute] = []
        if let q = query, !q.isEmpty {
            results = store.search(q).routes
        } else {
            results = Array(store.routes.prefix(5))
        }

        if results.isEmpty {
            return jsonEncode(["error": "No routes found matching \(query ?? "any query")."])
        }

        let top = results.prefix(5).map { r -> [String: String] in
            [
                "title": r.title,
                "from_to": r.fromTo,
                "length": r.estimate?.distanceText ?? "—",
                "tags": r.tags.joined(separator: ", ")
            ]
        }
        return jsonEncode(["routes": Array(top)])
    }

    private static func jsonEncode(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

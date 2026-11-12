// ChatTools.swift
import Foundation
import MapKit

enum ChatTools {
    static let allToolNames: [String] = [
        "search_places", "search_routes", "list_my_rides", "list_my_crews", "list_my_friends",
        "suggest_checkpoints", "begin_ride_planning", "set_ride_companions", "set_ride_start",
        "set_ride_checkpoints", "set_ride_time", "fetch_routes", "finalize_ride_plan",
        "join_ride", "send_friend_request", "create_crew", "invite_to_crew"
    ]

    static let writeTools: Set<String> = [
        "join_ride", "send_friend_request", "create_crew", "invite_to_crew", "finalize_ride_plan"
    ]

    static func requiresConfirmation(_ name: String) -> Bool { writeTools.contains(name) }
    static func isNavigating(_ name: String) -> Bool { name == "finalize_ride_plan" }

    static let schemas: [[String: Any]] = [
        searchPlacesSchema, searchRoutesSchema, listMyRidesSchema, listMyCrewsSchema, listFriendsSchema,
        findUserSchema, suggestCheckpointsSchema,
        beginRideSchema, setCompanionsSchema, setStartSchema,
        setCheckpointsSchema, setTimeSchema, fetchRoutesSchema, finalizeRideSchema,
        joinRideSchema, sendFriendSchema, createCrewSchema, inviteToCrewSchema
    ]

    private static func fn(_ name: String, _ desc: String, _ props: [String: Any] = [:], _ required: [String] = []) -> [String: Any] {
        ["type": "function", "function": ["name": name, "description": desc, "parameters": ["type": "object", "properties": props, "required": required]]]
    }

    private static let searchPlacesSchema = fn("search_places", "Find places to ride to.", ["query": ["type": "string"], "category": ["type": "string", "enum": ["lake","waterfall","viewpoint","beach","forest","cafe","historical","hillRoad","hillStation","waterfront"]]])
    private static let searchRoutesSchema = fn("search_routes", "Find curated routes.", ["query": ["type": "string"]])
    private static let listMyRidesSchema = fn("list_my_rides", "List the current user's accepted upcoming rides.")
    private static let listMyCrewsSchema = fn("list_my_crews", "List crews the current user belongs to.")
    private static let listFriendsSchema = fn("list_my_friends", "List the user's friends (name and handle).")
    private static let findUserSchema = fn("find_user", "Look up a Convoy user by @handle.", ["username": ["type": "string"]], ["username"])
    
    private static let suggestCheckpointsSchema = fn("suggest_checkpoints", "Suggest real cafes or scenic stops along the route.", ["start": ["type": "string"], "destination": ["type": "string"], "category": ["type": "string", "enum": ["cafe", "viewpoint", "restaurant", "waterfall"]]], ["start", "destination", "category"])

    private static let beginRideSchema = fn("begin_ride_planning", "Start a new ride-planning session.", ["destination": ["type": "string"]], ["destination"])
    private static let setCompanionsSchema = fn("set_ride_companions", "Record who's riding.", ["crew_name": ["type": "string"], "friend_usernames": ["type": "array", "items": ["type": "string"]], "solo": ["type": "boolean"]])
    private static let setStartSchema = fn("set_ride_start", "Record the starting point.", ["location": ["type": "string"], "use_current_location": ["type": "boolean"]], ["location"])
    private static let setCheckpointsSchema = fn("set_ride_checkpoints", "Record chosen intermediate stops.", ["checkpoints": ["type": "array", "items": ["type": "string"]]], ["checkpoints"])
    private static let setTimeSchema = fn("set_ride_time", "Record start time. Must be ISO8601.", ["iso8601": ["type": "string"]], ["iso8601"])
    
    private static let fetchRoutesSchema = fn("fetch_routes", "Calculate route options between start and destination. Call this AFTER start & destination are set, but BEFORE finalizing.", ["start": ["type": "string"], "destination": ["type": "string"], "stops": ["type": "array", "items": ["type": "string"]]], ["start", "destination"])
    
    private static let finalizeRideSchema = fn("finalize_ride_plan", "Call ONLY after all details are set and route is chosen.", ["route_style": ["type": "string", "enum": ["Fastest", "Scenic", "Off-route"], "description": "The user's chosen route style from the fetch_routes options."]], ["route_style"])

    private static let joinRideSchema = fn("join_ride", "Join a ride by 6-character code.", ["code": ["type": "string"]], ["code"])
    private static let sendFriendSchema = fn("send_friend_request", "Send a friend request.", ["username": ["type": "string"]], ["username"])
    private static let createCrewSchema = fn("create_crew", "Create a new crew.", ["name": ["type": "string"]], ["name"])
    private static let inviteToCrewSchema = fn("invite_to_crew", "Invite a user to a crew.", ["crew_name": ["type": "string"], "username": ["type": "string"]], ["crew_name", "username"])

    static func confirmationTitle(_ name: String, _ args: [String: Any]) -> String {
        switch name {
        case "join_ride": return "Join this ride?"
        case "send_friend_request": return "Send friend request?"
        case "create_crew": return "Create this crew?"
        case "invite_to_crew": return "Invite to crew?"
        case "finalize_ride_plan": return "Open ride review?"
        default: return "Confirm action"
        }
    }

    static func confirmationDetail(_ name: String, _ args: [String: Any], _ engine: ChatbotEngine) -> String {
        switch name {
        case "join_ride": return "Code: \(args["code"] as? String ?? "—")"
        case "send_friend_request": return "to @\(args["username"] as? String ?? "—")"
        case "create_crew": return "\"\(args["name"] as? String ?? "—")\""
        case "invite_to_crew": return "@\(args["username"] as? String ?? "—") → \"\(args["crew_name"] as? String ?? "—")\""
        case "finalize_ride_plan":
            let d = engine.rideDraft
            var lines: [String] = []
            if let dest = d.destination { lines.append("To: \(dest)") }
            if let s = d.startLocation { lines.append("From: \(s)") }
            if !d.checkpoints.isEmpty { lines.append("Stops: \(d.checkpoints.joined(separator: ", "))") }
            if let when = d.scheduledAt { lines.append("When: \(when.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))") }
            if let crew = d.crewName { lines.append("Crew: \(crew)") }
            if !d.friendUsernames.isEmpty { lines.append("Friends: \(d.friendUsernames.map { "@\($0)" }.joined(separator: ", "))") }
            if let style = args["route_style"] as? String { lines.append("Route: \(style)") }
            return lines.joined(separator: " · ")
        default: return ""
        }
    }

    static func statusLabel(_ name: String) -> String {
        switch name {
        case "search_places": return "Searching places…"
        case "list_my_friends": return "Checking friends…"
        case "suggest_checkpoints": return "Searching MapKit…"
        case "fetch_routes": return "Calculating routes…"
        case "finalize_ride_plan": return "Opening review…"
        default: return "Working…"
        }
    }

    @MainActor
    static func execute(name: String, args: [String: Any], app: AppState, engine: ChatbotEngine) async -> String {
        do {
            switch name {
            case "search_places":
                return await searchPlaces(query: args["query"] as? String, category: (args["category"] as? String).flatMap(PlaceCategory.init(rawValue:)))
            case "search_routes":
                return await searchRoutes(query: args["query"] as? String)
            case "list_my_rides":
                await app.refreshRides(force: true)
                return jsonEncode(app.rides.prefix(6).map { ["title": $0.title, "date": $0.displayDate] })
            case "list_my_crews":
                await app.loadCrews(force: true)
                return jsonEncode(app.crews.map { ["name": $0.name, "code": $0.code] })
            case "list_my_friends":
                await app.loadFriends(force: true)
                return jsonEncode(app.friends.map { ["name": $0.display_name, "handle": "@\($0.username)"] })
            case "find_user":
                let u = (args["username"] as? String ?? "").lowercased().replacingOccurrences(of: "@", with: "")
                if let p = try await SupabaseManager.shared.fetchProfile(username: u) { return jsonEncode(["user": p.display_name, "handle": "@\(p.username)"]) }
                return jsonEncode(["error": "No user found"])
                
            case "suggest_checkpoints":
                return await suggestCheckpoints(
                    start: args["start"] as? String ?? "",
                    destination: args["destination"] as? String ?? "",
                    category: args["category"] as? String ?? "cafe"
                )

            case "begin_ride_planning":
                let dest = (args["destination"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                engine.rideDraft = RidePlanDraft(destination: dest)
                return jsonEncode(["status": "started", "missing": engine.rideDraft.missingFields, "hint": nextHint(engine.rideDraft)])
                
            case "set_ride_companions":
                let crew = args["crew_name"] as? String
                let friends = args["friend_usernames"] as? [String] ?? []
                let solo = args["solo"] as? Bool ?? false
                if solo { engine.rideDraft.crewName = nil; engine.rideDraft.friendUsernames = [] }
                else { engine.rideDraft.crewName = crew; engine.rideDraft.friendUsernames = friends }
                return jsonEncode(["status": "ok", "missing": engine.rideDraft.missingFields, "hint": nextHint(engine.rideDraft)])
                
            case "set_ride_start":
                let loc = (args["location"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let useCurrent = args["use_current_location"] as? Bool ?? false
                engine.rideDraft.startLocation = useCurrent ? "Current Location" : loc
                return jsonEncode(["status": "ok", "missing": engine.rideDraft.missingFields, "hint": nextHint(engine.rideDraft)])
                
            case "set_ride_checkpoints":
                engine.rideDraft.checkpoints = args["checkpoints"] as? [String] ?? []
                return jsonEncode(["status": "ok", "missing": engine.rideDraft.missingFields, "hint": nextHint(engine.rideDraft)])
                
            case "set_ride_time":
                let iso = args["iso8601"] as? String ?? ""
                if let date = parseISO(iso), date > Date() { engine.rideDraft.scheduledAt = date; return jsonEncode(["status": "ok", "missing": engine.rideDraft.missingFields, "hint": nextHint(engine.rideDraft)]) }
                return jsonEncode(["error": "Date must be in the future and ISO8601 format."])
                
            case "fetch_routes":
                let start = args["start"] as? String ?? ""
                let dest = args["destination"] as? String ?? ""
                let stops = args["stops"] as? [String] ?? []
                
                let seed = PlanSeed(name: "Ride to \(dest)", start: start, startCoord: nil, destination: dest, destinationCoord: nil, stops: stops.map { .init(name: $0, coord: nil) })
                app.startPlan(seed)
                await app.findRoutes()
                
                if app.planner.state == .ready {
                    let opts = RouteStyle.allCases.filter { app.draft.routes[$0] != nil }.map { $0.rawValue }
                    return jsonEncode(["status": "success", "options": opts, "hint": "Ask the user which route they prefer."])
                } else {
                    return jsonEncode(["error": "Could not calculate routes. Ask for a more specific location."])
                }
                
            case "finalize_ride_plan":
                guard engine.rideDraft.isComplete else { return jsonEncode(["error": "Missing fields. Ask user."]) }
                let d = engine.rideDraft
                let styleStr = args["route_style"] as? String ?? "Fastest"
                var style = RouteStyle(rawValue: styleStr) ?? .fastest
                
                if let crewName = d.crewName, let crew = app.crews.first(where: { $0.name.lowercased() == crewName.lowercased() }) { app.selectedCrew = crew.id }
                app.selectedFriends = Set(d.friendUsernames.filter { u in app.friends.contains { $0.username.lowercased() == u.lowercased() } })

                // ✅ FIX: If fetch_routes wasn't called, calculate now. Otherwise preserve existing routes.
                if app.draft.routes.isEmpty {
                    let seed = PlanSeed(name: "Ride to \(d.destination ?? "")", start: d.startLocation ?? "", startCoord: nil, destination: d.destination ?? "", destinationCoord: nil, stops: d.checkpoints.map { .init(name: $0, coord: nil) })
                    app.startPlan(seed)
                    if let when = d.scheduledAt { app.draft.starts = when }
                    await app.findRoutes()
                } else {
                    if let when = d.scheduledAt { app.draft.starts = when }
                }
                
                guard app.draft.selected != nil else {
                    return jsonEncode(["error": "Could not calculate route to \(d.destination ?? ""). Ask the user for a more specific location."])
                }
                
                // ✅ FIX: Fallback if the chosen style doesn't exist
                if app.draft.routes[style] == nil {
                    style = RouteStyle.allCases.first(where: { app.draft.routes[$0] != nil }) ?? .fastest
                }
                
                app.draft.style = style
                app.push(.planReview)
                engine.rideDraft = RidePlanDraft()
                engine.saveState()
                return jsonEncode(["status": "opened_review"])

            case "join_ride": return jsonEncode(["error": "Use manual flow"])
            case "send_friend_request":
                guard let u = await resolveUserId(app) else { return jsonEncode(["error": "Not signed in"]) }
                try await SupabaseManager.shared.sendFriendRequest(senderId: u, receiverUsername: args["username"] as? String ?? "")
                return jsonEncode(["status": "sent"])
            case "create_crew":
                guard let u = await resolveUserId(app) else { return jsonEncode(["error": "Not signed in"]) }
                let name = args["name"] as? String ?? ""
                _ = try await SupabaseManager.shared.createCrew(name: name, code: CrewGroup.makeCode(name: name), creatorId: u, memberIds: [], avatarData: nil)
                return jsonEncode(["status": "created"])
            case "invite_to_crew":
                guard let u = await resolveUserId(app) else { return jsonEncode(["error": "Not signed in"]) }
                let crewName = args["crew_name"] as? String ?? ""
                if let crew = app.crews.first(where: { $0.name.lowercased() == crewName.lowercased() }) {
                    try await SupabaseManager.shared.inviteToCrew(crewId: crew.id, receiverUsername: args["username"] as? String ?? "", invitedBy: u)
                    return jsonEncode(["status": "invited"])
                }
                return jsonEncode(["error": "Crew not found"])

            default: return jsonEncode(["error": "Unknown tool"])
            }
        } catch { return jsonEncode(["error": error.localizedDescription]) }
    }

    private static func resolveUserId(_ app: AppState) async -> UUID? {
        if let id = app.backendUserId { return id }
        return await SupabaseManager.shared.getOrRestoreUserId()
    }

    private static func nextHint(_ draft: RidePlanDraft) -> String {
        if draft.destination == nil { return "Ask for destination." }
        if draft.startLocation == nil { return "Ask where it starts." }
        if draft.scheduledAt == nil { return "Ask when they want to leave." }
        return "Ask if they want checkpoints, then calculate routes."
    }

    private static func parseISO(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    @MainActor
    private static func searchPlaces(query: String?, category: PlaceCategory?) async -> String {
        let store = DiscoverStore.shared
        await store.loadIfNeeded()
        let results = query?.isEmpty == false ? store.search(query!).places : (category != nil ? store.placesNear([category!], minimum: 6).items : store.placesNear().items)
        return jsonEncode(["places": results.prefix(5).map { ["name": $0.name, "region": $0.region] }])
    }

    @MainActor
    private static func searchRoutes(query: String?) async -> String {
        let store = DiscoverStore.shared
        await store.loadIfNeeded()
        let results = query?.isEmpty == false ? store.search(query!).routes : Array(store.routes.prefix(5))
        return jsonEncode(["routes": results.prefix(5).map { ["title": $0.title, "from_to": $0.fromTo] }])
    }

    @MainActor
    private static func suggestCheckpoints(start: String, destination: String, category: String) async -> String {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = "\(category) near \(destination)"
        guard let res = try? await MKLocalSearch(request: req).start() else {
            return jsonEncode(["suggestions": [], "note": "No results found."])
        }
        let items = res.mapItems.prefix(3).compactMap { $0.name }
        return jsonEncode(["suggestions": Array(items), "note": "Suggest these to the user."])
    }

    private static func jsonEncode(_ v: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: v)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

// ChatTools.swift
import Foundation
import MapKit

enum ChatTools {
    static let allToolNames: [String] = [
        "search_places", "search_routes", "list_my_rides", "list_my_crews", "list_my_friends", "find_user",
        "suggest_checkpoints",
        "begin_ride_planning", "set_ride_companions", "set_ride_start", "set_ride_checkpoints",
        "set_ride_time", "fetch_routes", "finalize_ride_plan", "select_location",
        "join_ride", "join_crew",
        "send_friend_request", "create_crew", "invite_to_crew",
        "invite_to_ride", "post_to_crew_feed",
        "get_ride_details"
    ]

    static let writeTools: Set<String> = [
        "join_ride", "join_crew", "send_friend_request", "create_crew", "invite_to_crew",
        "invite_to_ride", "post_to_crew_feed", "finalize_ride_plan"
    ]

    static func requiresConfirmation(_ name: String) -> Bool { writeTools.contains(name) }
    static func isNavigating(_ name: String) -> Bool { name == "finalize_ride_plan" }

    static let schemas: [[String: Any]] = [
        searchPlacesSchema, searchRoutesSchema, listMyRidesSchema, listMyCrewsSchema, listFriendsSchema,
        findUserSchema, suggestCheckpointsSchema,
        beginRideSchema, setCompanionsSchema, setStartSchema,
        setCheckpointsSchema, setTimeSchema, fetchRoutesSchema, finalizeRideSchema,
        selectLocationSchema,
        joinRideSchema, joinCrewSchema,
        sendFriendSchema, createCrewSchema, inviteToCrewSchema,
        inviteToRideSchema, postToCrewFeedSchema,
        getRideDetailsSchema
    ]

    private static func fn(_ name: String, _ desc: String, _ props: [String: Any] = [:], _ required: [String] = []) -> [String: Any] {
        ["type": "function", "function": [
            "name": name, "description": desc,
            "parameters": ["type": "object", "properties": props, "required": required]
        ]]
    }

    // MARK: - Schemas

    private static let searchPlacesSchema = fn("search_places", "Find places to ride to.",
        ["query": ["type": "string"],
         "category": ["type": "string", "enum": ["lake","waterfall","viewpoint","beach","forest","cafe","historical","hillRoad","hillStation","waterfront"]]])
    private static let searchRoutesSchema = fn("search_routes", "Find curated routes.",
        ["query": ["type": "string"]])
    private static let listMyRidesSchema = fn("list_my_rides", "List the current user's accepted upcoming rides with details.")
    private static let listMyCrewsSchema = fn("list_my_crews", "List crews the current user belongs to.")
    private static let listFriendsSchema = fn("list_my_friends", "List the user's friends (name and handle).")
    private static let findUserSchema = fn("find_user", "Look up a Convoy user by @handle.",
        ["username": ["type": "string"]], ["username"])

    private static let suggestCheckpointsSchema = fn("suggest_checkpoints", "Suggest real cafes or scenic stops along the route.",
        ["start": ["type": "string"],
         "destination": ["type": "string"],
         "category": ["type": "string", "enum": ["cafe", "viewpoint", "restaurant", "waterfall"]]],
        ["start", "destination", "category"])

    private static let beginRideSchema = fn("begin_ride_planning", "Start a new ride-planning session. Searches MapKit for the destination; may return needs_choice with options.",
        ["destination": ["type": "string"]], ["destination"])
    private static let setCompanionsSchema = fn("set_ride_companions", "Record who's riding.",
        ["crew_name": ["type": "string"],
         "friend_usernames": ["type": "array", "items": ["type": "string"]],
         "solo": ["type": "boolean"]])
    private static let setStartSchema = fn("set_ride_start", "Record the starting point. Searches MapKit if not using current location.",
        ["location": ["type": "string"],
         "use_current_location": ["type": "boolean"]], ["location"])
    private static let setCheckpointsSchema = fn("set_ride_checkpoints", "Record chosen intermediate stops.",
        ["checkpoints": ["type": "array", "items": ["type": "string"]]], ["checkpoints"])
    private static let setTimeSchema = fn("set_ride_time", "Record start time. Must be ISO8601.",
        ["iso8601": ["type": "string"]], ["iso8601"])

    private static let fetchRoutesSchema = fn("fetch_routes", "Calculate route options between start and destination. Call this AFTER start & destination are set, but BEFORE finalizing.",
        ["start": ["type": "string"],
         "destination": ["type": "string"],
         "stops": ["type": "array", "items": ["type": "string"]]],
        ["start", "destination"])

    private static let finalizeRideSchema = fn("finalize_ride_plan", "Call ONLY after all details are set and route is chosen.",
        ["route_style": ["type": "string", "enum": ["Fastest", "Scenic", "Off-route"],
                         "description": "The user's chosen route style from the fetch_routes options."]],
        ["route_style"])

    private static let selectLocationSchema = fn("select_location", "Pick a location from the options returned by begin_ride_planning or set_ride_start.",
        ["kind": ["type": "string", "enum": ["destination", "start"]],
         "index": ["type": "integer", "description": "1-based index from the options list."]],
        ["kind", "index"])

    private static let joinRideSchema = fn("join_ride", "Join a ride by 6-character code.",
        ["code": ["type": "string"]], ["code"])
    private static let joinCrewSchema = fn("join_crew", "Join an existing crew by its 6-character code.",
        ["code": ["type": "string"]], ["code"])
    private static let sendFriendSchema = fn("send_friend_request", "Send a friend request.",
        ["username": ["type": "string"]], ["username"])
    private static let createCrewSchema = fn("create_crew", "Create a new crew.",
        ["name": ["type": "string"]], ["name"])
    private static let inviteToCrewSchema = fn("invite_to_crew", "Invite a user to a crew you admin.",
        ["crew_name": ["type": "string"], "username": ["type": "string"]],
        ["crew_name", "username"])

    private static let inviteToRideSchema = fn("invite_to_ride", "Invite a user to a ride you organise.",
        ["code": ["type": "string", "description": "The ride's 6-character code."],
         "username": ["type": "string", "description": "The rider's @handle (without @)."]],
        ["code", "username"])

    private static let postToCrewFeedSchema = fn("post_to_crew_feed", "Post a ride you organise to the Crew feed so other riders can request to join.",
        ["code": ["type": "string", "description": "The ride's 6-character code."],
         "caption": ["type": "string", "description": "Optional message for the post."],
         "max_riders": ["type": "integer", "description": "Maximum riders allowed. Default 6."]],
        ["code"])

    private static let getRideDetailsSchema = fn("get_ride_details", "Get detailed information about a specific ride by code, or the next upcoming ride if no code is given.",
        ["code": ["type": "string", "description": "Optional 6-character ride code. Omit for the user's next ride."]])

    // MARK: - Confirmation copy

    static func confirmationTitle(_ name: String, _ args: [String: Any]) -> String {
        switch name {
        case "join_ride": return "Join this ride?"
        case "join_crew": return "Join this crew?"
        case "send_friend_request": return "Send friend request?"
        case "create_crew": return "Create this crew?"
        case "invite_to_crew": return "Invite to crew?"
        case "invite_to_ride": return "Invite to ride?"
        case "post_to_crew_feed": return "Post to Crew feed?"
        case "finalize_ride_plan": return "Open ride review?"
        default: return "Confirm action"
        }
    }

    static func confirmationDetail(_ name: String, _ args: [String: Any], _ engine: ChatbotEngine) -> String {
        switch name {
        case "join_ride": return "Code: \(args["code"] as? String ?? "—")"
        case "join_crew": return "Code: \(args["code"] as? String ?? "—")"
        case "send_friend_request": return "to @\(args["username"] as? String ?? "—")"
        case "create_crew": return "\"\(args["name"] as? String ?? "—")\""
        case "invite_to_crew": return "@\(args["username"] as? String ?? "—") → \"\(args["crew_name"] as? String ?? "—")\""
        case "invite_to_ride": return "@\(args["username"] as? String ?? "—") → ride \(args["code"] as? String ?? "—")"
        case "post_to_crew_feed": return "Ride \(args["code"] as? String ?? "—") · up to \(intArg(args["max_riders"]) ?? 6) riders"
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
        case "begin_ride_planning", "set_ride_start": return "Looking up the place…"
        case "finalize_ride_plan": return "Opening review…"
        default: return "Working…"
        }
    }

    // MARK: - Main dispatcher

    @MainActor
    static func execute(name: String, args: [String: Any], app: AppState, engine: ChatbotEngine) async -> String {
        do {
            switch name {
            case "search_places":
                return await searchPlaces(query: args["query"] as? String,
                                          category: (args["category"] as? String).flatMap(PlaceCategory.init(rawValue:)))
            case "search_routes":
                return await searchRoutes(query: args["query"] as? String)
            case "list_my_rides":
                await app.refreshRides(force: true)
                return jsonEncode(app.rides.prefix(8).map { rideDetails($0) })
            case "list_my_crews":
                await app.loadCrews(force: true)
                return jsonEncode(app.crews.map { [
                    "name": $0.name, "code": $0.code,
                    "members": $0.members.count
                ] })
            case "list_my_friends":
                await app.loadFriends(force: true)
                return jsonEncode(app.friends.map { ["name": $0.display_name, "handle": "@\($0.username)"] })
            case "find_user":
                let u = SupabaseManager.normalizeHandle(args["username"] as? String ?? "")
                if let p = try await SupabaseManager.shared.fetchProfile(username: u) {
                    return jsonEncode(["user": p.display_name, "handle": "@\(p.username)"])
                }
                return jsonEncode(["error": "No user found for @\(u)"])

            case "suggest_checkpoints":
                return await suggestCheckpoints(
                    start: args["start"] as? String ?? "",
                    destination: args["destination"] as? String ?? "",
                    category: args["category"] as? String ?? "cafe")

            // MARK: Ride planning with MapKit location resolution

            case "begin_ride_planning":
                let rawDest = (args["destination"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                guard !rawDest.isEmpty else { return jsonEncode(["error": "Missing destination"]) }
                return await beginRidePlanning(rawDest, engine: engine)

            case "set_ride_start":
                return await setRideStart(args: args, engine: engine)

            case "select_location":
                return selectLocation(args: args, engine: engine)

            case "set_ride_companions":
                let crew = args["crew_name"] as? String
                let friends = args["friend_usernames"] as? [String] ?? []
                let solo = args["solo"] as? Bool ?? false
                if solo { engine.rideDraft.crewName = nil; engine.rideDraft.friendUsernames = [] }
                else { engine.rideDraft.crewName = crew; engine.rideDraft.friendUsernames = friends }
                return jsonEncode(["status": "ok", "missing": engine.rideDraft.missingFields, "hint": nextHint(engine.rideDraft)])

            case "set_ride_checkpoints":
                engine.rideDraft.checkpoints = args["checkpoints"] as? [String] ?? []
                return jsonEncode(["status": "ok", "missing": engine.rideDraft.missingFields, "hint": nextHint(engine.rideDraft)])

            case "set_ride_time":
                let iso = args["iso8601"] as? String ?? ""
                if let date = parseISO(iso), date > Date() {
                    engine.rideDraft.scheduledAt = date
                    return jsonEncode(["status": "ok", "missing": engine.rideDraft.missingFields, "hint": nextHint(engine.rideDraft)])
                }
                return jsonEncode(["error": "Date must be in the future and ISO8601 format."])

            case "fetch_routes":
                let start = args["start"] as? String ?? engine.rideDraft.startLocation ?? ""
                let dest = args["destination"] as? String ?? engine.rideDraft.destination ?? ""
                let stops = args["stops"] as? [String] ?? engine.rideDraft.checkpoints
                let seed = PlanSeed(
                    name: "Ride to \(dest)",
                    start: start, startCoord: engine.rideDraft.startCoord,
                    destination: dest, destinationCoord: engine.rideDraft.destinationCoord,
                    stops: stops.map { .init(name: $0, coord: nil) })
                app.startPlan(seed)
                if let when = engine.rideDraft.scheduledAt { app.draft.starts = when }
                if let crewName = engine.rideDraft.crewName,
                   let crew = app.crews.first(where: { $0.name.lowercased() == crewName.lowercased() }) {
                    app.selectedCrew = crew.id
                }
                app.selectedFriends = Set(engine.rideDraft.friendUsernames.filter { u in
                    app.friends.contains { $0.username.lowercased() == u.lowercased() }
                })
                await app.findRoutes()

                if app.planner.state == .ready {
                    let opts = RouteStyle.allCases.filter { app.draft.routes[$0] != nil }.map { $0.rawValue }
                    return jsonEncode(["status": "success", "options": opts,
                                       "hint": "Ask the user which route they prefer."])
                }
                return jsonEncode(["error": "Could not calculate routes. Ask for a more specific location."])

            case "finalize_ride_plan":
                return await finalizeRidePlan(args: args, app: app, engine: engine)

            // MARK: Social

            case "join_ride":
                let code = (args["code"] as? String ?? "").uppercased().trimmingCharacters(in: .whitespaces)
                guard !code.isEmpty else { return jsonEncode(["error": "Missing ride code"]) }
                switch await app.joinRideByCode(code) {
                case .joined(let id):
                    await app.refreshRides(force: true)
                    return jsonEncode(["status": "joined", "ride_id": id.uuidString])
                case .requestPending(let id):
                    return jsonEncode(["status": "request_pending", "ride_id": id.uuidString,
                                       "hint": "Request sent. Tell the user the admin must approve."])
                case .failed:
                    return jsonEncode(["error": "No ride found with code \(code)."])
                }

            case "join_crew":
                let code = (args["code"] as? String ?? "").uppercased().trimmingCharacters(in: .whitespaces)
                guard !code.isEmpty else { return jsonEncode(["error": "Missing crew code"]) }
                let result = try await SupabaseManager.shared.joinCrewByCode(code)
                await app.loadCrews(force: true)
                await app.refreshNotifications(force: true)
                return jsonEncode(["status": result.status, "crew_name": result.name,
                                   "crew_id": result.crew_id.uuidString])

            case "send_friend_request":
                guard let u = await resolveUserId(app) else { return jsonEncode(["error": "Not signed in"]) }
                try await SupabaseManager.shared.sendFriendRequest(
                    senderId: u, receiverUsername: args["username"] as? String ?? "")
                await app.loadFriends(force: true)
                return jsonEncode(["status": "sent"])

            case "create_crew":
                guard let u = await resolveUserId(app) else { return jsonEncode(["error": "Not signed in"]) }
                let name = args["name"] as? String ?? ""
                guard !name.isEmpty else { return jsonEncode(["error": "Missing crew name"]) }
                let crewId = try await SupabaseManager.shared.createCrew(
                    name: name, code: CrewGroup.makeCode(name: name),
                    creatorId: u, memberIds: [], avatarData: nil,
                    displayName: app.displayName, handle: app.handle)
                await app.loadCrews(force: true)
                return jsonEncode(["status": "created", "crew_id": crewId.uuidString, "name": name])

            case "invite_to_crew":
                guard let u = await resolveUserId(app) else { return jsonEncode(["error": "Not signed in"]) }
                let crewName = args["crew_name"] as? String ?? ""
                await app.loadCrews(force: true)
                guard let crew = app.crews.first(where: { $0.name.lowercased() == crewName.lowercased() }) else {
                    return jsonEncode(["error": "Crew '\(crewName)' not found."])
                }
                try await SupabaseManager.shared.inviteToCrew(
                    crewId: crew.id, receiverUsername: args["username"] as? String ?? "", invitedBy: u)
                return jsonEncode(["status": "invited"])

            case "invite_to_ride":
                return await inviteToRide(args: args, app: app)

            case "post_to_crew_feed":
                return await postToCrewFeed(args: args, app: app)

            case "get_ride_details":
                let code = (args["code"] as? String ?? "").uppercased().trimmingCharacters(in: .whitespaces)
                if !code.isEmpty {
                    if let (ride, _) = await app.findRide(byCode: code) {
                        return jsonEncode(rideDetails(ride, full: true))
                    }
                    return jsonEncode(["error": "No ride found with code \(code)."])
                }
                if let ride = app.activeRide ?? app.upcomingRide {
                    return jsonEncode(rideDetails(ride, full: true))
                }
                return jsonEncode(["error": "No upcoming ride."])

            default: return jsonEncode(["error": "Unknown tool"])
            }
        } catch {
            return jsonEncode(["error": error.localizedDescription])
        }
    }

    // MARK: - Ride-planning helpers (MapKit search → unique / choose)

    @MainActor
    private static func beginRidePlanning(_ rawDest: String, engine: ChatbotEngine) async -> String {
        let matches = await searchForDestination(rawDest)
        if matches.isEmpty {
            engine.rideDraft = RidePlanDraft()
            return jsonEncode([
                "status": "no_results",
                "destination": rawDest,
                "hint": "Nothing matched. Ask the user for a more specific place name (include city and state)."
            ])
        }
        if matches.count == 1 {
            let m = matches[0]
            engine.rideDraft = RidePlanDraft()
            engine.rideDraft.destination = m.name.isEmpty ? rawDest : m.name
            engine.rideDraft.destinationCoord = m.coord
            return jsonEncode([
                "status": "started",
                "resolved": ["name": m.name, "address": m.address, "lat": m.lat, "lon": m.lon],
                "missing": engine.rideDraft.missingFields,
                "hint": nextHint(engine.rideDraft)
            ])
        }
        // Multiple matches — let the user pick
        engine.rideDraft = RidePlanDraft()
        engine.rideDraft.destination = rawDest
        engine.rideDraft.pendingDestinationChoices = matches
        return jsonEncode([
            "status": "needs_choice",
            "kind": "destination",
            "options": matches.enumerated().map { (i, m) in
                ["index": i + 1, "name": m.name, "address": m.address]
            },
            "hint": "Ask the user which one by number (1-\(matches.count)). When they answer, call select_location(kind: \"destination\", index: N)."
        ])
    }

    @MainActor
    private static func setRideStart(args: [String: Any], engine: ChatbotEngine) async -> String {
        let useCurrent = args["use_current_location"] as? Bool ?? false

        if useCurrent {
            if let loc = LocationService.shared.currentLocation {
                let geocoded = await LocationService.shared.reverseGeocode(coordinate: loc.coordinate)
                let clean = geocoded.isEmpty ? "Current Location" : primaryPlaceName(geocoded)
                engine.rideDraft.startLocation = clean
                engine.rideDraft.startCoord = Coord(loc.coordinate)
                engine.rideDraft.startIsCurrentLocation = true
                engine.rideDraft.pendingStartChoices = []
                return jsonEncode([
                    "status": "ok",
                    "resolved": ["name": clean, "lat": loc.coordinate.latitude, "lon": loc.coordinate.longitude],
                    "missing": engine.rideDraft.missingFields,
                    "hint": nextHint(engine.rideDraft)
                ])
            }
            return jsonEncode(["error": "Current location unavailable. Ask the user to type a place name instead."])
        }

        let rawLoc = (args["location"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !rawLoc.isEmpty else { return jsonEncode(["error": "Missing location"]) }

        let matches = await searchForStart(rawLoc)
        if matches.isEmpty {
            return jsonEncode([
                "status": "no_results",
                "hint": "Nothing matched. Ask the user for a more specific place name."
            ])
        }
        if matches.count == 1 {
            let m = matches[0]
            engine.rideDraft.startLocation = m.name.isEmpty ? rawLoc : m.name
            engine.rideDraft.startCoord = m.coord
            engine.rideDraft.startIsCurrentLocation = false
            engine.rideDraft.pendingStartChoices = []
            return jsonEncode([
                "status": "ok",
                "resolved": ["name": m.name, "address": m.address, "lat": m.lat, "lon": m.lon],
                "missing": engine.rideDraft.missingFields,
                "hint": nextHint(engine.rideDraft)
            ])
        }
        engine.rideDraft.startLocation = rawLoc
        engine.rideDraft.pendingStartChoices = matches
        return jsonEncode([
            "status": "needs_choice",
            "kind": "start",
            "options": matches.enumerated().map { (i, m) in
                ["index": i + 1, "name": m.name, "address": m.address]
            },
            "hint": "Ask the user which one by number (1-\(matches.count)). When they answer, call select_location(kind: \"start\", index: N)."
        ])
    }

    private static func selectLocation(args: [String: Any], engine: ChatbotEngine) -> String {
        let kind = args["kind"] as? String ?? ""
        let index = intArg(args["index"]) ?? 0
        switch kind {
        case "destination":
            let choices = engine.rideDraft.pendingDestinationChoices
            guard index >= 1 && index <= choices.count else {
                return jsonEncode(["error": "Invalid index. Valid range is 1-\(choices.count)."])
            }
            let picked = choices[index - 1]
            engine.rideDraft.destination = picked.name.isEmpty ? picked.address : picked.name
            engine.rideDraft.destinationCoord = picked.coord
            engine.rideDraft.pendingDestinationChoices = []
            return jsonEncode(["status": "ok", "missing": engine.rideDraft.missingFields,
                               "hint": nextHint(engine.rideDraft)])
        case "start":
            let choices = engine.rideDraft.pendingStartChoices
            guard index >= 1 && index <= choices.count else {
                return jsonEncode(["error": "Invalid index. Valid range is 1-\(choices.count)."])
            }
            let picked = choices[index - 1]
            engine.rideDraft.startLocation = picked.name.isEmpty ? picked.address : picked.name
            engine.rideDraft.startCoord = picked.coord
            engine.rideDraft.startIsCurrentLocation = false
            engine.rideDraft.pendingStartChoices = []
            return jsonEncode(["status": "ok", "missing": engine.rideDraft.missingFields,
                               "hint": nextHint(engine.rideDraft)])
        default:
            return jsonEncode(["error": "Invalid kind — must be 'destination' or 'start'."])
        }
    }

    @MainActor
    private static func finalizeRidePlan(args: [String: Any], app: AppState, engine: ChatbotEngine) async -> String {
        guard engine.rideDraft.isComplete else {
            return jsonEncode(["error": "Missing fields: \(engine.rideDraft.missingFields.joined(separator: ", ")). Ask the user."])
        }
        let d = engine.rideDraft
        let styleStr = args["route_style"] as? String ?? "Fastest"
        var style = RouteStyle(rawValue: styleStr) ?? .fastest

        if let crewName = d.crewName,
           let crew = app.crews.first(where: { $0.name.lowercased() == crewName.lowercased() }) {
            app.selectedCrew = crew.id
        }
        app.selectedFriends = Set(d.friendUsernames.filter { u in
            app.friends.contains { $0.username.lowercased() == u.lowercased() }
        })

        // Preserve pre-computed routes from fetch_routes; otherwise plan now.
        if app.draft.routes.isEmpty {
            let seed = PlanSeed(
                name: "Ride to \(d.destination ?? "")",
                start: d.startLocation ?? "",
                startCoord: d.startCoord,
                destination: d.destination ?? "",
                destinationCoord: d.destinationCoord,
                stops: d.checkpoints.map { .init(name: $0, coord: nil) })
            app.startPlan(seed)
            if let when = d.scheduledAt { app.draft.starts = when }
            await app.findRoutes()
        } else if let when = d.scheduledAt {
            app.draft.starts = when
        }

        guard app.draft.selected != nil else {
            return jsonEncode(["error": "Could not calculate route to \(d.destination ?? ""). Ask the user for a more specific location."])
        }

        if app.draft.routes[style] == nil {
            style = RouteStyle.allCases.first(where: { app.draft.routes[$0] != nil }) ?? .fastest
        }
        app.draft.style = style

        // Push BOTH so "Edit route" on planReview has somewhere to land that isn't Home.
        app.push(.planDetails)
        app.push(.planReview)

        engine.rideDraft = RidePlanDraft()
        engine.saveState()
        return jsonEncode(["status": "opened_review"])
    }

    // MARK: - Social helpers

    @MainActor
    private static func inviteToRide(args: [String: Any], app: AppState) async -> String {
        guard let me = await resolveUserId(app) else { return jsonEncode(["error": "Not signed in"]) }
        let code = (args["code"] as? String ?? "").uppercased().trimmingCharacters(in: .whitespaces)
        let username = SupabaseManager.normalizeHandle(args["username"] as? String ?? "")
        guard !code.isEmpty, !username.isEmpty else {
            return jsonEncode(["error": "Missing code or username"])
        }
        guard let (ride, _) = await app.findRide(byCode: code) else {
            return jsonEncode(["error": "No ride found with code \(code)."])
        }
        guard ride.organiserId == me || ride.organiser == "you" else {
            return jsonEncode(["error": "Only the ride admin can invite riders."])
        }

        // Lookup is a throwing network call — wrap it in its own do-catch so this function
        // (which is declared non-throwing) can't propagate an unhandled error.
        let profile: ProfileRow
        do {
            guard let p = try await SupabaseManager.shared.fetchProfile(username: username) else {
                return jsonEncode(["error": "User @\(username) not found."])
            }
            profile = p
        } catch {
            return jsonEncode(["error": "Couldn't look up @\(username): \(error.localizedDescription)"])
        }

        do {
            try await SupabaseManager.shared.inviteRiderToRide(rideId: ride.id, userId: profile.id)
            await app.refreshRides(force: true)
            return jsonEncode(["status": "invited", "user": profile.display_name, "ride": ride.title])
        } catch {
            return jsonEncode(["error": "Couldn't invite: \(error.localizedDescription)"])
        }
    }

    @MainActor
    private static func postToCrewFeed(args: [String: Any], app: AppState) async -> String {
        let code = (args["code"] as? String ?? "").uppercased().trimmingCharacters(in: .whitespaces)
        let caption = (args["caption"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let maxRiders = max(2, intArg(args["max_riders"]) ?? 6)
        guard !code.isEmpty else { return jsonEncode(["error": "Missing ride code"]) }
        guard let (ride, _) = await app.findRide(byCode: code) else {
            return jsonEncode(["error": "No ride found with code \(code)."])
        }
        do {
            try await app.social.postOpenRide(ride: ride, caption: caption, maxRiders: maxRiders)
            return jsonEncode(["status": "posted", "ride": ride.title, "ride_code": ride.code])
        } catch {
            return jsonEncode(["error": "Couldn't post: \(error.localizedDescription)"])
        }
    }

    // MARK: - MapKit search helpers

    @MainActor
    private static func searchForDestination(_ query: String) async -> [LocationOption] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = clean
        req.resultTypes = [.address, .pointOfInterest]
        guard let res = try? await MKLocalSearch(request: req).start() else { return [] }
        return res.mapItems.prefix(5).compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            var parts: [String] = []
            if let loc = item.placemark.locality, !loc.isEmpty { parts.append(loc) }
            if let region = item.placemark.administrativeArea, !region.isEmpty { parts.append(region) }
            if let country = item.placemark.country, !country.isEmpty { parts.append(country) }
            let address = parts.joined(separator: ", ")
            let coord = item.placemark.coordinate
            return LocationOption(name: name, address: address, lat: coord.latitude, lon: coord.longitude)
        }
    }

    @MainActor
    private static func searchForStart(_ query: String) async -> [LocationOption] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = clean
        req.resultTypes = [.address, .pointOfInterest]
        if let loc = LocationService.shared.currentLocation {
            req.region = MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0))
        }
        guard let res = try? await MKLocalSearch(request: req).start() else { return [] }
        return res.mapItems.prefix(5).compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            var parts: [String] = []
            if let t = item.placemark.thoroughfare, !t.isEmpty { parts.append(t) }
            if let sub = item.placemark.subLocality, !sub.isEmpty { parts.append(sub) }
            if let loc = item.placemark.locality, !loc.isEmpty { parts.append(loc) }
            let address = parts.joined(separator: ", ")
            let coord = item.placemark.coordinate
            return LocationOption(name: name, address: address, lat: coord.latitude, lon: coord.longitude)
        }
    }

    // MARK: - Misc helpers

    /// Whole numbers from the model can arrive as 2, 2.0 or "2".
    private static func intArg(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double, d.rounded() == d { return Int(d) }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func resolveUserId(_ app: AppState) async -> UUID? {
        if let id = app.backendUserId { return id }
        return await SupabaseManager.shared.getOrRestoreUserId()
    }

    private static func nextHint(_ draft: RidePlanDraft) -> String {
        if draft.destination == nil { return "Ask for destination." }
        if !draft.pendingDestinationChoices.isEmpty { return "Destination choice pending — ask user which one by number." }
        if draft.startLocation == nil { return "Ask where it starts." }
        if !draft.pendingStartChoices.isEmpty { return "Start choice pending — ask user which one by number." }
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

    private static func rideDetails(_ ride: Ride, full: Bool = false) -> [String: Any] {
        var d: [String: Any] = [
            "title": ride.title,
            "code": ride.code,
            "departs": ride.departs.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()),
            "distance": ride.distance,
            "duration": ride.duration,
            "riders_going": ride.acceptedRiders.count,
            "organiser_is_me": ride.organiser == "you" || ride.rsvp == .organizing
        ]
        if full {
            d["from"] = ride.plan.from
            d["to"] = ride.plan.to
            d["stops"] = ride.plan.stops
            d["riders_invited"] = ride.invitedRiders.count
        } else {
            d["to"] = ride.plan.to.components(separatedBy: ",").first ?? ride.plan.to
        }
        return d
    }

    @MainActor
    private static func searchPlaces(query: String?, category: PlaceCategory?) async -> String {
        let store = DiscoverStore.shared
        await store.loadIfNeeded()
        let results = query?.isEmpty == false
            ? store.search(query!).places
            : (category != nil ? store.placesNear([category!], minimum: 6).items : store.placesNear().items)
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
        (try? JSONSerialization.data(withJSONObject: v))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

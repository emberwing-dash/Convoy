// ChatbotV2Tests.swift — chatbot hardening: destination confirmation, tool selection, history
// compaction, retry policy, V2 error parsing, Edit-route navigation, estimate labels, per-account chat.
import Testing
import Foundation
@testable import Convoy

private func place(_ name: String, geo: Bool = true, lat: Double = 10, lon: Double = 77) -> LocationOption {
    LocationOption(name: name, address: "", lat: lat, lon: lon, isGeographic: geo)
}

@Suite("Chatbot · destination confirmation")
struct DestinationTests {
    @Test func singleGeographicPlaceIsPicked() {
        let d = DestinationResolver.decide(query: "Munnar", options: [place("Munnar"), place("Munnar Tea Hotel", geo: false)], purpose: .destination)
        #expect(d == .unique(place("Munnar")))
    }

    @Test func exactNameWinsAmongSeveralPlaces() {
        let d = DestinationResolver.decide(query: "ooty", options: [place("Ooty"), place("Ooty Lake"), place("Ooty Botanical Garden")], purpose: .destination)
        #expect(d == .unique(place("Ooty")))
    }

    @Test func twoPlacesWithTheSameNameAskTheRider() {
        let a = place("Aurangabad", lat: 19.9, lon: 75.3), b = place("Aurangabad", lat: 24.7, lon: 84.4)
        let d = DestinationResolver.decide(query: "Aurangabad", options: [a, b], purpose: .destination)
        #expect(d == .choose([a, b]))
    }

    @Test func vagueQueryWithManyPlacesAsks() {
        let opts = [place("Kodagu"), place("Madikeri"), place("Coorg Wildlife Sanctuary")]
        if case .choose(let o) = DestinationResolver.decide(query: "Coorg hills", options: opts, purpose: .destination) {
            #expect(o.count == 3)
        } else { Issue.record("expected a choice") }
    }

    @Test func businessesAreNeverPickedSilentlyForDestinations() {
        let d = DestinationResolver.decide(query: "Mahabalipuram", options: [place("Mahabalipuram Resort", geo: false)], purpose: .destination)
        #expect(d == .choose([place("Mahabalipuram Resort", geo: false)]))
    }

    @Test func noResults() {
        #expect(DestinationResolver.decide(query: "zzz", options: [], purpose: .destination) == .none)
    }

    @Test func singleLandmarkIsFineForStart() {
        let mall = place("Phoenix Marketcity", geo: false)
        #expect(DestinationResolver.decide(query: "Phoenix Marketcity", options: [mall], purpose: .start) == .unique(mall))
    }

    @Test func normalizeIgnoresCaseCommasAndThe() {
        #expect(DestinationResolver.normalize("The Nilgiris, Tamil Nadu") == "nilgiris")
    }

    @Test func typedNameAloneIsNotAConfirmedDestination() {
        var d = RidePlanDraft()
        d.destinationQuery = "Munnar"
        d.pendingDestinationChoices = [place("Munnar")]
        #expect(d.missingFields.contains("destination"))
        #expect(!d.isComplete)
        #expect(d.isActive)
        d.destination = "Munnar"                 // name without coordinates still isn't confirmed
        #expect(!d.hasConfirmedDestination)
        d.destinationCoord = Coord(lat: 10.08, lon: 77.06)
        d.pendingDestinationChoices = []
        #expect(d.hasConfirmedDestination)
    }

    @Test func completeOnlyWithConfirmedPlacesAndTime() {
        var d = RidePlanDraft()
        d.destination = "Ooty"; d.destinationCoord = Coord(lat: 11.41, lon: 76.69)
        d.startLocation = "Bengaluru"; d.startCoord = Coord(lat: 12.97, lon: 77.59)
        #expect(!d.isComplete)
        d.scheduledAt = .now.addingTimeInterval(3600)
        #expect(d.isComplete)
        d.pendingStartChoices = [place("Bengaluru")]
        #expect(!d.isComplete)
    }

    @Test func draftsSavedByOlderBuildsStillLoad() throws {
        let old = #"{"destination":"Munnar","startLocation":"Kochi","checkpoints":[],"friendUsernames":[],"startIsCurrentLocation":false}"#
        let d = try JSONDecoder().decode(RidePlanDraft.self, from: Data(old.utf8))
        #expect(d.destination == "Munnar")
        #expect(d.pendingDestinationChoices.isEmpty)
        #expect(!d.hasConfirmedDestination)      // no coordinates → must be confirmed again
    }
}

@Suite("Chatbot · tool selection")
struct ToolSelectionTests {
    @Test func generalQuestionGetsASmallSet() {
        let t = ChatToolSelector.select(lastUserText: "hi there", draft: RidePlanDraft())
        #expect(t == ChatToolSelector.general)
        #expect(!t.contains("create_crew"))
    }

    @Test func crewRequestGetsCrewTools() {
        let t = ChatToolSelector.select(lastUserText: "Create a crew called Night Owls", draft: RidePlanDraft())
        #expect(t.isSuperset(of: ["create_crew", "invite_to_crew", "join_crew"]))
        #expect(!t.contains("finalize_ride_plan"))
    }

    @Test func activePlanKeepsPlanningToolsForANumberReply() {
        var d = RidePlanDraft(); d.pendingDestinationChoices = [place("Munnar")]
        let t = ChatToolSelector.select(lastUserText: "2", draft: d)
        #expect(t.isSuperset(of: ["select_location", "set_ride_start", "set_ride_time", "fetch_routes", "finalize_ride_plan"]))
    }

    @Test func planRequestStartsPlanning() {
        let t = ChatToolSelector.select(lastUserText: "Plan a ride to Munnar this weekend", draft: RidePlanDraft())
        #expect(t.contains("begin_ride_planning"))
    }

    @Test func everySelectedToolExistsAndEveryToolIsReachable() {
        let all = Set(ChatTools.allToolNames)
        let groups = [ChatToolSelector.planning, ChatToolSelector.startPlanning, ChatToolSelector.discovery,
                      ChatToolSelector.crews, ChatToolSelector.social, ChatToolSelector.rides, ChatToolSelector.general]
        let union = groups.reduce(Set<String>()) { $0.union($1) }
        #expect(union.isSubset(of: all))
        #expect(all.isSubset(of: union), "unreachable: \(all.subtracting(union))")
        #expect(ChatTools.schemas(named: all).count == all.count)
        #expect(ChatTools.allToolNames.count == 24)   // 23 existing + cancel_ride_planning
    }

    @Test func selectedSchemasAreMuchSmallerThanAll() {
        let few = ChatHistoryCompactor.estimateTokens(ChatTools.schemas(named: ChatToolSelector.general))
        let every = ChatHistoryCompactor.estimateTokens(ChatTools.schemas)
        #expect(few * 3 < every)
    }
}

@Suite("Chatbot · history & tokens")
struct HistoryTests {
    func turn(_ i: Int, toolResult: String = String(repeating: "x", count: 2_000)) -> [[String: Any]] {
        [["role": "user", "content": "question \(i)"],
         ["role": "assistant", "content": NSNull(), "tool_calls": [["id": "c\(i)", "type": "function",
                                                                   "function": ["name": "list_my_rides", "arguments": "{}"]]]],
         ["role": "tool", "tool_call_id": "c\(i)", "content": toolResult],
         ["role": "assistant", "content": "answer \(i)"]]
    }

    @Test func keepsLatestTurnAndSummarisesOlderOnes() {
        let msgs = [["role": "system", "content": "sys"]] + (1...12).flatMap { turn($0) }
        let out = ChatHistoryCompactor.compact(msgs, budget: 1_500)
        #expect((out.first?["content"] as? String) == "sys")
        #expect((out[1]["content"] as? String)?.hasPrefix("Earlier in this chat") == true)
        #expect(out.contains { ($0["content"] as? String) == "question 12" })
        #expect(ChatHistoryCompactor.estimateTokens(out) <= 1_500 + 600)
        // Every kept tool result still follows its call.
        for (i, m) in out.enumerated() where (m["role"] as? String) == "tool" {
            #expect((out[i - 1]["tool_calls"] as? [[String: Any]])?.first?["id"] as? String == m["tool_call_id"] as? String)
        }
    }

    @Test func olderToolResultsAreShortenedNewestKept() {
        let msgs = [["role": "system", "content": "sys"]] + turn(1) + turn(2)
        let out = ChatHistoryCompactor.compact(msgs, budget: 100_000)
        let tools = out.filter { ($0["role"] as? String) == "tool" }.compactMap { $0["content"] as? String }
        #expect(tools.count == 2)
        #expect(tools[0].count < 500)
        #expect(tools[1].count == 2_000)
    }

    @Test func sanitizeDropsUnknownAndUnansweredCalls() {
        let msgs: [[String: Any]] = [
            ["role": "system", "content": "s"],
            ["role": "user", "content": "q"],
            ["role": "assistant", "content": "", "tool_calls": [["id": "a", "type": "function", "function": ["name": "made_up_tool", "arguments": "{}"]]]],
            ["role": "tool", "tool_call_id": "a", "content": "{\"error\":\"Unknown tool\"}"],
            ["role": "assistant", "content": "", "tool_calls": [["id": "b", "type": "function", "function": ["name": "list_my_rides", "arguments": "{}"]]]],
        ]
        let out = ChatHistoryCompactor.sanitize(msgs, knownTools: Set(ChatTools.allToolNames))
        #expect(out.count == 2)                  // system + user; bad + unanswered calls removed
    }

    @Test func usageStatsAccumulate() {
        var u = ChatUsageStats()
        u.add(response: ["usage": ["prompt_tokens": 1200, "completion_tokens": 300, "completion_tokens_details": ["reasoning_tokens": 90]],
                         "choices": [["message": ["tool_calls": [[:], [:]]]]]])
        #expect(u == ChatUsageStats(requests: 1, inputTokens: 1200, outputTokens: 300, reasoningTokens: 90, toolCalls: 2))
    }
}

@Suite("Chatbot · retries & errors")
struct RetryTests {
    func err(_ code: String, retry: Double? = nil) -> ChatServiceError {
        ChatServiceError(status: 429, code: code, message: "m", retryAfter: retry)
    }

    @Test func honoursRetryAfterWhenLonger() {
        #expect(RetryPolicy.delay(for: err("rate_limited", retry: 12), attempt: 0, jitter: 0) == 12)
    }

    @Test func exponentialBackoffWithJitterWhenNoHint() {
        #expect(RetryPolicy.delay(for: err("provider_unavailable"), attempt: 0, jitter: 0) == 2)
        #expect(RetryPolicy.delay(for: err("provider_unavailable"), attempt: 1, jitter: 0) == 4)
        #expect(RetryPolicy.delay(for: err("provider_unavailable"), attempt: 1, jitter: 1) == 5)
    }

    @Test func boundedAttempts() {
        #expect(RetryPolicy.delay(for: err("rate_limited", retry: 1), attempt: RetryPolicy.maxAttempts, jitter: 0) == nil)
    }

    @Test func neverRetriesDailyLimitsAuthOrInvalid() {
        for code in ["daily_limit", "provider_daily_limit", "unauthenticated", "invalid_request", "request_too_large"] {
            #expect(RetryPolicy.delay(for: err(code, retry: 5), attempt: 0, jitter: 0) == nil, "\(code)")
        }
    }

    @Test func longWaitsAreShownNotSlept() {
        #expect(RetryPolicy.delay(for: err("rate_limited", retry: 600), attempt: 0, jitter: 0) == nil)
    }

    @Test func parsesV2ErrorBody() {
        let body = #"{"error":{"code":"rate_limited","message":"The assistant is busy right now.","scope":"tpm","retry_after_s":7}}"#
        let e = ChatServiceError.parse(status: 429, data: Data(body.utf8))
        #expect(e.code == "rate_limited" && e.retryAfter == 7 && e.scope == "tpm")
        #expect(e.friendlyMessage == "The assistant is busy right now.")
        let gateway = ChatServiceError.parse(status: 401, data: Data(#"{"code":"UNAUTHORIZED_INVALID_JWT_FORMAT"}"#.utf8))
        #expect(gateway.code == "unauthenticated")
    }
}

@MainActor
@Suite("Plan · Edit route & estimates")
struct EditRouteTests {
    @Test func normalFlowReturnsToDetails() {
        let app = AppState()
        app.path = [.planWho, .planDetails, .planReview]
        app.editRouteFromReview()
        #expect(app.path == [.planWho, .planDetails])
    }

    @Test func mapAndRoutesFlowReturnsToDetails() {
        let app = AppState()
        app.path = [.planWho, .planDetails, .planMap, .planRoutes, .planReview]
        app.editRouteFromReview()
        #expect(app.path == [.planWho, .planDetails])
    }

    @Test func chatbotFlowOpensDetailsInsteadOfHomeOrChat() {
        let app = AppState()
        app.path = [.chatbot, .planReview]
        app.editRouteFromReview()
        #expect(app.path == [.chatbot, .planDetails])
    }

    @Test func editKeepsTheDraft() {
        let app = AppState()
        app.draft.to = "Munnar"; app.draft.endCoord = Coord(lat: 10.08, lon: 77.06)
        app.path = [.chatbot, .planReview]
        app.editRouteFromReview()
        #expect(app.draft.to == "Munnar" && app.draft.endCoord == Coord(lat: 10.08, lon: 77.06))
    }

    @Test func estimatesAreLabelled() {
        var draft = PlanDraft()
        draft.routes[.fastest] = RouteSummary(km: 120.4, minutes: 180, coords: [], rawDistance: 120_400, rawTime: 10_800, isEstimate: true)
        #expect(draft.distanceText(.fastest) == "≈ 120.4 km")
        #expect(draft.durationText(.fastest).hasPrefix("≈ "))
        draft.routes[.scenic] = RouteSummary(km: 130, minutes: 200, coords: [], rawDistance: 130_000, rawTime: 12_000)
        #expect(draft.distanceText(.scenic) == "130.0 km")
    }
}

@MainActor
@Suite("Chatbot · per-account chat", .serialized)
struct ChatPrivacyTests {
    let legacy = ["chat.messages.v2", "chat.apiMessages.v2", "chat.timestamp.v2", "chat.rideDraft.v2"]

    @Test func accountsNeverShareAConversationAndOldChatMovesToCurrentRider() throws {
        let d = UserDefaults.standard
        // Preserve whatever this simulator already has, and restore it afterwards.
        let saved = legacy.map { d.object(forKey: $0) }
        let a = UUID(), b = UUID()
        defer {
            for (k, v) in zip(legacy, saved) { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } }
            for id in [a, b] { for k in legacy + ["chat.usage.v2"] { d.removeObject(forKey: "\(k).\(id.uuidString.lowercased())") } }
        }

        let old = [ChatMessage(kind: .user, text: "hello from before the update")]
        d.set(try JSONEncoder().encode(old), forKey: "chat.messages.v2")
        d.set(Date(), forKey: "chat.timestamp.v2")

        let app = AppState()
        AppStateResolver.shared.current = app
        app.backendUserId = a
        let engineA = ChatbotEngine()
        #expect(engineA.messages.map(\.text) == ["hello from before the update"])   // not lost
        #expect(d.object(forKey: "chat.messages.v2") == nil)                         // shared copy gone

        app.backendUserId = b
        let engineB = ChatbotEngine()
        #expect(engineB.messages.isEmpty)                                            // B never sees A's chat

        app.backendUserId = a
        #expect(ChatbotEngine().messages.count == 1)                                 // A gets theirs back
    }
}

@Suite("Chatbot · answer formatting")
struct AnswerFormattingTests {
    @Test func numberedPlacesBecomeAListCard() {
        let text = """
        Here are some well-known spots around Chennai:
        1. **Marina Beach** – one of the longest urban beaches in the world.
        2. **Kapaleeshwarar Temple** – iconic Dravidian-style temple in Mylapore.

        3. Fort St. George - historic British fort
        Let me know if you'd like directions.
        """
        let b = ChatTextFormatter.blocks(text)
        #expect(b.count == 3)
        #expect(b.first == .paragraph("Here are some well-known spots around Chennai:"))
        guard case .list(let items, let numbered) = b[1] else { Issue.record("no list"); return }
        #expect(numbered && items.count == 3)
        #expect(items[0] == ChatListItem(number: 1, title: "Marina Beach", detail: "one of the longest urban beaches in the world."))
        #expect(items[2].title == "Fort St. George" && items[2].detail == "historic British fort")
        #expect(b[2] == .paragraph("Let me know if you'd like directions."))
    }

    @Test func repeatedQuestionIsShownOnce() {
        let text = "When would you like to start the ride? Please provide a date and time (future).When would you like to start the ride? Please provide a date and time (future)."
        let b = ChatTextFormatter.blocks(text)
        #expect(b == [.paragraph("When would you like to start the ride? Please provide a date and time (future).")])
    }

    @Test func repeatedLinesAreShownOnce() {
        let b = ChatTextFormatter.blocks("Which style?\nWhich style?\n\nWhich style?")
        #expect(b == [.paragraph("Which style?")])
    }

    @Test func routeOptionsAndBullets() {
        let b = ChatTextFormatter.blocks("Route options:\n1. Fastest\n2. Off-route\n\n- Sangeetha Veg Restaurant\n- SS Hyderabad Biryani")
        #expect(b.count == 3)
        if case .list(let items, true) = b[1] { #expect(items.map(\.title) == ["Fastest", "Off-route"]) } else { Issue.record("no numbered list") }
        if case .list(let items, false) = b[2] { #expect(items.count == 2) } else { Issue.record("no bullet list") }
    }

    @Test func boldOnlyLineIsAHeading() {
        #expect(ChatTextFormatter.blocks("**Nearby cafés:**\n- Cafe A") .first == .heading("Nearby cafés"))
    }
}

@Suite("Chatbot · plan kept after review")
struct PlanKeptTests {
    @Test func olderDraftsDecodeWithReviewFields() throws {
        let d = try JSONDecoder().decode(RidePlanDraft.self, from: Data(#"{"destination":"Ooty"}"#.utf8))
        #expect(!d.reviewOpened && d.routeStyle == nil)
    }
}

@Suite("Chatbot · looping replies")
struct ChatLoopingReplyTests {
    /// The reply from the rider's screenshot after "Current location".
    static let looped = "When would you like to start the ride? Please give a date and time (future). (e.g., “Tomorrow at 8 am”) Whenever you’re ready, just let me know the date and time you’d like to start. What date and time would you like to begin the ride? Whenever you decide, just tell me the start date and time (future). Let me know the date and time you’d like to start, and we’ll fetch route options for you. Whenever you’re ready, just share the start date and time (e.g., “Saturday at 9 am”). Let me know the date and time you’d like to start the ride."

    @Test func rewordedRepeatsAreDropped() {
        let out = ChatTextFormatter.clean(Self.looped)
        #expect(out.hasPrefix("When would you like to start the ride?"))
        #expect(!out.contains("What date and time would you like to begin"))
        #expect(!out.contains("Whenever you decide"))
        #expect(!out.contains("Saturday at 9 am"))
        #expect(out.count < Self.looped.count / 2)
    }

    @Test func abbreviationsKeepTheirSpacing() {
        let out = ChatTextFormatter.clean("Give a time (e.g., “Tomorrow at 8 am”). Mt. Abu is lovely.")
        #expect(out == "Give a time (e.g., “Tomorrow at 8 am”). Mt. Abu is lovely.")
    }

    @Test func normalProseIsUntouched() {
        let text = "Munnar is a hill town in Kerala known for tea gardens. The ride from Kochi to Munnar takes about 4 hours through tea gardens and hills. Want me to plan it?"
        #expect(ChatTextFormatter.clean(text) == text)
    }

    @Test func listsAreUntouched() {
        let text = "Here are some stops:\n1. **Marina Beach** – long beach\n2. **Marina Beach Road** – long beach road"
        #expect(ChatTextFormatter.clean(text) == text)
    }

    @Test func confirmedActionDecodesFromOlderMessages() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","kind":"confirmation","text":"Confirmed: Open ride review?"}"#
        let m = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        #expect(m.action == nil)
    }
}

@Suite("Chatbot · reopen review request")
struct ChatReopenIntentTests {
    @Test func recognisesReopenRequests() {
        for t in ["Open the ride planner again", "show review", "take me back to the plan", "Reopen ride review"] {
            #expect(ChatbotEngine.isReopenReviewRequest(t), "\(t)")
        }
        for t in ["Plan a ride to Ooty", "What rides do I have?", "Is the review screen open on weekends at Guindy park? I'd love to see it"] {
            #expect(!ChatbotEngine.isReopenReviewRequest(t), "\(t)")
        }
    }
}

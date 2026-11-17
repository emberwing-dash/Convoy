// ChatbotEngine.swift
import Foundation
import SwiftUI
import Supabase

// MARK: - Location resolution option (used by begin_ride_planning / set_ride_start)

struct LocationOption: Codable, Equatable, Hashable {
    let name: String
    let address: String
    let lat: Double
    let lon: Double
    /// Town / city / region / natural place (true) vs a business such as a hotel (false).
    /// Optional so drafts saved by older builds still decode.
    var isGeographic: Bool? = nil
    var coord: Coord { Coord(lat: lat, lon: lon) }
}

// MARK: - Draft

struct RidePlanDraft: Equatable, Codable {
    var destination: String? = nil
    var destinationCoord: Coord? = nil
    var startLocation: String? = nil
    var startCoord: Coord? = nil
    var startIsCurrentLocation: Bool = false
    var checkpoints: [String] = []
    var scheduledAt: Date? = nil
    var crewName: String? = nil
    var friendUsernames: [String] = []

    /// Places awaiting the user's choice (returned by begin_ride_planning / set_ride_start).
    var pendingDestinationChoices: [LocationOption] = []
    var pendingStartChoices: [LocationOption] = []
    /// What the rider typed while a choice is pending (shown in the plan banner only).
    var destinationQuery: String? = nil
    /// Route style the rider chose when review was opened (used to reopen review directly).
    var routeStyle: String? = nil
    /// Set when review has been opened, with the app's last-created ride at that moment, so the
    /// chat can tell when the rider actually created the ride (then the plan is done).
    var reviewOpened = false
    var lastCreatedRideAtReview: UUID? = nil

    /// A place only counts as set once it has real coordinates from a chosen search result —
    /// never from typed text alone.
    var hasConfirmedDestination: Bool { destination != nil && destinationCoord != nil }
    var hasConfirmedStart: Bool { startLocation != nil && (startCoord != nil || startIsCurrentLocation) }

    var missingFields: [String] {
        var m: [String] = []
        if !hasConfirmedDestination { m.append("destination") }
        if !hasConfirmedStart { m.append("start") }
        if scheduledAt == nil { m.append("time") }
        return m
    }
    var isComplete: Bool { missingFields.isEmpty && pendingDestinationChoices.isEmpty && pendingStartChoices.isEmpty }
    var isActive: Bool { destination != nil || destinationQuery != nil || !pendingDestinationChoices.isEmpty }

    init() {}

    /// Tolerant decoding: drafts saved by older builds (missing newer fields) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        destination = try c.decodeIfPresent(String.self, forKey: .destination)
        destinationCoord = try c.decodeIfPresent(Coord.self, forKey: .destinationCoord)
        startLocation = try c.decodeIfPresent(String.self, forKey: .startLocation)
        startCoord = try c.decodeIfPresent(Coord.self, forKey: .startCoord)
        startIsCurrentLocation = try c.decodeIfPresent(Bool.self, forKey: .startIsCurrentLocation) ?? false
        checkpoints = try c.decodeIfPresent([String].self, forKey: .checkpoints) ?? []
        scheduledAt = try c.decodeIfPresent(Date.self, forKey: .scheduledAt)
        crewName = try c.decodeIfPresent(String.self, forKey: .crewName)
        friendUsernames = try c.decodeIfPresent([String].self, forKey: .friendUsernames) ?? []
        pendingDestinationChoices = try c.decodeIfPresent([LocationOption].self, forKey: .pendingDestinationChoices) ?? []
        pendingStartChoices = try c.decodeIfPresent([LocationOption].self, forKey: .pendingStartChoices) ?? []
        destinationQuery = try c.decodeIfPresent(String.self, forKey: .destinationQuery)
        routeStyle = try c.decodeIfPresent(String.self, forKey: .routeStyle)
        reviewOpened = try c.decodeIfPresent(Bool.self, forKey: .reviewOpened) ?? false
        lastCreatedRideAtReview = try c.decodeIfPresent(UUID.self, forKey: .lastCreatedRideAtReview)
    }
}

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Kind: String, Codable, Hashable { case user, assistant, confirmation, error, system }
    let id: UUID
    var kind: Kind
    var text: String
    var pendingConfirmation: PendingConfirmation? = nil
    /// The tool a confirmation card ran once confirmed (e.g. "finalize_ride_plan"), so the chat can
    /// offer to repeat it later ("Open ride review" again after visiting the planner).
    var action: String? = nil

    init(id: UUID = UUID(), kind: Kind, text: String, pendingConfirmation: PendingConfirmation? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.pendingConfirmation = pendingConfirmation
    }
}

struct PendingConfirmation: Identifiable, Hashable, Codable {
    let id: UUID
    let toolCallId: String
    let toolName: String
    let argsData: Data
    let displayTitle: String
    let displayDetail: String
    let isNavigating: Bool
    let buttonLabel: String

    var rawArgs: [String: Any] {
        (try? JSONSerialization.jsonObject(with: argsData)) as? [String: Any] ?? [:]
    }

    init(id: UUID = UUID(), toolCallId: String, toolName: String, argsData: Data,
         displayTitle: String, displayDetail: String, isNavigating: Bool, buttonLabel: String) {
        self.id = id
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.argsData = argsData
        self.displayTitle = displayTitle
        self.displayDetail = displayDetail
        self.isNavigating = isNavigating
        self.buttonLabel = buttonLabel
    }

    static func == (l: PendingConfirmation, r: PendingConfirmation) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
@Observable
final class ChatbotEngine {

    // MARK: - Published state
    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false
    private(set) var thinkingStatus: String? = nil
    private(set) var promptsRemaining: Int = 9999
    private(set) var errorMessage: String? = nil
    private(set) var pendingConfirmation: PendingConfirmation? = nil
    /// Set when the last message couldn't be answered, so the rider can retry without retyping.
    private(set) var failedUserText: String? = nil
    /// Token usage for this conversation (both backends report it).
    private(set) var usage = ChatUsageStats()
    /// Backend used for the current request (fixed for a whole send → reply cycle).
    private(set) var backend: ChatbotBackend = .v1

    var rideDraft = RidePlanDraft()

    // MARK: - Private
    private var apiMessages: [[String: Any]] = []
    private let dailyLimit = 9999

    private let endpoint = URL(string: "https://avykoruhcgwpmvmddlta.supabase.co/functions/v1/groq-proxy")!
    private let supabaseKey = "sb_publishable_4cTQxSHnQbUtxLE_n2Rz7A_YDCuQ5-0"
    private var toolFailureRetries = 0
    private var rateLimitRetries = 0
    private var isExecutingTool = false
    // V2 only: one-off adjustments after specific server errors.
    private var v2ForceAllTools = false
    private var v2OmitReasoningEffort = false

    private static let countKey = "chat.promptsToday"
    private static let dateKey  = "chat.promptsDate"

    // Chat state is stored per account, so riders sharing a phone never see each other's chat.
    // Keys: "chat.<kind>.v2.<user id>". Older builds stored one shared copy under "chat.<kind>.v2".
    private let owner: String
    private var messagesKey: String { "chat.messages.v2.\(owner)" }
    private var apiMessagesKey: String { "chat.apiMessages.v2.\(owner)" }
    private var timestampKey: String { "chat.timestamp.v2.\(owner)" }
    private var rideDraftKey: String { "chat.rideDraft.v2.\(owner)" }
    private var usageKey: String { "chat.usage.v2.\(owner)" }
    private static let legacyKeys = ["chat.messages.v2", "chat.apiMessages.v2", "chat.timestamp.v2", "chat.rideDraft.v2"]

    init() {
        owner = AppStateResolver.shared.current?.backendUserId?.uuidString.lowercased() ?? "signed-out"
        migrateLegacyStateIfNeeded()
        loadState()
        refreshRateLimit()
    }

    /// One-time move of the old shared chat into the signed-in rider's own slot (they're the
    /// person who has been using this phone), so nobody loses an ongoing conversation.
    private func migrateLegacyStateIfNeeded() {
        let d = UserDefaults.standard
        guard owner != "signed-out", d.object(forKey: "chat.timestamp.v2") != nil else { return }
        if d.object(forKey: timestampKey) == nil {
            for key in Self.legacyKeys {
                if let value = d.object(forKey: key) { d.set(value, forKey: "\(key).\(owner)") }
            }
        }
        for key in Self.legacyKeys { d.removeObject(forKey: key) }
    }

    // MARK: - Memory Persistence

    private func loadState() {
        let lastDate = UserDefaults.standard.object(forKey: timestampKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(lastDate) > 48 * 60 * 60 {
            clearState()
            return
        }

        if let data = UserDefaults.standard.data(forKey: messagesKey),
           let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = decoded
        }
        if let data = UserDefaults.standard.data(forKey: apiMessagesKey),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            apiMessages = decoded
        }
        if let data = UserDefaults.standard.data(forKey: rideDraftKey),
           let decoded = try? JSONDecoder().decode(RidePlanDraft.self, from: data) {
            rideDraft = decoded
        }
        if let data = UserDefaults.standard.data(forKey: usageKey),
           let decoded = try? JSONDecoder().decode(ChatUsageStats.self, from: data) {
            usage = decoded
        }
    }

    func saveState() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: messagesKey)
        }
        if let data = try? JSONSerialization.data(withJSONObject: apiMessages) {
            UserDefaults.standard.set(data, forKey: apiMessagesKey)
        }
        if let data = try? JSONEncoder().encode(rideDraft) {
            UserDefaults.standard.set(data, forKey: rideDraftKey)
        }
        if let data = try? JSONEncoder().encode(usage) {
            UserDefaults.standard.set(data, forKey: usageKey)
        }
        UserDefaults.standard.set(Date(), forKey: timestampKey)
    }

    /// Starts a fresh conversation (from the Ellis sheet). The plan and history are cleared.
    func startNewChat() {
        guard !isThinking, !isExecutingTool else { return }
        pendingConfirmation = nil
        errorMessage = nil
        failedUserText = nil
        clearState()
    }

    private func clearState() {
        messages = []
        apiMessages = []
        rideDraft = RidePlanDraft()
        usage = ChatUsageStats()
        UserDefaults.standard.removeObject(forKey: messagesKey)
        UserDefaults.standard.removeObject(forKey: apiMessagesKey)
        UserDefaults.standard.removeObject(forKey: rideDraftKey)
        UserDefaults.standard.removeObject(forKey: timestampKey)
        UserDefaults.standard.removeObject(forKey: usageKey)
    }

    // MARK: - Public API

    func send(_ text: String, app: AppState) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // One message at a time: a double tap or a send while the reply is coming is ignored.
        guard !isThinking, !isExecutingTool else { return }
        failedUserText = nil
        // A new message while a Confirm card is open declines that action, so the conversation
        // never contains an unanswered tool call (which providers reject on every later request).
        if let pending = pendingConfirmation {
            pendingConfirmation = nil
            if let idx = messages.lastIndex(where: { $0.pendingConfirmation?.id == pending.id }) {
                messages[idx].pendingConfirmation = nil
                messages[idx].text = "Skipped"
            }
            apiMessages.append(["role": "tool", "tool_call_id": pending.toolCallId,
                                "content": "{\"error\": \"User moved on without confirming\"}"])
        }
        // "Open the ride planner again" with a finished plan: open it straight away. The model does
        // not reliably remember that the plan is complete and would start asking for details again.
        if rideDraft.isComplete, Self.isReopenReviewRequest(trimmed) {
            messages.append(ChatMessage(kind: .user, text: trimmed))
            apiMessages.append(["role": "user", "content": trimmed])
            let reply = "Opening the review for your ride to \(rideDraft.destination ?? "your destination")."
            messages.append(ChatMessage(kind: .assistant, text: reply))
            apiMessages.append(["role": "assistant", "content": reply])
            saveState()
            await reopenReview(app: app)
            return
        }
        guard promptsRemaining > 0 else {
            errorMessage = "You've used all \(dailyLimit) prompts today. Come back tomorrow."
            return
        }
        consumePrompt()

        messages.append(ChatMessage(kind: .user, text: trimmed))
        apiMessages.append(["role": "user", "content": trimmed])

        trimHistoryIfNeeded()

        errorMessage = nil
        toolFailureRetries = 0
        rateLimitRetries = 0
        saveState()
        await runLoop(app: app)
        if errorMessage != nil { failedUserText = trimmed }
    }

    /// Retries the last message that failed (it's already in the conversation — no retyping).
    func retryLastFailed(app: AppState) async {
        guard failedUserText != nil, !isThinking, !isExecutingTool else { return }
        let text = failedUserText
        failedUserText = nil
        errorMessage = nil
        toolFailureRetries = 0
        rateLimitRetries = 0
        await runLoop(app: app)
        if errorMessage != nil { failedUserText = text }
    }

    func confirmPending(app: AppState) async {
        guard let pending = pendingConfirmation else { return }
        guard !isExecutingTool else { return }

        isExecutingTool = true
        defer { isExecutingTool = false }
        pendingConfirmation = nil

        if let idx = messages.lastIndex(where: { $0.pendingConfirmation?.id == pending.id }) {
            messages[idx].pendingConfirmation = nil
            messages[idx].action = pending.toolName
            messages[idx].text = pending.toolName == "finalize_ride_plan"
                ? "Ride review opened" : "Confirmed: \(pending.displayTitle)"
        }

        isThinking = true
        thinkingStatus = ChatTools.statusLabel(pending.toolName)
        let result = await ChatTools.execute(
            name: pending.toolName, args: pending.rawArgs,
            app: app, engine: self)

        if result.contains("\"error\"") {
            print("⚠️ [Chatbot] Tool '\(pending.toolName)' failed. Result: \(result)")
        }

        apiMessages.append(["role": "tool", "tool_call_id": pending.toolCallId, "content": result])
        isThinking = false
        thinkingStatus = nil

        saveState()
        // Opening a screen ends the turn — unless it failed, then the assistant explains.
        if pending.isNavigating && !result.contains("\"error\"") { return }
        await runLoop(app: app)
    }

    func cancelPending(app: AppState) async {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        if let idx = messages.lastIndex(where: { $0.pendingConfirmation?.id == pending.id }) {
            messages[idx].pendingConfirmation = nil
            messages[idx].text = "Cancelled"
        }
        apiMessages.append([
            "role": "tool",
            "tool_call_id": pending.toolCallId,
            "content": "{\"error\": \"User declined\"}"
        ])
        saveState()
        await runLoop(app: app)
    }

    func clearError() { errorMessage = nil; failedUserText = nil }

    // MARK: - Ride plan after review

    /// Reopens the ride review for the current plan straight away (no AI call). Used by the
    /// plan banner's "Review" button after coming back from the planner.
    func reopenReview(app: AppState) async {
        guard rideDraft.isComplete, !isThinking, !isExecutingTool else { return }
        isExecutingTool = true
        defer { isExecutingTool = false }
        let result = await ChatTools.execute(name: "finalize_ride_plan",
                                             args: ["route_style": rideDraft.routeStyle ?? "Fastest"],
                                             app: app, engine: self)
        if result.contains("\"error\"") {
            errorMessage = "Couldn't open the planner right now. Please try again."
        }
        saveState()
    }

    /// "open the ride planner again", "show review", "go back to the plan"… (short requests only).
    nonisolated static func isReopenReviewRequest(_ text: String) -> Bool {
        let t = text.lowercased()
        guard t.count <= 60 else { return false }
        let verbs = ["open", "show", "go to", "go back", "back to", "take me", "reopen", "view", "see"]
        let targets = ["planner", "review", "ride plan", "the plan", "my plan", "route plan"]
        return verbs.contains { t.contains($0) } && targets.contains { t.contains($0) }
    }

    /// When the rider has created the ride from review, the chat plan is finished: clear it and say so.
    func noteRideCreatedIfNeeded(app: AppState) {
        guard rideDraft.reviewOpened, let created = app.lastCreatedRideID,
              created != rideDraft.lastCreatedRideAtReview else { return }
        let name = rideDraft.destination ?? "your destination"
        rideDraft = RidePlanDraft()
        let text = "Your ride to \(name) is created. You'll find it on the Ride tab."
        messages.append(ChatMessage(kind: .assistant, text: text))
        apiMessages.append(["role": "assistant", "content": text])
        saveState()
    }

    // MARK: - Main loop

    private func runLoop(app: AppState) async {
        isThinking = true
        defer { isThinking = false; thinkingStatus = nil; saveState() }
        backend = ChatbotBackend.current
        v2ForceAllTools = false

        let sysPrompt: [String: Any] = ["role": "system", "content": buildSystemPrompt(app: app)]
        if apiMessages.first?["role"] as? String == "system" {
            apiMessages[0] = sysPrompt
        } else {
            apiMessages.insert(sysPrompt, at: 0)
        }

        for _ in 0..<8 {
            thinkingStatus = "Thinking…"
            do {
                let response = try await callAI()
                usage.add(response: response)

                guard let choice = (response["choices"] as? [[String: Any]])?.first,
                      let message = choice["message"] as? [String: Any] else {
                    errorMessage = "The assistant didn't respond. Try again."
                    return
                }

                if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                    apiMessages.append(message)

                    for call in toolCalls {
                        guard let id = call["id"] as? String,
                              let fn = call["function"] as? [String: Any],
                              let name = fn["name"] as? String,
                              let argsStr = fn["arguments"] as? String,
                              let data = argsStr.data(using: .utf8),
                              let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                        else { continue }

                        if ChatTools.requiresConfirmation(name) {
                            let argsData = (try? JSONSerialization.data(withJSONObject: parsed)) ?? Data()
                            let pending = PendingConfirmation(
                                toolCallId: id,
                                toolName: name,
                                argsData: argsData,
                                displayTitle: ChatTools.confirmationTitle(name, parsed),
                                displayDetail: ChatTools.confirmationDetail(name, parsed, self),
                                isNavigating: ChatTools.isNavigating(name),
                                buttonLabel: ChatTools.isNavigating(name) ? "Open planner" : "Confirm")
                            self.pendingConfirmation = pending
                            messages.append(ChatMessage(kind: .confirmation, text: "", pendingConfirmation: pending))
                            return
                        }

                        thinkingStatus = ChatTools.statusLabel(name)
                        let result = await ChatTools.execute(name: name, args: parsed, app: app, engine: self)
                        if result.contains("\"error\"") {
                            print("⚠️ [Chatbot] Tool '\(name)' failed. Result: \(result)")
                        }
                        apiMessages.append(["role": "tool", "tool_call_id": id, "content": result])
                    }
                    continue
                }

                if let raw = message["content"] as? String, !raw.isEmpty {
                    // The model sometimes loops ("Let me know the date… Whenever you're ready, tell me
                    // the date…"). Keep only the first wording, in the chat and in the history it sees.
                    let text = ChatTextFormatter.clean(raw)
                    apiMessages.append(["role": "assistant", "content": text])
                    messages.append(ChatMessage(kind: .assistant, text: text))
                }
                return
            } catch let serviceError as ChatServiceError {
                // V2 only: structured errors from groq-proxy-v2.
                if serviceError.code == "tool_call_invalid", toolFailureRetries == 0 {
                    // The model asked for a tool it wasn't given this turn: retry once with all tools.
                    toolFailureRetries += 1
                    v2ForceAllTools = true
                    continue
                }
                if serviceError.code == "unsupported_parameter", !v2OmitReasoningEffort {
                    v2OmitReasoningEffort = true
                    continue
                }
                if let wait = RetryPolicy.delay(for: serviceError, attempt: rateLimitRetries, jitter: Double.random(in: 0...1)) {
                    rateLimitRetries += 1
                    thinkingStatus = "Busy — retrying in \(Int(wait.rounded()))s…"
                    do { try await Task.sleep(for: .seconds(wait)) }
                    catch { errorMessage = "Cancelled."; return }
                    continue
                }
                errorMessage = Self.message(for: serviceError)
                return
            } catch {
                if isToolHallucinationError(error), toolFailureRetries == 0 {
                    toolFailureRetries += 1
                    apiMessages.append([
                        "role": "system",
                        "content": "IMPORTANT: The previous tool call was invalid. Only use these exact tool names: \(ChatTools.allToolNames.joined(separator: ", ")). Do not invent tool names. If no tool fits, respond in plain text asking the user to rephrase."
                    ])
                    continue
                }
                if isRateLimitError(error), rateLimitRetries < 2 {
                    // groq-proxy rotates GROQ_API_KEY_1 ↔ GROQ_API_KEY_2 server-side; we only
                    // see a 429 when both keys are exhausted. Short retry first, then a longer one.
                    rateLimitRetries += 1
                    let wait: Double = rateLimitRetries == 1 ? 6 : 20
                    thinkingStatus = "Busy — retrying in \(Int(wait))s…"
                    do { try await Task.sleep(for: .seconds(wait)) }
                    catch { errorMessage = "Cancelled."; return }
                    continue
                }
                errorMessage = error.localizedDescription
                return
            }
        }
        errorMessage = "The assistant took too long. Try rephrasing."
    }

    private func isToolHallucinationError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("tool call validation failed") || msg.contains("tool_use_failed")
            || msg.contains("output_parse_failed")
    }

    private func isRateLimitError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("429") || msg.contains("rate limit")
    }

    private func trimHistoryIfNeeded() {
        guard apiMessages.count > 10 else { return }
        var cutIndex = apiMessages.count - 8
        while cutIndex < apiMessages.count {
            let role = apiMessages[cutIndex]["role"] as? String ?? ""
            if role == "user" { break }
            cutIndex += 1
        }
        guard cutIndex < apiMessages.count, cutIndex > 1 else { return }
        let systemPrompt = apiMessages[0]
        let recent = Array(apiMessages[cutIndex...])
        apiMessages = [systemPrompt] + recent
    }

    // MARK: - Backends

    private func callAI() async throws -> [String: Any] {
        switch backend {
        case .v1: return try await callGroq()      // original request, unchanged
        case .v2: return try await callV2()
        }
    }

    /// Friendly text for a V2 error, with the wait time when a retry isn't automatic.
    private static func message(for e: ChatServiceError) -> String {
        if let wait = e.retryAfter, wait > RetryPolicy.longestAutoWait,
           e.code == "rate_limited" || e.code == "user_rate_limited" {
            let minutes = Int((wait / 60).rounded(.up))
            return "The assistant is busy right now. Please try again in about \(minutes) minute\(minutes == 1 ? "" : "s")."
        }
        return e.friendlyMessage
    }

    /// groq-proxy-v2: the signed-in rider's own access token, only the relevant tools, a compacted
    /// history within a token budget, low reasoning effort and a capped reply length.
    private func callV2() async throws -> [String: Any] {
        guard let session = try? await SupabaseManager.shared.client.auth.session else {
            // Never fall back to V1 on an auth problem.
            throw ChatServiceError(status: 401, code: "unauthenticated", message: "Please reopen the app to continue chatting.")
        }

        let lastUser = apiMessages.last(where: { ($0["role"] as? String) == "user" })?["content"] as? String ?? ""
        var names = v2ForceAllTools ? Set(ChatTools.allToolNames) : ChatToolSelector.select(lastUserText: lastUser, draft: rideDraft)
        let known = Set(ChatTools.allToolNames)
        let plannedToolTokens = ChatHistoryCompactor.estimateTokens(ChatTools.schemas(named: names))
        let history = ChatHistoryCompactor.compact(
            ChatHistoryCompactor.sanitize(apiMessages, knownTools: known),
            budget: max(1_500, Self.v2InputBudget - plannedToolTokens))
        // Tools referenced by calls still in the history stay defined.
        names.formUnion(ChatHistoryCompactor.referencedTools(history))
        let tools = ChatTools.schemas(named: names)

        var body: [String: Any] = [
            "messages": history,
            "temperature": 0.4,
            "max_tokens": 900,
            "client": "ios",
        ]
        if !tools.isEmpty { body["tools"] = tools; body["tool_choice"] = "auto" }
        if !v2OmitReasoningEffort { body["reasoning_effort"] = "low" }

        var req = URLRequest(url: ChatbotBackend.v2.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(ChatbotBackend.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 45

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            let timedOut = (error as? URLError)?.code == .timedOut
            throw ChatServiceError(status: 0, code: timedOut ? "provider_timeout" : "provider_unavailable",
                                   message: timedOut ? "The assistant took too long to answer. Please try again."
                                                     : "Can't reach the assistant. Check your connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ChatServiceError.parse(status: status, data: data) }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ChatServiceError(status: 502, code: "provider_bad_response", message: "The assistant sent an unexpected reply. Please try again.")
        }
        return json
    }

    /// Input budget for one V2 request (system prompt + tools + history), in estimated tokens.
    /// Keeps a single request well inside Groq's free-tier 8K tokens/minute.
    static let v2InputBudget = 5_200

    private func callGroq() async throws -> [String: Any] {
        let body: [String: Any] = [
            "messages": apiMessages,
            "tools": ChatTools.schemas,
            "tool_choice": "auto",
            "temperature": 0.4,
            "max_tokens": 500
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Chat", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Server \(http.statusCode): \(bodyStr.prefix(280))"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Chat", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        return json
    }

    private func buildSystemPrompt(app: AppState) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        let currentDate = dateFormatter.string(from: Date())

        let crews = app.crews.map(\.name).joined(separator: ", ")
        let friends = app.friends.map { "\($0.display_name) (@\($0.username))" }.joined(separator: ", ")

        var draftStatus = "No active ride plan."
        if rideDraft.isActive {
            draftStatus = """
            ACTIVE RIDE PLAN:
            - Destination: \(rideDraft.destination ?? "Not set")
            - Destination coord: \(rideDraft.destinationCoord.map { "\($0.lat), \($0.lon)" } ?? "Not resolved")
            - Start: \(rideDraft.startLocation ?? "Not set")
            - Start coord: \(rideDraft.startCoord.map { "\($0.lat), \($0.lon)" } ?? "Not resolved")
            - Time: \(rideDraft.scheduledAt.map { "\($0)" } ?? "Not set")
            - Companions: \(rideDraft.crewName ?? "") \(rideDraft.friendUsernames.joined(separator: ", "))
            - Checkpoints: \(rideDraft.checkpoints.joined(separator: ", "))
            - Missing Fields: \(rideDraft.missingFields.joined(separator: ", "))
            - Pending destination choices: \(rideDraft.pendingDestinationChoices.count)
            - Pending start choices: \(rideDraft.pendingStartChoices.count)
            """
        }

        let toolList = ChatTools.allToolNames.joined(separator: ", ")

        return """
        You are Convoy's ride assistant for a motorcycle group-ride app in India.
        TODAY'S DATE IS: \(currentDate)

        USER CONTEXT:
        - Crews: \(crews.isEmpty ? "None" : crews)
        - Friends: \(friends.isEmpty ? "None" : friends)

        \(draftStatus)

        TOOLS: \(toolList)

        MULTI-ACTION PROMPTS:
        If the user says "Create a crew and invite X", you must:
        1. Call create_crew.
        2. After it succeeds, call invite_to_crew.

        RIDE PLANNING FLOW (follow exactly):
        1. Call begin_ride_planning(destination: <extract from message>)
           Response cases:
           - "started": destination resolved uniquely. Continue to step 2.
           - "needs_choice": multiple places matched. Read the "options" array, then ask the user which one by number (1-based). When they reply with a number, call select_location(kind: "destination", index: N).
           - "no_results": nothing matched. Ask the user to be more specific (include city/state).
        2. Ask ONE question at a time based on "Missing Fields".
           - Missing "start":
             * Ask where the ride starts; suggest "current location".
             * Call set_ride_start(location: "...", use_current_location: false) OR set_ride_start(location: "Current Location", use_current_location: true).
             * If set_ride_start returns "needs_choice", ask the user, then call select_location(kind: "start", index: N).
           - Missing "time":
             * Ask when. Convert to ISO8601 based on TODAY'S DATE (must be in the future).
             * Call set_ride_time(iso8601: "...").
           - Checkpoints (optional): use suggest_checkpoints if the user wants them.
        3. Once start and destination are resolved (both have coords), call fetch_routes.
           Present only the options returned in the response (Fastest / Scenic / Off-route — as present).
           Ask the user to pick one.
        4. When the user picks a style, call finalize_ride_plan(route_style: "ChosenStyle").
        - A place is only set once a search result is chosen. Never treat the typed name as confirmed.
        - To change the destination, call begin_ride_planning again with the new place (start and time are kept).
        - If the user cancels or wants to start over, call cancel_ride_planning.
        - If fetch_routes returns "estimate": true, tell the user distances are approximate.

        SOCIAL / CREW TOOLS:
        - find_user(username: "handle") — look up a rider (without @).
        - send_friend_request(username: "handle") — send a friend request.
        - create_crew(name: "name") — create a new crew.
        - join_crew(code: "ABC123") — join an existing crew by code.
        - invite_to_crew(crew_name: "Name", username: "handle") — invite a rider to a crew you admin.
        - invite_to_ride(code: "RIDE123", username: "handle") — invite a rider to a ride you organise.

        COMMUNITY / FEED:
        - post_to_crew_feed(code: "RIDE123", caption: "...", max_riders: 6) — post an open ride you organise to the Crew feed.

        READ-ONLY INFO (no confirmation needed):
        - list_my_rides — the user's upcoming rides (title, code, when, distance).
        - list_my_crews — the user's crews (name, code, member count).
        - list_my_friends — the user's friends (name, @handle).
        - get_ride_details(code: "RIDE123" | omit code for next ride) — full details of one ride.

        STYLE:
        - 1-2 short sentences.
        - ONE question per message. Ask it once, then stop — never re-ask it in other words.
        - Plain text. When listing places or options, put each on its own line as a numbered list:
          "1. **Name** – short detail". Never repeat the same sentence.
        - After review opens, the plan is kept. If the user asks to open the planner again, call finalize_ride_plan.
        - When listing options, show them as a numbered list.
        """
    }

    private func refreshRateLimit() {
        let today = Calendar.current.startOfDay(for: .now)
        let stored = UserDefaults.standard.object(forKey: Self.dateKey) as? Date ?? .distantPast
        if !Calendar.current.isDate(stored, inSameDayAs: today) {
            promptsRemaining = dailyLimit
            return
        }
        let used = UserDefaults.standard.integer(forKey: Self.countKey)
        promptsRemaining = max(0, dailyLimit - used)
    }

    private func consumePrompt() {
        let today = Calendar.current.startOfDay(for: .now)
        let stored = UserDefaults.standard.object(forKey: Self.dateKey) as? Date ?? .distantPast
        let newCount: Int = Calendar.current.isDate(stored, inSameDayAs: today)
            ? UserDefaults.standard.integer(forKey: Self.countKey) + 1
            : 1
        UserDefaults.standard.set(newCount, forKey: Self.countKey)
        UserDefaults.standard.set(today, forKey: Self.dateKey)
        promptsRemaining = max(0, dailyLimit - newCount)
    }
}

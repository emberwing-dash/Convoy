// ChatbotEngine.swift
import Foundation
import SwiftUI

struct RidePlanDraft: Equatable, Codable {
    var destination: String? = nil
    var startLocation: String? = nil
    var startIsCurrentLocation: Bool = false
    var checkpoints: [String] = []
    var scheduledAt: Date? = nil
    var crewName: String? = nil
    var friendUsernames: [String] = []

    var missingFields: [String] {
        var m: [String] = []
        if destination == nil { m.append("destination") }
        if startLocation == nil { m.append("start") }
        if scheduledAt == nil { m.append("time") }
        return m
    }
    var isComplete: Bool { missingFields.isEmpty }
    var isActive: Bool { destination != nil }
}

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Kind: String, Codable, Hashable { case user, assistant, confirmation, error, system }
    let id: UUID
    var kind: Kind
    var text: String
    var pendingConfirmation: PendingConfirmation? = nil

    // ✅ Explicit init with default UUID
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
    let argsData: Data // Store as Data for Codable
    let displayTitle: String
    let displayDetail: String
    let isNavigating: Bool
    let buttonLabel: String
    
    var rawArgs: [String: Any] {
        (try? JSONSerialization.jsonObject(with: argsData)) as? [String: Any] ?? [:]
    }
    
    // ✅ Explicit init with default UUID
    init(id: UUID = UUID(), toolCallId: String, toolName: String, argsData: Data, displayTitle: String, displayDetail: String, isNavigating: Bool, buttonLabel: String) {
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

    var rideDraft = RidePlanDraft()

    // MARK: - Private
    private var apiMessages: [[String: Any]] = []
    private let dailyLimit = 9999
    
    private let endpoint = URL(string: "https://avykoruhcgwpmvmddlta.supabase.co/functions/v1/groq-proxy")!
    private let supabaseKey = "sb_publishable_4cTQxSHnQbUtxLE_n2Rz7A_YDCuQ5-0"
    private var toolFailureRetries = 0
    private var rateLimitRetries = 0
    private var isExecutingTool = false

    private static let countKey = "chat.promptsToday"
    private static let dateKey  = "chat.promptsDate"
    
    // ✅ Memory Keys
    private let messagesKey = "chat.messages.v2"
    private let apiMessagesKey = "chat.apiMessages.v2"
    private let timestampKey = "chat.timestamp.v2"
    private let rideDraftKey = "chat.rideDraft.v2"

    init() {
        loadState()
        refreshRateLimit()
    }

    // MARK: - Memory Persistence

    private func loadState() {
        let lastDate = UserDefaults.standard.object(forKey: timestampKey) as? Date ?? .distantPast
        // Expire after 48 hours
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
        UserDefaults.standard.set(Date(), forKey: timestampKey)
    }

    private func clearState() {
        messages = []
        apiMessages = []
        rideDraft = RidePlanDraft()
        UserDefaults.standard.removeObject(forKey: messagesKey)
        UserDefaults.standard.removeObject(forKey: apiMessagesKey)
        UserDefaults.standard.removeObject(forKey: rideDraftKey)
        UserDefaults.standard.removeObject(forKey: timestampKey)
    }

    // MARK: - Public API

    func send(_ text: String, app: AppState) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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
    }

    func confirmPending(app: AppState) async {
        guard let pending = pendingConfirmation else { return }
        guard !isExecutingTool else { return }
        
        isExecutingTool = true
        defer { isExecutingTool = false }
        
        pendingConfirmation = nil

        if let idx = messages.lastIndex(where: { $0.pendingConfirmation?.id == pending.id }) {
            messages[idx].pendingConfirmation = nil
            messages[idx].text = "Confirmed: \(pending.displayTitle)"
        }

        isThinking = true
        thinkingStatus = ChatTools.statusLabel(pending.toolName)
        let result = await ChatTools.execute(
            name: pending.toolName, args: pending.rawArgs,
            app: app, engine: self)
            
        if result.contains("\"error\"") {
            print("⚠️ [Chatbot] Tool '\(pending.toolName)' failed. Result: \(result)")
        }
        
        apiMessages.append([
            "role": "tool",
            "tool_call_id": pending.toolCallId,
            "content": result
        ])
        isThinking = false
        thinkingStatus = nil

        saveState()
        if pending.isNavigating { return }
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

    func clearError() { errorMessage = nil }

    // MARK: - Main loop

    private func runLoop(app: AppState) async {
        isThinking = true
        defer {
            isThinking = false
            thinkingStatus = nil
            saveState()
        }

        let sysPrompt: [String: Any] = ["role": "system", "content": buildSystemPrompt(app: app)]
        if apiMessages.first?["role"] as? String == "system" {
            apiMessages[0] = sysPrompt
        } else {
            apiMessages.insert(sysPrompt, at: 0)
        }

        for _ in 0..<8 {
            thinkingStatus = "Thinking…"
            do {
                let response = try await callGroq()

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
                        let result = await ChatTools.execute(
                            name: name, args: parsed, app: app, engine: self)
                        
                        if result.contains("\"error\"") {
                            print("⚠️ [Chatbot] Tool '\(name)' failed. Result: \(result)")
                        }
                        
                        apiMessages.append([
                            "role": "tool", "tool_call_id": id, "content": result
                        ])
                    }
                    continue
                }

                if let text = message["content"] as? String, !text.isEmpty {
                    apiMessages.append(["role": "assistant", "content": text])
                    messages.append(ChatMessage(kind: .assistant, text: text))
                }
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
                if isRateLimitError(error), rateLimitRetries == 0 {
                    rateLimitRetries += 1
                    thinkingStatus = "Rate limited. Waiting 20s…"
                    do {
                        try await Task.sleep(for: .seconds(21))
                    } catch {
                        errorMessage = "Cancelled."
                        return
                    }
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
            let snippet = bodyStr.prefix(280)
            throw NSError(domain: "Chat", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Server \(http.statusCode): \(snippet)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Chat", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
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
            - Start: \(rideDraft.startLocation ?? "Not set")
            - Time: \(rideDraft.scheduledAt != nil ? "\(rideDraft.scheduledAt!)" : "Not set")
            - Companions: \(rideDraft.crewName ?? "") \(rideDraft.friendUsernames.joined(separator: ", "))
            - Checkpoints: \(rideDraft.checkpoints.joined(separator: ", "))
            - Missing Fields: \(rideDraft.missingFields.joined(separator: ", "))
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
        2. Ask ONE question at a time based on "Missing Fields".
           - If missing "start": Ask where to start. Suggest current location.
           - If missing "time": Ask when. (Calculate ISO8601 based on TODAY'S DATE).
           - Ask about checkpoints if they want them. Use suggest_checkpoints.
        3. Once start and destination are known, call fetch_routes to calculate options. Ask the user to pick one (Fastest, Scenic, etc.).
        4. Call finalize_ride_plan(route_style: "ChosenStyle") when all details are set.
        
        STYLE:
        - 1-2 short sentences.
        - ONE question per message.
        - Plain text only.
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

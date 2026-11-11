// ChatbotEngine.swift
import Foundation
import SwiftUI

struct RidePlanDraft: Equatable {
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

struct ChatMessage: Identifiable, Hashable {
    enum Kind: Hashable { case user, assistant, confirmation, error, system }
    let id = UUID()
    var kind: Kind
    var text: String
    var pendingConfirmation: PendingConfirmation? = nil
}

struct PendingConfirmation: Identifiable, Hashable {
    let id = UUID()
    let toolCallId: String
    let toolName: String
    let args: [String: AnyHashable]
    let displayTitle: String
    let displayDetail: String
    let isNavigating: Bool
    let buttonLabel: String
    var rawArgs: [String: Any] { args.mapValues { $0.base as Any } }
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
    private(set) var promptsRemaining: Int = 50
    private(set) var errorMessage: String? = nil
    private(set) var pendingConfirmation: PendingConfirmation? = nil

    /// Live ride planning state, filled by ChatTools.set_* calls.
    var rideDraft = RidePlanDraft()

    // MARK: - Private
    private var apiMessages: [[String: Any]] = []
    private let dailyLimit = 50
    private let endpoint = URL(string: "https://avykoruhcgwpmvmddlta.supabase.co/functions/v1/groq-proxy")!
    private let supabaseKey = "sb_publishable_4cTQxSHnQbUtxLE_n2Rz7A_YDCuQ5-0"
    private var didInitSystemPrompt = false
    private var toolFailureRetries = 0
    private var rateLimitRetries = 0

    private static let countKey = "chat.promptsToday"
    private static let dateKey  = "chat.promptsDate"

    init() { refreshRateLimit() }

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

        // Trim history to prevent hitting the token-per-minute limit
        trimHistoryIfNeeded()

        errorMessage = nil
        toolFailureRetries = 0
        rateLimitRetries = 0
        await runLoop(app: app)
    }

    private var isExecutingTool = false // ✅ Add this variable near the top of the class

        func confirmPending(app: AppState) async {
            guard let pending = pendingConfirmation else { return }
            guard !isExecutingTool else { return } // ✅ Prevents double-taps
            
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
        apiMessages.append([
            "role": "tool",
            "tool_call_id": pending.toolCallId,
            "content": result
        ])
        isThinking = false
        thinkingStatus = nil

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
        await runLoop(app: app)
    }

    func clearError() { errorMessage = nil }

    // MARK: - Main loop

    private func runLoop(app: AppState) async {
        isThinking = true
        defer { isThinking = false; thinkingStatus = nil }

        // ✅ Inject fresh system prompt on EVERY turn
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
                            let hashable = parsed.compactMapValues { $0 as? AnyHashable }
                            let pending = PendingConfirmation(
                                toolCallId: id,
                                toolName: name,
                                args: hashable,
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
                // ── Tool hallucination retry ────────────────────────
                if isToolHallucinationError(error), toolFailureRetries == 0 {
                    toolFailureRetries += 1
                    apiMessages.append([
                        "role": "system",
                        "content": "IMPORTANT: The previous tool call was invalid. Only use these exact tool names: \(ChatTools.allToolNames.joined(separator: ", ")). Do not invent tool names. If no tool fits, respond in plain text asking the user to rephrase."
                    ])
                    continue
                }
                // ── Rate limit retry ──────────────────────────────
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

    /// Keeps the conversation under Groq's 7,000 ITPM limit.
    /// Trims from the top but keeps the system prompt and the last complete turn.
    private func trimHistoryIfNeeded() {
        // Keep system prompt (index 0) + last ~8 messages
        guard apiMessages.count > 10 else { return }

        // Find a safe cut point — the start of a user message (not a tool result)
        var cutIndex = apiMessages.count - 8
        while cutIndex < apiMessages.count {
            let role = apiMessages[cutIndex]["role"] as? String ?? ""
            if role == "user" { break }
            cutIndex += 1
        }
        // Don't trim if we can't find a safe point
        guard cutIndex < apiMessages.count, cutIndex > 1 else { return }

        let systemPrompt = apiMessages[0]
        let recent = Array(apiMessages[cutIndex...])
        apiMessages = [systemPrompt] + recent
    }

    // MARK: - Groq

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

    // Call this at the start of runLoop, NOT just once in init.
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
                You are Convoy's ride assistant.
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
                
                RIDE PLANNING FLOW:
                ...
                """
    }

    // MARK: - Rate limiting

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

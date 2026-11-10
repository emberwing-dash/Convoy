// ChatbotEngine.swift
import Foundation
import SwiftUI

/// One message in the chat transcript.
struct ChatMessage: Identifiable, Hashable {
    enum Kind: Hashable { case user, assistant, confirmation, error }
    let id = UUID()
    var kind: Kind
    var text: String
    var pendingConfirmation: PendingConfirmation? = nil
}

/// A tool call paused awaiting user approval.
struct PendingConfirmation: Identifiable, Hashable {
    let id = UUID()
    let toolCallId: String
    let toolName: String
    let args: [String: AnyHashable]  // store as Hashable wrapper for equatability
    let displayTitle: String
    let displayDetail: String
    let isNavigating: Bool
    let buttonLabel: String

    var rawArgs: [String: Any] {
        args.mapValues { $0.base as Any }
    }

    static func == (l: PendingConfirmation, r: PendingConfirmation) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Runs the Groq chat loop with tool support.
@MainActor
@Observable
final class ChatbotEngine {

    // MARK: - Published state
    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false
    private(set) var thinkingStatus: String? = nil
    private(set) var promptsRemaining: Int = 50
    private(set) var errorMessage: String? = nil

    /// The tool call the user is currently confirming, if any.
    private(set) var pendingConfirmation: PendingConfirmation? = nil

    // MARK: - Private
    private var apiMessages: [[String: Any]] = []
    private let dailyLimit = 50
    private let endpoint = URL(string: "https://avykoruhcgwpmvmddlta.supabase.co/functions/v1/groq-proxy")!
    private let supabaseKey = "sb_publishable_4cTQxSHnQbUtxLE_n2Rz7A_YDCuQ5-0"
    private var didInitSystemPrompt = false

    private static let countKey = "chat.promptsToday"
    private static let dateKey  = "chat.promptsDate"

    // MARK: - Init

    init() {
        refreshRateLimit()
    }

    // MARK: - Public API

    func send(_ text: String, app: AppState) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard promptsRemaining > 0 else {
            errorMessage = "You've used all \(dailyLimit) prompts today. Come back tomorrow."
            return
        }

        // Consume one prompt
        consumePrompt()

        // Append to display + API history
        messages.append(ChatMessage(kind: .user, text: trimmed))
        ensureSystemPrompt()
        apiMessages.append(["role": "user", "content": trimmed])

        errorMessage = nil
        await runLoop(app: app)
    }

    func confirmPending(app: AppState) async {
        guard let pending = pendingConfirmation else { return }
        // Clear immediately to prevent double-tap
        pendingConfirmation = nil

        // Replace the confirmation card in the UI with a resolved state
        if let idx = messages.lastIndex(where: { $0.pendingConfirmation?.id == pending.id }) {
            messages[idx].pendingConfirmation = nil
            messages[idx].text = "Confirmed: \(pending.displayTitle)"
        }

        // Execute (or navigate) and append tool result so history stays valid.
        isThinking = true
        thinkingStatus = ChatTools.statusLabel(pending.toolName)

        let result = await ChatTools.execute(
            name: pending.toolName, args: pending.rawArgs, app: app
        )
        apiMessages.append([
            "role": "tool",
            "tool_call_id": pending.toolCallId,
            "content": result
        ])

        isThinking = false
        thinkingStatus = nil

        // If the tool navigated away (closed the chat), stop here.
        if pending.isNavigating { return }

        // Otherwise let the model react to the result.
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
            "content": "{\"error\": \"User declined this action\"}"
        ])

        await runLoop(app: app)
    }

    func clearError() { errorMessage = nil }

    // MARK: - Main loop

    private func runLoop(app: AppState) async {
        isThinking = true
        defer { isThinking = false; thinkingStatus = nil }

        for _ in 0..<6 {
            thinkingStatus = "Thinking…"

            do {
                let response = try await callGroq()
                guard let choice = (response["choices"] as? [[String: Any]])?.first,
                      let message = choice["message"] as? [String: Any] else {
                    errorMessage = "The assistant didn't respond. Try again."
                    return
                }

                // Tool call(s)?
                if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                    // Save the assistant tool_calls message into history
                    apiMessages.append(message)

                    for call in toolCalls {
                        guard let id = call["id"] as? String,
                              let fn = call["function"] as? [String: Any],
                              let name = fn["name"] as? String,
                              let argsStr = fn["arguments"] as? String,
                              let argsData = argsStr.data(using: .utf8),
                              let parsed = (try? JSONSerialization.jsonObject(with: argsData)) as? [String: Any]
                        else { continue }

                        if ChatTools.requiresConfirmation(name) {
                            // Pause — show a confirmation card
                            let hashableArgs = parsed.compactMapValues { $0 as? AnyHashable }
                            let pending = PendingConfirmation(
                                toolCallId: id,
                                toolName: name,
                                args: hashableArgs,
                                displayTitle: ChatTools.confirmationTitle(name, parsed),
                                displayDetail: ChatTools.confirmationDetail(name, parsed),
                                isNavigating: ChatTools.isNavigating(name),
                                buttonLabel: ChatTools.isNavigating(name) ? "Open planner" : "Confirm"
                            )
                            self.pendingConfirmation = pending
                            messages.append(ChatMessage(kind: .confirmation, text: "", pendingConfirmation: pending))
                            return
                        }

                        // Read-only / navigation → execute now
                        thinkingStatus = ChatTools.statusLabel(name)
                        let result = await ChatTools.execute(name: name, args: parsed, app: app)
                        apiMessages.append([
                            "role": "tool",
                            "tool_call_id": id,
                            "content": result
                        ])
                    }
                    // Loop to let the model see the tool results and reply
                    continue
                }

                // Plain text reply
                if let text = message["content"] as? String, !text.isEmpty {
                    apiMessages.append(["role": "assistant", "content": text])
                    messages.append(ChatMessage(kind: .assistant, text: text))
                }
                return
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        errorMessage = "The assistant took too long. Try rephrasing."
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
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw NSError(domain: "Chat", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Server \(http.statusCode): \(snippet)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Chat", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        return json
    }

    private func ensureSystemPrompt() {
        guard !didInitSystemPrompt else { return }
        didInitSystemPrompt = true
        apiMessages.insert([
            "role": "system",
            "content": """
            You are Convoy's ride assistant. Convoy is a motorcycle group-ride app for India.

            Users can: find places (lakes, waterfalls, viewpoints, beaches, cafes, hill roads, hill stations, historical sites), plan multi-stop rides, create crews and invite friends, join rides by 6-character code, track rides on a live map.

            Rules:
            1. Keep replies SHORT — 1–2 sentences when possible. Users are on a phone.
            2. When the user wants to DO something (plan a ride, send a friend request, join a ride, create a crew, invite someone), call the matching tool. The app handles confirmation — do NOT ask "shall I?" in text first.
            3. When the user asks a question, call read-only tools (search_places, list_my_rides, etc.) and answer using the results.
            4. Never invent place names, usernames, ride codes, or crew names. If you're not sure, use a search tool.
            5. If a tool returns an error, tell the user plainly and suggest what to do.
            6. Do not output URLs, markdown links, or code blocks. Plain text only.
            7. If the user asks for something Convoy can't do yet, say so honestly and suggest the closest thing it can do.
            8. For "plan a ride to X" — call plan_ride with destination X. Don't try to invent route stops unless the user provides them.
            """
        ], at: 0)
    }

    // MARK: - Rate limiting (per-device, resets at midnight)

    private func refreshRateLimit() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let storedDate = UserDefaults.standard.object(forKey: Self.dateKey) as? Date ?? .distantPast
        if !calendar.isDate(storedDate, inSameDayAs: today) {
            promptsRemaining = dailyLimit
            return
        }
        let used = UserDefaults.standard.integer(forKey: Self.countKey)
        promptsRemaining = max(0, dailyLimit - used)
    }

    private func consumePrompt() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let storedDate = UserDefaults.standard.object(forKey: Self.dateKey) as? Date ?? .distantPast

        let newCount: Int
        if !calendar.isDate(storedDate, inSameDayAs: today) {
            newCount = 1
        } else {
            newCount = UserDefaults.standard.integer(forKey: Self.countKey) + 1
        }
        UserDefaults.standard.set(newCount, forKey: Self.countKey)
        UserDefaults.standard.set(today, forKey: Self.dateKey)
        promptsRemaining = max(0, dailyLimit - newCount)
    }
}

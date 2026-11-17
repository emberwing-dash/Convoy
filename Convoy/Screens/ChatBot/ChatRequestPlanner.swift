// ChatRequestPlanner.swift — what the V2 chatbot sends, and how it retries.
//
// All pure / deterministic so it is unit-tested (ConvoyTests/ChatbotV2Tests.swift):
//   • selectTools        — only the tools relevant to the current message and planning stage
//                          (all 24 tools stay available; a tool-name error retries with all of them).
//   • compactHistory     — recent turns verbatim, older turns summarised, old tool results shortened,
//                          tool calls never separated from their results, within a token budget.
//                          Confirmed places, coordinates and times live in the ride draft, which is
//                          always sent in full in the system prompt, so they are never lost.
//   • RetryPolicy        — honours the server's retry_after, exponential backoff with jitter,
//                          bounded attempts, never retries daily limits / auth / invalid requests.
import Foundation

// MARK: - Errors from V2

/// A structured error returned by groq-proxy-v2 (`{"error": {"code", "message", "retry_after_s", "scope"}}`).
struct ChatServiceError: Error, Equatable {
    let status: Int
    let code: String
    let message: String
    var retryAfter: Double? = nil
    var scope: String? = nil

    /// Text safe to show riders (never raw provider output).
    var friendlyMessage: String {
        message.isEmpty ? "The assistant is unavailable right now. Please try again." : message
    }

    static func parse(status: Int, data: Data) -> ChatServiceError {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let err = obj?["error"] as? [String: Any]
        let code = err?["code"] as? String ?? (status == 401 ? "unauthenticated" : "http_\(status)")
        let message = err?["message"] as? String ?? ""
        let retry = (err?["retry_after_s"] as? NSNumber)?.doubleValue
        return ChatServiceError(status: status, code: code, message: message,
                                retryAfter: retry, scope: err?["scope"] as? String)
    }
}

enum RetryPolicy {
    static let maxAttempts = 2          // retries after the first try
    static let longestAutoWait: Double = 45

    /// Seconds to wait before retrying, or nil when retrying would not help.
    /// `jitter` is 0…1 (injected for tests).
    static func delay(for error: ChatServiceError, attempt: Int, jitter: Double) -> Double? {
        guard attempt < maxAttempts else { return nil }
        let spread = 1 + 0.25 * jitter
        switch error.code {
        case "rate_limited", "user_rate_limited", "server_busy", "request_in_progress":
            let backoff = 2 * pow(2, Double(attempt))                  // 2 s, 4 s
            let wait = max(error.retryAfter ?? 0, backoff) * spread
            return wait <= longestAutoWait ? wait : nil              // a long wait is shown, not slept
        case "provider_unavailable", "provider_timeout", "provider_bad_response", "usage_unavailable":
            return 2 * pow(2, Double(attempt)) * spread
        default:
            // daily limits, auth, invalid requests, misconfiguration: retrying won't help.
            return nil
        }
    }
}

// MARK: - Tool selection

enum ChatToolSelector {
    static let planning: Set<String> = [
        "begin_ride_planning", "select_location", "set_ride_start", "set_ride_time", "set_ride_companions",
        "set_ride_checkpoints", "suggest_checkpoints", "fetch_routes", "finalize_ride_plan",
        "cancel_ride_planning", "list_my_crews", "list_my_friends",
    ]
    static let startPlanning: Set<String> = ["begin_ride_planning", "search_places", "search_routes"]
    static let discovery: Set<String> = ["search_places", "search_routes", "begin_ride_planning"]
    static let crews: Set<String> = ["list_my_crews", "create_crew", "join_crew", "invite_to_crew", "find_user"]
    static let social: Set<String> = ["find_user", "send_friend_request", "list_my_friends"]
    static let rides: Set<String> = ["list_my_rides", "get_ride_details", "join_ride", "invite_to_ride", "post_to_crew_feed"]
    static let general: Set<String> = ["list_my_rides", "search_places", "begin_ride_planning", "get_ride_details"]

    static func select(lastUserText: String, draft: RidePlanDraft) -> Set<String> {
        let t = " " + lastUserText.lowercased() + " "
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }

        var tools: Set<String> = []
        if draft.isActive { tools.formUnion(planning) }
        if has(["crew"]) { tools.formUnion(crews) }
        if has(["friend", "@", "request", " add "]) { tools.formUnion(social) }
        if has([" join"]) { tools.formUnion(["join_ride", "join_crew"]) }
        if has([" code"]) { tools.formUnion(["join_ride", "join_crew", "get_ride_details"]) }
        if has(["my ride", "upcoming", "next ride", "details", "invite", " post", "feed", "rides"]) { tools.formUnion(rides) }
        if has([" ride", " trip", " plan", " go to", "visit", " route", "weekend", "travel"]) { tools.formUnion(startPlanning) }
        if has([" place", "lake", "waterfall", "beach", "cafe", "viewpoint", "scenic", " near", "explore", "suggest"]) { tools.formUnion(discovery) }
        if has(["cancel", "start over", "never mind", "nevermind"]), draft.isActive { tools.insert("cancel_ride_planning") }
        if tools.isEmpty { tools = general }
        return tools
    }
}

// MARK: - History & token budget

enum ChatHistoryCompactor {
    /// Rough token estimate (~4 characters per token for English JSON).
    static func estimateTokens(_ value: Any) -> Int {
        guard JSONSerialization.isValidJSONObject(value) || value is String else { return 0 }
        if let s = value as? String { return max(1, s.count / 4) }
        let data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
        return max(1, data.count / 4)
    }

    /// Removes history entries a provider would reject: calls to unknown tools (e.g. an old
    /// hallucinated name), calls that never got a result, and results whose call is gone.
    static func sanitize(_ messages: [[String: Any]], knownTools: Set<String>) -> [[String: Any]] {
        let answered = Set(messages.compactMap { ($0["role"] as? String) == "tool" ? $0["tool_call_id"] as? String : nil })
        var keptCallIds = Set<String>()
        var out: [[String: Any]] = []
        for m in messages {
            let role = m["role"] as? String ?? ""
            if role == "assistant", let calls = m["tool_calls"] as? [[String: Any]] {
                let good = calls.filter { call in
                    let name = (call["function"] as? [String: Any])?["name"] as? String ?? ""
                    let id = call["id"] as? String ?? ""
                    return knownTools.contains(name) && answered.contains(id)
                }
                good.forEach { if let id = $0["id"] as? String { keptCallIds.insert(id) } }
                var copy = m
                if good.isEmpty {
                    copy.removeValue(forKey: "tool_calls")
                    let text = (m["content"] as? String) ?? ""
                    if text.isEmpty { continue }
                    copy["content"] = text
                } else {
                    copy["tool_calls"] = good
                }
                out.append(copy)
            } else if role == "tool" {
                if let id = m["tool_call_id"] as? String, keptCallIds.contains(id) { out.append(m) }
            } else {
                out.append(m)
            }
        }
        return out
    }

    /// Names of tools called in these messages.
    static func referencedTools(_ messages: [[String: Any]]) -> Set<String> {
        var names = Set<String>()
        for m in messages {
            for call in (m["tool_calls"] as? [[String: Any]]) ?? [] {
                if let n = (call["function"] as? [String: Any])?["name"] as? String { names.insert(n) }
            }
        }
        return names
    }

    /// `messages[0]` must be the system prompt. Returns system + (optional summary) + recent turns,
    /// keeping at least the latest turn whole, within `budget` tokens (system prompt included).
    static func compact(_ messages: [[String: Any]], budget: Int,
                        oldToolResultChars: Int = 400, summaryChars: Int = 140) -> [[String: Any]] {
        guard let system = messages.first, (system["role"] as? String) == "system" else { return messages }
        let rest = Array(messages.dropFirst())

        // Split into turns: each starts at a user message and includes the assistant/tool replies.
        var turns: [[[String: Any]]] = []
        for m in rest {
            if (m["role"] as? String) == "user" || turns.isEmpty { turns.append([m]) } else { turns[turns.count - 1].append(m) }
        }
        guard !turns.isEmpty else { return [system] }

        // Shorten tool results in every turn except the newest.
        for i in 0..<(turns.count - 1) {
            turns[i] = turns[i].map { m in
                guard (m["role"] as? String) == "tool", let c = m["content"] as? String, c.count > oldToolResultChars else { return m }
                var short = m
                short["content"] = String(c.prefix(oldToolResultChars)) + "…"
                return short
            }
        }

        // Keep newest turns while they fit; summarise the rest.
        var kept: [[[String: Any]]] = []
        var used = estimateTokens(system)
        for turn in turns.reversed() {
            let cost = estimateTokens(turn)
            if kept.isEmpty || used + cost <= budget {
                kept.insert(turn, at: 0)
                used += cost
            } else {
                break
            }
        }
        let dropped = turns.count - kept.count
        var out: [[String: Any]] = [system]
        if dropped > 0 {
            let lines = turns.prefix(dropped).map { turn -> String in
                let user = (turn.first?["content"] as? String) ?? ""
                let reply = turn.last(where: { ($0["role"] as? String) == "assistant" && ($0["content"] as? String)?.isEmpty == false })?["content"] as? String ?? ""
                return "- User: \(user.prefix(summaryChars))" + (reply.isEmpty ? "" : " → Assistant: \(reply.prefix(summaryChars))")
            }
            out.append(["role": "system",
                        "content": "Earlier in this chat (summary; the active ride plan above is authoritative):\n" + lines.suffix(8).joined(separator: "\n")])
        }
        out.append(contentsOf: kept.flatMap { $0 })
        return out
    }
}

// MARK: - Usage stats

/// Token usage for this rider's current conversation (V1 and V2 both report `usage`).
struct ChatUsageStats: Codable, Equatable {
    var requests = 0
    var inputTokens = 0
    var outputTokens = 0
    var reasoningTokens = 0
    var toolCalls = 0

    mutating func add(response: [String: Any]) {
        requests += 1
        let usage = response["usage"] as? [String: Any] ?? [:]
        inputTokens += (usage["prompt_tokens"] as? NSNumber)?.intValue ?? 0
        outputTokens += (usage["completion_tokens"] as? NSNumber)?.intValue ?? 0
        reasoningTokens += ((usage["completion_tokens_details"] as? [String: Any])?["reasoning_tokens"] as? NSNumber)?.intValue ?? 0
        let calls = (((response["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["tool_calls"] as? [Any])?.count ?? 0
        toolCalls += calls
    }
}

// ChatbotBackend.swift — the ONE place that decides which AI proxy the chatbot talks to.
//
//   v1 → `groq-proxy`     (original; unchanged request format; known auth weakness — see docs/chatbot)
//   v2 → `groq-proxy-v2`  (signed-in rider token, validation, server-side limits, structured errors)
//
// How the choice is made (first match wins):
//   1. DEBUG builds only: a local override for testing on a simulator / test phone.
//   2. Remote switch: `public.app_config` row key = "chatbot", value {"backend": "v1"|"v2", "rollout": "beta"|"all"}.
//      With rollout "beta", only riders listed in `public.chatbot_beta_testers` get v2.
//   3. Otherwise v1.
// The last resolved choice is cached, so an offline launch keeps behaving the same.
//
// Operator rollback (no app rebuild):  update public.app_config set value = '{"backend":"v1","rollout":"beta"}' where key = 'chatbot';
// Apps pick it up the next time the chat screen opens. Nothing ever falls back to v1 automatically.
import Foundation
import Supabase

enum ChatbotBackend: String, Codable {
    case v1, v2

    var endpoint: URL {
        switch self {
        case .v1: return URL(string: "https://avykoruhcgwpmvmddlta.supabase.co/functions/v1/groq-proxy")!
        case .v2: return URL(string: "https://avykoruhcgwpmvmddlta.supabase.co/functions/v1/groq-proxy-v2")!
        }
    }

    /// Publishable (public) project key — always sent as `apikey`. Never a secret.
    static let publishableKey = "sb_publishable_4cTQxSHnQbUtxLE_n2Rz7A_YDCuQ5-0"

    private static let cacheKey = "chatbot.backend.resolved"
    private static let overrideKey = "chatbot.backend.debugOverride"

    /// The backend to use right now (cached remote decision, or the DEBUG override).
    @MainActor static var current: ChatbotBackend {
        #if DEBUG
        if let o = debugOverride { return o }
        #endif
        return UserDefaults.standard.string(forKey: cacheKey).flatMap(ChatbotBackend.init(rawValue:)) ?? .v1
    }

    #if DEBUG
    /// Local test switch (Debug builds only). nil = follow the remote switch.
    @MainActor static var debugOverride: ChatbotBackend? {
        get { UserDefaults.standard.string(forKey: overrideKey).flatMap(ChatbotBackend.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: overrideKey) }
    }
    #endif

    private struct RemoteConfig: Decodable { let backend: String?; let rollout: String? }
    private struct ConfigRow: Decodable { let value: RemoteConfig }
    private struct BetaRow: Decodable { let user_id: UUID }

    /// Reads the remote switch and caches the result. Failures keep the last known choice.
    @MainActor static func refresh(userId: UUID?) async {
        let client = SupabaseManager.shared.client
        guard let rows: [ConfigRow] = try? await client.from("app_config")
            .select("value").eq("key", value: "chatbot").limit(1).execute().value,
              let config = rows.first?.value else { return }

        var resolved: ChatbotBackend = .v1
        if config.backend == "v2" {
            if config.rollout == "all" {
                resolved = .v2
            } else if let userId,
                      let beta: [BetaRow] = try? await client.from("chatbot_beta_testers")
                        .select("user_id").eq("user_id", value: userId).limit(1).execute().value,
                      !beta.isEmpty {
                resolved = .v2
            }
        }
        UserDefaults.standard.set(resolved.rawValue, forKey: cacheKey)
    }
}

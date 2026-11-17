// supabase/functions/groq-proxy-v2/index.ts
//
// Convoy chatbot AI proxy — V2 (runs in parallel with the original `groq-proxy`, which is untouched).
//
// What V2 adds over V1:
//   • Auth: only a signed-in rider's Supabase access token is accepted (anonymous-session riders
//     count — that's how Convoy accounts work). The public publishable key alone is rejected.
//     The user is verified with Supabase Auth; user ids in request bodies are never trusted.
//   • Credentials: provider keys are read ONLY from Edge Function secrets. Nothing is hard-coded.
//     If GROQ_API_KEY_1 is missing the function refuses to run (503 provider_not_configured).
//   • Validation: whitelisted top-level fields, roles, tool names and sizes; the model is fixed
//     server-side; max_tokens / temperature / reasoning_effort are clamped.
//   • Usage & fairness: every request is checked and recorded atomically in Postgres
//     (ai_begin_request / ai_end_request): per-rider daily requests + tokens, per-minute requests,
//     one in-flight request per rider (duplicate protection) and a global in-flight cap.
//   • Rate limits: Groq 429s are classified (RPM / TPM / RPD / TPD) from Groq's headers and error
//     text and returned as a structured error with retry_after_s. The proxy itself does NOT sleep
//     or retry in a loop — the app does one bounded backoff, so retries never multiply across layers.
//     Note: GROQ_API_KEY_2 is tried after a 429 on key 1. If both keys belong to the same Groq
//     organisation they share that organisation's limits — a second key then adds no quota.
//   • Backup provider (optional): if GEMINI_API_KEY is set, temporary Groq failures (429, 5xx,
//     timeout) fail over to Gemini's OpenAI-compatible endpoint with the same messages and tools.
//     Never on invalid requests or auth errors. Responses are not streamed, and tools run in the
//     app only after a complete reply, so a failover can never execute a tool twice.
//   • Errors: friendly messages + stable codes; raw provider errors are logged, not shown.
//
// Required secrets: GROQ_API_KEY_1 (required), GROQ_API_KEY_2 (optional), GEMINI_API_KEY (optional),
// GEMINI_MODEL (optional, default gemini-2.5-flash). SUPABASE_URL / SUPABASE_ANON_KEY /
// SUPABASE_SERVICE_ROLE_KEY are provided by Supabase automatically.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// ─── Configuration ──────────────────────────────────────────────────────────────────────────

const GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions";
const GROQ_MODEL = "openai/gpt-oss-120b";
const GEMINI_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";
const GEMINI_MODEL = (Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash").trim();

const PROVIDER_TIMEOUT_MS = 30_000;
const MAX_BODY_BYTES = 160_000;
const MAX_MESSAGES = 60;
const MAX_CONTENT_CHARS = 12_000;      // per message
const MAX_TOTAL_CONTENT_CHARS = 60_000;
const MAX_TOOLS = 24;
const MAX_TOOL_JSON_CHARS = 4_000;     // per tool definition
const MAX_TOOL_CALLS_PER_MESSAGE = 8;
const OUTPUT_TOKENS = { min: 64, max: 1_500, default: 800 };

/// Every tool the Convoy app knows. Anything else is rejected.
const ALLOWED_TOOLS = new Set([
  "search_places", "search_routes", "list_my_rides", "list_my_crews", "list_my_friends", "find_user",
  "suggest_checkpoints", "begin_ride_planning", "set_ride_companions", "set_ride_start",
  "set_ride_checkpoints", "set_ride_time", "fetch_routes", "finalize_ride_plan", "select_location",
  "cancel_ride_planning", "join_ride", "join_crew", "send_friend_request", "create_crew",
  "invite_to_crew", "invite_to_ride", "post_to_crew_feed", "get_ride_details",
]);
const ALLOWED_TOP_LEVEL = new Set([
  "messages", "tools", "tool_choice", "temperature", "max_tokens", "reasoning_effort", "client",
]);
const ALLOWED_ROLES = new Set(["system", "user", "assistant", "tool"]);
const REASONING_EFFORTS = new Set(["low", "medium", "high"]);

const groqKeys = [Deno.env.get("GROQ_API_KEY_1"), Deno.env.get("GROQ_API_KEY_2")]
  .map((k) => (k ?? "").trim()).filter((k) => k.length > 0);
const geminiKey = (Deno.env.get("GEMINI_API_KEY") ?? "").trim();

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// ─── Provider health (per isolate, best effort) ─────────────────────────────────────────────

type ProviderName = "groq" | "gemini";
const health: Record<ProviderName, { failures: number; openUntil: number }> = {
  groq: { failures: 0, openUntil: 0 },
  gemini: { failures: 0, openUntil: 0 },
};
function healthy(p: ProviderName) { return Date.now() >= health[p].openUntil; }
function markOk(p: ProviderName) { health[p].failures = 0; health[p].openUntil = 0; }
function markFail(p: ProviderName) {
  health[p].failures += 1;
  // 3 consecutive temporary failures → skip this provider for 30 s (if another is available).
  if (health[p].failures >= 3) { health[p].openUntil = Date.now() + 30_000; health[p].failures = 0; }
}

// ─── Entry point ────────────────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors() });

  // 1. Authenticate the rider (fail closed).
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) return fail(401, "unauthenticated", "Please sign in to use the assistant.");
  if (token.startsWith("sb_publishable_") || token.startsWith("sb_secret_") || token === SUPABASE_ANON_KEY) {
    return fail(401, "unauthenticated", "Please sign in to use the assistant.");
  }
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SERVICE_ROLE_KEY) {
    console.error("[groq-proxy-v2] Supabase environment is incomplete");
    return fail(503, "server_misconfigured", "The assistant is unavailable right now.");
  }
  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { persistSession: false } });
  const { data: userData, error: userError } = await authClient.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) return fail(401, "unauthenticated", "Your session has expired. Please reopen the app.");

  // Health check for operators/tests (authenticated): reports configuration only, never values.
  if (req.method === "GET") {
    return json(200, {
      ok: true, user: user.id, model: GROQ_MODEL,
      providers: {
        groq: { configured: groqKeys.length > 0, keys: groqKeys.length, healthy: healthy("groq") },
        gemini: { configured: geminiKey.length > 0, model: GEMINI_MODEL, healthy: healthy("gemini") },
      },
    });
  }
  if (req.method !== "POST") return fail(405, "method_not_allowed", "Method not allowed.");
  if (groqKeys.length === 0) {
    console.error("[groq-proxy-v2] GROQ_API_KEY_1 is not configured as a secret");
    return fail(503, "provider_not_configured", "The assistant is unavailable right now.");
  }

  // 2. Validate the request.
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) return fail(413, "request_too_large", "That conversation is too long. Start a new chat.");
  let body: Record<string, unknown>;
  try { body = JSON.parse(raw); } catch { return fail(400, "invalid_request", "Invalid request."); }
  const validated = validate(body);
  if ("error" in validated) return fail(400, "invalid_request", validated.error);

  // 3. Fair-use check (atomic in Postgres).
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data: begin, error: beginError } = await admin.rpc("ai_begin_request", { p_user: user.id });
  if (beginError || !begin) {
    console.error("[groq-proxy-v2] ai_begin_request failed", beginError?.message);
    return fail(503, "usage_unavailable", "The assistant is unavailable right now. Try again shortly.");
  }
  if (!begin.ok) return usageRefusal(begin.reason, begin.retry_after_s);
  const slot: string = begin.slot;

  // 4. Call providers (Groq first, Gemini as controlled backup).
  const started = Date.now();
  let outcome: ProviderOutcome = { kind: "error", code: "provider_unavailable", status: 503 };
  try {
    outcome = await callWithFailover(validated.payload);
  } catch (err) {
    console.error("[groq-proxy-v2] unexpected", String(err));
  }
  const latency = Date.now() - started;

  // 5. Record usage and answer.
  if (outcome.kind === "ok") {
    const u = outcome.usage;
    await admin.rpc("ai_end_request", {
      p_slot: slot, p_user: user.id, p_ok: true, p_provider: outcome.provider, p_error_code: null,
      p_input: u.input, p_output: u.output, p_reasoning: u.reasoning, p_tool_calls: u.toolCalls,
      p_latency_ms: latency,
    });
    const payload = outcome.body as Record<string, unknown>;
    payload.convoy = { provider: outcome.provider, usage: u };
    return json(200, payload, { "x-convoy-provider": outcome.provider });
  }
  await admin.rpc("ai_end_request", {
    p_slot: slot, p_user: user.id, p_ok: false, p_provider: outcome.provider ?? null, p_error_code: outcome.code,
    p_input: 0, p_output: 0, p_reasoning: 0, p_tool_calls: 0, p_latency_ms: latency,
  });
  return providerFailure(outcome);
});

// ─── Validation ─────────────────────────────────────────────────────────────────────────────

type Validated = { payload: Record<string, unknown> } | { error: string };

function validate(body: Record<string, unknown>): Validated {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return { error: "Body must be an object." };
  for (const k of Object.keys(body)) if (!ALLOWED_TOP_LEVEL.has(k)) return { error: `Unknown field: ${k}` };

  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) {
    return { error: `messages must contain 1–${MAX_MESSAGES} items.` };
  }
  let total = 0;
  const cleanMessages: Record<string, unknown>[] = [];
  for (const m of messages) {
    if (typeof m !== "object" || m === null) return { error: "Invalid message." };
    const msg = m as Record<string, unknown>;
    const role = msg.role;
    if (typeof role !== "string" || !ALLOWED_ROLES.has(role)) return { error: "Invalid message role." };
    const content = msg.content;
    if (content !== null && content !== undefined && typeof content !== "string") return { error: "Message content must be text." };
    const text = (content as string | undefined) ?? "";
    if (text.length > MAX_CONTENT_CHARS) return { error: "A message is too long." };
    total += text.length;
    const out: Record<string, unknown> = { role, content: content ?? "" };
    if (role === "assistant" && msg.tool_calls !== undefined) {
      if (!Array.isArray(msg.tool_calls) || msg.tool_calls.length > MAX_TOOL_CALLS_PER_MESSAGE) return { error: "Invalid tool calls." };
      for (const c of msg.tool_calls) {
        const call = c as Record<string, unknown>;
        const fn = call?.function as Record<string, unknown> | undefined;
        if (typeof call?.id !== "string" || typeof fn?.name !== "string" || typeof fn?.arguments !== "string") return { error: "Invalid tool call." };
        if (!ALLOWED_TOOLS.has(fn.name)) return { error: "Unknown tool in history." };
        total += (fn.arguments as string).length;
      }
      out.tool_calls = msg.tool_calls;
      if (content === null || content === undefined || content === "") out.content = null;
    }
    if (role === "tool") {
      if (typeof msg.tool_call_id !== "string") return { error: "Tool result needs tool_call_id." };
      out.tool_call_id = msg.tool_call_id;
    }
    cleanMessages.push(out);
  }
  if (total > MAX_TOTAL_CONTENT_CHARS) return { error: "The conversation is too long. Start a new chat." };

  const payload: Record<string, unknown> = { messages: cleanMessages };

  if (body.tools !== undefined) {
    if (!Array.isArray(body.tools) || body.tools.length > MAX_TOOLS) return { error: "Invalid tools." };
    for (const t of body.tools) {
      const tool = t as Record<string, unknown>;
      const fn = tool?.function as Record<string, unknown> | undefined;
      if (tool?.type !== "function" || typeof fn?.name !== "string" || !ALLOWED_TOOLS.has(fn.name)) return { error: "Unknown tool." };
      if (JSON.stringify(tool).length > MAX_TOOL_JSON_CHARS) return { error: "Tool definition too large." };
    }
    if (body.tools.length > 0) payload.tools = body.tools;
  }
  if (body.tool_choice !== undefined) {
    if (body.tool_choice !== "auto" && body.tool_choice !== "none") return { error: "Invalid tool_choice." };
    if (payload.tools) payload.tool_choice = body.tool_choice;
  }
  const temp = typeof body.temperature === "number" ? body.temperature : 0.4;
  payload.temperature = Math.min(1, Math.max(0, temp));
  const maxTokens = typeof body.max_tokens === "number" ? Math.floor(body.max_tokens) : OUTPUT_TOKENS.default;
  payload.max_tokens = Math.min(OUTPUT_TOKENS.max, Math.max(OUTPUT_TOKENS.min, maxTokens));
  if (body.reasoning_effort !== undefined) {
    if (typeof body.reasoning_effort !== "string" || !REASONING_EFFORTS.has(body.reasoning_effort)) return { error: "Invalid reasoning_effort." };
    payload.reasoning_effort = body.reasoning_effort;
  }
  return { payload };
}

// ─── Providers ──────────────────────────────────────────────────────────────────────────────

type Usage = { input: number; output: number; reasoning: number; toolCalls: number };
type ProviderOutcome =
  | { kind: "ok"; provider: ProviderName; body: unknown; usage: Usage }
  | { kind: "error"; code: string; status: number; provider?: ProviderName; scope?: string; retryAfter?: number; temporary?: boolean };

async function callWithFailover(payload: Record<string, unknown>): Promise<ProviderOutcome> {
  let groqResult: ProviderOutcome | null = null;
  if (healthy("groq") || !geminiKey) {
    groqResult = await callGroq(payload);
    if (groqResult.kind === "ok") { markOk("groq"); return groqResult; }
    if (groqResult.temporary) markFail("groq");
    // Never fail over on our own/invalid requests.
    if (!groqResult.temporary) return groqResult;
  }
  if (geminiKey && healthy("gemini")) {
    const g = await callGemini(payload);
    if (g.kind === "ok") { markOk("gemini"); return g; }
    if (g.temporary) markFail("gemini");
    console.warn("[groq-proxy-v2] gemini backup failed", g.code);
    // Report the primary provider's condition (e.g. its retry-after) when we have it.
    return groqResult ?? g;
  }
  return groqResult ?? { kind: "error", code: "provider_unavailable", status: 503, temporary: true };
}

async function callGroq(payload: Record<string, unknown>): Promise<ProviderOutcome> {
  let last: ProviderOutcome = { kind: "error", code: "provider_unavailable", status: 503, provider: "groq", temporary: true };
  for (let i = 0; i < groqKeys.length; i++) {
    const res = await post(GROQ_ENDPOINT, groqKeys[i], { ...payload, model: GROQ_MODEL, include_reasoning: false });
    if (res.kind === "network") {
      last = { kind: "error", code: res.timeout ? "provider_timeout" : "provider_unavailable", status: 503, provider: "groq", temporary: true };
      break; // a network problem is not key-specific
    }
    if (res.status === 200) {
      const parsed = safeJson(res.text);
      if (!parsed) return { kind: "error", code: "provider_bad_response", status: 502, provider: "groq", temporary: true };
      return { kind: "ok", provider: "groq", body: parsed, usage: usageOf(parsed) };
    }
    if (res.status === 429) {
      last = classify429("groq", res.headers, res.text);
      console.warn(`[groq-proxy-v2] groq key ${i + 1} rate limited (${last.kind === "error" ? last.scope : ""})`);
      continue; // try the next key (same-org keys share limits — see header note)
    }
    if (res.status >= 500) {
      last = { kind: "error", code: "provider_unavailable", status: 503, provider: "groq", temporary: true };
      break;
    }
    // 4xx other than 429: the request itself was rejected (e.g. bad tool call from the model).
    const msg = errorText(res.text);
    console.warn("[groq-proxy-v2] groq rejected request", res.status, msg.slice(0, 300));
    const toolIssue = /tool call validation|tool_use_failed|failed to call a function|output_parse_failed|parsing failed/i.test(msg + " " + res.text);
    const reasoningIssue = /reasoning_effort|include_reasoning/i.test(msg);
    return {
      kind: "error", provider: "groq", status: 422, temporary: false,
      code: toolIssue ? "tool_call_invalid" : reasoningIssue ? "unsupported_parameter" : "provider_rejected",
    };
  }
  return last;
}

async function callGemini(payload: Record<string, unknown>): Promise<ProviderOutcome> {
  // Gemini's OpenAI-compatible endpoint takes the same messages/tools; drop Groq-only fields.
  const { reasoning_effort: _r, ...rest } = payload;
  const res = await post(GEMINI_ENDPOINT, geminiKey, { ...rest, model: GEMINI_MODEL });
  if (res.kind === "network") return { kind: "error", code: res.timeout ? "provider_timeout" : "provider_unavailable", status: 503, provider: "gemini", temporary: true };
  if (res.status === 200) {
    const parsed = safeJson(res.text);
    if (!parsed) return { kind: "error", code: "provider_bad_response", status: 502, provider: "gemini", temporary: true };
    return { kind: "ok", provider: "gemini", body: parsed, usage: usageOf(parsed) };
  }
  if (res.status === 429) return classify429("gemini", res.headers, res.text);
  if (res.status >= 500) return { kind: "error", code: "provider_unavailable", status: 503, provider: "gemini", temporary: true };
  console.warn("[groq-proxy-v2] gemini rejected request", res.status, errorText(res.text).slice(0, 300));
  return { kind: "error", code: "provider_rejected", status: 422, provider: "gemini", temporary: false };
}

type PostResult = { kind: "http"; status: number; text: string; headers: Headers } | { kind: "network"; timeout: boolean };

async function post(url: string, key: string, body: unknown): Promise<PostResult> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), PROVIDER_TIMEOUT_MS);
  try {
    const r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${key}` },
      body: JSON.stringify(body),
      signal: ctrl.signal,
    });
    return { kind: "http", status: r.status, text: await r.text(), headers: r.headers };
  } catch (err) {
    return { kind: "network", timeout: (err as Error)?.name === "AbortError" };
  } finally {
    clearTimeout(timer);
  }
}

/// Which limit was hit, and how long to wait. Groq: `x-ratelimit-*-requests` are per-day,
/// `x-ratelimit-*-tokens` per-minute; the error text names the exact limit (RPM/TPM/RPD/TPD).
function classify429(provider: ProviderName, h: Headers, text: string): ProviderOutcome {
  const msg = errorText(text);
  let scope = "unknown";
  if (/\(TPM\)|tokens per minute/i.test(msg)) scope = "tpm";
  else if (/\(RPM\)|requests per minute/i.test(msg)) scope = "rpm";
  else if (/\(TPD\)|tokens per day/i.test(msg)) scope = "tpd";
  else if (/\(RPD\)|requests per day/i.test(msg)) scope = "rpd";
  else if (h.get("x-ratelimit-remaining-requests") === "0") scope = "rpd";
  else if (h.get("x-ratelimit-remaining-tokens") === "0") scope = "tpm";

  let retry = Number(h.get("retry-after"));
  if (!Number.isFinite(retry) || retry <= 0) {
    const m = msg.match(/try again in\s+(?:(\d+)h)?(?:(\d+)m)?(?:([\d.]+)s)?/i);
    retry = m ? (Number(m[1] ?? 0) * 3600 + Number(m[2] ?? 0) * 60 + Number(m[3] ?? 0)) : NaN;
  }
  if (!Number.isFinite(retry) || retry <= 0) retry = scope === "tpm" || scope === "rpm" ? 20 : 3600;
  return { kind: "error", code: "rate_limited", status: 429, provider, scope, retryAfter: Math.ceil(retry), temporary: true };
}

function usageOf(body: unknown): Usage {
  const b = body as Record<string, any>;
  const u = b?.usage ?? {};
  const calls = b?.choices?.[0]?.message?.tool_calls;
  return {
    input: Number(u.prompt_tokens ?? 0) || 0,
    output: Number(u.completion_tokens ?? 0) || 0,
    reasoning: Number(u.completion_tokens_details?.reasoning_tokens ?? 0) || 0,
    toolCalls: Array.isArray(calls) ? calls.length : 0,
  };
}

// ─── Responses ──────────────────────────────────────────────────────────────────────────────

function usageRefusal(reason: string, retryAfter?: number): Response {
  switch (reason) {
    case "daily_requests":
    case "daily_tokens":
      return fail(429, "daily_limit", "You've reached today's assistant limit. It resets at midnight.", { scope: "user_daily" });
    case "per_minute":
      return fail(429, "user_rate_limited", "You're sending messages quickly. Give it a few seconds.", { scope: "user_minute", retry_after_s: retryAfter ?? 20 });
    case "duplicate_inflight":
      return fail(409, "request_in_progress", "Still working on your last message.", { retry_after_s: retryAfter ?? 3 });
    case "server_busy":
      return fail(503, "server_busy", "The assistant is busy. Trying again shortly…", { retry_after_s: retryAfter ?? 5 });
    default:
      return fail(401, "unauthenticated", "Please sign in to use the assistant.");
  }
}

function providerFailure(o: Extract<ProviderOutcome, { kind: "error" }>): Response {
  if (o.code === "rate_limited") {
    const daily = o.scope === "rpd" || o.scope === "tpd";
    return fail(429, daily ? "provider_daily_limit" : "rate_limited",
      daily ? "The assistant has reached its daily capacity. Please try again later."
            : "The assistant is busy right now. Retrying shortly…",
      { scope: o.scope, retry_after_s: o.retryAfter, provider: o.provider });
  }
  const messages: Record<string, string> = {
    provider_timeout: "The assistant took too long to answer. Please try again.",
    provider_unavailable: "The assistant is temporarily unavailable. Please try again shortly.",
    provider_bad_response: "The assistant sent an unexpected reply. Please try again.",
    tool_call_invalid: "The assistant got confused. Please rephrase.",
    unsupported_parameter: "The assistant is misconfigured. Please try again later.",
    provider_rejected: "The assistant couldn't process that. Please rephrase.",
  };
  return fail(o.status, o.code, messages[o.code] ?? "Something went wrong. Please try again.", { provider: o.provider });
}

function fail(status: number, code: string, message: string, extra: Record<string, unknown> = {}): Response {
  return json(status, { error: { code, message, ...extra } });
}

function json(status: number, payload: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json", ...cors(), ...headers } });
}

function cors(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  };
}

function safeJson(t: string): unknown | null { try { return JSON.parse(t); } catch { return null; } }
function errorText(t: string): string {
  const j = safeJson(t) as Record<string, any> | null;
  return String(j?.error?.message ?? j?.message ?? t ?? "");
}

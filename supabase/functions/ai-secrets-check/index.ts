// supabase/functions/ai-secrets-check/index.ts
//
// Read-only diagnostic: reports only WHETHER the AI provider secrets exist in the Edge Function
// environment (true/false). It never returns, logs or derives anything from their values.
// Used before deploying/activating groq-proxy-v2, which reads keys from secrets only.

Deno.serve((_req) => {
  const has = (name: string) => (Deno.env.get(name) ?? "").trim().length > 0
  return new Response(JSON.stringify({
    GROQ_API_KEY_1: has("GROQ_API_KEY_1"),
    GROQ_API_KEY_2: has("GROQ_API_KEY_2"),
    GEMINI_API_KEY: has("GEMINI_API_KEY"),
  }), { headers: { "Content-Type": "application/json" } })
})

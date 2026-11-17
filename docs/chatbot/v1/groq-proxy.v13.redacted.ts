// REFERENCE COPY — NOT FOR DEPLOYMENT.
// Deployed Supabase Edge Function `groq-proxy`, version 13 (verify_jwt: true),
// ezbr_sha256 e9cdf2bc01d1e3bf2a7b016d63dbc8befcc4662e238a944cf9a5c25a91a2a1fa, captured 2026-11-17.
// The two hard-coded Groq key fallbacks in the deployed code are REDACTED here on purpose.
// The deployed function itself was not modified.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts"

const GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
const MODEL = "openai/gpt-oss-120b"

const KEYS: string[] = [
  Deno.env.get("GROQ_API_KEY_1") ?? "<REDACTED — hard-coded fallback key 1 in deployed v13>",
  Deno.env.get("GROQ_API_KEY_2") ?? "<REDACTED — hard-coded fallback key 2 in deployed v13>",
].map((k) => k.trim()).filter((k) => k.length > 0)

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight()
  if (req.method !== "POST") return jsonResponse(405, { error: "Method not allowed" })

  if (KEYS.length === 0) {
    console.error("[groq-proxy] GROQ_API_KEY_1 / GROQ_API_KEY_2 are not configured")
    return jsonResponse(500, { error: "Server is missing Groq API keys" })
  }

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return jsonResponse(400, { error: "Invalid JSON body" })
  }

  // Server owns the model — no client override.
  body.model = MODEL

  let lastStatus = 0
  let lastPayload = ""

  for (let i = 0; i < KEYS.length; i++) {
    const label = `key ${i + 1}`
    try {
      const upstream = await fetch(GROQ_ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${KEYS[i]}`,
        },
        body: JSON.stringify(body),
      })

      const text = await upstream.text()

      if (upstream.ok) {
        if (i > 0) console.log(`[groq-proxy] Served via ${label} (fallback)`)
        return new Response(text, {
          status: 200,
          headers: { "Content-Type": "application/json", ...corsHeaders() },
        })
      }

      lastStatus = upstream.status
      lastPayload = text

      if (upstream.status === 429) {
        console.warn(`[groq-proxy] ${label} rate limited — trying next key`)
        continue
      }

      // Non-429: real error — do not rotate, surface it to the client.
      return new Response(text, {
        status: upstream.status,
        headers: { "Content-Type": "application/json", ...corsHeaders() },
      })
    } catch (err) {
      console.error(`[groq-proxy] ${label} network error:`, err)
      lastStatus = 502
      lastPayload = JSON.stringify({ error: String(err) })
    }
  }

  // Every key is rate limited.
  return new Response(
    lastPayload || JSON.stringify({ error: "All Groq keys rate-limited. Try again shortly." }),
    {
      status: lastStatus || 429,
      headers: { "Content-Type": "application/json", ...corsHeaders() },
    },
  )
})

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  }
}

function preflight(): Response {
  return new Response("ok", { headers: corsHeaders() })
}

function jsonResponse(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders() },
  })
}

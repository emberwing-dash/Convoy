// supabase/functions/notify-outbox/index.ts
//
// Drains `notification_outbox` and forwards each row to APNs.
// Called every minute by pg_cron + pg_net (job `process-notification-outbox`) with the
// project's secret key, so it runs with RLS bypassed.
//
// v2 (2026-11-16)
//   • SOS is sent as a critical-priority, time-sensitive alert; ride start/updates as time-sensitive.
//   • apns-collapse-id = outbox id → a retried row replaces itself on the phone instead of duplicating.
//   • Rows are claimed before sending (sent_at set first) so two overlapping runs can't double-send.
//   • A row that fails is retried up to 5 times, then given up (no endless loop).
//   • Tokens APNs reports as dead (400 BadDeviceToken / 410 Unregistered) are deleted.
//
// Required secrets (Dashboard → Edge Functions → Secrets):
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (.p8 contents), APNS_TOPIC (bundle id: com.joydip.Convoy)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "jsr:@supabase/server@^1";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { create as createJwt } from "https://deno.land/x/djwt@v3.0.1/mod.ts";

const APNS_HOST_PROD = "https://api.push.apple.com";
const APNS_HOST_DEV = "https://api.sandbox.push.apple.com";
const MAX_ATTEMPTS = 5;

export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (_req, ctx) => {
    if (ctx.authMode !== "secret") {
      return json({ error: "Unauthorized — secret key required" }, 401);
    }
    const serviceKey = Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    if (!serviceKey || !supabaseUrl) return json({ error: "Missing SUPABASE_URL / secret key env" }, 500);

    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: rows, error } = await supabase
      .from("notification_outbox")
      .select("*")
      .is("sent_at", null)
      .eq("cancelled", false)
      .lt("attempts", MAX_ATTEMPTS)
      .order("created_at", { ascending: true })
      .limit(100);
    if (error) return json({ error: error.message }, 500);
    if (!rows || rows.length === 0) return json({ processed: 0, delivered: 0 });

    let jwt: string;
    try {
      jwt = await buildApnsJwt();
    } catch (e) {
      // APNs isn't configured yet: leave rows queued (attempts untouched) so they go out once it is.
      console.error("[notify-outbox] APNs JWT build failed:", e);
      return json({ error: "APNs auth not configured", queued: rows.length }, 500);
    }

    let delivered = 0;
    const failures: Array<{ id: string; reason: string }> = [];

    for (const row of rows) {
      // Claim the row first so an overlapping run skips it.
      const { data: claimed } = await supabase
        .from("notification_outbox")
        .update({ sent_at: new Date().toISOString(), attempts: (row.attempts ?? 0) + 1 })
        .eq("id", row.id)
        .is("sent_at", null)
        .select("id");
      if (!claimed || claimed.length === 0) continue;

      const { data: tokens } = await supabase
        .from("device_tokens")
        .select("apns_token, environment")
        .eq("user_id", row.user_id);

      const priority: string = row.priority ?? "normal";
      const payload = {
        aps: {
          alert: { title: row.title, body: row.body },
          sound: "default",
          badge: 1,
          "thread-id": row.kind,
          "interruption-level": priority === "normal" ? "active" : "time-sensitive",
          ...(priority === "critical" ? { "relevance-score": 1.0 } : {}),
        },
        kind: row.kind,
        deepLink: row.payload?.deep_link ?? null,
        payload: row.payload ?? {},
      };

      let rowDelivered = 0;
      let lastError: string | null = null;
      for (const t of tokens ?? []) {
        try {
          await sendApns(t.apns_token, t.environment ?? "production", payload, jwt, row.id, priority);
          delivered++;
          rowDelivered++;
        } catch (e) {
          const reason = e instanceof Error ? e.message : String(e);
          lastError = reason;
          if (/APNs (400|410).*(BadDeviceToken|Unregistered|DeviceTokenNotForTopic)/.test(reason)) {
            await supabase.from("device_tokens").delete().eq("apns_token", t.apns_token);
          }
          console.error(`[notify-outbox] APNs failed for ${String(t.apns_token).slice(0, 8)}…: ${reason}`);
          failures.push({ id: row.id, reason });
        }
      }

      // Nothing reached a device but there were devices → release for a retry (until MAX_ATTEMPTS).
      if (rowDelivered === 0 && (tokens ?? []).length > 0) {
        await supabase
          .from("notification_outbox")
          .update({ sent_at: (row.attempts ?? 0) + 1 >= MAX_ATTEMPTS ? new Date().toISOString() : null, last_error: lastError })
          .eq("id", row.id);
      }
    }

    return json({ processed: rows.length, delivered, failures });
  }),
};

let cachedJwt: { token: string; exp: number } | null = null;

async function buildApnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && cachedJwt.exp > now + 60) return cachedJwt.token;
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const rawKey = Deno.env.get("APNS_PRIVATE_KEY");
  if (!keyId || !teamId || !rawKey) throw new Error("APNS_KEY_ID / APNS_TEAM_ID / APNS_PRIVATE_KEY not set");

  const pemBody = rawKey.replace(/\\n/g, "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", keyBytes, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const token = await createJwt({ alg: "ES256", kid: keyId }, { iss: teamId, iat: now }, key);
  cachedJwt = { token, exp: now + 50 * 60 };
  return token;
}

async function sendApns(deviceToken: string, environment: string, payload: object, jwt: string,
                        collapseId: string, priority: string): Promise<void> {
  const host = environment === "sandbox" ? APNS_HOST_DEV : APNS_HOST_PROD;
  const topic = Deno.env.get("APNS_TOPIC");
  if (!topic) throw new Error("APNS_TOPIC not set");
  const res = await fetch(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": priority === "critical" ? "0" : String(Math.floor(Date.now() / 1000) + 24 * 3600),
      "apns-collapse-id": collapseId.slice(0, 64),
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) throw new Error(`APNs ${res.status}: ${await res.text()}`);
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}

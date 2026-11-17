# Chatbot V2 — rollout and rollback guide

Status (2026-11-17): **V2 is deployed (`groq-proxy-v2` v1) and tested, but NOT active for riders.**
Secrets `GROQ_API_KEY_1/2` are set. `app_config.chatbot` = `{"backend":"v1","rollout":"beta"}`,
so every rider still uses V1 (`groq-proxy` v13, untouched). Activation (step 4) waits for approval.

## Restore points

| What | How to get back to it |
|---|---|
| Entire project before this work | `git checkout backup/pre-chatbot-hardening` (tag) — or `git switch -c restore backup/pre-chatbot-hardening` |
| Offline copy of the whole repo (all branches + tags) | `backups/convoy-pre-chatbot-hardening.bundle` (git-ignored). Restore: `git clone backups/convoy-pre-chatbot-hardening.bundle restored-convoy` |
| Deployed V1 function | Still deployed and unchanged (`groq-proxy` v13, `ezbr_sha256 e9cdf2bc…`). Reference copy without keys: `docs/chatbot/v1/groq-proxy.v13.redacted.ts` |
| Database | Only **new** tables/functions were added (`supabase/migrations/20261117220000_chatbot_v2_usage.sql`). Nothing existing was altered; V1 does not use them. |

`discover-v2` still points at `741b396`. The previously uncommitted work from that branch is the
first commit on `feature/chatbot-production-hardening` (`18bdc9f`, tagged `backup/pre-chatbot-hardening`).

## 1. Add the existing Groq keys as secrets (manual — required before V2)

V1 currently runs on two keys **hard-coded in its source** (the secrets do not exist —
verified with the `ai-secrets-check` function, which only reports true/false). V2 reads keys from
secrets only and refuses to run without them. No key needs to be rotated for this.

1. Supabase Dashboard → Edge Functions → `groq-proxy` → Code. Copy the two fallback key values
   (or copy them from your Groq console).
2. Dashboard → Edge Functions → **Secrets** → add:
   - `GROQ_API_KEY_1` = first key (required)
   - `GROQ_API_KEY_2` = second key (optional)
   - optional backup provider: `GEMINI_API_KEY` (and optionally `GEMINI_MODEL`, default `gemini-2.5-flash`)
3. Verify (prints only true/false):
   `curl -s -X POST https://avykoruhcgwpmvmddlta.supabase.co/functions/v1/ai-secrets-check -H "apikey: <publishable key>" -H "Authorization: Bearer <publishable key>"`
   Expected: `{"GROQ_API_KEY_1":true,...}`

Adding the secrets does not change V1's behaviour (V1 already prefers the secret over its fallback,
and the values are the same).

Note: if both keys belong to the same Groq organisation they share that organisation's limits;
the second key then adds no extra quota.

## 2. Deploy V2 (no rider traffic yet)

Deploy `supabase/functions/groq-proxy-v2/index.ts` as a new function named `groq-proxy-v2`
(keep "Verify JWT" on). V1 is not touched. Nothing calls V2 until step 4.

Then run the server checks:
- `GET …/groq-proxy-v2` with the publishable key only → **401** (public key rejected)
- with a made-up token → **401**
- with a real rider session token → **200** health JSON (providers configured, never key values)
- POST a short chat with a rider token → 200 with `convoy.usage`; a row appears in `ai_usage_daily`
- Confirm `reasoning_effort: "low"` is accepted by the model (the app drops it automatically if Groq rejects it)

## 3. Internal test (Debug builds)

In a Debug build, open the chat and **long-press the V1/V2 badge** in the header to cycle
`Remote → V1 → V2`. Test on V2:
- plan a ride (Munnar / Ooty / Coorg / Mahabalipuram), a vague place (asks "which one?"), change destination, cancel
- crews / friends / rides questions, confirm and cancel cards
- send twice quickly (second is ignored), Retry after an error
- Edit route from review (chatbot entry and normal planner entry)

Or for a TestFlight build: add tester user ids to `chatbot_beta_testers` and set
`app_config.chatbot = {"backend":"v2","rollout":"beta"}` — only those riders get V2.

## 4. Activate V2 for everyone (only after approval)

```sql
update public.app_config set value = '{"backend":"v2","rollout":"all"}', updated_at = now() where key = 'chatbot';
```
Apps pick this up the next time the chat screen is opened. No app release needed.

## Emergency rollback to V1

```sql
update public.app_config set value = '{"backend":"v1","rollout":"beta"}', updated_at = now() where key = 'chatbot';
```
- Takes effect the next time a rider opens the chat. Conversations and ride drafts are kept
  (they are stored on the phone per account, independent of the backend).
- Do **not** delete `groq-proxy-v2` or the new tables — they are inert when the switch says v1.
- ⚠️ V1 still has the known weakness: anyone with the public app key can call it and use the
  Groq quota. A rollback to V1 should be temporary.
- The app never falls back to V1 by itself (not on auth, validation or security errors).

## Adjusting limits

```sql
-- view
select value from public.ai_config where key = 'limits';
-- e.g. allow 200 requests per rider per day
update public.ai_config set value = jsonb_set(value, '{daily_requests}', '200') where key = 'limits';
```
Keys: `daily_requests`, `daily_input_tokens`, `daily_output_tokens`, `per_minute_requests`,
`max_inflight_per_user`, `max_inflight_global`, `inflight_stale_seconds`.

Usage per rider per day: `select * from public.ai_usage_daily order by day desc, requests desc;`

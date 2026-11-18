# Live-location privacy — audit, migration review and rollout

Status (2026-11-18): **reviewed, NOT applied.** No production database change and no Realtime setting
was changed. Waiting for approval.

Branch `feature/group-ride-session` · checkpoint tag `backup/pre-group-ride-session` (commit `7a8fbb5`).

## 1. Realtime inventory (every channel in the iOS app and the database)

| # | Topic | Purpose | Type | Today | Policies needed for private | iOS ready for private-only? | Breaks if "Allow public access" is turned OFF? |
|---|---|---|---|---|---|---|---|
| 1 | `ride_location_<ride uuid>` | Live positions, shared stops, ride events, who is online | Broadcast + Presence (client ↔ client) | Public | This migration (SELECT + INSERT on `realtime.messages`) | **Yes** — joins as private when `app_config.live_location.private = true` | No, once the flag is on |
| 2 | `inbox-<user uuid>` (`App/SocialStore.swift`) | Instant in-app notification refresh | Postgres Changes on `public.notifications` (filtered to the rider) | Public | Postgres Changes are authorized by the `notifications` table RLS; a *private* channel join additionally needs a `realtime.messages` SELECT policy for this topic — **to be added and verified in a separate change** | **No** — created without `isPrivate` | **Yes** — live updates stop (the list still loads when the screen opens) |
| 3 | `leaderboard` (`App/SocialStore.swift`, trigger `broadcast_ride_logged`) | Leaderboards refresh when anyone records a ride | Broadcast, sent by the server with `realtime.send(..., private => false)` | Public | SELECT policy for `authenticated` on topic `leaderboard`; the trigger must send with `private => true` | **No** | **Yes** — boards stop live-refreshing (they still load on open) |

Not using Realtime: crew feed, chat/chatbot, ride invitations, join requests, SOS (SOS is a database
trigger + push notification), achievements.

**Conclusion: do NOT turn off "Allow public access to channels" yet.** Channels 2 and 3 still need
public access. Converting them is a separate, small change (client `isPrivate` + 2 policies + trigger
update) that should be done and tested before the global switch.

## 2. Files inspected

- `supabase/migrations/20261118010000_ride_live_location_private.sql` (was `20261118000000_…`)
- `supabase/tests/ride-live-location/authorization_test.sql`
- `supabase/migrations/20261118000000_restore_crew_backend.sql` (version clash), `20261117140000_leaderboard_v2.sql`
  (server broadcast), all other `supabase/migrations/*` names
- `Convoy/Services/RideLiveLocationManager.swift`, `Convoy/Services/RideSession/ActiveRideSession.swift`,
  `Convoy/App/SocialStore.swift`, `Convoy/Services/SupabaseManager.swift`
- supabase-swift **v2.55.4** sources: `RealtimeChannelV2`, `RealtimeClientV2`, `ChannelStateManager`,
  `RealtimeJoinConfig` (`isPrivate`), `SupabaseClient` (auth → Realtime token wiring)
- Live database (read-only): `realtime.messages` policies/grants/columns, `realtime.topic()`, `auth.uid()`,
  `public.ride_members` constraints and status values, `public.app_config`, migration history

## 3. Findings and changes

### Migration (`supabase/migrations/20261118010000_ride_live_location_private.sql`)
1. **Version clash fixed.** It used `20261118000000`, already taken by `restore_crew_backend.sql`; renamed to `20261118010000`.
2. **Cast safety.** `regex AND exists(… ::uuid)` gives no evaluation-order guarantee — a malformed topic could raise an error instead of returning false. Now `CASE WHEN regex THEN exists(…) ELSE false END`.
3. Header documents purpose, scope, join-time authorization caveat and the full rollback.
- Verified: uses `auth.uid()` (account id), never names; only `accepted` members; `anon` has no policy (denied);
  topic format matches the app exactly (`ride_location_` + lower-case uuid, `substring(… from 15)`);
  both directions covered (SELECT = receive/join, INSERT = send broadcast + track presence);
  **no other policies exist on `realtime.messages`**, so nothing combines permissively; additive only — no
  table, ride, SOS or invitation logic touched.

### Authorization test (`supabase/tests/ride-live-location/authorization_test.sql`) — rewritten
The old version needed hand-typed ids and could not write its results as `authenticated` (it would have
failed with "permission denied"). Now: picks real ids read-only, grants its temp table, tests the helper
**and the real RLS on `realtime.messages`** (send allowed for a member; blocked on another ride, for an
outsider, for presence), checks there are no extra policies, and ends in `ROLLBACK`.

### iOS (`RideLiveLocationManager.swift`, `ActiveRideSession.swift`)
- Private join uses the SDK's `config.isPrivate` (v2.55.4).
- Before a private join: refreshes the session (`auth.session`) and pushes the token (`realtimeV2.setAuth()`).
  Later token refreshes are forwarded to joined channels by the SDK itself.
- Membership pre-check (`ride_members`): a non-member gets "Not sharing — not on this ride" instead of a retry loop.
- A refused join (server "Unauthorized…" system message) → status **denied**, no retry loop.
- Removes any leftover channel object for the topic before joining (the SDK returns an existing channel for
  the same topic, which could carry the old public/private setting) → no duplicates.
- **Bug fixed:** the freshness clock was cancelled by `connect()`, so riders never turned Delayed/Offline. It
  now runs in its own task.
- Rides that exist only on the phone (never synced) don't open a live channel ("GPS active · not shared").
- Test added: the app's topic matches the policy pattern. 187/187 tests pass.

## 4. Security test results

Pre-apply simulation on the live database (read-only, helper logic inlined with real ids):

| Check | Result |
|---|---|
| Accepted member → own ride topic | ✅ allowed |
| Same member → another ride | ✅ blocked |
| Outsider → ride topic | ✅ blocked |
| Malformed topic | ✅ false, no error |
| Upper-case topic | ✅ blocked |
| No user id | ✅ blocked |
| `auth.uid()` reads the JWT claims | ✅ |
| Existing `realtime.messages` policies | none (no conflicts) |

The full SQL test (including real RLS inserts) can only run **after** the migration is applied.

## 5. Migration history — why `supabase db push` must not be used yet

Remote history has versions like `20261114215957_crew_social`, `20261117142849_chatbot_v2_usage` (applied
through the dashboard/MCP). **No local file version matches a remote version**, so `supabase db push`
would try to apply **all 15 local migrations** again (crew, discover, notifications, chatbot …).

Two safe options:
- **A (recommended now):** apply only this file in the SQL editor (or via the MCP `apply_migration`
  tool, which records it as `ride_live_location_private`).
- **B (to adopt the CLI later):** install the CLI, link, then mark the already-applied local files as applied
  so only the new one is pending:
  ```bash
  brew install supabase/tap/supabase
  supabase link --project-ref avykoruhcgwpmvmddlta
  supabase migration list            # confirm: remote-only + local-only versions, Convoy project
  supabase migration repair --status applied 20261102000000 20261104000000 20261115000000 20261116000000 \
    20261116120000 20261117000000 20261117120000 20261117140000 20261117160000 20261117180000 \
    20261117200000 20261117210000 20261117220000 20261118000000
  supabase db push --dry-run         # must list ONLY 20261118010000_ride_live_location_private.sql
  ```
  The CLI also refuses to push while the remote history has versions that don't exist locally (the 18
  dashboard/MCP versions such as `20261114215957`). Resolving that means either
  `supabase migration repair --status reverted <those versions>` (edits the history table only — schema and
  data are untouched) or adding matching local files. Review `supabase migration list` output before
  repairing anything; this history clean-up is a separate decision from the privacy rollout.
  Never run `supabase db reset` against the linked project.

## 6. Rollout (each step needs your go-ahead)

1. **Apply the migration** (option A): SQL editor → paste `20261118010000_ride_live_location_private.sql` → Run.
   Nothing changes for riders (`private` stays false).
2. **Run the test**: SQL editor → paste `authorization_test.sql` → Run → every row `pass = true`.
3. **Build** the Debug app from Xcode onto both iPhones (no App Store release).
4. Keep "Allow public access to channels" **ON**.
5. **Turn on private ride channels:**
   ```sql
   update public.app_config set value = '{"private": true}', updated_at = now() where key = 'live_location';
   ```
   Apps pick it up when a ride session starts (reopen the ride map / restart the app).
6. **Two-iPhone test** (organiser + accepted participant): both show "Sharing live"; positions, stops, ride
   events, lock screen, airplane-mode reconnect and SOS all work.
7. **Outsider test:** a third account that is not on the ride opens the ride (or the topic) → "Not sharing —
   not on this ride"; nothing received.
8. Check the inbox notifications and leaderboards still update live (they use public channels — unaffected).
9. Only after channels 2 and 3 are converted and tested: Dashboard → Project Settings → Realtime →
   turn off **Allow public access to channels**. ⚠️ Saving Realtime settings disconnects all connected
   clients; they reconnect automatically within seconds — do it outside ride hours.

## 7. Rollback

Instant (no app change): riders fall back to public channels on their next ride start.
```sql
update public.app_config set value = '{"private": false}', updated_at = now() where key = 'live_location';
```
Full removal of the migration:
```sql
drop policy if exists "ride members receive live ride messages" on realtime.messages;
drop policy if exists "ride members send live ride messages" on realtime.messages;
drop function if exists public.can_access_ride_topic(text);
delete from public.app_config where key = 'live_location';
```
If "Allow public access" was turned off, turn it back on first. Code: `git switch` back or
`git reset --hard backup/pre-group-ride-session` on this branch.

## 8. Remaining limitations

- **Impersonation inside a ride:** RLS decides who may join/send on a ride's channel. It does not check the
  `userId` inside each message. Receivers ignore non-members, but an accepted member could send a position
  labelled as another member. Closing this needs a server relay that signs/rewrites messages (not done).
- **Join-time authorization:** a rider removed mid-ride keeps their open connection until it reconnects or
  the token refreshes (up to ~1 hour).
- Old app versions join as public channels; once "Allow public access" is off they can't share live
  locations until updated.

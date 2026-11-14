# Convoy — Community Rides Architecture

Status: **proposal, not implemented.** No code, schema or Supabase changes have been made.
Branch analysed: `discover-v2` @ `50fbbf4` (14 Nov 2026).

---

## 1. What the app does today

### 1.1 Shape of the app

| Area | What exists | Key files |
|---|---|---|
| Shell | One `NavigationStack`, typed `Route` enum, three tabs `ride · discover · crew` kept mounted in a `ZStack` | `App/MainShell.swift`, `App/AppState.swift` (1,525 lines), `Components/TabBar.swift` |
| State | Single `@Observable AppState`: rides, crews, friends, notifications, join requests, draft plan, saved routes/places. Pull-based refresh with staleness windows (notifications 45 s, rides/crews/friends 120 s) | `AppState.swift` |
| Planning | `PlanWho → PlanDetails → PlanMap → PlanRoutes → PlanReview → PlanCreated`, then `AppState.finishPlan()` → `create_ride_atomic` RPC | `Screens/Plan/*`, `Models/PlanModels.swift` |
| Joining | 6-char code (typed, QR, deep link `convoy://ride/CODE`) → `findRide(byCode:)` → `create_ride_join_request` RPC → organiser accepts in Notifications → `respond_ride_join_request` RPC | `Screens/Join/*`, `AppState.swift:1261-1430`, `supabase/migrations/20261104000000_harden_ride_joins.sql` |
| Crew tab | Segments **Crews** (create, invite, crew detail) and **Friends** (requests, search, invite). No public or community surface | `Screens/Crew/*` |
| Notifications | Friend requests, crew invites, ride-join requests; Accept/Decline inline. Built by polling | `Screens/Home/NotificationView.swift` |
| Discover v2 | Places/routes/scenic/Surprise me, ranking engine, on-phone history, **origin model** (current location or chosen city, stored only on the phone), repository pattern with mock + Supabase implementations | `Screens/Discover/*`, `Services/Discover/*` |
| Ride day | Navigation, chatbot, Ellis mascot; separate realtime/navigation design under review | `Screens/Nav/*`, `docs/navigation/*` |

### 1.2 Backend in use

Tables: `profiles`, `friendships`, `crews`, `crew_members`, `rides`, `ride_members`, `ride_join_requests`, `saved_routes`, `fill_ups`, `discover_places` (+ sources/review).
RPCs: `create_ride_atomic`, `create_crew_atomic`, `create_ride_join_request`, `respond_ride_join_request`, `cancel_ride_join_request`, `respond_ride_invitation`, `complete_group_ride`, `discover_places_near`. PostGIS is already enabled (`20261102000000_discover_places.sql`).

**No realtime and no push** (no channels, no APNs entitlement). Everything is polled.

### 1.3 Findings that affect a community feature

These must be dealt with **before** any ride becomes discoverable by strangers.

1. **Ride access is protected only by the code.** `fetchRideByCode` (`SupabaseManager.swift:667`) selects directly from `rides` as a non-member, so the `rides` SELECT policy must allow non-members to read rides. That policy is not in the repo's migrations. If it is "any signed-in user can read all rides", then today every ride's code, start coordinates and route are readable by anyone with an account. **Verify the live policy first.**
2. **`create_ride_join_request` accepts any `ride_id`.** It checks authentication, self-join and existing membership only — not visibility, ride status, departure time, capacity or blocks. Fine while ride IDs are unguessable; not fine once a feed lists them.
3. **Membership is matched by display name** in several client checks (`AppState.findRide`, `sendRideJoinRequest`). Two riders called "Arjun" collide. Use user IDs.
4. **`sendRideJoinRequest` falls back to `UUID()` for the requester** when there is no session, and `createRideJoinRequest` falls back to a direct `ride_members` write if the RPC errors. Both bypass the hardened path.
5. **Ride data is text-formatted** (`distance`, `duration`, `display_date` as strings). Feed filtering/sorting needs numbers (`route_km`, `route_minutes`, `departs` already exist — use those).
6. **The organiser learns of requests only by polling.** Acceptable for a first release, but strangers waiting on approval will need push soon.

---

## 2. Goals

**MVP (this architecture):**
- Organisers can choose to list an upcoming ride publicly.
- Riders browse community rides near their chosen start city and request to join.
- Organisers review requesters (with a profile card) and accept or decline — through the existing join-request pipeline.
- Privacy and safety are designed in: no codes, no exact start points, block and report.

**Later (designed for, not built now):** push notifications, following riders, public rider profiles, leaderboards, post-ride photo posts, community rides inside Discover.

**Non-goals:** chat between strangers before acceptance, live location of public rides, open (no-approval) public rides.

---

## 3. Product structure

### 3.1 Crew tab

The Crew home redesign (Figma page "Crew · Community — UX & Prototype", frame "01 · Crew Home") already has a **Community** section with Leaderboards and Challenges. Community rides join it as a **"Rides near you"** card that opens C01 — no new tab or segment.

- **Crews** and **Friends** are unchanged.
- The tab keeps its name. Renaming to "Squad" changes the mental model of existing users for little gain.
- Designs: Figma page **"07 · Community rides"** (C00–C08).

### 3.2 Screens (to design in Figma before building)

| ID | Screen | Purpose |
|---|---|---|
| C01 | Community · rides near you | Origin pill (shared with Discover), filter chips (When · Type · Distance), ride cards, empty and location-off states |
| C02 | Community ride detail | Safe public view: title, area, destination, day and time window, km and ride time, riders going / max, organiser card, trimmed route preview, "Request to join" |
| C03 | Request to join sheet | Optional note (≤ 200 chars), what the organiser will see about you, confirm |
| C04 | Request pending / accepted / declined states | On C02 and in My rides |
| C05 | Publish ride sheet | From PlanReview and RideDetails: "Who can find this ride" (Only people I invite · Community), area label, ride type, max riders, short description |
| C06 | Organiser request review | Requester card (name, handle, avatar, rides completed, member since, mutual friends, crews in common, note), Accept / Decline, block / report |
| C07 | Report and block sheets | Reasons, confirmation |
| C08 | Listing managed state | On RideDetails: Listed · N requests · Unlist |

### 3.3 Key flows

```
Organiser:  PlanReview ─(Community)→ create_ride_atomic → publish_ride_listing
            RideDetails ─ List / Unlist

Rider:      Crew ▸ Community (C01) → ride (C02) → Request (C03)
                → create row in ride_join_requests (source = community)
Organiser:  Notifications → review (C06) → respond_ride_join_request
Rider:      accepted → ride appears in My rides with code, meeting point and full route
```

What a non-member **never** sees: the ride code, exact start coordinates, the first and last kilometres of the route, other riders' names, live location.

---

## 4. Data model

All changes are additive. Nothing existing is renamed or dropped.

### 4.1 `rides` (existing) — add

| Column | Type | Notes |
|---|---|---|
| `visibility` | `text not null default 'private' check (visibility in ('private','community'))` | `crew` can be added later |
| `max_riders` | `int check (max_riders between 2 and 50)` | null = no limit (private rides) |
| `cancelled_at` | `timestamptz` | lets listings close on cancellation |

### 4.2 `ride_listings` (new) — the public face of a ride

| Column | Type | Notes |
|---|---|---|
| `ride_id` | `uuid primary key references rides(id) on delete cascade` | one listing per ride |
| `organiser_id` | `uuid not null references auth.users(id)` | must equal `rides.organiser_id` (checked in RPC) |
| `area_name` | `text not null` | "Adyar, Chennai" — never a street address |
| `area` | `geography(Point,4326) not null` | start point **snapped server-side to ~1 km** |
| `destination_name` | `text not null` | |
| `ride_type` | `text not null` | `day`, `weekend`, `multi_day` (same buckets as Discover) |
| `categories` | `text[] not null default '{}'` | `scenic`, `coastal`, `hills`, `sunrise`, `beginner_friendly`, `long_distance` |
| `description` | `text check (char_length(description) <= 280)` | |
| `preview_path` | `jsonb` | simplified polyline with the first and last 2 km removed (computed in the app at publish) |
| `listed_at`, `unlisted_at` | `timestamptz` | |

Indexes: `gist(area)`, `(unlisted_at, ride_id)`. Departure time, km and minutes are **joined from `rides`** at read time, so the listing never goes stale.

### 4.3 `ride_join_requests` (existing) — add

| Column | Type | Notes |
|---|---|---|
| `source` | `text not null default 'code' check (source in ('code','community','invite'))` | lets notifications say "via Community" |
| `note` | `text check (char_length(note) <= 200)` | |

### 4.4 Safety tables (new)

- `user_blocks (blocker_id, blocked_id, created_at, primary key (blocker_id, blocked_id))`
- `content_reports (id, reporter_id, subject_type check in ('ride','user'), subject_id, reason, details, status default 'open', created_at)` — readable only by the service role.

### 4.5 Access rules (RLS)

| Table | Direct client access |
|---|---|
| `ride_listings` | none — read through `community_rides` / `community_ride`; write through RPCs |
| `rides` | **members and organiser only** (fix from §1.3.1); code lookup moves to an RPC |
| `user_blocks` | select/insert/delete own rows only |
| `content_reports` | insert own; no select |

---

## 5. Server functions (Postgres RPCs)

All `SECURITY DEFINER`, `SET search_path = public`, `REVOKE ... FROM public; GRANT ... TO authenticated`.

| RPC | Does | Key checks |
|---|---|---|
| `find_ride_by_code(code)` | Replaces the direct `rides` select for joining by code; returns a safe preview | rate-limited; returns nothing for completed/cancelled rides |
| `publish_ride_listing(ride_id, area_name, area_lat, area_lon, destination_name, ride_type, categories, description, preview_path, max_riders)` | Creates/updates the listing, sets `rides.visibility = 'community'` | caller is organiser; ride is upcoming, not completed/cancelled; snaps `area` to ~1 km; validates lengths |
| `unpublish_ride_listing(ride_id)` | Sets `unlisted_at`, visibility back to private | caller is organiser |
| `community_rides(lat, lon, radius_km, after, before, ride_types, categories, cursor, limit)` | Feed page | listed, not unlisted, departs in future, not full, not own, not already member/requested, no block either way; ordered by score (§7) |
| `community_ride(ride_id)` | Detail for C02 | same visibility checks; returns the caller's request status |
| `request_to_join_community_ride(ride_id, note)` | Inserts `ride_join_requests` with `source = 'community'` | all feed checks + capacity + max 10 pending per requester + max 20 requests per day |
| `respond_ride_join_request` (existing) | **Extend:** on accept, check `max_riders`; unlist automatically when full | unchanged otherwise |
| `create_ride_join_request` (existing) | **Harden:** reject community-only access paths, completed/cancelled/departed rides, and blocked users | |
| `rider_card(user_id)` | Profile card for C06 | only callable by an organiser with a pending request from that user |
| `block_user(user_id)`, `unblock_user(user_id)` | | also cancels pending requests between the two |
| `report_content(subject_type, subject_id, reason, details)` | | rate-limited |

Lifecycle trigger on `rides`: when `is_completed` becomes true or `cancelled_at` is set, set `ride_listings.unlisted_at` and cancel pending community requests. Departure in the past is filtered at read time, so no scheduled job is needed.

**Testing:** every RPC gets SQL tests run against a **local Supabase** (`supabase start`) using the real policies, never production. Include negative tests: stranger reads a private ride, reads a code, requests a full / past / blocked ride, organiser of ride A publishes ride B.

---

## 6. App architecture

Mirror the Discover v2 pattern so screens never talk to Supabase directly.

```
Models/Community.swift          CommunityRide, CommunityFilter, ListingDraft, RiderCard, JoinSource
Services/Community/
  CommunityRepository.swift     protocol: rides(filter, cursor), ride(id), requestToJoin, publish,
                                unpublish, riderCard, block, report
  SupabaseCommunityRepository   RPC calls only
  MockCommunityRepository       #if DEBUG sample rides for previews / simulator
  CommunityStore.swift          @Observable: feed pages, filter, request states, staleness (60 s),
                                pull-to-refresh, offline banner (reuse Discover's cache approach)
Screens/Community/
  CommunityView (C01) · CommunityRideView (C02) · RequestToJoinSheet (C03)
  PublishRideSheet (C05) · JoinRequestReviewView (C06) · ReportBlockSheets (C07)
Components/Community/
  CommunityRideCard · RiderCardView · ListingStatusRow
```

**Shared origin.** Community and Discover use the same start city. Move the origin out of `DiscoverStore` into a small `OriginStore` (same storage keys, so existing users keep their city) used by both.

**Changes to existing code (small, contained):**

| File | Change |
|---|---|
| `AppState.swift` | `CrewSegment` gains `.community`; `Route` gains `.communityRide(UUID)`, `.joinRequestReview(UUID)`; replace name-based membership checks with user IDs; remove the random-UUID requester fallback |
| `PlanModels.swift` | `PlanDraft.listing: ListingDraft?` |
| `PlanReviewView.swift` | "Who can find this ride" row → `PublishRideSheet` |
| `AppState.finishPlan()` | after `create_ride_atomic` succeeds, call `publish_ride_listing` if `draft.listing != nil`; surface failure on the ride ("Not listed — retry") |
| `RideDetailsView.swift` | organiser: listing status row (C08) |
| `CrewView.swift` | segment control adds Community and hosts `CommunityView` |
| `NotificationView.swift` | ride-join rows with `source == .community` show "via Community" and open C06 |
| `SupabaseManager.swift` | `fetchRideByCode` → `find_ride_by_code` RPC; remove the direct `ride_members` fallback |
| `MainShell.swift` | two new destinations |

---

## 7. Ranking the feed

Server-side in `community_rides`, with weights in one SQL function so they can be tuned:

- **Distance** from the rider's origin to the listing area (inside the radius, closer is better).
- **Departure soonness** — this weekend beats next month; nothing that has departed.
- **Social proximity** — organiser is a friend, friend-of-friend, or shares a crew.
- **Organiser reliability** — completed rides as organiser; new organisers are shown but not boosted.
- **Fit** — matches selected ride type / categories.
- **Diversity** — no more than two rides from the same organiser per page.

Riders can hide a listing ("Not interested"); hidden IDs are stored on the phone like Discover skips.

---

## 8. Privacy and safety rules

1. Listing is opt-in per ride; default is private.
2. Public data is limited to the safe projection in §5. Code, exact start, full route and member names stay members-only.
3. Every community join needs organiser approval. No open joining.
4. The organiser sees a rider card before deciding; the requester sees the organiser card before requesting.
5. Block works both ways: blocked users never see each other's listings or requests.
6. Report on every listing and rider card; reports go to a service-role-only table for review.
7. Rate limits on requests, publishing and reports.
8. Descriptions and area names are length-limited and run through a simple word filter before publishing.
9. Location: the rider's origin stays on the phone and is sent only as query parameters; it is never stored server-side.

---

## 9. Delivery phases

| Phase | Scope | Exit criteria |
|---|---|---|
| **0. Prerequisites** | Verify and fix `rides` SELECT policy; `find_ride_by_code` RPC; ID-based membership checks; remove client fallbacks that bypass RPCs; local Supabase for testing | Stranger cannot read a private ride or its code; join-by-code still works |
| **1. Backend** | Migration (§4), RPCs (§5), lifecycle trigger, SQL tests | All negative tests pass locally |
| **2. Design** | Figma C01–C08, matching Discover v2 tokens and components | Approved |
| **3. Publish** | `ListingDraft`, `PublishRideSheet`, `finishPlan` hook, RideDetails listing row | Organiser can list and unlist; failure is visible |
| **4. Browse and request** | `CommunityStore`, C01–C04 | Rider can find and request; states correct after relaunch |
| **5. Review** | C06 rider card, "via Community" notifications, capacity handling | Accept adds member and reveals code; full ride unlists |
| **6. Safety** | Block, report, rate limits, word filter | Abuse tests pass |
| **7. Soft launch** | Feature flag, one or two cities | Monitor requests per listing, accept rate, reports |
| Later | Push notifications (APNs + Edge Function), follows, public profiles, leaderboard, ride photo posts, community rides in Discover | — |

---

## 10. Decisions needed

1. **Live `rides` policy** — someone with dashboard access confirms what non-members can read today.
2. **Crew-only visibility** (rides visible to all crew members without an invite) — now or later?
3. **Max riders default** for community rides (suggest 8).
4. **Minimum account requirements** to request (e.g. profile photo + one completed ride)?
5. **Push notifications timing** — before or after soft launch?
6. **Moderation owner** — who reviews `content_reports`?
7. **Coordination with the navigation work** in `docs/navigation/` (it adds `group_ride_sessions` and realtime on `rides`); community must not change those tables' semantics.

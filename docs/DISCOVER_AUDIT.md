# Convoy Discover — Stage 1 audit & plan

_2026-11-02 · read-only audit · no code, Figma or database changes were made_

---

## 0. Blocking finding — the screenshots aren't from any code we have

The six screenshots show:
- a **Home / Routes / Crew / Garage** tab bar with a floating red action button;
- "Afternoon, Rishav";
- Start here / Popular / Public / Scenic cards;
- "20 of 2933 routes" and "20 of 6995 places";
- Google satellite map tiles ("Map data ©2026 Google");
- a "Surprise me" reel.

I searched for that UI everywhere I could:

| Where | Tab bar | Has the screenshot UI? |
|---|---|---|
| `feature/roadbook-share-studio` (this folder) | Ride / Discover / Crew | **No** |
| GitHub `main`, `combined` (moved to `Convoy_WatchPhone/`), `siri`, `watch`, `feature/notifications-crew-caching` | Ride / Discover / Crew | **No** |
| `Downloads/Convoy-Main`, `Downloads/Convoy-Main 2`, `Downloads/Convoy-Prototype`, `Desktop/Convoy MVP/Convoy-Main`, `Desktop/Ridee` (React Native) | — | **No** |
| Figma `BqLdRyITiHGuQb2Dh50H1z`, page `05 · Discover` | Ride / Discover / Crew | **No**: R01–R06 + P01 match the *current* code |
| Supabase (read-only probe with the app's publishable key) | — | **No** places/routes tables. Only `saved_routes`, `rides`, `profiles`. |

There's also no Google SDK, no Google key and no remote-image code anywhere in the repo.

**Conclusion:** the screenshots come from unpushed work, most likely Rishav's ("Afternoon, Rishav"; he authors the `siri` branch). Their 2,933-route / 6,995-place dataset and Google integration aren't available to me.

**Decision needed before Stage 2:**
- **(a)** Get that code pushed, so I redesign on top of it and reuse its data source; or
- **(b)** treat the screenshots as visual reference only, and build the new Discover on the code here (Ride / Discover / Crew tabs).

The plan below assumes **(b)** and keeps the existing tab bar. If **(a)**, sections 1, 5 and 7 change and I re-audit.

**Screenshot numbering.** You sent **6** images, but the brief describes 7. I've mapped them as:
1. Routes landing (the "current" screen, with Start here / Public);
2. Popular routes;
3. Places;
4. Scenic;
5. landing, scrolled (Explore on map / Surprise me);
6. Surprise me reel.

Your note to drop "Start here" and "Public" refers to image 1.

---

## 1. Existing architecture (what's really in the repo)

| Area | What exists | Reuse? |
|---|---|---|
| Navigation | One `NavigationStack(path: app.path)` in `App/MainShell.swift`, a typed `Route` enum in `App/AppState.swift`, a tab bar with `AppTab { ride, discover, crew }` in `Components/TabBar.swift` | **Yes**: add routes, no new navigator, no new tab |
| Discover screens | `Screens/Discover/DiscoverView.swift` (search, 4 chips, horizontal cards, "Popular this month"), `DiscoverOtherViews.swift` (Search, Saved, Explore map, row), `RouteDetailView.swift` (detail + "Where do you start?") | Rebuild the views; keep the flow shape |
| Discover data | `Models/Discover.swift` → `DiscoverService`: 8 MapKit keyword searches near the user, top 4 each, and an MKDirections `.automobile` polyline for 12 of them | **Replace** (problems below) |
| Ride planner | `AppState.startPlan(from:startAt:)` → `.planDetails` → `planMap` → `planRoutes` → `planReview` → `planCreated`. `PlanDraft` has `from/to/stops/stopCoords/startCoord/endCoord`. `RoutePlanner` computes MapKit routes. | **Yes, the only planner.** Fix: `startPlan` drops the route's stops (`stops: []`, `AppState.swift:722`). |
| Saved routes | `app.savedRoutes`, `toggleSaved`, SwiftData `SavedRouteEntity`, Supabase `saved_routes` (`user_id, route_id, title, payload_json`) | **Yes**; extend for places |
| Location | `LocationService` (When-In-Use, prompts only when `.notDetermined`, reverse geocode, `MKLocalSearch` place search) | **Yes**; add manual origin |
| Maps | Apple MapKit only (`Map`, `MapPolyline`, `MKMapSnapshotter` in `RouteSnapshotView` / `MapSnapshot`) | **Yes** for previews; no Google Maps SDK needed |
| Images | Asset catalogue only. No remote image loading or cache, except the Roadbook media cache I wrote (`RoadbookService.image`) | **New**: a small shared image pipeline |
| Backend | Supabase (anonymous auth). Tables used by the app: `profiles, friendships, crews, crew_members, rides, ride_members, fill_ups, saved_routes`. Roadbook migration written, **not applied**. | **Yes**; new tables via a reviewed migration |
| Design system | `CV.*` tokens (bg `#0B0B0C`, cream `#F3EEE3`, red `#FF3B30`…), `cvText`, `cvEyebrow`, `ContourBackdrop`, `RoundIconButton`, `CircleBackButton`, `PrimaryButton`, glass chips; Figma R01–R06 use the same look | **Yes**: no new theme |

**Problems in today's Discover, all violating the brief:**
1. **Distance and time are fake.** The card's km is straight-line distance, and the time is `km / 45 km/h` (`Discover.swift:76-80`). The polyline is computed but its distance is never used.
2. **"Popular" is fake.** It's simply the 4 nearest results (`Discover.swift:110-115`).
3. **The "routes" aren't journeys.** Each is "your location → one POI".
4. **There are no photos.** MapKit returns none, so cards show map snapshots.
5. **MapKit's "temple / beach" keyword search** returns mixed-quality POIs, with no notion of fame or scenic value.
6. **Search** only covers saved routes plus the current suggestions.

---

## 2. Proposed information architecture

The existing **Discover** tab stays where it is. No new tab, and all screens are pushed on the existing stack.

```
Discover (tab)
├─ Hero · "Find your next ride" · origin selector (My location ▾ / pick a city)
├─ 4 category cards ─────────────────────────────────────────────┐
│   Routes · Scenic · Places · Surprise me                       │
├─ Explore near you  (chips: All Lakes Waterfalls Viewpoints …)  │
├─ Popular routes    (only if ≥3 verified routes in scope)       │
├─ Famous places     (real fame/popularity signal, §6)           │
└─ Weekend rides / Hidden gems (shown only when content exists)  │
                                                                 │
Routes ──── tabs: Near me · Popular · Weekend · Long distance · Scenic · Mountain · Coastal
│            search · filters sheet (distance, duration, scenery)
└─ Route detail ── map + polyline · stops · photos · Save · Share · ▶ Plan this ride
Places ──── chips: Near me · Popular · Lakes · Waterfalls · Viewpoints · Beaches · Cafés · Historical
│            search · radius
└─ Place detail ── photos · map · ride distance/ETA · nearby · Save · Share · ▶ Plan this ride
Scenic ──── editorial collections over the SAME places/routes data (no separate DB)
Surprise me ── mode sheet (Near me · Anywhere · Scenic · Weekend · Mixed) → full-screen vertical feed
             each card: Save · Skip · Shuffle · Details · ▶ Plan this ride · Close

▶ Plan this ride → existing planner:
   app.startPlan(...) → RouteStart "Where do you start?" (R06) → PlanDetails (P01) → map → routes → review
   "Add stop" on a place while a draft exists → appends to PlanDraft.stops (Flow F)
```

**What I drop from the references:** "Start here", "Public" (per your note), the persistent mascot button, and fake "0.0 ★ · 0 rides". Ratings and ride counts show only when real.

---

## 3. Screen inventory (Stage 2 Figma work)

| # | Screen | Replaces / new | Key states |
|---|---|---|---|
| D01 | Discover landing | replaces R01 | loading skeleton, location denied (manual city), offline (cached) |
| D02 | Origin picker sheet | new | My location · recent · search city |
| D03 | Routes browse | replaces R01 list | empty-in-scope, filters applied |
| D04 | Route filters sheet | new | distance, duration, scenery |
| D05 | Route search | replaces R03 | no results |
| D06 | Route detail | replaces R02 | unverified-route label, no photos |
| D07 | Places browse | new | radius auto-expanded notice |
| D08 | Place category results | new | — |
| D09 | Place detail | new | photo attribution, no photos → map hero |
| D10 | Scenic landing | new | — |
| D11 | Scenic collection | new | — |
| D12 | Surprise me — mode sheet | new | — |
| D13 | Surprise me — feed | new | end of feed, offline, loading next |
| D14 | Plan hand-off (R06 updated) | updates R06 | route vs single place vs multi-stop |
| D15 | "Add to trip" mini-bar | new | 1–N stops queued → "Plan ride with 3 stops" |
| D16 | Saved (routes + places) | replaces R04 | empty |
| D17 | Error / empty / permission set | new | network, quota, denied |

Explore on map (R05) stays, restyled.

---

## 4. Reusable components

**Reuse as is:** `CV` tokens, `cvText`/`cvEyebrow`, `ContourBackdrop`, `RoundIconButton`, `CircleBackButton`, `PrimaryButton`, glass chip style, `AvatarChip`, `RouteSnapshotView` / `MapSnapshot`, `RouteMark`.

**New, small and shared:**
- `RemoteImage`: async loading, memory and disk cache, downsampling, attribution overlay.
- `HeroHeader`: a static hero image with gradient and title.
- `CategoryTile`
- `PlaceCard` / `RouteCard` (one family, two layouts)
- `ChipBar`
- `FeedPage` (Surprise me)
- `AttributionLabel` (required by Google and Wikimedia)
- `EmptyState`

**One model per concept:**
- `DiscoverPlace`
- `DiscoverRoute`, which replaces today's struct of the same name; `SavedRouteEntity` is migrated.
- Scenic and Surprise are **presentations** over these two models. They don't get their own models.

---

## 5. Backend requirements (proposed; migration for review only)

| Table | Purpose | Notes |
|---|---|---|
| `discover_places` | Our place catalogue | `id, provider ('google','wikidata','convoy'), provider_place_id, name, lat, lon, category[], tags[], fame_score, popularity_score, verification_status, region, updated_at`. Google content is **not** stored beyond what its terms allow (place ID kept; details refreshed on demand). Wikidata/Wikimedia content (CC-licensed) can be stored with attribution. |
| `discover_routes` | Real journeys | `id, title, start/end name+coords, encoded_polyline, distance_m, duration_s (two-wheeler), stops jsonb, scenery_tags[], difficulty (null unless verified), source, verification_status`. |
| `rider_discovery_prefs` | Personalisation | Owner-only RLS. |
| `discovery_interactions` | save / view / dismiss / plan | Owner-only insert/select. **Never** stores precise location. Aggregates are exposed to everyone only via a SECURITY DEFINER view of counts. |
| `saved_routes` (exists) | — | Add `item_type ('route','place')` **or** a sibling `saved_places`. To decide in review; prefer extending to avoid duplication. |

**Popular routes from Convoy rides.** `rides.route_coords_json` already holds planned routes. Later, routes ridden often (`ride_results`, after the Roadbook migration) can feed "popular" with real counts, aggregated server-side only, with no individual tracks exposed.

---

## 6. APIs, photos and the discovery algorithm

### Real photos of the actual place (your main ask)

| Source | Quality and coverage (India) | Rules |
|---|---|---|
| **Google Places API (New) — Place Photos** | Best coverage, including small lakes and viewpoints | Must show author attribution. Photo URLs are fetched per view and **can't be stored long-term**. Billed per photo. |
| **Wikimedia Commons via Wikidata** | Excellent for famous places (forts, falls, hill stations); thin for obscure spots | CC-BY/SA: show author and licence. Can be stored. Free. |
| **Convoy riders' photos** (Roadbook moments, crew-visible) | Real riders, real roads; grows with use | Needs explicit rider opt-in to make a photo public. Moderation. |

**Plan:**
1. Wikimedia first, for famous places (free, storable).
2. Google Place Photos for everything else.
3. Rider photos once opted in.

A place with **no real photo** gets a map/satellite hero, never a stock or placeholder image. Every photo shows its attribution.

### Distance and ETA
- Use the **Google Routes API `computeRoutes` with `travelMode: TWO_WHEELER`**. India is supported, which gives real motorcycle distance and ETA.
- Use `computeRouteMatrix` for lists, so one call covers about 25 destinations.
- The polyline comes back too. Apple MapKit stays the map renderer.
- **Fallback when quota or network fails:** MapKit `.automobile` distance, labelled **"car estimate"**. It's never shown as motorcycle time.

### "Famous" and "popular", from real signals only

| Signal | Source |
|---|---|
| Fame | Wikidata sitelinks count, plus Wikipedia pageviews (last 60 days) |
| Popularity | Google `userRatingCount` (+ rating), shown only when present; later Convoy saves, plans and rides |
| Scenic relevance | Category (lake, waterfall, viewpoint, forest, hill road, beach) + Wikidata "instance of" + curated tags |

### Ranking (Surprise me and "for you")
1. **Hard filters:**
   - exclude duplicates (place ID, or coordinates within 150 m);
   - exclude invalid coordinates;
   - exclude items dismissed in the last 30 days;
   - exclude Google `businessStatus = CLOSED_PERMANENTLY`;
   - keep only items in scope (radius or region);
   - routes: exclude unverified geometry.
2. **Scoring:** each signal is normalised to 0–1, then combined with weights. Weights are config, stored in Supabase, so they can be tuned without an app release.

   | Signal | Default weight |
   |---|---|
   | distance fit | 0.30 |
   | popularity / fame | 0.25 |
   | scenic | 0.20 |
   | novelty | 0.15 |
   | personal | 0.10 |

3. **Mix:** 70 % top-scored, 30 % exploration sampled from the rest, weighted by score. The ratio is configurable.
4. **Near me radius:** 25 → 50 → 100 km until there are at least 12 candidates. The rider can override it.
5. **Paging:** the feed asks for 10 at a time and preloads the next 3 images.

All of this runs in a **Supabase Edge Function**: the Google key stays server-side, and results are cached briefly as the terms allow. A unit-tested Swift `DiscoveryRanker` mirrors it for offline re-ranking of cached items.

### Credentials (needed only at Stage 5; nothing is requested now)
- **Google Cloud APIs to enable:** Places API (New) and Routes API.
- **Keys:**
  - one **server key** stored as a Supabase Edge Function secret, restricted by API to Places + Routes;
  - **no Google key in the iOS app**, because Apple MapKit renders the maps.
- Set billing alerts and daily quotas. I'll give exact steps when Stage 5 starts.

---

## 7. File-by-file plan (Stages 4–5; nothing touched yet)

| File | Change |
|---|---|
| `App/AppState.swift` | Add `Route` cases: `discoverRoutes, discoverPlaces, discoverScenic(String?), surprise(SurpriseMode), placeDetail(DiscoverPlace), routeDetail(DiscoverRoute)` (exists), `originPicker`. `startPlan(place:)` / `startPlan(route:)` keep stops. `addStop(_ place:)`. |
| `App/MainShell.swift` | Destinations for the new routes |
| `Models/Discover.swift` | Replace with `DiscoverPlace`, `DiscoverRoute`, `PlaceCategory`, `SurpriseMode`, `DiscoveryScope` |
| `Services/Discover/DiscoverRepository.swift` (new) | Protocol + `SupabaseDiscoverRepository` + `MockDiscoverRepository` (Stage 4 UI only) |
| `Services/Discover/RoutingProvider.swift` (new) | Protocol; Edge-Function-backed two-wheeler implementation; MapKit car-estimate fallback |
| `Services/Discover/DiscoveryRanker.swift` (new) | Pure scoring and filtering (unit-tested) |
| `Services/Discover/DiscoveryStore.swift` (new) | `@Observable` cache, paging, origin, offline |
| `Services/ImagePipeline.swift` (new) | Shared remote image cache (Roadbook can adopt it later) |
| `Screens/Discover/*` | Rewritten: Landing, Routes, Places, Scenic, Surprise feed, Place detail, Route detail (updated), Origin picker, Saved (routes + places) |
| `Components/Discover/*` (new) | `RemoteImage`, `HeroHeader`, `CategoryTile`, `PlaceCard`, `RouteCard`, `ChipBar`, `AttributionLabel` |
| `Services/LocationService.swift` | Manual origin; no repeated prompts (already only asks when not determined) |
| `supabase/migrations/…_discover.sql` (new, **review only**) | Tables in §5 + RLS + indexes |
| `supabase/functions/discover/` (new) | Places search, photos, two-wheeler matrix, ranking |
| `ConvoyTests/DiscoveryTests.swift` (new) | Ranker, filters, radius expansion, planner hand-off |

**Untouched:** Home, Crew, Garage, Roadbook, onboarding.

---

## 8. Stages after approval

| Stage | Work |
|---|---|
| 2 | Figma design of D01–D17 on a new page **"06 · Discover v2"** in the Convoy · Fresh file, using the existing tokens and components |
| 3 | Your review |
| 4 | SwiftUI with the mock repository |
| 5 | Edge Function + Google + Wikimedia + Supabase migration (presented for review first) |
| 6 | Flows A–G on the simulator |
| 7 | Final report |

**Branching:** Discover work goes on its own branch, `feature/discover-v2`, based on whichever branch you choose in §0 — not mixed into the Roadbook branch.

---

## 9. Stage 4 QA: Storage Safety & Saved-Item Compatibility Audit

_2026-11-02 · Stage 4 Step 1 Verification_

### 9.1 Potentially Destructive Migration Behaviour Removed
- **Issue:** Prior to this QA pass, `StorageService.init` contained an automatic fallback in its `catch` block that called `resetStore()`, permanently deleting all `.store`, `.store-shm`, and `.store-wal` SQLite files in `Application Support` whenever `ModelContainer` failed to initialize.
- **Data-loss impact:** This wiped user profiles, ride history, crew memberships, fuel logs, and saved items upon any transient schema, permission, or SQLite initialization error.
- **Fix:** 
  1. `resetStore()` has been completely removed. Active SQLite database files are never automatically deleted or overwritten.
  2. `StorageService` introduces explicit fallback flags: `isEphemeral`, `isEphemeralFallback`, and `initializationError`.
  3. If persistent container initialization fails, an in-memory `ModelContainer` is opened for the session so the app does not crash, while prominent warnings and diagnostics flag that changes in the fallback session will not persist across app relaunch.
  4. Dependency injection initializers `init(inMemory:)` and `init(container:)` were added, allowing tests to run in isolated memory or temporary sandboxes without touching real user storage.

### 9.2 Saved Items Compatibility Findings & Safeguards
- **Unified Entity Model:** Saved places and routes share `SavedRouteEntity` with an additive `payloadJSON` property and a `place:` ID prefix (`DiscoverPlace.savedPrefix`).
- **Legacy Route Decoding:** Routes saved before Discover v2 (`payloadJSON == ""`) decode via `DiscoverRoute(legacy:)`, restoring endpoints, coordinates from `coordsJSON`, and basic metadata.
- **Corrupt Payload Fallback for Places:** Added `DiscoverPlace(legacy:)` fallback so that if a saved place row has corrupted or invalid JSON in `payloadJSON`, it is reconstructed from entity columns (`title`, `startLat`, `startLon`, `from`, `category`) rather than disappearing completely.
- **Supabase Synchronization Behavior & Limitations:**
  - `AppState.toggleSaved` dispatches upserts/deletes to Supabase's `saved_routes` table.
  - If offline or network errors occur, IDs are queued in `UserDefaults` (`discover.pendingSavedSync`) and retried upon reconnection via `AppState.retryPendingSavedSync()`.
  - **Limitation:** Remote reads (`from("saved_routes").select()`) are not currently implemented; the app only reads saved items from local SwiftData. Cross-device restoration will require a bidirectional sync mechanism in Stage 5.
  - **Sign-Out Behavior:** Sign-out empties in-memory arrays (`savedRoutes = []`, `savedPlaces = []`), but does not delete local SwiftData records on disk.

### 9.3 Test Suite Coverage
All 22 unit tests across 5 test suites pass cleanly:
- `MockCatalogueTests` (3 tests)
- `PlanHandoffTests` (3 tests)
- `DiscoveryRankerTests` (5 tests)
- `DiscoveryHistoryTests` (2 tests)
- `SavedItemsCompatibilityTests` (9 tests)


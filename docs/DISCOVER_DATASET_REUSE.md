# Reusing the "2,933 routes / 6,995 places" dataset — what we'd need

_2026-11-02 · short report · nothing was contacted, copied or changed_

## What we actually know (from the screenshots only)

| Seen in the screenshots | Implies |
|---|---|
| "20 of **2933** routes · across India · ranked by riders"; "20 of **6995** places · ranked by mentions"; Scenic "20 of **838** places · within 500 km" | A catalogue large enough to page through, with some ranking signal |
| Region chips: All India · Ladakh · Spiti · Western Ghats · Kashmir · Uttarakhand | Places/routes carry a region field |
| "Permit needed", "Max 4,135 m", "Open Jun–Sep", "Expert / Easy" | Extra attributes exist (permit, altitude, season, difficulty). Their source and accuracy are unknown. |
| Map tiles credited "Map data ©2026 Google · Imagery ©2026 NASA" | Google Maps (SDK or Static Maps) is integrated somewhere |
| "★ 0.0 · 0 rides" on every card; "Spiti Valley · 0 km" | Ratings and distances aren't populated, so they're placeholders rather than real data |
| "Afternoon, Rishav", tab bar Home / Routes / Crew / Garage | It's Rishav's local build, a different app shell from ours |

## What we don't know

- Where the data lives: a bundled JSON, another Supabase project, a different schema, or a third-party API.
- Who created it, how, and under what licence. This includes the photos.
- How "ranked by riders" and "ranked by mentions" are computed.
- Whether route geometries are real road polylines, and for which vehicle.
- Whether any Google API keys exist, and where they're stored.

Searched with no result:
- **Git:** every branch on `emberwing-dash/Convoy` (`main`, `combined`, `siri`, `watch`, `feature/notifications-crew-caching`).
- **Folders:** the four other Convoy folders on this Mac, and `Ridee`.
- **Figma:** the Convoy Figma file.
- **Supabase:** our project `avykoruhcgwpmvmddlta`, probed read-only with the app's publishable key. No `places`, `routes` or `discover_*` tables are exposed.

## What reuse would require

1. **Repository access.** Rishav pushes the work to a branch on `emberwing-dash/Convoy`, or shares read access to wherever it lives. We need:
   - the data loader;
   - the models;
   - the Google Maps integration;
   - how config and keys are loaded.

   I'd inspect it before reusing anything.
2. **Database access.** The backend name, the schema (a `pg_dump --schema-only` is enough to start), row counts and RLS policies. Read-only access is enough.
3. **Provenance and licensing. This decides whether reuse is possible at all.**
   - **Origin of the place and route data.** Google Places content generally can't be stored long-term beyond the `place_id`; OpenStreetMap is ODbL with attribution; Wikidata is CC0; copying from blogs or other apps is not allowed.
   - **Photo source, author and licence for each image.** Every photo must carry its credit in the UI.
   - **Basis for "Permit needed", altitude and season.** We'd need a source per field, or we hide the field.
4. **API configuration.**
   - Which Google products are used: the Maps SDK for iOS, Static Maps, Places (New), Routes.
   - Which key is used in the app, restricted to the iOS bundle ID.
   - Which keys are server-only (Supabase Edge Function secrets).
   - Billing alerts and quotas.

   No unrestricted keys may be in source.
5. **Data mapping to the proposed model.** Fields not in this table would be dropped.

   | Their field (expected) | Discover v2 | Rule |
   |---|---|---|
   | place id / name / lat-lon / region / type | `DiscoverPlace.provider_place_id, name, lat, lon, region, category` | Dedupe by ID or within 150 m; reject invalid coordinates |
   | images | `images[] {url, author, licence, source}` | No credit means no photo; show the map instead |
   | permit / season / max altitude / difficulty | `tags[]` with `verification_status` | Shown only when sourced |
   | "ranked by mentions / riders" | `popularity_score`, `fame_score` | Only if computed from real counts; "0 ★ / 0 rides" fields are dropped |
   | route start / end / geometry | `DiscoverRoute.start, end, encoded_polyline` | Re-validated with Routes API `TWO_WHEELER`; unverifiable geometry is excluded |
   | stored distance / time | — | Not reused. Recomputed per origin with two-wheeler routing. |
6. **Validation run before go-live:**
   - dedupe;
   - check that each photo matches its place (sample review);
   - drop permanently closed places;
   - check that each geometry snaps to roads;
   - report how many records survive.

## Recommendation

Discover v2 doesn't depend on this dataset. Stage 5 puts every source behind a `DiscoverRepository` interface, so the dataset can be plugged in as one more source once items 1–3 are answered. The fastest unblock is Rishav pushing his branch and stating where the data and photos came from.

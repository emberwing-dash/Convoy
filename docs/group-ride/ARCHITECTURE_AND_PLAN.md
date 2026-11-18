# Group ride session — architecture review, plan and test guide

Branch: `feature/group-ride-session` · checkpoint commit `7a8fbb5` · tag `backup/pre-group-ride-session`
Rollback: `git switch feature/chatbot-production-hardening` (untouched) or `git reset --hard backup/pre-group-ride-session` on this branch.

## 1. What was there (review)

| Concern | Where | Problem |
|---|---|---|
| GPS for the ride | `RideNavView.onAppear/onDisappear` → `LocationService` | Tracking started and **stopped by the screen**. Leaving the map (chat, Home, a notification) stopped GPS. `allowsBackgroundLocationUpdates` was never set, so a locked phone stopped too. |
| Live location | `RideLiveLocationManager` | Broadcasts were **never parsed** (the SDK delivers `{event, payload:{…}}`, the code decoded the outer object). Riders only appeared because every update was *also* sent as Presence (`track`) — 2 messages per update, the useful one being the heavy one. No stale handling, public channel. |
| Pack alerts | `RallyCoordinator` | Straight-line distance to a mid point; only the rider concerned was told; Debug builds used a 15 m circle; others' direction came from the compass. |
| Turn-by-turn | `RoutePlanner`, `RideNavView` | Step position = `MKPolyline.coordinate` (centre of the step), so prompts and step changes were relative to the wrong point; straight-line distance to the turn. |
| End of ride | `RideNavView.finish()` | Organiser decided by **display name**; a rider with the organiser's name got stuck; other riders were never stopped. |
| Stops | `RideNavView` `@State stop` | Local only — nobody else knew. |

## 2. New architecture

```
                 ┌──────────────────────── ActiveRideSession (singleton, @MainActor) ───────────────────────┐
 Start ride ───► │ lifecycle: idle → active → ending → ended         owns for the whole ride:                  │
 (AppState)      │  • LocationService ride mode (background GPS, CLBackgroundActivitySession, guards)        │
                 │  • RideLiveLocationManager (one Realtime channel: positions + ride events)                │
 any screen ◄─── │  • RallyCoordinator (pack status for every rider + alerts)                                 │
 (status pill)   │  • RideRecorder (distance/time)                                                            │
                 │  • shared stops, ride events feed, completion watcher, network monitor, scenePhase         │
                 └────────────────────────────────────────────────────────────────────────────────────────────┘
 RideNavView only *displays* the session. Leaving it changes nothing. The session ends only on:
 organiser "End ride for everyone" · rider "Leave ride" · server says ride completed · sign-out.
```

Files:
- `Services/RideSession/ActiveRideSession.swift` — the session (new).
- `Services/RideSession/RideEvents.swift` — event model, in-app event feed, shared stops (new).
- `Services/RideSession/NavProgress.swift` — along-route maneuver maths (new, unit-tested).
- `Services/RideLiveLocationManager.swift` — rewritten transport (same public type).
- `Screens/Nav/RallyCoordinator.swift` — algorithm v2 (pure part unit-tested).
- `Screens/Nav/RideSessionViews.swift` — status pill, tracking chip, event banners, dev settings (new).
- `Services/LocationService.swift` — ride mode + background config.
- `Screens/Nav/RideNavView.swift` — uses the session; no GPS stop on disappear; shared stops; riders status; end/leave.
- `Services/RoutePlanner.swift` — maneuver point = first point of the step.
- `Services/NotificationService.swift` — new ride kinds; foreground presentation rules.
- `App/AppState.swift`, `App/MainShell.swift` — start/end through the session; global pill.
- `supabase/migrations/20261118010000_ride_live_location_private.sql` — Realtime authorization (**not deployed**).

## 3. Pack algorithm v2 ("gap chain")

Real ride captains manage the *gaps between riders* ("keep the rider behind you in your mirror"), not a circle.

1. Fresh positions only (≤ 45 s old, own GPS accuracy ≤ limit), lightly smoothed (existing smoothing kept).
2. Order riders by **distance along the planned route** (projection onto the route polyline). If someone is off the
   route, that rider falls back to along-track distance on the pack's direction of travel; the others keep their
   route position — one rider off-route no longer degrades everyone.
3. Walk the ordered list. Wherever the along-route gap between two consecutive riders exceeds **G** the convoy is
   split into groups.
4. The **main group** is the largest group; ties → the group containing the organiser; then the front-most group.
5. Riders in a group behind the main group are **behind** (gap = to the main group's last rider); in front, **ahead**.
6. Hysteresis/cooldown from v1 are kept: sustained 15 s (test 3 s), re-arm after being back for 20 s, repeat at most
   every 5 min, never more than one alert per minute (test: 10 s).

| | Test profile (2 phones) | Road profile |
|---|---|---|
| Split gap G | **25 m** | 800 m |
| Re-join margin | 5 m | 150 m |
| Sustain | 3 s | 15 s |
| Max GPS error used | 100 m | 150 m |
| GPS-noise discount | 0.7 × combined accuracy | same |

With two phones: walk them **about 50–60 m apart** (phone GPS is often ±20–35 m, and that error is discounted
from the gap so two phones side by side never count as split). Both get the alert within ~5 s; walk back together
and it clears.

Who is told:
- the rider who is behind/ahead → banner + voice (if voice on) + time-sensitive notification when the app isn't open;
- the **organiser** → "Ravi is 1.2 km behind" (or "the group split") on their phone, same rules;
- everyone → status tag on the Riders panel and on the map marker (Behind · 1.2 km / Ahead / With group / Delayed / Offline).

## 4. Live-location transport

- One channel per ride: `ride_location_<ride id>`. Positions are **broadcast only** (parsed correctly now).
  Presence is tracked **once** (identity) so joins/leaves are visible; it is no longer re-sent with every update.
- Send rate: every ~2 s while moving (≥ 5 m), every 10 s heartbeat when stationary. Payload adds `course`,
  `accuracy` (optional fields — older apps still decode it).
- Freshness on receivers: **Live** < 12 s · **Delayed** < 45 s · **Offline** ≥ 45 s → hidden from the map, shown
  as Offline in the panel; speed is never shown for non-live riders.
- Ride events on the same channel: `stop_added`, `stop_removed`, `ride_ended`, `rider_arrived`, `rider_left`.
- Only accepted riders of the ride are accepted as senders (checked against the ride's members, refreshed when an
  unknown id appears).
- Reconnect: channel status is watched; on drop it re-subscribes with backoff; network changes (NWPathMonitor)
  and returning to the foreground force a resync. Status shown honestly: Live / Reconnecting / Offline.

Realtime messages for 10 riders × 2 h: about 10 × 3 600 × 9 ≈ **325 k** (was ≈ 860 k).

## 5. Privacy (Realtime authorization)

Migration `20261118010000_ride_live_location_private.sql` (written, **not applied**):
- `public.can_access_ride_topic(topic text)` — true only when `auth.uid()` is an **accepted member** of the ride in
  the topic name.
- RLS policies on `realtime.messages` for `authenticated`: SELECT (receive) and INSERT (send) for broadcast and
  presence, only on `ride_location_*` topics the user may access. Nothing for `anon`.
- App switch: `app_config.live_location = {"private": true|false}`. The app joins the channel as **private** when
  true. Keep false until the migration is deployed, then flip (no app release). Finally disable "Allow public
  access" for Realtime in the dashboard so public channels can't be used at all.
- Limitation (honest): RLS authorizes *who may join/send on a ride*. It does not check the `userId` inside each
  message; receivers ignore senders that aren't accepted members, but a member could still impersonate another
  member's marker. Fixing that needs a server relay (not free-tier friendly) — documented, not done.

## 6. Turn-by-turn

- Maneuver point = **first** coordinate of each step's polyline (`RoutePlanner.navSteps(from:)`), used everywhere.
- `NavProgress`: projects the rider onto the route and measures **along-route** distance to the maneuver; the next
  instruction only appears after the maneuver point has actually been passed.
- Estimated (corridor) routes: the app tries Apple Maps for real steps; if that fails it says
  "Approximate route — no turn-by-turn" and gives no turn prompts.

## 7. End / leave

- Organiser (by **account id**): "End ride for everyone" → `complete_group_ride` → broadcast `ride_ended` → every
  phone stops navigation/sharing and opens the ride summary. Riders who were offline are stopped by the completion
  watcher (checks `rides.is_completed` on reconnect/foreground and every 60 s).
- Rider: "Leave ride" → stops only their own session; the group continues. Never calls the group closure.
- If closing fails (no network) nothing is stopped and the organiser sees "Couldn't end the ride — try again".

## 8. Test guide (2 iPhones, Debug build)

Debug builds start in the **test profile (25 m)**, shown as a "TEST 25 m" chip on the map. **Tap** the chip to
choose Test or Road; the choice applies to every phone on the ride. Release builds are always Road.

Before you start:
- Test **outdoors**. Phone GPS is often ±20–35 m; that error is discounted from the gap, so indoors (±65 m+)
  alerts are unlikely to fire — the map then shows "Weak GPS".
- An alert needs a split of more than **25 m after the GPS-noise discount**, held for **3 s**. Walk about **50–60 m apart**.
- Both phones must be *accepted* riders of the same ride and both must open the ride map once (that starts their
  session; after that they can switch screens or lock the phone).
- Allow location "While Using" and keep **Precise Location** on. The blue location pill in the status bar while the
  app is in the background means sharing is still running.
- During a ride, other screens show a pill on the tabs and a round button on pushed screens: green = sharing live,
  amber = reconnecting / weak GPS, red = location off or no internet. Tap either to get back to the map.

1. Both phones: same ride, both accepted. Organiser taps Start → rider gets "ride started" → opens live map.
2. Both on the map: Riders panel shows both "With group · Live".
3. Walk ~50–60 m apart: within ~5 s both get the alert; organiser also gets "X is behind/ahead".
4. Lock one phone for 2 min while walking: the other phone keeps seeing it move (blue location pill on the locked
   phone's status bar). Alerts arrive on the lock screen.
5. Switch to Home / Chat / Crew: the "Ride live" pill stays; tap it to return. Positions keep flowing.
6. Airplane mode 30 s on one phone: the other shows Delayed → Offline; turning it back reconnects automatically.
7. Add a stop (Fuel) on one phone: the other gets a stop card + notification, the pin appears on its map.
8. SOS: unchanged behaviour (critical push to the others).
9. Rider "Leave ride": only that phone stops; organiser sees them Offline / "left".
10. Organiser "End ride for everyone": both phones stop and show the summary.
11. Two riders with the same display name: statuses and "YOU" stay correct (matched by id).

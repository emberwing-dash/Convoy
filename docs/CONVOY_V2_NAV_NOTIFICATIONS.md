# Convoy v2: Navigation branch merge, notifications, rider separation

_16 Nov 2026 · branch `discover-v2` (local only, nothing committed or pushed)_

This brings the `origin/Navigation` work into the current app, which keeps the black-and-white UI. It also implements the five requirements and fixes the issues found along the way.

---

## 1. What came from the Navigation branch

The Navigation branch split from our branch 24 commits ago, so it was **not merged wholesale**. A full merge would have replaced the newer Crew feed, Home, Garage and theme work, and its `Database Schema.sql` drops tables with `CASCADE`. Only the parts listed below were brought in, using a 3-way merge so our newer changes in the same files were kept.

| From `origin/Navigation` | How it was brought in |
|---|---|
| `RideLiveLocationManager.swift` (live location sharing) | Copied **unchanged**. This is the working live-location code. |
| `RideNavView.swift`: live rider markers, "focus on convoy", riders sheet with live speed and distance, `currentRide`, shared start | 3-way merge. Our GPS ride recording and async `completeRide` were kept. |
| `NavParts.swift`: new top banner (back button above the turn card), rider map marker | 3-way merge, recoloured to the black-and-white palette (cyan `0x00D2FF` changed to white). |
| `RallyCoordinator.swift` | Taken as the starting point, then **rewritten** (section 6). |
| `CodeExtractor.swift` | Rewritten to handle crew codes (6–7 chars) and links inside text. |
| `ProfileSetupView.swift`: single `@`, no tick | Merged cleanly. |
| `StorageService.markRideActive` | Merged cleanly. |
| `PlanWhoView` avatar strip and invitee sheet | Re-implemented on our current `PlanWhoView` (15 conflicts made a merge unsafe). |
| `NotificationService` / `ConvoyAppDelegate` | Used as the base and rewritten (section 5). |

**Not brought over:** the branch's older Crew screens (`CrewFeedView`, `CrewHomeView`, `CrewLeaderboardView`, `PostComposerView`), which ours replace; the appearance toggle; the PlanDetails/PlanReview/PlanMap tweaks; the TabBar font change; `RiderProfileSheet`; and `Convoy/Schema/Database Schema.sql`, which is destructive and **was not run**. The branch also removed `NSCameraUsageDescription`, which would crash the QR scanner, so it was kept.

---

## 2. Requirement 1: onboarding handle

- The handle is stored **without** `@`; the text field's prefix draws the single `@`.
- The green tick inside the field is removed.
- Old handles saved as `@name` are cleaned up on launch (`AppState.init`) and at onboarding, so Profile no longer shows `@@name`.

## 3. Requirement 4: Who's riding?

- Above **Continue**, overlapping avatars show **everyone who will get the invite**: the selected crew's members plus the selected friends. You and duplicates are excluded, and pending crew invitees are skipped. Up to 5 avatars are shown, then a `+N` chip.
- The line reads "N riders invited". **See all** opens a bottom sheet with the full list; each rider shows the crew name or @handle that put them on the list.
- The list is computed from the current selection, so it updates whenever a crew or friend is selected or removed.
- Fixed: the checkmarks on selected friends were white on a white circle and invisible. They are now black.

## 4. Requirement 9: friends and crew joining/sharing

**Why crew links didn't work:** a rider who isn't in a crew isn't allowed to read that crew's row (RLS), so "find crew by code" always failed. Joining now goes through a server function.

- **Join a crew with a code:** Crew tab → **Join with code** (next to "Create a crew").
  - Enter or paste the code, or a whole shared message. The code is validated on the server, and the rider joins straight away.
  - Messages: invalid code; already a member; a pending invite gets accepted; a rider who declined before can rejoin; signed out; no network.
- **Tap to copy**, the same as Join Ride: the crew code card, the friend invite link (Add Friend) and the Invite Friends link are now `CopyLinkRow`s. One tap copies, with haptic feedback and a "Copied" state, and there is a share button next to it.
- **Links:**
  - `convoy://crew/<code>` opens the Join-crew screen with the code filled in; the rider confirms with one tap. Previously it silently created a pending row that no admin ever saw.
  - `convoy://friend/<handle>` opens Add Friend and searches that handle immediately.
- *Expired / already-used codes:* crew codes don't expire today (there is no expiry column). Reusing a code you've already joined with shows "You're already in …".

## 5. Requirement 11: notifications

### How it flows
```
event (friend request, crew invite, ride edit, SOS…)
  → DB trigger inserts into public.notifications      ← Home bell list (live via Realtime)
  → trigger copies it to notification_outbox           ← one row per notification (unique, no duplicates)
  → pg_cron every minute → edge function notify-outbox → APNs → lock screen
```
Navigation alerts ("slow down / catch up") and the "ride starts in 30 min" reminder are **local** notifications created on the phone.

### Events covered
| Area | Events | Who is notified |
|---|---|---|
| Ride invitations | invited to a ride | the invitee |
| Ride updates | date/time, route, meeting point or checkpoints changed (one alert per 10 min while editing) | riders on the ride |
| Ride status | started (organiser starts navigation), completed, cancelled (ride deleted), reminder 30 min before | riders |
| Join requests | request, accepted, declined (existing triggers, now also pushed) | organiser / requester |
| Crew | invite received, member joined (invite accepted or by code), member left | invitee / crew admins and the inviter |
| Friends | friend request, request accepted, new follower | the other rider |
| Community | likes, comments, a rider you follow shares a ride | post author / followers |
| Navigation | ahead of / behind the group (section 6) | the rider themselves |
| SOS | **Alert my convoy** button on the SOS screen | everyone on the ride, **critical / time-sensitive** |
| Achievements | 100 / 500 / 1,000 / 2,500 / 5,000 / 10,000 km milestones; monthly top-10 leaderboard (1st of the month, 09:00 UTC) | the rider |
| Chat | **not built.** The app has no chat feature or table yet. Add a trigger when chat exists. | — |

### App side
- **Permission** is asked once after onboarding. The APNs token is stored with `register_device_token`; a token moves to whichever account signs in on that phone, and it is removed on sign-out.
- **Foreground:** banners show while the app is open, and the bell list refreshes immediately.
- **Background or closed:** delivered by APNs.
- **Taps** open the right screen (ride details, crew, notifications list, or back to navigation for pack alerts), including from a cold start.
- **Home bell fix:** friend requests and crew invites weren't in the live table, so Home only noticed them on a manual refresh. They now create live rows, and any live event reloads the whole list (requests, invites and inbox). The app icon badge now matches the unread count.
- **Preferences:** Notifications → ⚙︎ gives on/off switches for Rides, Crews, Friends, Community, Navigation alerts and Achievements, plus a master switch. They are saved in `notification_prefs`, and the server checks them before queuing a push. **SOS is always delivered.**
- The bell list shows all new types with their own icon, tag and action ("Open ride", "Open live map", …). The icons on white badges were drawn white and were invisible; they are now black.
- **Duplicates prevented by:** de-duplication in `notify_user`, a unique `notification_id` in the outbox, `apns-collapse-id`, rows claimed before sending, and a fixed id for pack alerts.

### ⚠️ Setup needed before pushes reach real phones
1. **Xcode → Signing & Capabilities:** confirm **Push Notifications** is present. I added `Convoy.entitlements` (`aps-environment = development`) and wired it into the target. A *paid* Apple developer team is required: if the team is a free personal team, device builds will fail signing. In that case, remove the `CODE_SIGN_ENTITLEMENTS` line and the in-app and local notifications still work.
2. **Apple Developer → Keys:** create an APNs key (.p8).
3. **Supabase → Edge Functions → Secrets:** `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (the .p8 contents), `APNS_TOPIC` = `com.joydip.Convoy`.

Until step 3 is done, pushes wait in the outbox; nothing is lost or retried in a loop. The in-app list, realtime updates and local alerts work without it. The simulator can't receive real APNs pushes.

## 6. Requirement 13: rider separation (core navigation)

`Screens/Nav/RallyCoordinator.swift`. **Live location sharing is unchanged:** this code only *reads* `RideLiveLocationManager` and `LocationService`. The circle is never drawn, and map markers are unchanged.

**Algorithm (every 5 s, during a ride):**
1. Collect positions: your GPS fix (skipped if accuracy is worse than 80 m) and every other rider's broadcast (skipped if older than 45 s). Small jitter is smoothed; large jumps are taken as they are.
2. Order riders by **progress in the direction of travel**:
   - distance along the planned route when everyone is within 300 m of it;
   - otherwise along the pack's average heading (circular mean of riders moving faster than 5 km/h);
   - otherwise along the bearing to the destination.
3. The **middle rider** is the centre, and their position is the midpoint. With an even number of riders, the midpoint is halfway between the two middle riders.
4. **Haversine** distance from the midpoint. More than **500 m** (a 1 km circle) means outside: *ahead* if further along than the centre, *behind* otherwise.
5. Each phone alerts **its own rider** ("Slow down — you're ahead" / "Catch up — you're behind"): an in-ride banner plus a system notification, which also works in the background thanks to background location.

**Avoiding false or repeated alerts:**
- The rider must be outside for 15 s before the first alert.
- **Re-entry** only counts once back inside by 60 m (a 440 m radius) for 20 s. After that, leaving again fires a new alert.
- While a rider stays outside, the reminder repeats at most every **5 min**, and never more often than once per minute.
- Works for any number of riders, and for 2 or more.
- No extra GPS work: it reuses the navigation location stream, and the 5 s recompute is cheap.

Unit tests (`ConvoyTests/RallyAndCodesTests.swift`) cover: haversine accuracy, everyone inside, head and tail flagged, direction taken from heading rather than latitude, ordering by route progress on a bend, the 2-rider midpoint, and a single rider having no pack.

---

## 7. Supabase changes (all applied to project `avykoruhcgwpmvmddlta`)

Migrations: `notifications_v2`, `notifications_v2_body_fix`, `notifications_v2_ride_changes_fix`. The file is `supabase/migrations/20261116120000_notifications_v2.sql`. **Additive only: no tables dropped, no rows deleted.**

| Change | Type |
|---|---|
| `notifications`: new `crew_id` column; `kind` check widened; index on (recipient, created_at) | edit |
| `notification_prefs` table plus an RLS policy so each user manages only their own row | **new** |
| `notification_outbox`: `notification_id` (unique), `priority`, `attempts`, `last_error` | edit |
| `notify_user()`, `notification_category()`, `fanout_notification_push()` plus a trigger on `notifications` | **new** |
| Triggers on `friendships`, `crew_members`, `ride_members`, `rides` (update and delete), `sos_events`, `feed_posts`, `ride_logs` | **new** |
| `join_crew_by_code(code)`, `mark_ride_started(ride)`, `register_device_token`, `unregister_device_token` | **new** RPCs |
| `notify_monthly_leaderboard()` plus pg_cron job `monthly-leaderboard-notifications` | **new** |
| `raise_sos()`: **bug fix**; it wrote to `sos_alerts`, which doesn't exist. Now writes to `sos_events`, max one per minute | edit |
| `my_notifications()`: also hides `friend_request` / `crew_invite` (the app lists those with Accept/Decline) | edit |
| `enqueue_notification()`: **security fix**; it was callable by anyone, including signed-out users, and could push any text to any rider. Now server-only | permission |
| Edge function `notify-outbox` v2: priority and time-sensitive, collapse-id, claim-before-send, 5 retries max, removes dead tokens | redeployed |

Two bugs in my first version were caught by the smoke test and fixed before any real use: a NULL `body` and an array append. The smoke tests ran inside transactions that were rolled back, so no test data was left.

To undo: drop the new triggers and functions listed above, then `drop table notification_prefs`. The added columns are harmless to keep.

---

## 8. Where the app stands

**Working (built, 108/108 tests passing):**
- Group navigation with live rider markers and focus-on-convoy.
- The riders sheet shows live speed and distance.
- Separation alerts.
- An active ride resumes after an app restart.
- SOS alerts the convoy.
- The full notification pipeline, in-app and live.
- Join or share crews by code.
- The friend link opens the search.
- Who's riding avatars and sheet.
- The onboarding handle fix.

**Needs you:**
- The APNs key and secrets, and confirming the Push capability (section 5).
- Test on two or more real phones riding together. The separation logic is unit-tested, but not tested on the road.

**Not done / ideas next:**
- Chat notifications (needs a chat feature).
- Crew announcements (needs an announcements table).
- Crew code expiry (needs an `expires_at` column).
- A notification to the *organiser* when someone drifts.
- Showing ahead/behind status in the riders sheet (`RallyCoordinator.lastResult` already has it).

**Files touched (app):** `App/AppState.swift`, `App/ConvoyApp.swift`, `App/MainShell.swift`, `App/RootView.swift`, `App/SocialStore.swift`, `Models/Models.swift`, `Models/Social.swift`, `Services/{NotificationService, ConvoyAppDelegate, CodeExtractor, RideLiveLocationManager, SupabaseManager, StorageService}.swift`, `Screens/Nav/{RideNavView, NavParts, RallyCoordinator}.swift`, `Screens/Plan/PlanWhoView.swift`, `Screens/Onboarding/ProfileSetupView.swift`, `Screens/Join/{JoinCrewView, JoinCodeView}.swift`, `Screens/Home/{NotificationView, NotificationSettingsView, UserSearchView}.swift`, `Screens/Crew/{CrewView, CrewInviteViews, InviteFriendsView}.swift`, `Components/Social/CopyLinkRow.swift`, `Info.plist`, `Convoy.entitlements`, `project.pbxproj`, `ConvoyTests/RallyAndCodesTests.swift`.

A backup of the working tree from before this work is on local branch `backup-bw-theme-2026-11-16`.

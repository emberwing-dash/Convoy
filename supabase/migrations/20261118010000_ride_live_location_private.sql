-- 20261118010000_ride_live_location_private.sql
-- Live ride locations: Realtime Authorization for PRIVATE ride channels.
--
-- STATUS: NOT APPLIED. Apply only after review/approval (see docs/group-ride/LIVE_LOCATION_PRIVACY_ROLLOUT.md).
-- (Renamed from 20261118000000_…: that version number is already used by restore_crew_backend.sql.)
--
-- What it does — additive only, nothing existing is altered or dropped:
--   1. public.can_access_ride_topic(text): true only when the signed-in user (auth.uid()) is an ACCEPTED
--      member of the ride named in the topic "ride_location_<ride uuid, lower case>". Display names are
--      never used.
--   2. Two RLS policies on realtime.messages for the `authenticated` role:
--        SELECT = may receive broadcast/presence on that topic (join + listen),
--        INSERT = may send broadcast / track presence on that topic.
--      There are no other policies on realtime.messages today (checked 2026-11-17), so nothing combines
--      with these. `anon` gets no policy → denied. service_role bypasses RLS (server-side sends only).
--   3. app_config row 'live_location' = {"private": false}. The app joins ride channels as private only
--      when this is true, so applying the migration changes nothing for riders until you flip it.
--
-- These policies only apply to channels joined with private: true. They do not affect public channels,
-- Postgres Changes (inbox notifications use table RLS) or any table.
--
-- Authorization is checked by Realtime when a client joins (and when its access token is refreshed); a
-- rider removed from a ride mid-ride keeps the connection they already have until it reconnects or the
-- token refreshes (max ~1 hour).
--
-- ROLLBACK (safe in any order; run in the SQL editor):
--   update public.app_config set value = '{"private": false}', updated_at = now() where key = 'live_location';
--   drop policy if exists "ride members receive live ride messages" on realtime.messages;
--   drop policy if exists "ride members send live ride messages" on realtime.messages;
--   drop function if exists public.can_access_ride_topic(text);
--   delete from public.app_config where key = 'live_location';   -- optional

create or replace function public.can_access_ride_topic(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- CASE (not AND) so the uuid cast is only attempted on a well-formed topic: AND gives no
  -- evaluation-order guarantee, and a failed cast would raise an error instead of returning false.
  select case
    when p_topic is not null
     and p_topic ~ '^ride_location_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then exists (
      select 1
      from public.ride_members m
      where m.user_id = (select auth.uid())
        and m.status = 'accepted'
        and m.ride_id = (substring(p_topic from 15))::uuid
    )
    else false
  end
$$;

comment on function public.can_access_ride_topic(text) is
  'Realtime Authorization: true when auth.uid() is an accepted member of the ride in topic ride_location_<uuid>.';

revoke all on function public.can_access_ride_topic(text) from public, anon;
grant execute on function public.can_access_ride_topic(text) to authenticated;

-- Receive (join + listen) broadcast and presence on a ride's private live channel.
drop policy if exists "ride members receive live ride messages" on realtime.messages;
create policy "ride members receive live ride messages"
  on realtime.messages
  for select
  to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and public.can_access_ride_topic((select realtime.topic()))
  );

-- Send broadcast and track presence on a ride's private live channel.
drop policy if exists "ride members send live ride messages" on realtime.messages;
create policy "ride members send live ride messages"
  on realtime.messages
  for insert
  to authenticated
  with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and public.can_access_ride_topic((select realtime.topic()))
  );

-- App switch, read when a ride starts. Starts OFF; flip it after testing (see the rollout doc).
insert into public.app_config (key, value)
values ('live_location', '{"private": false}')
on conflict (key) do nothing;

-- 20261116120000_notifications_v2.sql
-- Convoy notifications v2: every important event becomes an in-app notification
-- (public.notifications, shown on Home → Notifications, live over Realtime) AND a push
-- (public.notification_outbox → `notify-outbox` edge function → APNs, run every minute by pg_cron).
--
-- Additive only: no table is dropped, no existing row is deleted.
--
-- What it adds / changes
--   notifications          + crew_id column, more `kind` values (friend/crew/ride/sos/community/achievement)
--   notification_prefs     NEW  per-user push preferences (categories on/off)
--   notification_outbox    + notification_id (unique → no duplicate pushes), priority, attempts, last_error
--   triggers               friendships, crew_members, ride_members, rides, sos_events, feed_posts, ride_logs
--                          now create notifications; every notification fans out to the push outbox
--   join_crew_by_code()    NEW  join a crew with its code (validates, handles already-member / invited)
--   mark_ride_started()    NEW  organiser starts a ride → riders are told
--   register_device_token() / unregister_device_token()  NEW  safe APNs token storage
--   raise_sos()            FIX  wrote to a table that doesn't exist (sos_alerts) → now sos_events
--   my_notifications()     friend requests / crew invites excluded (the app lists those with Accept/Decline)
--   enqueue_notification() no longer callable by app users (it let any user push any text to anyone)

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. notifications: new kinds + crew link
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind = any (array[
  'ride_join_request','ride_join_accepted','ride_join_declined',
  'new_follower','post_like','post_comment','new_post',
  'friend_request','friend_accepted',
  'crew_invite','crew_joined','crew_member_left',
  'ride_invite','ride_updated','ride_started','ride_completed','ride_cancelled',
  'sos','achievement'
]));
alter table public.notifications add column if not exists crew_id uuid references public.crews(id) on delete cascade;
create index if not exists notifications_recipient_created_idx on public.notifications (recipient_id, created_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Push preferences (one row per user; missing row = everything on)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.notification_prefs (
  user_id      uuid primary key references public.profiles(id) on delete cascade,
  push_enabled boolean not null default true,
  rides        boolean not null default true,
  crews        boolean not null default true,
  friends      boolean not null default true,
  community    boolean not null default true,
  navigation   boolean not null default true,
  achievements boolean not null default true,
  updated_at   timestamptz not null default now()
);
alter table public.notification_prefs enable row level security;
drop policy if exists prefs_own on public.notification_prefs;
create policy prefs_own on public.notification_prefs for all
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Outbox: de-duplication, priority, retry bookkeeping
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.notification_outbox add column if not exists notification_id uuid;
alter table public.notification_outbox add column if not exists priority text not null default 'normal';
alter table public.notification_outbox add column if not exists attempts int not null default 0;
alter table public.notification_outbox add column if not exists last_error text;
create unique index if not exists notification_outbox_notification_uidx
  on public.notification_outbox (notification_id) where notification_id is not null;
create index if not exists notification_outbox_pending_idx
  on public.notification_outbox (created_at) where sent_at is null and cancelled = false;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Helpers
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.notification_category(p_kind text)
returns text language sql immutable set search_path = '' as $$
  select case
    when p_kind = 'sos' then 'sos'
    when p_kind like 'ride_%' then 'rides'
    when p_kind like 'crew_%' then 'crews'
    when p_kind in ('friend_request','friend_accepted','new_follower') then 'friends'
    when p_kind in ('post_like','post_comment','new_post') then 'community'
    when p_kind = 'achievement' then 'achievements'
    else 'other' end
$$;

-- Inserts a notification unless an identical unread one was created recently.
create or replace function public.notify_user(
  p_recipient uuid, p_actor uuid, p_kind text,
  p_ride uuid default null, p_crew uuid default null, p_post uuid default null,
  p_body text default null, p_request uuid default null, p_dedupe interval default interval '10 minutes')
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_recipient is null or p_recipient = p_actor then return; end if;
  if exists (select 1 from public.notifications n
             where n.recipient_id = p_recipient and n.kind = p_kind
               and n.actor_id is not distinct from p_actor
               and n.ride_id is not distinct from p_ride
               and n.crew_id is not distinct from p_crew
               and n.post_id is not distinct from p_post
               and n.read_at is null
               and n.created_at > now() - p_dedupe) then
    return;
  end if;
  insert into public.notifications (recipient_id, actor_id, kind, ride_id, crew_id, post_id, request_id, body)
  values (p_recipient, p_actor, p_kind, p_ride, p_crew, p_post, p_request, coalesce(p_body, ''));  -- body is NOT NULL
end $$;
revoke all on function public.notify_user(uuid,uuid,text,uuid,uuid,uuid,text,uuid,interval) from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Fan-out: every new notification → one push in the outbox (respecting prefs)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fanout_notification_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor text; v_ride text; v_crew text; v_title text; v_body text;
  v_cat text := public.notification_category(new.kind);
  v_prefs public.notification_prefs;
  v_link text;
begin
  select * into v_prefs from public.notification_prefs where user_id = new.recipient_id;
  if found and v_cat <> 'sos' then
    if not v_prefs.push_enabled then return new; end if;
    if (v_cat = 'rides' and not v_prefs.rides) or (v_cat = 'crews' and not v_prefs.crews)
       or (v_cat = 'friends' and not v_prefs.friends) or (v_cat = 'community' and not v_prefs.community)
       or (v_cat = 'achievements' and not v_prefs.achievements) then
      return new;
    end if;
  end if;

  select coalesce(nullif(display_name, ''), username, 'A rider') into v_actor from public.profiles where id = new.actor_id;
  v_actor := coalesce(v_actor, 'A rider');
  select title into v_ride from public.rides where id = new.ride_id;
  select name into v_crew from public.crews where id = new.crew_id;
  v_ride := coalesce(v_ride, 'your ride');
  v_crew := coalesce(v_crew, 'your crew');

  case new.kind
    when 'ride_join_request'  then v_title := 'Ride join request';      v_body := v_actor || ' wants to join ' || v_ride || '.';
    when 'ride_join_accepted' then v_title := 'You''re in!';            v_body := v_actor || ' accepted you on ' || v_ride || '.';
    when 'ride_join_declined' then v_title := 'Ride request declined';  v_body := 'Your request to join ' || v_ride || ' wasn''t accepted.';
    when 'ride_invite'        then v_title := 'Ride invitation';        v_body := v_actor || ' invited you to ride ' || v_ride || '.';
    when 'ride_updated'       then v_title := 'Ride updated';           v_body := coalesce(nullif(new.body, ''), v_ride || ' was updated.');
    when 'ride_started'       then v_title := 'Ride started';           v_body := v_actor || ' started ' || v_ride || '. Open the live map.';
    when 'ride_completed'     then v_title := 'Ride complete';          v_body := v_ride || ' is done. See how it went.';
    when 'ride_cancelled'     then v_title := 'Ride cancelled';         v_body := coalesce(nullif(new.body, ''), 'A ride you were in was cancelled.');
    when 'sos'                then v_title := 'SOS — ' || v_actor || ' needs help'; v_body := coalesce(nullif(new.body, ''), 'Open Convoy to see their location.');
    when 'friend_request'     then v_title := 'Friend request';         v_body := v_actor || ' wants to be friends.';
    when 'friend_accepted'    then v_title := 'Friend request accepted';v_body := v_actor || ' accepted your friend request.';
    when 'new_follower'       then v_title := 'New follower';           v_body := v_actor || ' started following you.';
    when 'crew_invite'        then v_title := 'Crew invite';            v_body := v_actor || ' invited you to join ' || v_crew || '.';
    when 'crew_joined'        then v_title := 'New crew member';        v_body := v_actor || ' joined ' || v_crew || '.';
    when 'crew_member_left'   then v_title := 'Crew update';            v_body := v_actor || ' left ' || v_crew || '.';
    when 'post_like'          then v_title := 'New like';               v_body := v_actor || ' liked your post.';
    when 'post_comment'       then v_title := 'New comment';            v_body := v_actor || ': ' || coalesce(nullif(new.body, ''), '');
    when 'new_post'           then v_title := 'New from ' || v_actor;   v_body := coalesce(nullif(new.body, ''), v_actor || ' shared a ride.');
    when 'achievement'        then v_title := 'Achievement unlocked';   v_body := coalesce(nullif(new.body, ''), 'You reached a new milestone.');
    else                           v_title := 'Convoy';                 v_body := coalesce(nullif(new.body, ''), 'You have a new update.');
  end case;

  v_link := case
    when new.ride_id is not null then 'convoy://ride-details/' || new.ride_id
    when new.crew_id is not null then 'convoy://crew-detail/' || new.crew_id
    else 'convoy://notifications' end;

  insert into public.notification_outbox (user_id, kind, title, body, payload, notification_id, priority)
  values (new.recipient_id, new.kind, v_title, left(v_body, 240),
          jsonb_strip_nulls(jsonb_build_object(
            'notification_id', new.id, 'kind', new.kind, 'deep_link', v_link,
            'ride_id', new.ride_id, 'crew_id', new.crew_id, 'post_id', new.post_id, 'actor_id', new.actor_id)),
          new.id, case when new.kind = 'sos' then 'critical'
                       when new.kind in ('ride_started','ride_cancelled','ride_updated') then 'time_sensitive'
                       else 'normal' end)
  on conflict (notification_id) where notification_id is not null do nothing;
  return new;
end $$;

drop trigger if exists trg_fanout_notification_push on public.notifications;
create trigger trg_fanout_notification_push after insert on public.notifications
  for each row execute function public.fanout_notification_push();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Event triggers that create notifications
-- ─────────────────────────────────────────────────────────────────────────────

-- Friends
create or replace function public.notify_friendship()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    perform public.notify_user(new.receiver_id, new.sender_id, 'friend_request', p_dedupe => interval '1 day');
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    update public.notifications set read_at = coalesce(read_at, now())
     where recipient_id = new.receiver_id and actor_id = new.sender_id and kind = 'friend_request';
    if new.status = 'accepted' then
      perform public.notify_user(new.sender_id, new.receiver_id, 'friend_accepted');
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_notify_friendship on public.friendships;
create trigger trg_notify_friendship after insert or update on public.friendships
  for each row execute function public.notify_friendship();

-- Crews: invites, joins (invite accepted or code), members leaving
create or replace function public.notify_crew_membership()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  if tg_op = 'INSERT' then
    if new.status = 'pending' and new.invited_by is not null then
      perform public.notify_user(new.user_id, new.invited_by, 'crew_invite', p_crew => new.crew_id, p_dedupe => interval '1 day');
    elsif new.status = 'accepted' and new.role = 'member' then
      for r in select user_id from public.crew_members
               where crew_id = new.crew_id and role = 'admin' and status = 'accepted' and user_id <> new.user_id loop
        perform public.notify_user(r.user_id, new.user_id, 'crew_joined', p_crew => new.crew_id);
      end loop;
    end if;
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status = 'accepted' then
    update public.notifications set read_at = coalesce(read_at, now())
     where recipient_id = new.user_id and kind = 'crew_invite' and crew_id = new.crew_id;
    for r in select distinct user_id from public.crew_members
             where crew_id = new.crew_id and status = 'accepted' and user_id <> new.user_id
               and (role = 'admin' or user_id = new.invited_by) loop
      perform public.notify_user(r.user_id, new.user_id, 'crew_joined', p_crew => new.crew_id);
    end loop;
  elsif tg_op = 'DELETE' then
    -- Only a member leaving on their own, and only while the crew still exists (not a crew delete).
    if old.status = 'accepted' and old.user_id = (select auth.uid())
       and exists (select 1 from public.crews where id = old.crew_id) then
      for r in select user_id from public.crew_members
               where crew_id = old.crew_id and role = 'admin' and status = 'accepted' and user_id <> old.user_id loop
        perform public.notify_user(r.user_id, old.user_id, 'crew_member_left', p_crew => old.crew_id);
      end loop;
    end if;
    return old;
  end if;
  return new;
end $$;
drop trigger if exists trg_notify_crew_membership on public.crew_members;
create trigger trg_notify_crew_membership after insert or update or delete on public.crew_members
  for each row execute function public.notify_crew_membership();

-- Rides: invitations
create or replace function public.notify_ride_invite()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid;
begin
  if new.status = 'invited' then
    select organiser_id into v_org from public.rides where id = new.ride_id;
    perform public.notify_user(new.user_id, v_org, 'ride_invite', p_ride => new.ride_id, p_dedupe => interval '1 day');
  end if;
  return new;
end $$;
drop trigger if exists trg_notify_ride_invite on public.ride_members;
create trigger trg_notify_ride_invite after insert on public.ride_members
  for each row execute function public.notify_ride_invite();

-- Rides: date / time / route / meeting point / stops changed, ride completed
create or replace function public.notify_ride_changes()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r record; v_what text[] := '{}'; v_body text;
begin
  if new.is_completed is true and old.is_completed is not true then
    for r in select user_id from public.ride_members where ride_id = new.id and status = 'accepted' loop
      perform public.notify_user(r.user_id, new.organiser_id, 'ride_completed', p_ride => new.id, p_dedupe => interval '1 day');
    end loop;
    return new;
  end if;
  if coalesce(new.is_completed, false) then return new; end if;

  if new.departs is distinct from old.departs then v_what := array_append(v_what, 'date & time'); end if;
  if new.route_coords_json is distinct from old.route_coords_json or new.to_location is distinct from old.to_location then v_what := array_append(v_what, 'route'); end if;
  if new.from_location is distinct from old.from_location or new.start_lat is distinct from old.start_lat then v_what := array_append(v_what, 'meeting point'); end if;
  if new.stops_json is distinct from old.stops_json then v_what := array_append(v_what, 'checkpoints'); end if;
  if cardinality(v_what) = 0 then return new; end if;

  v_body := new.title || ': the organiser changed the ' || array_to_string(v_what, ', ') || '.';
  if new.departs is distinct from old.departs then
    v_body := v_body || ' Now ' || coalesce(nullif(new.display_date, ''), '') || ' ' || coalesce(nullif(new.display_time, ''), '') || '.';
  end if;
  for r in select user_id from public.ride_members where ride_id = new.id and status in ('accepted','invited') loop
    perform public.notify_user(r.user_id, new.organiser_id, 'ride_updated', p_ride => new.id,
                               p_body => btrim(regexp_replace(v_body, '\s+', ' ', 'g')), p_dedupe => interval '10 minutes');
  end loop;
  return new;
end $$;
drop trigger if exists trg_notify_ride_changes on public.rides;
create trigger trg_notify_ride_changes after update on public.rides
  for each row execute function public.notify_ride_changes();

-- Rides: deleted by the organiser → cancelled (notification keeps no ride link, the ride is gone)
create or replace function public.notify_ride_cancelled()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  if coalesce(old.is_completed, false) then return old; end if;
  for r in select user_id from public.ride_members where ride_id = old.id and status in ('accepted','invited') loop
    perform public.notify_user(r.user_id, old.organiser_id, 'ride_cancelled',
                               p_body => old.title || ' was cancelled by the organiser.', p_dedupe => interval '1 minute');
  end loop;
  return old;
end $$;
drop trigger if exists trg_notify_ride_cancelled on public.rides;
create trigger trg_notify_ride_cancelled before delete on public.rides
  for each row execute function public.notify_ride_cancelled();

-- Ride started (called by the organiser's app when they start navigation)
create or replace function public.mark_ride_started(p_ride_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); r record;
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  update public.rides set tag = 'Ongoing' where id = p_ride_id and organiser_id = v_uid;
  if not found then return; end if;  -- only the organiser announces the start
  for r in select user_id from public.ride_members where ride_id = p_ride_id and status = 'accepted' loop
    perform public.notify_user(r.user_id, v_uid, 'ride_started', p_ride => p_ride_id, p_dedupe => interval '6 hours');
  end loop;
end $$;
revoke all on function public.mark_ride_started(uuid) from public, anon;
grant execute on function public.mark_ride_started(uuid) to authenticated;

-- SOS: fix raise_sos (it inserted into a non-existent table) and alert the ride
create or replace function public.raise_sos(p_ride_id uuid, p_lat double precision, p_lon double precision, p_accuracy double precision)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_member boolean;
  v_id uuid;
  v_recent uuid;
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  v_member := p_ride_id is not null and exists (
    select 1 from public.ride_members where ride_id = p_ride_id and user_id = v_uid and status = 'accepted');
  -- One alert per rider per minute: repeated taps don't spam the group.
  select id into v_recent from public.sos_events
   where user_id = v_uid and created_at > now() - interval '1 minute' order by created_at desc limit 1;
  if v_recent is not null then
    return jsonb_build_object('sos_id', v_recent, 'status', 'already_sent', 'notified', v_member);
  end if;
  insert into public.sos_events (user_id, ride_id, lat, lon)
  values (v_uid, case when v_member then p_ride_id end,
          case when p_lat between -90 and 90 then p_lat end, case when p_lon between -180 and 180 then p_lon end)
  returning id into v_id;
  return jsonb_build_object('sos_id', v_id, 'status', 'recorded', 'notified', v_member);
end $$;
revoke all on function public.raise_sos(uuid,double precision,double precision,double precision) from public, anon;
grant execute on function public.raise_sos(uuid,double precision,double precision,double precision) to authenticated;

create or replace function public.notify_sos()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r record; v_body text;
begin
  if new.ride_id is null then return new; end if;
  v_body := case when new.lat is not null and new.lon is not null
                 then 'Last position ' || round(new.lat::numeric, 5) || ', ' || round(new.lon::numeric, 5) || '. Open Convoy to see them on the map.'
                 else 'Open Convoy to see their last position.' end;
  for r in select user_id from public.ride_members where ride_id = new.ride_id and status = 'accepted' and user_id <> new.user_id loop
    perform public.notify_user(r.user_id, new.user_id, 'sos', p_ride => new.ride_id, p_body => v_body, p_dedupe => interval '1 minute');
  end loop;
  return new;
end $$;
drop trigger if exists trg_notify_sos on public.sos_events;
create trigger trg_notify_sos after insert on public.sos_events
  for each row execute function public.notify_sos();

-- Community: a rider you follow shares a ride
create or replace function public.notify_new_post()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in select follower_id from public.follows where following_id = new.author_id limit 500 loop
    perform public.notify_user(r.follower_id, new.author_id, 'new_post', p_post => new.id,
                               p_body => left(coalesce(nullif(new.caption, ''), 'Shared a new ride.'), 140), p_dedupe => interval '1 hour');
  end loop;
  return new;
end $$;
drop trigger if exists trg_notify_new_post on public.feed_posts;
create trigger trg_notify_new_post after insert on public.feed_posts
  for each row execute function public.notify_new_post();

-- Achievements: distance milestones when a ride is logged
create or replace function public.notify_ride_milestone()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_total numeric; v_before numeric; m int;
begin
  select coalesce(sum(distance_m), 0) / 1000.0 into v_total from public.ride_logs where user_id = new.user_id;
  v_before := v_total - coalesce(new.distance_m, 0) / 1000.0;
  foreach m in array array[100, 500, 1000, 2500, 5000, 10000] loop
    if v_before < m and v_total >= m then
      insert into public.notifications (recipient_id, actor_id, kind, body)
      values (new.user_id, null, 'achievement', 'You''ve ridden ' || m || ' km with Convoy. Keep it rolling!');
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists trg_notify_ride_milestone on public.ride_logs;
create trigger trg_notify_ride_milestone after insert on public.ride_logs
  for each row execute function public.notify_ride_milestone();

-- Achievements: monthly leaderboard (top 10 by distance), run on the 1st of each month
create or replace function public.notify_monthly_leaderboard()
returns int language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0;
  v_from timestamptz := date_trunc('month', now()) - interval '1 month';
  v_to   timestamptz := date_trunc('month', now());
begin
  for r in select user_id, sum(distance_m) / 1000.0 km, rank() over (order by sum(distance_m) desc) rnk
             from public.ride_logs where started_at >= v_from and started_at < v_to
            group by user_id order by 3 limit 10 loop
    insert into public.notifications (recipient_id, actor_id, kind, body)
    values (r.user_id, null, 'achievement',
            'You finished #' || r.rnk || ' on the ' || to_char(v_from, 'FMMonth') || ' leaderboard with ' || round(r.km) || ' km.');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.notify_monthly_leaderboard() from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Join a crew with its code
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.join_crew_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_crew public.crews;
  v_member public.crew_members;
begin
  if v_uid is null then raise exception 'unauthenticated' using errcode = '28000'; end if;
  if length(v_code) < 4 then raise exception 'invalid_code' using errcode = 'P0001'; end if;
  select * into v_crew from public.crews where upper(code) = v_code;
  if not found then raise exception 'invalid_code' using errcode = 'P0001'; end if;

  select * into v_member from public.crew_members where crew_id = v_crew.id and user_id = v_uid;
  if found then
    if v_member.status = 'accepted' then
      return jsonb_build_object('crew_id', v_crew.id, 'name', v_crew.name, 'status', 'already_member');
    elsif v_member.status = 'pending' then
      update public.crew_members set status = 'accepted' where id = v_member.id;   -- accepting a waiting invite
    else
      delete from public.crew_members where id = v_member.id;                     -- declined before: rejoin
      insert into public.crew_members (crew_id, user_id, role, status) values (v_crew.id, v_uid, 'member', 'accepted');
    end if;
  else
    insert into public.crew_members (crew_id, user_id, role, status) values (v_crew.id, v_uid, 'member', 'accepted');
  end if;
  return jsonb_build_object('crew_id', v_crew.id, 'name', v_crew.name, 'status', 'joined');
end $$;
revoke all on function public.join_crew_by_code(text) from public, anon;
grant execute on function public.join_crew_by_code(text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Device tokens
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.register_device_token(p_token text, p_environment text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  if p_token !~ '^[0-9a-fA-F]{32,200}$' then raise exception 'invalid token'; end if;
  -- A phone belongs to one signed-in account: drop the token from anyone else.
  delete from public.device_tokens where apns_token = lower(p_token) and user_id <> v_uid;
  insert into public.device_tokens (user_id, apns_token, environment, platform, updated_at)
  values (v_uid, lower(p_token), case when p_environment = 'sandbox' then 'sandbox' else 'production' end, 'ios', now())
  on conflict (user_id, apns_token) do update set environment = excluded.environment, updated_at = now();
end $$;
revoke all on function public.register_device_token(text,text) from public, anon;
grant execute on function public.register_device_token(text,text) to authenticated;

create or replace function public.unregister_device_token(p_token text)
returns void language sql security definer set search_path = '' as $$
  delete from public.device_tokens where apns_token = lower(p_token) and user_id = (select auth.uid());
$$;
revoke all on function public.unregister_device_token(text) from public, anon;
grant execute on function public.unregister_device_token(text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Lock down enqueue_notification (was executable by anon + any user → push spam)
-- ─────────────────────────────────────────────────────────────────────────────
revoke all on function public.enqueue_notification(uuid,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.enqueue_notification(uuid,text,text,text,jsonb) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. In-app inbox: requests with Accept/Decline are listed by the app itself
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.my_notifications(p_limit integer default 50)
returns table(id uuid, kind text, created_at timestamptz, read_at timestamptz, body text, actor_id uuid,
              actor_name text, actor_username text, actor_avatar text, ride_id uuid, ride_title text,
              request_id uuid, post_id uuid, i_follow_actor boolean)
language sql stable security definer set search_path to 'public' as $$
    select n.id, n.kind, n.created_at, n.read_at, n.body, n.actor_id, p.display_name, p.username, p.avatar_data,
           n.ride_id, r.title, n.request_id, n.post_id,
           exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.followee_id = n.actor_id)
    from public.notifications n
    left join public.profiles p on p.id = n.actor_id
    left join public.rides r on r.id = n.ride_id
    where n.recipient_id = auth.uid() and n.kind not in ('ride_join_request','friend_request','crew_invite')
    order by n.created_at desc
    limit least(greatest(p_limit, 1), 100);
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. Monthly leaderboard job (1st of the month, 09:00 UTC)
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
  if exists (select 1 from cron.job where jobname = 'monthly-leaderboard-notifications') then
    perform cron.unschedule('monthly-leaderboard-notifications');
  end if;
  perform cron.schedule('monthly-leaderboard-notifications', '0 9 1 * *', 'select public.notify_monthly_leaderboard();');
end $$;

commit;

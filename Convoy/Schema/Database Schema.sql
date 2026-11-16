-- =========================================================================
-- CONVOY — FULL SCHEMA RESET (v2)
-- =========================================================================
-- Drop everything Convoy-owned and rebuild from scratch, including all v2
-- additions (follows, posts, leaderboards, notifications, device tokens).
-- Destructive. Idempotent. Safe to re-run.
-- =========================================================================

begin;

-- =========================================================================
-- 0. DROP EVERYTHING (children → parents → enums)
-- =========================================================================

-- v2 tables (reference profiles, crews, rides)
drop table if exists public.notification_outbox  cascade;
drop table if exists public.device_tokens        cascade;
drop table if exists public.leaderboard_monthly  cascade;
drop table if exists public.post_comments        cascade;
drop table if exists public.post_likes           cascade;
drop table if exists public.posts                cascade;
drop table if exists public.follows              cascade;

-- original tables (order matters for FK chains)
drop table if exists public.sos_events   cascade;
drop table if exists public.ride_media   cascade;
drop table if exists public.ride_members cascade;
drop table if exists public.rides        cascade;
drop table if exists public.fill_ups     cascade;
drop table if exists public.saved_routes cascade;
drop table if exists public.crew_members cascade;
drop table if exists public.crews        cascade;
drop table if exists public.friendships  cascade;
drop table if exists public.profiles     cascade;

-- v2 enums
drop type if exists public.post_kind       cascade;
drop type if exists public.post_visibility cascade;

-- v2 fix — drop every Convoy function so CREATE OR REPLACE has a clean
-- slate. Without this, PostgreSQL rejects any function whose parameter
-- defaults differ from the existing definition (SQLSTATE 42P13).
drop function if exists public.is_crew_member(uuid);
drop function if exists public.is_crew_admin(uuid);
drop function if exists public.is_ride_member(uuid);
drop function if exists public.create_ride_atomic(
  uuid, text, text, text, text, uuid, text, timestamptz,
  text, text, text, text, text, text, text, text, boolean,
  double precision, double precision, double precision, double precision,
  text, double precision, integer);
drop function if exists public.create_crew_atomic(text, text, uuid, text, uuid[]);
drop function if exists public.touch_updated_at();
drop function if exists public.protect_friendship_fields();
drop function if exists public.protect_crew_membership_fields();
drop function if exists public.enqueue_notification(uuid, text, text, text, jsonb);
drop function if exists public.refresh_leaderboard_monthly(int, int);
drop function if exists public.cleanup_old_outbox();
drop function if exists public.suggest_riders_for_user(uuid, int);
drop function if exists public.crew_leaderboard_for_month(int, int);

-- Stale anonymous accounts (profiles cascade was already dropped above)
delete from auth.users where email is null;

-- =========================================================================
-- 1. CORE TABLES
-- =========================================================================

-- 1.1 Profiles ----------------------------------------------------------
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text unique not null,
  display_name text not null,
  avatar_data  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index profiles_username_idx on public.profiles(username);

-- 1.2 Friendships -------------------------------------------------------
create table public.friendships (
  id          uuid primary key default gen_random_uuid(),
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status      text not null default 'pending'
              check (status in ('pending', 'accepted', 'declined')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint friendships_not_self check (sender_id <> receiver_id),
  constraint friendships_unique   unique (sender_id, receiver_id)
);
create index friendships_sender_idx   on public.friendships(sender_id);
create index friendships_receiver_idx on public.friendships(receiver_id);

-- 1.3 Crews -------------------------------------------------------------
create table public.crews (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  code        text unique not null,
  created_by  uuid not null references public.profiles(id) on delete cascade,
  avatar_data text,
  created_at  timestamptz not null default now()
);
create index crews_creator_idx on public.crews(created_by);

-- 1.4 Crew members ------------------------------------------------------
create table public.crew_members (
  id         uuid primary key default gen_random_uuid(),
  crew_id    uuid not null references public.crews(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  role       text not null default 'member' check (role in ('admin', 'member')),
  status     text not null default 'pending'
             check (status in ('pending', 'accepted', 'declined')),
  invited_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint crew_members_unique unique (crew_id, user_id)
);
create index crew_members_crew_idx on public.crew_members(crew_id);
create index crew_members_user_idx on public.crew_members(user_id);

-- 1.5 Rides (with v2 max_speed_kmh) -------------------------------------
create table public.rides (
  id                uuid primary key default gen_random_uuid(),
  title             text not null,
  place             text,
  subtitle          text,
  tag               text,
  organiser_id      uuid not null references public.profiles(id) on delete cascade,
  code              text unique not null,
  departs           timestamptz not null,
  distance          text,
  duration          text,
  display_date      text,
  display_time      text,
  from_location     text,
  to_location       text,
  stops_json        text default '[]',
  style_raw         text default 'Fastest',
  route_set         boolean default false,
  start_lat         double precision default 0,
  start_lon         double precision default 0,
  end_lat           double precision default 0,
  end_lon           double precision default 0,
  route_coords_json text default '[]',
  route_km          double precision default 0,
  route_minutes     integer default 0,
  is_completed      boolean default false,
  completed_at      timestamptz,
  max_speed_kmh     double precision default 0,     -- v2
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index rides_organiser_idx on public.rides(organiser_id);
create index rides_code_idx      on public.rides(code);

-- 1.6 Ride members ------------------------------------------------------
create table public.ride_members (
  id         uuid primary key default gen_random_uuid(),
  ride_id    uuid not null references public.rides(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  role       text not null default 'rider' check (role in ('organiser', 'rider')),
  status     text not null default 'pending'
             check (status in ('pending', 'accepted', 'declined')),
  joined_at  timestamptz not null default now(),
  constraint ride_members_unique unique (ride_id, user_id)
);
create index ride_members_ride_idx   on public.ride_members(ride_id);
create index ride_members_user_idx   on public.ride_members(user_id);
create index ride_members_status_idx on public.ride_members(status);

-- 1.7 Fill-ups ----------------------------------------------------------
create table public.fill_ups (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references public.profiles(id) on delete cascade,
  odo       integer not null,
  litres    numeric(6,2) not null,
  price     numeric(6,2) not null,
  filled_at timestamptz not null default now()
);
create index fill_ups_user_idx on public.fill_ups(user_id);

-- 1.8 Saved routes ------------------------------------------------------
create table public.saved_routes (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  route_id     text not null,
  title        text not null,
  payload_json text not null,
  created_at   timestamptz not null default now(),
  constraint saved_routes_unique unique (user_id, route_id)
);
create index saved_routes_user_idx on public.saved_routes(user_id);

-- 1.9 Ride media --------------------------------------------------------
create table public.ride_media (
  id          uuid primary key default gen_random_uuid(),
  ride_id     uuid not null references public.rides(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  type        text not null check (type in ('photo', 'video')),
  url         text,
  data_base64 text,
  caption     text,
  created_at  timestamptz not null default now()
);
create index ride_media_ride_idx on public.ride_media(ride_id);
create index ride_media_user_idx on public.ride_media(user_id);

-- 1.10 SOS events -------------------------------------------------------
create table public.sos_events (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  ride_id    uuid references public.rides(id) on delete set null,
  lat        double precision,
  lon        double precision,
  created_at timestamptz not null default now()
);
create index sos_events_user_idx on public.sos_events(user_id);
create index sos_events_ride_idx on public.sos_events(ride_id);

-- =========================================================================
-- 2. RLS ENABLE (original)
-- =========================================================================
alter table public.profiles      enable row level security;
alter table public.friendships   enable row level security;
alter table public.crews         enable row level security;
alter table public.crew_members  enable row level security;
alter table public.rides         enable row level security;
alter table public.ride_members  enable row level security;
alter table public.fill_ups      enable row level security;
alter table public.saved_routes  enable row level security;
alter table public.ride_media    enable row level security;
alter table public.sos_events    enable row level security;

-- =========================================================================
-- 3. HELPER FUNCTIONS (security definer, used by policies)
-- =========================================================================
create or replace function public.is_crew_member(p_crew_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.crew_members cm
    where cm.crew_id = p_crew_id
      and cm.user_id = (select auth.uid())
      and cm.status = 'accepted'
  );
$$;

create or replace function public.is_crew_admin(p_crew_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.crew_members cm
    where cm.crew_id = p_crew_id
      and cm.user_id = (select auth.uid())
      and cm.role = 'admin'
      and cm.status = 'accepted'
  );
$$;

create or replace function public.is_ride_member(p_ride_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.ride_members rm
    where rm.ride_id = p_ride_id
      and rm.user_id = (select auth.uid())
      and rm.status = 'accepted'
  );
$$;

revoke all on function public.is_crew_member(uuid) from public;
revoke all on function public.is_crew_admin(uuid)  from public;
revoke all on function public.is_ride_member(uuid) from public;
grant execute on function public.is_crew_member(uuid) to authenticated;
grant execute on function public.is_crew_admin(uuid)  to authenticated;
grant execute on function public.is_ride_member(uuid) to authenticated;

-- =========================================================================
-- 4. ATOMIC CREATION FUNCTIONS
-- =========================================================================
create or replace function public.create_ride_atomic(
  p_ride_id uuid, p_title text, p_place text, p_subtitle text, p_tag text,
  p_organiser_id uuid, p_code text, p_departs timestamptz,
  p_distance text, p_duration text, p_display_date text, p_display_time text,
  p_from_location text, p_to_location text, p_stops_json text,
  p_style_raw text, p_route_set boolean,
  p_start_lat double precision, p_start_lon double precision,
  p_end_lat double precision, p_end_lon double precision,
  p_route_coords_json text, p_route_km double precision, p_route_minutes integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or auth.uid() != p_organiser_id then
    raise exception 'Not authenticated as organiser';
  end if;

  insert into public.rides (
    id, title, place, subtitle, tag, organiser_id, code, departs,
    distance, duration, display_date, display_time,
    from_location, to_location, stops_json, style_raw, route_set,
    start_lat, start_lon, end_lat, end_lon,
    route_coords_json, route_km, route_minutes
  ) values (
    p_ride_id, p_title, p_place, p_subtitle, p_tag, p_organiser_id, p_code, p_departs,
    p_distance, p_duration, p_display_date, p_display_time,
    p_from_location, p_to_location, p_stops_json, p_style_raw, p_route_set,
    p_start_lat, p_start_lon, p_end_lat, p_end_lon,
    p_route_coords_json, p_route_km, p_route_minutes
  );

  insert into public.ride_members (ride_id, user_id, role, status)
  values (p_ride_id, p_organiser_id, 'organiser', 'accepted');

  return p_ride_id;
end;
$$;
grant execute on function public.create_ride_atomic to authenticated;

create or replace function public.create_crew_atomic(
  p_name text, p_code text, p_creator_id uuid,
  p_avatar_data text, p_member_ids uuid[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_crew_id uuid;
  v_member_id uuid;
begin
  if auth.uid() is null or auth.uid() != p_creator_id then
    raise exception 'Not authenticated as creator';
  end if;

  insert into public.crews (name, code, created_by, avatar_data)
  values (p_name, p_code, p_creator_id, p_avatar_data)
  returning id into v_crew_id;

  insert into public.crew_members (crew_id, user_id, role, status)
  values (v_crew_id, p_creator_id, 'admin', 'accepted');

  foreach v_member_id in array p_member_ids loop
    if v_member_id != p_creator_id then
      insert into public.crew_members (crew_id, user_id, role, status, invited_by)
      values (v_crew_id, v_member_id, 'member', 'pending', p_creator_id)
      on conflict (crew_id, user_id) do nothing;
    end if;
  end loop;

  return v_crew_id;
end;
$$;
grant execute on function public.create_crew_atomic to authenticated;

-- =========================================================================
-- 5. TRIGGER FUNCTIONS + ORIGINAL TRIGGERS
-- =========================================================================
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end;
$$;

create trigger trg_profiles_updated
  before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger trg_friendships_updated
  before update on public.friendships
  for each row execute function public.touch_updated_at();
create trigger trg_rides_updated
  before update on public.rides
  for each row execute function public.touch_updated_at();

create or replace function public.protect_friendship_fields()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.sender_id is distinct from old.sender_id
     or new.receiver_id is distinct from old.receiver_id then
    raise exception 'Friendship participants cannot be changed';
  end if;
  return new;
end;
$$;
create trigger trg_protect_friendship_fields
  before update on public.friendships
  for each row execute function public.protect_friendship_fields();

create or replace function public.protect_crew_membership_fields()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.crew_id is distinct from old.crew_id
     or new.user_id is distinct from old.user_id
     or new.role is distinct from old.role then
    raise exception 'Crew membership identity and role cannot be changed';
  end if;

  if old.invited_by is not null
     and new.invited_by is not null
     and old.invited_by is distinct from new.invited_by then
    raise exception 'Crew membership inviter cannot be changed';
  end if;

  if new.status is distinct from old.status
     and not (
       (old.status = 'pending'  and new.status in ('accepted', 'declined'))
       or (old.status = 'declined' and new.status = 'pending')
     ) then
    raise exception 'Invalid crew membership status transition';
  end if;

  return new;
end;
$$;
create trigger trg_protect_crew_membership_fields
  before update on public.crew_members
  for each row execute function public.protect_crew_membership_fields();

-- =========================================================================
-- 6. ORIGINAL RLS POLICIES
-- =========================================================================

-- 6.1 profiles ----------------------------------------------------------
create policy "Profiles are viewable by authenticated users"
  on public.profiles for select to authenticated using (true);
create policy "Users can insert their own profile"
  on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy "Users can update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy "Users can delete their own profile"
  on public.profiles for delete to authenticated using ((select auth.uid()) = id);

-- 6.2 friendships -------------------------------------------------------
create policy "Users can view their own friendships"
  on public.friendships for select to authenticated
  using ((select auth.uid()) = sender_id or (select auth.uid()) = receiver_id);
create policy "Users can send friend requests"
  on public.friendships for insert to authenticated
  with check ((select auth.uid()) = sender_id and status = 'pending');
create policy "Receiver can update friendship status"
  on public.friendships for update to authenticated
  using ((select auth.uid()) = receiver_id)
  with check ((select auth.uid()) = receiver_id and status in ('accepted', 'declined'));
create policy "Either party can delete friendship"
  on public.friendships for delete to authenticated
  using ((select auth.uid()) = sender_id or (select auth.uid()) = receiver_id);

-- 6.3 crews -------------------------------------------------------------
create policy "Members can view their crews"
  on public.crews for select to authenticated
  using ((select auth.uid()) = created_by or (select public.is_crew_member(id)));
create policy "Authenticated users can create crews"
  on public.crews for insert to authenticated
  with check ((select auth.uid()) = created_by);
create policy "Creator can update crew"
  on public.crews for update to authenticated
  using ((select auth.uid()) = created_by) with check ((select auth.uid()) = created_by);
create policy "Creator can delete crew"
  on public.crews for delete to authenticated using ((select auth.uid()) = created_by);

-- 6.4 crew_members ------------------------------------------------------
create policy "Crew members can view roster"
  on public.crew_members for select to authenticated
  using ((select auth.uid()) = user_id or (select public.is_crew_member(crew_id)));

create policy "Self join or accepted admin invites"
  on public.crew_members for insert to authenticated
  with check (
    status = 'pending'
    and (
      ((select auth.uid()) = user_id and role = 'member' and invited_by is null)
      or ((select auth.uid()) = invited_by and (select public.is_crew_admin(crew_id)) and role = 'member')
    )
  );

create policy "Users can accept or decline own invitations"
  on public.crew_members for update to authenticated
  using ((select auth.uid()) = user_id and status = 'pending')
  with check ((select auth.uid()) = user_id and status in ('accepted', 'declined'));

create policy "Admin can reopen declined invites"
  on public.crew_members for update to authenticated
  using ((select public.is_crew_admin(crew_id)) and status = 'declined')
  with check ((select public.is_crew_admin(crew_id)) and status = 'pending');

create policy "Users can leave crew or admins can remove members"
  on public.crew_members for delete to authenticated
  using ((select auth.uid()) = user_id or (select public.is_crew_admin(crew_id)));

-- 6.5 rides -------------------------------------------------------------
create policy "Authenticated users can view rides"
  on public.rides for select to authenticated using (true);
create policy "Authenticated users can create rides"
  on public.rides for insert to authenticated
  with check ((select auth.uid()) = organiser_id);
create policy "Organiser can update ride"
  on public.rides for update to authenticated
  using ((select auth.uid()) = organiser_id) with check ((select auth.uid()) = organiser_id);
create policy "Organiser can delete ride"
  on public.rides for delete to authenticated using ((select auth.uid()) = organiser_id);

-- 6.6 ride_members ------------------------------------------------------
create policy "Ride members can view roster"
  on public.ride_members for select to authenticated
  using (
    (select auth.uid()) = user_id
    or exists (
      select 1 from public.ride_members me
      where me.ride_id = ride_id
        and me.user_id = (select auth.uid())
        and me.status = 'accepted'
    )
  );

create policy "Users join as pending riders or organiser adds members"
  on public.ride_members for insert to authenticated
  with check (
    ((select auth.uid()) = user_id and role = 'rider' and status = 'pending')
    or exists (select 1 from public.rides r where r.id = ride_id and r.organiser_id = (select auth.uid()))
  );

create policy "Organiser can update ride member status"
  on public.ride_members for update to authenticated
  using (exists (select 1 from public.rides r where r.id = ride_id and r.organiser_id = (select auth.uid())))
  with check (exists (select 1 from public.rides r where r.id = ride_id and r.organiser_id = (select auth.uid())));

create policy "Users leave ride or organiser removes members"
  on public.ride_members for delete to authenticated
  using (
    (select auth.uid()) = user_id
    or exists (select 1 from public.rides r where r.id = ride_id and r.organiser_id = (select auth.uid()))
  );

-- 6.7 fill_ups ----------------------------------------------------------
create policy "View own fill-ups"
  on public.fill_ups for select to authenticated using ((select auth.uid()) = user_id);
create policy "Insert own fill-ups"
  on public.fill_ups for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Update own fill-ups"
  on public.fill_ups for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Delete own fill-ups"
  on public.fill_ups for delete to authenticated using ((select auth.uid()) = user_id);

-- 6.8 saved_routes ------------------------------------------------------
create policy "View own saved routes"
  on public.saved_routes for select to authenticated using ((select auth.uid()) = user_id);
create policy "Insert own saved routes"
  on public.saved_routes for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Update own saved routes"
  on public.saved_routes for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Delete own saved routes"
  on public.saved_routes for delete to authenticated using ((select auth.uid()) = user_id);

-- 6.9 ride_media --------------------------------------------------------
create policy "Ride members can view media"
  on public.ride_media for select to authenticated using ((select public.is_ride_member(ride_id)));
create policy "Ride members can upload media"
  on public.ride_media for insert to authenticated
  with check ((select auth.uid()) = user_id and (select public.is_ride_member(ride_id)));
create policy "Uploader or organiser can delete media"
  on public.ride_media for delete to authenticated
  using (
    (select auth.uid()) = user_id
    or exists (select 1 from public.rides r where r.id = ride_id and r.organiser_id = (select auth.uid()))
  );

-- 6.10 sos_events -------------------------------------------------------
create policy "Insert own SOS"
  on public.sos_events for insert to authenticated
  with check ((select auth.uid()) = user_id and (ride_id is null or (select public.is_ride_member(ride_id))));
create policy "View own or ride member SOS"
  on public.sos_events for select to authenticated
  using ((select auth.uid()) = user_id or (ride_id is not null and (select public.is_ride_member(ride_id))));

-- =========================================================================
-- 7. v2 ENUMS
-- =========================================================================
create type public.post_kind       as enum ('ride','experience','update','photo');
create type public.post_visibility as enum ('public','followers','crew');

-- =========================================================================
-- 8. v2 TABLES
-- =========================================================================

-- 8.1 follows -----------------------------------------------------------
create table public.follows (
  follower_id  uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint follows_no_self check (follower_id <> following_id)
);
create index follows_following_idx on public.follows(following_id, created_at desc);

-- 8.2 posts -------------------------------------------------------------
create table public.posts (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid not null references public.profiles(id) on delete cascade,
  kind         public.post_kind not null default 'update',
  visibility   public.post_visibility not null default 'public',
  crew_id      uuid references public.crews(id) on delete set null,
  ride_id      uuid references public.rides(id) on delete set null,
  title        text,
  body         text,
  media_json   text not null default '[]',
  route_km     double precision,
  route_from   text,
  route_to     text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index posts_author_idx on public.posts(author_id, created_at desc);
create index posts_recent_idx on public.posts(created_at desc);
create index posts_crew_idx   on public.posts(crew_id, created_at desc)
  where crew_id is not null;

-- 8.3 post_likes --------------------------------------------------------
create table public.post_likes (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index post_likes_user_idx on public.post_likes(user_id);

-- 8.4 post_comments -----------------------------------------------------
create table public.post_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts(id) on delete cascade,
  author_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now()
);
create index post_comments_post_idx on public.post_comments(post_id, created_at);

-- 8.5 leaderboard_monthly -----------------------------------------------
create table public.leaderboard_monthly (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles(id) on delete cascade,
  period_year       int  not null,
  period_month      int  not null check (period_month between 1 and 12),
  total_km          double precision not null default 0,
  rides_count       int  not null default 0,
  longest_ride_km   double precision not null default 0,
  top_speed_kmh     double precision not null default 0,
  streak_days       int  not null default 0,
  computed_at       timestamptz not null default now(),
  unique (user_id, period_year, period_month)
);
create index leaderboard_period_idx
  on public.leaderboard_monthly(period_year, period_month, total_km desc);

-- 8.6 device_tokens -----------------------------------------------------
create table public.device_tokens (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  apns_token  text not null,
  environment text not null default 'production'
              check (environment in ('sandbox','production')),
  platform    text not null default 'ios',
  updated_at  timestamptz not null default now(),
  primary key (user_id, apns_token)
);

-- 8.7 notification_outbox -----------------------------------------------
create table public.notification_outbox (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null,
  title      text not null,
  body       text not null,
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  cancelled  boolean not null default false
);
create index outbox_pending_idx
  on public.notification_outbox(created_at)
  where sent_at is null and not cancelled;

-- =========================================================================
-- 9. RLS ENABLE (v2)
-- =========================================================================
alter table public.follows              enable row level security;
alter table public.posts                enable row level security;
alter table public.post_likes           enable row level security;
alter table public.post_comments        enable row level security;
alter table public.leaderboard_monthly  enable row level security;
alter table public.device_tokens        enable row level security;
alter table public.notification_outbox  enable row level security;

-- =========================================================================
-- 10. v2 RPCs
-- =========================================================================

-- 10.1 enqueue_notification --------------------------------------------
create or replace function public.enqueue_notification(
  p_user_id uuid,
  p_kind    text,
  p_title   text,
  p_body    text,
  p_payload jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.notification_outbox(user_id, kind, title, body, payload)
  values (p_user_id, p_kind, p_title, p_body, coalesce(p_payload, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

revoke all on function public.enqueue_notification(uuid,text,text,text,jsonb) from public;
grant execute on function public.enqueue_notification(uuid,text,text,text,jsonb) to authenticated;

-- 10.2 refresh_leaderboard_monthly -------------------------------------
create or replace function public.refresh_leaderboard_monthly(
  p_year  int,
  p_month int
) returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_start timestamptz := make_timestamptz(p_year, p_month, 1, 0, 0, 0, 'UTC');
  v_end   timestamptz := v_start + interval '1 month';
  v_rows  int := 0;
begin
  with base as (
    select rm.user_id,
           coalesce(r.route_km, 0)          as route_km,
           coalesce(r.max_speed_kmh, 0)     as max_speed_kmh,
           r.completed_at::date             as ride_day
    from public.rides r
    join public.ride_members rm on rm.ride_id = r.id
    where rm.status = 'accepted'
      and r.is_completed = true
      and r.completed_at >= v_start
      and r.completed_at <  v_end
  ),
  per_user as (
    select user_id,
           sum(route_km)::double precision       as total_km,
           count(*)::int                          as rides_count,
           max(route_km)::double precision        as longest_ride_km,
           max(max_speed_kmh)::double precision   as top_speed_kmh
    from base
    group by user_id
  ),
  distinct_days as (
    select distinct user_id, ride_day as d from base
  ),
  grouped_days as (
    select user_id, d,
           d - (row_number() over (partition by user_id order by d))::int as grp
    from distinct_days
  ),
  streaks as (
    select user_id, count(*)::int as len
    from grouped_days
    group by user_id, grp
  ),
  max_streaks as (
    select user_id, max(len)::int as streak_days
    from streaks
    group by user_id
  )
  insert into public.leaderboard_monthly
    (user_id, period_year, period_month, total_km, rides_count,
     longest_ride_km, top_speed_kmh, streak_days, computed_at)
  select u.user_id, p_year, p_month,
         u.total_km, u.rides_count, u.longest_ride_km, u.top_speed_kmh,
         coalesce(s.streak_days, 0),
         now()
  from per_user u
  left join max_streaks s on s.user_id = u.user_id
  on conflict (user_id, period_year, period_month) do update
    set total_km        = excluded.total_km,
        rides_count     = excluded.rides_count,
        longest_ride_km = excluded.longest_ride_km,
        top_speed_kmh   = excluded.top_speed_kmh,
        streak_days     = excluded.streak_days,
        computed_at     = excluded.computed_at;

  get diagnostics v_rows = row_count;
  return v_rows;
end $$;

revoke all on function public.refresh_leaderboard_monthly(int,int) from public;
grant execute on function public.refresh_leaderboard_monthly(int,int) to authenticated;

-- 10.3 cleanup_old_outbox ----------------------------------------------
create or replace function public.cleanup_old_outbox()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare v_rows int;
begin
  delete from public.notification_outbox
  where (sent_at is not null and sent_at < now() - interval '30 days')
     or (cancelled = true and created_at < now() - interval '30 days');
  get diagnostics v_rows = row_count;
  return v_rows;
end $$;

revoke all on function public.cleanup_old_outbox() from public;
grant execute on function public.cleanup_old_outbox() to authenticated;

-- 10.4 suggest_riders_for_user -----------------------------------------
create or replace function public.suggest_riders_for_user(
  p_user_id uuid,
  p_limit   int default 20
)
returns table (
  id               uuid,
  username         text,
  display_name     text,
  avatar_data      text,
  followers_count  bigint,
  following_count  bigint,
  is_followed      boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id,
         p.username,
         p.display_name,
         p.avatar_data,
         coalesce(fc.cnt, 0) as followers_count,
         coalesce(fg.cnt, 0) as following_count,
         exists (
           select 1 from public.follows f
           where f.follower_id = p_user_id
             and f.following_id = p.id
         ) as is_followed
  from public.profiles p
  left join (
    select following_id, count(*) as cnt
    from public.follows group by following_id
  ) fc on fc.following_id = p.id
  left join (
    select follower_id, count(*) as cnt
    from public.follows group by follower_id
  ) fg on fg.follower_id = p.id
  where p.id <> p_user_id
  order by coalesce(fc.cnt, 0) desc, p.created_at desc
  limit p_limit;
$$;

revoke all on function public.suggest_riders_for_user(uuid,int) from public;
grant execute on function public.suggest_riders_for_user(uuid,int) to authenticated;

-- 10.5 crew_leaderboard_for_month --------------------------------------
create or replace function public.crew_leaderboard_for_month(
  p_year  int,
  p_month int
)
returns table (
  crew_id    uuid,
  crew_name  text,
  total_km   double precision
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id,
         c.name,
         coalesce(sum(lm.total_km), 0)::double precision
  from public.crews c
  join public.crew_members cm
    on cm.crew_id = c.id and cm.status = 'accepted'
  left join public.leaderboard_monthly lm
    on lm.user_id = cm.user_id
   and lm.period_year  = p_year
   and lm.period_month = p_month
  group by c.id, c.name
  order by coalesce(sum(lm.total_km), 0) desc;
$$;

revoke all on function public.crew_leaderboard_for_month(int,int) from public;
grant execute on function public.crew_leaderboard_for_month(int,int) to authenticated;

-- =========================================================================
-- 11. v2 TRIGGERS
-- =========================================================================
create trigger trg_posts_updated
  before update on public.posts
  for each row execute function public.touch_updated_at();

-- =========================================================================
-- 12. v2 RLS POLICIES
-- =========================================================================

-- 12.1 follows ----------------------------------------------------------
create policy follows_select_all on public.follows
  for select using (true);
create policy follows_insert_own on public.follows
  for insert with check (follower_id = (select auth.uid()));
create policy follows_delete_own on public.follows
  for delete using (follower_id = (select auth.uid()));

-- 12.2 posts ------------------------------------------------------------
create policy posts_select on public.posts
  for select using (
    visibility = 'public'
    or author_id = (select auth.uid())
    or (
      visibility = 'followers'
      and exists (
        select 1 from public.follows f
        where f.follower_id = (select auth.uid())
          and f.following_id = posts.author_id
      )
    )
    or (
      visibility = 'crew'
      and crew_id is not null
      and public.is_crew_member(crew_id)
    )
  );
create policy posts_insert_own on public.posts
  for insert with check (author_id = (select auth.uid()));
create policy posts_update_own on public.posts
  for update using (author_id = (select auth.uid()));
create policy posts_delete_own on public.posts
  for delete using (author_id = (select auth.uid()));

-- 12.3 post_likes -------------------------------------------------------
create policy post_likes_select on public.post_likes
  for select using (true);
create policy post_likes_own on public.post_likes
  for all
  using  (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- 12.4 post_comments ----------------------------------------------------
create policy post_comments_select on public.post_comments
  for select using (true);
create policy post_comments_insert on public.post_comments
  for insert with check (author_id = (select auth.uid()));
create policy post_comments_delete_own on public.post_comments
  for delete using (author_id = (select auth.uid()));

-- 12.5 leaderboard_monthly ---------------------------------------------
create policy leaderboard_read_all on public.leaderboard_monthly
  for select using (true);

-- 12.6 device_tokens ----------------------------------------------------
create policy tokens_own on public.device_tokens
  for all
  using  (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- 12.7 notification_outbox ---------------------------------------------
create policy outbox_read_own on public.notification_outbox
  for select using (user_id = (select auth.uid()));

-- Drop the broken policy
drop policy if exists "Ride members can view roster" on public.ride_members;

-- Recreate it using the SECURITY DEFINER helper (no recursion)
create policy "Ride members can view roster"
  on public.ride_members for select to authenticated
  using (
    (select auth.uid()) = user_id
    or (select public.is_ride_member(ride_id))
  );

commit;

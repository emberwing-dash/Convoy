-- =========================================================================
-- CONVOY — SCHEMA RESET (with atomic functions + fixed RLS)
-- =========================================================================
begin;

-- 0. Drop all app tables
drop table if exists public.sos_events cascade;
drop table if exists public.ride_media cascade;
drop table if exists public.ride_members cascade;
drop table if exists public.rides cascade;
drop table if exists public.fill_ups cascade;
drop table if exists public.saved_routes cascade;
drop table if exists public.crew_members cascade;
drop table if exists public.crews cascade;
drop table if exists public.friendships cascade;
drop table if exists public.profiles cascade;

-- 1. Kill old anonymous users (otherwise profiles FK fails)
delete from auth.users where email is null;

-- 2. Profiles
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text unique not null,
  display_name text not null,
  avatar_data  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index profiles_username_idx on public.profiles(username);

-- 3. Friendships
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

-- 4. Crews
create table public.crews (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  code        text unique not null,
  created_by  uuid not null references public.profiles(id) on delete cascade,
  avatar_data text,
  created_at  timestamptz not null default now()
);
create index crews_creator_idx on public.crews(created_by);

-- 5. Crew members
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

-- 6. Rides
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
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index rides_organiser_idx on public.rides(organiser_id);
create index rides_code_idx      on public.rides(code);

-- 7. Ride members (status included from the start)
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

-- 8. Fill-ups
create table public.fill_ups (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references public.profiles(id) on delete cascade,
  odo       integer not null,
  litres    numeric(6,2) not null,
  price     numeric(6,2) not null,
  filled_at timestamptz not null default now()
);
create index fill_ups_user_idx on public.fill_ups(user_id);

-- 9. Saved routes
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

-- 10. Ride media
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

-- 11. SOS events
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

-- 12. Enable RLS everywhere
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

-- 13. Security-definer helpers (avoid recursive RLS)
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

-- 14. Atomic creation functions
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

-- 15. Updated_at + protection triggers
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end;
$$;

create trigger trg_profiles_updated    before update on public.profiles    for each row execute function public.touch_updated_at();
create trigger trg_friendships_updated before update on public.friendships for each row execute function public.touch_updated_at();
create trigger trg_rides_updated       before update on public.rides       for each row execute function public.touch_updated_at();

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
create trigger trg_protect_friendship_fields before update on public.friendships for each row execute function public.protect_friendship_fields();

create or replace function public.protect_crew_membership_fields()
returns trigger language plpgsql set search_path = '' as $$
begin
  -- Identity + role are immutable
  if new.crew_id is distinct from old.crew_id
     or new.user_id is distinct from old.user_id
     or new.role is distinct from old.role then
    raise exception 'Crew membership identity and role cannot be changed';
  end if;

  -- invited_by: allow X → NULL (inviter's profile deleted, FK cascade)
  -- and NULL → X (new invite). Block X → Y (identity swap).
  if old.invited_by is not null
     and new.invited_by is not null
     and old.invited_by is distinct from new.invited_by then
    raise exception 'Crew membership inviter cannot be changed';
  end if;

  -- Status: only pending→accepted, pending→declined, declined→pending
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
create trigger trg_protect_crew_membership_fields before update on public.crew_members for each row execute function public.protect_crew_membership_fields();

-- 16. PROFILES policies
create policy "Profiles are viewable by authenticated users"
  on public.profiles for select to authenticated using (true);
create policy "Users can insert their own profile"
  on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy "Users can update their own profile"
  on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy "Users can delete their own profile"
  on public.profiles for delete to authenticated using ((select auth.uid()) = id);

-- 17. FRIENDSHIPS policies
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

-- 18. CREWS policies
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

-- 19. CREW_MEMBERS policies
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

-- 20. RIDES policies
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

-- 21. RIDE_MEMBERS policies (self-join MUST be pending)
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

-- 22. FILL_UPS policies
create policy "View own fill-ups"     on public.fill_ups for select to authenticated using ((select auth.uid()) = user_id);
create policy "Insert own fill-ups"   on public.fill_ups for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Update own fill-ups"   on public.fill_ups for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Delete own fill-ups"   on public.fill_ups for delete to authenticated using ((select auth.uid()) = user_id);

-- 23. SAVED_ROUTES policies
create policy "View own saved routes"   on public.saved_routes for select to authenticated using ((select auth.uid()) = user_id);
create policy "Insert own saved routes" on public.saved_routes for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Update own saved routes" on public.saved_routes for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Delete own saved routes" on public.saved_routes for delete to authenticated using ((select auth.uid()) = user_id);

-- 24. RIDE_MEDIA policies
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

-- 25. SOS_EVENTS policies
create policy "Insert own SOS"
  on public.sos_events for insert to authenticated
  with check ((select auth.uid()) = user_id and (ride_id is null or (select public.is_ride_member(ride_id))));
create policy "View own or ride member SOS"
  on public.sos_events for select to authenticated
  using ((select auth.uid()) = user_id or (ride_id is not null and (select public.is_ride_member(ride_id))));

commit;
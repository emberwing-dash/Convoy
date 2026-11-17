-- 20261117180000_achievements.sql
-- Achievements + rider XP / levels.
--
-- WHAT COUNTS
--   Everything is derived from data the server already trusts: GPS ride logs that passed
--   record_ride_log (de-duplicated the same way as the Ride Score, see public.ride_scores),
--   accepted friendships, accepted crew memberships and rides shared to the feed.
--   No speed achievements — top speed is never rewarded.
--
-- HOW IT UPDATES
--   public.evaluate_achievements(user) recomputes the rider's metrics and unlocks every
--   achievement whose target is now met (unlock rows are never removed). It runs from triggers
--   when a ride is recorded, a friendship is accepted, a crew membership is accepted and a ride
--   is posted, and again whenever the rider opens their achievements (catches up old data).
--   Each new unlock sends an 'achievement' notification.
--
-- XP AND LEVEL
--   XP = all-time Ride Score (public.ride_scores) + achievement points
--        (bronze 10 · silver 25 · gold 50 · platinum 100).
--   Level n starts at 50·n·(n−1) XP (public.rider_level). Leaderboards still rank by Ride Score only.

create table if not exists public.achievement_defs (
    id          text primary key,
    category    text not null check (category in ('distance','rides','long_ride','streak','group','social','explorer')),
    title       text not null,
    detail      text not null,
    icon        text not null,          -- SF Symbol name
    tier        text not null check (tier in ('bronze','silver','gold','platinum')),
    metric      text not null,
    target      numeric not null check (target > 0),
    points      integer not null,
    sort        integer not null default 0
);
alter table public.achievement_defs enable row level security;
drop policy if exists "achievement defs readable" on public.achievement_defs;
create policy "achievement defs readable" on public.achievement_defs for select to authenticated using (true);

insert into public.achievement_defs (id, category, title, detail, icon, tier, metric, target, points, sort) values
 ('first_ride',      'rides',     'First Ride',        'Finish your first GPS-recorded ride',          'flag.checkered',               'bronze',   'rides',        1,    10,  10),
 ('rides_10',        'rides',     'Getting Rolling',   'Finish 10 rides',                              'motorcycle',  'bronze',   'rides',        10,   10,  11),
 ('rides_50',        'rides',     'Regular',           'Finish 50 rides',                              'repeat.circle.fill',     'silver',   'rides',        50,   25,  12),
 ('rides_150',       'rides',     'Lifer',             'Finish 150 rides',                             'infinity.circle.fill',                     'gold',     'rides',        150,  50,  13),
 ('km_50',           'distance',  'First 50',          'Ride 50 km in total',                          'signpost.right.fill',                   'bronze',   'total_km',     50,   10,  20),
 ('km_500',          'distance',  'Road Warrior',      'Ride 500 km in total',                         'map.fill',                          'silver',   'total_km',     500,  25,  21),
 ('km_2000',         'distance',  'Mile Muncher',      'Ride 2,000 km in total',                       'globe.asia.australia.fill',         'gold',     'total_km',     2000, 50,  22),
 ('km_10000',        'distance',  'Ten Thousand',      'Ride 10,000 km in total',                      'crown.fill',                        'platinum', 'total_km',     10000,100, 23),
 ('long_100',        'long_ride', 'Century Ride',      'Ride 100 km in a single ride',                 'star.circle.fill', 'bronze', 'longest_km', 100, 10, 30),
 ('long_250',        'long_ride', 'Long Hauler',       'Ride 250 km in a single ride',                 'sun.horizon.fill',                  'silver',   'longest_km',   250,  25,  31),
 ('long_500',        'long_ride', 'Iron Saddle',       'Ride 500 km in a single ride',                 'mountain.2.fill',                   'gold',     'longest_km',   500,  50,  32),
 ('streak_3',        'streak',    'Three in a Row',    'Ride 5 km or more on 3 days in a row',         'flame.fill',                        'bronze',   'best_streak',  3,    10,  40),
 ('streak_7',        'streak',    'Week Warrior',      'Ride 5 km or more on 7 days in a row',         'flame.circle.fill',                   'silver',   'best_streak',  7,    25,  41),
 ('streak_30',       'streak',    'Unstoppable',       'Ride 5 km or more on 30 days in a row',        'bolt.heart.fill',                   'gold',     'best_streak',  30,   50,  42),
 ('hours_10',        'explorer',  'Saddle Time',       'Spend 10 hours moving on rides',               'clock.fill',                        'bronze',   'moving_hours', 10,   10,  50),
 ('hours_100',       'explorer',  'Road Life',         'Spend 100 hours moving on rides',              'hourglass.bottomhalf.filled',                    'gold',     'moving_hours', 100,  50,  51),
 ('dawn_5',          'explorer',  'Dawn Patrol',       'Start 5 rides before 7 am',                    'sunrise.fill',                      'silver',   'dawn_rides',   5,    25,  52),
 ('weekend_10',      'explorer',  'Weekend Warrior',   'Finish 10 rides on a Saturday or Sunday',      'calendar.circle.fill',                     'silver',   'weekend_rides',10,   25,  53),
 ('group_1',         'group',     'Pack Rider',        'Finish a ride with 2 or more riders',          'person.2.fill',                     'bronze',   'group_rides',  1,    10,  60),
 ('group_10',        'group',     'Convoy Regular',    'Finish 10 group rides',                        'person.3.fill',                     'silver',   'group_rides',  10,   25,  61),
 ('host_5',          'group',     'Ride Leader',       'Host 5 group rides',                           'flag.2.crossed.fill',               'gold',     'hosted_rides', 5,    50,  62),
 ('friend_1',        'social',    'First Friend',      'Add your first friend on Convoy',              'hand.wave.fill', 'bronze', 'friends',  1,    10,  70),
 ('friend_10',       'social',    'Inner Circle',      'Have 10 friends on Convoy',                    'heart.circle.fill',              'silver',   'friends',      10,   25,  71),
 ('crew_1',          'social',    'Crew Up',           'Create or join a ride crew',                   'shield.fill',       'bronze',   'crews',        1,    10,  72),
 ('share_5',         'social',    'Storyteller',       'Share 5 rides to the Crew feed',               'megaphone.fill',          'silver',   'shared_rides', 5,    25,  73)
on conflict (id) do update set category = excluded.category, title = excluded.title, detail = excluded.detail,
    icon = excluded.icon, tier = excluded.tier, metric = excluded.metric, target = excluded.target,
    points = excluded.points, sort = excluded.sort;

create table if not exists public.user_achievements (
    user_id        uuid not null references auth.users(id) on delete cascade,
    achievement_id text not null references public.achievement_defs(id) on delete cascade,
    unlocked_at    timestamptz not null default now(),
    primary key (user_id, achievement_id)
);
alter table public.user_achievements enable row level security;
drop policy if exists "own achievements readable" on public.user_achievements;
create policy "own achievements readable" on public.user_achievements for select to authenticated using (user_id = auth.uid());

-- Every metric an achievement can use, for one rider. Ride metrics use the same de-duplicated
-- qualifying rides as the Ride Score (≥ 1 km, ≥ 60 s moving, overlapping/duplicate logs dropped).
create or replace function public.rider_metrics(p_user uuid)
returns jsonb language sql stable security definer set search_path = public as $$
with valid as (
    select l.id, l.ride_id, l.started_at, l.ended_at, l.distance_m / 1000.0 as km, l.moving_s, l.rider_count, l.is_host,
           (l.started_at at time zone 'Asia/Kolkata') as local_start
    from ride_logs l
    where l.user_id = p_user and l.distance_m >= 1000 and l.moving_s >= 60
),
rides as (
    select v.* from valid v
    where not exists (
        select 1 from valid o
        where o.id <> v.id
          and ((o.started_at < v.ended_at and v.started_at < o.ended_at) or (v.ride_id is not null and o.ride_id = v.ride_id))
          and (o.km > v.km or (o.km = v.km and o.id < v.id)))
),
days as (select distinct local_start::date as d from rides where km >= 5),
runs as (select count(*) as n from (select d, d - (row_number() over (order by d))::int as grp from days) s group by grp)
select jsonb_build_object(
    'rides',         (select count(*) from rides),
    'total_km',      (select coalesce(round(sum(km), 1), 0) from rides),
    'longest_km',    (select coalesce(round(max(km), 1), 0) from rides),
    'best_streak',   (select coalesce(max(n), 0) from runs),
    'moving_hours',  (select coalesce(round(sum(moving_s) / 3600.0, 1), 0) from rides),
    'dawn_rides',    (select count(*) from rides where extract(hour from local_start) < 7),
    'weekend_rides', (select count(*) from rides where extract(isodow from local_start) in (6, 7)),
    'group_rides',   (select count(*) from rides where rider_count >= 2 and km >= 5),
    'hosted_rides',  (select count(*) from rides where rider_count >= 2 and km >= 5 and is_host),
    'friends',       (select count(*) from friendships f where f.status = 'accepted' and p_user in (f.sender_id, f.receiver_id)),
    'crews',         (select count(*) from crew_members m where m.user_id = p_user and m.status = 'accepted'),
    'shared_rides',  (select count(*) from feed_posts fp where fp.author_id = p_user and fp.ride_log_id is not null)
);
$$;
revoke all on function public.rider_metrics(uuid) from public, anon, authenticated;

-- Unlocks everything newly earned and notifies the rider. Returns the ids unlocked now.
create or replace function public.evaluate_achievements(p_user uuid)
returns setof text language plpgsql security definer set search_path = public as $$
declare
    m jsonb;
    rec record;
begin
    if p_user is null then return; end if;
    m := public.rider_metrics(p_user);
    for rec in
        insert into user_achievements (user_id, achievement_id)
        select p_user, d.id from achievement_defs d
        where coalesce((m ->> d.metric)::numeric, 0) >= d.target
        on conflict do nothing
        returning achievement_id
    loop
        begin
            perform public.notify_user(p_user, null, 'achievement', null, null, null,
                (select 'Achievement unlocked: ' || title || ' (+' || points || ' XP)' from achievement_defs where id = rec.achievement_id),
                null, null);
        exception when others then null;   -- a notification problem never blocks the unlock
        end;
        return next rec.achievement_id;
    end loop;
end $$;
revoke all on function public.evaluate_achievements(uuid) from public, anon, authenticated;

-- Lifetime XP for a rider: Ride Score + achievement points.
create or replace function public.rider_xp(p_user uuid)
returns integer language sql stable security definer set search_path = public as $$
    select coalesce((select score from public.ride_scores(null, null) where uid = p_user), 0)
         + coalesce((select sum(d.points) from user_achievements ua join achievement_defs d on d.id = ua.achievement_id
                     where ua.user_id = p_user), 0)::int;
$$;
revoke all on function public.rider_xp(uuid) from public, anon;
grant execute on function public.rider_xp(uuid) to authenticated;

-- The signed-in rider's achievements with live progress (also catches up any missed unlocks).
create or replace function public.my_achievements()
returns table(id text, category text, title text, detail text, icon text, tier text, metric text,
              target numeric, points integer, sort integer, progress numeric, unlocked_at timestamptz)
language plpgsql volatile security definer set search_path = public as $$
declare
    v_user uuid := auth.uid();
    m jsonb;
begin
    if v_user is null then raise exception 'Unauthorized: User not authenticated'; end if;
    perform public.evaluate_achievements(v_user);
    m := public.rider_metrics(v_user);
    return query
        select d.id, d.category, d.title, d.detail, d.icon, d.tier, d.metric, d.target, d.points, d.sort,
               least(coalesce((m ->> d.metric)::numeric, 0), d.target), ua.unlocked_at
        from achievement_defs d
        left join user_achievements ua on ua.achievement_id = d.id and ua.user_id = v_user
        order by d.sort;
end $$;
revoke all on function public.my_achievements() from public, anon;
grant execute on function public.my_achievements() to authenticated;

-- The signed-in rider's level summary: XP split into Ride Score and achievements, plus metrics.
create or replace function public.my_level()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
    v_user uuid := auth.uid();
    v_score int; v_ach int; v_xp int; v_level int;
begin
    if v_user is null then raise exception 'Unauthorized: User not authenticated'; end if;
    perform public.evaluate_achievements(v_user);
    v_score := coalesce((select score from public.ride_scores(null, null) where uid = v_user), 0);
    v_ach := coalesce((select sum(d.points) from user_achievements ua join achievement_defs d on d.id = ua.achievement_id
                       where ua.user_id = v_user), 0);
    v_xp := v_score + v_ach;
    v_level := public.rider_level(v_xp);
    return jsonb_build_object(
        'xp', v_xp, 'ride_score', v_score, 'achievement_xp', v_ach, 'level', v_level,
        'level_start', 50 * v_level * (v_level - 1), 'next_level_at', 50 * (v_level + 1) * v_level,
        'unlocked', (select count(*) from user_achievements where user_id = v_user),
        'total_achievements', (select count(*) from achievement_defs),
        'metrics', public.rider_metrics(v_user));
end $$;
revoke all on function public.my_level() from public, anon;
grant execute on function public.my_level() to authenticated;

-- Triggers: re-evaluate when anything an achievement depends on changes.
create or replace function public.achievements_on_ride_log() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform public.evaluate_achievements(new.user_id); return new;
exception when others then return new; end $$;
drop trigger if exists trg_achievements_ride_log on public.ride_logs;
create trigger trg_achievements_ride_log after insert on public.ride_logs
    for each row execute function public.achievements_on_ride_log();

create or replace function public.achievements_on_friendship() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if new.status = 'accepted' then
        perform public.evaluate_achievements(new.sender_id);
        perform public.evaluate_achievements(new.receiver_id);
    end if;
    return new;
exception when others then return new; end $$;
drop trigger if exists trg_achievements_friendship on public.friendships;
create trigger trg_achievements_friendship after insert or update of status on public.friendships
    for each row execute function public.achievements_on_friendship();

create or replace function public.achievements_on_crew_member() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if new.status = 'accepted' then perform public.evaluate_achievements(new.user_id); end if;
    return new;
exception when others then return new; end $$;
drop trigger if exists trg_achievements_crew_member on public.crew_members;
create trigger trg_achievements_crew_member after insert or update of status on public.crew_members
    for each row execute function public.achievements_on_crew_member();

create or replace function public.achievements_on_post() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform public.evaluate_achievements(new.author_id); return new;
exception when others then return new; end $$;
drop trigger if exists trg_achievements_post on public.feed_posts;
create trigger trg_achievements_post after insert on public.feed_posts
    for each row execute function public.achievements_on_post();

-- Levels everywhere now come from XP (Ride Score + achievements).
create or replace function public.leaderboard_v2(
    p_metric text, p_from timestamptz default null, p_to timestamptz default null, p_limit integer default 10)
returns table(rank integer, user_id uuid, display_name text, username text, avatar_data text,
              value numeric, score integer, distance_km numeric, rides integer, longest_km numeric,
              best_streak integer, current_streak integer, group_rides integer,
              pts_distance integer, pts_rides integer, pts_longest integer, pts_streak integer, pts_group integer,
              level integer, is_me boolean, riders_ranked integer, period_total numeric)
language sql stable security definer set search_path = public as $$
with s as (select * from public.ride_scores(p_from, p_to)),
valued as (
    select s.*, case p_metric
                    when 'distance' then s.distance_km
                    when 'rides'    then s.rides::numeric
                    when 'longest'  then s.longest_km
                    when 'streak'   then s.best_streak::numeric
                    else s.score::numeric
                end as v
    from s
),
ranked as (
    select valued.*, rank() over (order by v desc, valued.score desc, valued.distance_km desc)::int as rk,
           count(*) over ()::int as total_riders, sum(v) over () as total_v
    from valued where v > 0
),
lifetime as (select l.uid, l.score from public.ride_scores(null, null) l),
ach as (select ua.user_id as uid, sum(d.points)::int as pts
        from user_achievements ua join achievement_defs d on d.id = ua.achievement_id group by ua.user_id)
select r.rk, r.uid, p.display_name, p.username, p.avatar_data,
       r.v, r.score, r.distance_km, r.rides, r.longest_km, r.best_streak, r.current_streak, r.group_rides,
       r.pts_distance, r.pts_rides, r.pts_longest, r.pts_streak, r.pts_group,
       public.rider_level((coalesce(lt.score, 0) + coalesce(a.pts, 0))::bigint), r.uid = auth.uid(), r.total_riders, r.total_v
from ranked r
left join profiles p on p.id = r.uid
left join lifetime lt on lt.uid = r.uid
left join ach a on a.uid = r.uid
where auth.uid() is not null
  and (r.rk <= least(greatest(p_limit, 3), 100) or r.uid = auth.uid())
order by r.rk, p.display_name;
$$;

create or replace function public.rider_profile(p_user_id uuid)
returns table(user_id uuid, display_name text, username text, avatar_data text, followers integer, following integer,
              i_follow boolean, follows_me boolean, total_km numeric, rides_count integer, month_km numeric,
              month_points integer, total_points bigint, level integer, shared_crews integer)
language sql stable security definer set search_path = public as $$
    with month_start as (select (date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') as t),
         life as (select * from public.ride_scores(null, null) where uid = p_user_id),
         mon  as (select * from public.ride_scores((select t from month_start), null) where uid = p_user_id)
    select p.id, p.display_name, p.username, p.avatar_data,
           (select count(*)::int from public.follows where followee_id = p.id),
           (select count(*)::int from public.follows where follower_id = p.id),
           exists (select 1 from public.follows where follower_id = auth.uid() and followee_id = p.id),
           exists (select 1 from public.follows where follower_id = p.id and followee_id = auth.uid()),
           coalesce((select distance_km from life), 0),
           coalesce((select rides from life), 0),
           coalesce((select distance_km from mon), 0),
           coalesce((select score from mon), 0),
           coalesce((select score from life), 0)::bigint,
           public.rider_level(public.rider_xp(p.id)::bigint),
           (select count(*)::int from public.crew_members a
              join public.crew_members b on b.crew_id = a.crew_id and b.user_id = auth.uid() and b.status = 'accepted'
             where a.user_id = p.id and a.status = 'accepted' and p.id <> auth.uid())
    from public.profiles p
    where p.id = p_user_id and auth.uid() is not null;
$$;

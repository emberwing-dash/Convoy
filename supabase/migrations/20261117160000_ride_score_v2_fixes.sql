-- 20261117160000_ride_score_v2_fixes.sql
-- Logic audit of Ride Score v2 (20261117140000_leaderboard_v2.sql). Fixes:
--   1. Duplicate rides: the same trip saved twice (two phones, a reinstall, the same convoy ride logged
--      again) was counted twice. Now, per rider, a log is dropped when another of their logs overlaps it
--      in time or is for the same planned ride — the longer one is kept.
--   2. The 3-rides-a-day cap counted short (< 5 km) rides too, so three 2 km loops blocked a real ride's
--      points. Now only rides of 5 km or more fill the 3 daily slots.
--   3. The group bonus paid on any length; a 1 km group ride earned 10–15 pts. Now only rides ≥ 5 km.
--   4. The period was filtered by ride END while riding days use ride START, so a ride over midnight at
--      month end landed in one month but its day in another. Both now use the ride's start.
--   5. Levels (leaderboard and rider profiles) still came from the old per-ride points. They now come
--      from the all-time v2 Ride Score, so the same number appears everywhere.
-- All scoring now lives in one function, public.ride_scores(from, to), used by both the leaderboard
-- and rider profiles.

create or replace function public.ride_scores(p_from timestamptz default null, p_to timestamptz default null)
returns table(uid uuid, score integer, distance_km numeric, rides integer, longest_km numeric,
              best_streak integer, current_streak integer, group_rides integer,
              pts_distance integer, pts_rides integer, pts_longest integer, pts_streak integer, pts_group integer)
language sql stable security definer set search_path = public as $$
with valid as (       -- qualifying rides: ≥ 1 km and ≥ 60 s moving (record_ride_log already checked plausibility)
    select l.id, l.user_id as uid, l.ride_id, l.started_at, l.ended_at, l.distance_m / 1000.0 as km,
           l.rider_count, l.is_host, (l.started_at at time zone 'Asia/Kolkata')::date as d
    from ride_logs l
    where l.distance_m >= 1000 and l.moving_s >= 60
),
dedup as (            -- drop a log when a longer one of the same rider overlaps it or is for the same ride
    select v.* from valid v
    where not exists (
        select 1 from valid o
        where o.uid = v.uid and o.id <> v.id
          and ((o.started_at < v.ended_at and v.started_at < o.ended_at)
               or (v.ride_id is not null and o.ride_id = v.ride_id))
          and (o.km > v.km or (o.km = v.km and o.id < v.id)))
),
logs as (
    select * from dedup
    where (p_from is null or started_at >= p_from) and (p_to is null or started_at < p_to)
),
numbered as (         -- nth ride of ≥ 5 km that day, for the 3-a-day cap
    select logs.*,
           case when km >= 5 then row_number() over (partition by uid, d, (km >= 5) order by started_at) end as nth5
    from logs
),
agg as (
    select uid, sum(km) as dist_km, count(*)::int as n_rides, max(km) as longest,
           sum(least(km, 400) + 0.5 * greatest(km - 400, 0)) as d_pts,
           (10 * count(*) filter (where nth5 <= 3))::int as r_pts,
           count(*) filter (where rider_count >= 2 and km >= 5)::int as grp_n,
           coalesce(sum(case when rider_count >= 2 and km >= 5 then 10 + case when is_host then 5 else 0 end end), 0)::int as g_pts
    from numbered group by uid
),
p_days as (select distinct uid, d from logs where km >= 5),
p_runs as (select uid, count(*)::int as n
           from (select uid, d - (row_number() over (partition by uid order by d))::int as grp from p_days) s
           group by uid, grp),
p_best as (select uid, max(n) as best from p_runs group by uid),
a_days as (select distinct uid, d from dedup where km >= 5),
a_runs as (select uid, count(*)::int as n, max(d) as last_day
           from (select uid, d, d - (row_number() over (partition by uid order by d))::int as grp from a_days) s
           group by uid, grp),
a_cur as (select uid, max(n) as cur from a_runs
          where last_day >= (now() at time zone 'Asia/Kolkata')::date - 1 group by uid)
select a.uid,
       (round(a.d_pts)::int + a.r_pts + round(0.5 * least(a.longest, 1000))::int
        + 15 * greatest(least(coalesce(b.best, 0), 30) - 1, 0) + a.g_pts)::int,
       round(a.dist_km, 1), a.n_rides, round(a.longest, 1), coalesce(b.best, 0)::int, coalesce(c.cur, 0)::int, a.grp_n,
       round(a.d_pts)::int, a.r_pts, round(0.5 * least(a.longest, 1000))::int,
       (15 * greatest(least(coalesce(b.best, 0), 30) - 1, 0))::int, a.g_pts
from agg a left join p_best b on b.uid = a.uid left join a_cur c on c.uid = a.uid;
$$;
revoke all on function public.ride_scores(timestamptz, timestamptz) from public, anon, authenticated;

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
lifetime as (   -- level comes from the all-time Ride Score (only needed when a period is chosen)
    select l.uid, l.score from public.ride_scores(null, null) l where p_from is not null or p_to is not null
)
select r.rk, r.uid, p.display_name, p.username, p.avatar_data,
       r.v, r.score, r.distance_km, r.rides, r.longest_km, r.best_streak, r.current_streak, r.group_rides,
       r.pts_distance, r.pts_rides, r.pts_longest, r.pts_streak, r.pts_group,
       public.rider_level(coalesce(lt.score, r.score)::bigint), r.uid = auth.uid(), r.total_riders, r.total_v
from ranked r
left join profiles p on p.id = r.uid
left join lifetime lt on lt.uid = r.uid
where auth.uid() is not null
  and (r.rk <= least(greatest(p_limit, 3), 100) or r.uid = auth.uid())
order by r.rk, p.display_name;
$$;
revoke all on function public.leaderboard_v2(text, timestamptz, timestamptz, integer) from public, anon;
grant execute on function public.leaderboard_v2(text, timestamptz, timestamptz, integer) to authenticated;

-- Rider profiles show the same Ride Score and level as the leaderboard (same signature as before).
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
           public.rider_level(coalesce((select score from life), 0)::bigint),
           (select count(*)::int from public.crew_members a
              join public.crew_members b on b.crew_id = a.crew_id and b.user_id = auth.uid() and b.status = 'accepted'
             where a.user_id = p.id and a.status = 'accepted' and p.id <> auth.uid())
    from public.profiles p
    where p.id = p_user_id and auth.uid() is not null;
$$;

create index if not exists idx_ride_logs_user_started on public.ride_logs (user_id, started_at);

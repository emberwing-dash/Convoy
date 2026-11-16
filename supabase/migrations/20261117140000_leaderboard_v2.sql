-- 20261117140000_leaderboard_v2.sql
-- Convoy Ride Score v2 + five leaderboards (score, distance, rides, longest ride, streak).
--
-- Source of truth: public.ride_logs. Every row there already passed record_ride_log's checks
-- (signed-in rider, ended within 10 min of now, under 14 days old, elapsed time matches start/end,
-- average moving speed ≤ 200 km/h, rider really on the ride). Boards are computed LIVE from those
-- rows on every request — no cron, no cached totals — so a ride counts the moment its log uploads.
--
-- A ride qualifies when it is ≥ 1 km and ≥ 60 s of moving time.
-- Days are calendar days in India time (Asia/Kolkata), by the ride's start.
--
-- RIDE SCORE (per rider, inside the chosen period)
--   Distance  D = Σ min(km, 400) + 0.5 × Σ max(km − 400, 0)        → 1 pt/km, half beyond 400 km in one ride
--   Rides     R = 10 × rides of ≥ 5 km, at most 3 counted per day   → rewards riding often, stops farming
--   Longest   L = 0.5 × longest single ride km (capped at 1,000 km) → rewards endurance
--   Streak    S = 15 × (best streak − 1), streak capped at 30 days  → consecutive days with a ≥ 5 km ride
--   Group     G = 10 per group ride (≥ 2 riders) + 5 if you hosted it
--   SCORE = round(D) + R + round(L) + S + G
--
-- RANKING: by the board's metric, ties broken by score, then distance. Equal riders share a rank.
-- CURRENT STREAK (shown on your card) is all-time: the run of riding days ending today or yesterday.

create or replace function public.leaderboard_v2(
    p_metric text, p_from timestamptz default null, p_to timestamptz default null, p_limit integer default 10)
returns table(rank integer, user_id uuid, display_name text, username text, avatar_data text,
              value numeric, score integer, distance_km numeric, rides integer, longest_km numeric,
              best_streak integer, current_streak integer, group_rides integer,
              pts_distance integer, pts_rides integer, pts_longest integer, pts_streak integer, pts_group integer,
              level integer, is_me boolean, riders_ranked integer, period_total numeric)
language sql stable security definer set search_path = public as $$
with logs as (
    select l.user_id as uid, l.distance_m / 1000.0 as km, l.rider_count, l.is_host, l.ended_at,
           (l.started_at at time zone 'Asia/Kolkata')::date as d
    from ride_logs l
    where l.distance_m >= 1000 and l.moving_s >= 60
      and (p_from is null or l.ended_at >= p_from) and (p_to is null or l.ended_at < p_to)
),
numbered as (   -- nth qualifying ride of the day, for the 3-per-day cap
    select logs.*, row_number() over (partition by uid, d order by ended_at) as nth_of_day from logs
),
agg as (
    select uid,
           sum(km) as dist_km,
           count(*)::int as n_rides,
           max(km) as longest,
           sum(least(km, 400) + 0.5 * greatest(km - 400, 0)) as d_pts,
           sum(case when km >= 5 and nth_of_day <= 3 then 10 else 0 end)::int as r_pts,
           count(*) filter (where rider_count >= 2)::int as grp_n,
           sum(case when rider_count >= 2 then 10 + case when is_host then 5 else 0 end else 0 end)::int as g_pts
    from numbered group by uid
),
-- Best streak inside the period: islands of consecutive riding days (gaps-and-islands).
p_days as (select distinct uid, d from logs where km >= 5),
p_islands as (select uid, d - (row_number() over (partition by uid order by d))::int as grp from p_days),
p_best as (select uid, max(n)::int as best from (select uid, grp, count(*) as n from p_islands group by uid, grp) s group by uid),
-- Current streak: all-time riding days, the run that ends today or yesterday (India time).
a_days as (select distinct l.user_id as uid, (l.started_at at time zone 'Asia/Kolkata')::date as d
           from ride_logs l where l.distance_m >= 5000 and l.moving_s >= 60),
a_islands as (select uid, d, d - (row_number() over (partition by uid order by d))::int as grp from a_days),
a_runs as (select uid, count(*)::int as n, max(d) as last_day from a_islands group by uid, grp),
a_cur as (select uid, max(n) as cur from a_runs
          where last_day >= (now() at time zone 'Asia/Kolkata')::date - 1 group by uid),
scored as (
    select a.uid, a.dist_km, a.n_rides, a.longest, a.grp_n,
           round(a.d_pts)::int as pd, a.r_pts as pr,
           round(0.5 * least(a.longest, 1000))::int as pl,
           (15 * greatest(least(coalesce(b.best, 0), 30) - 1, 0))::int as ps,
           a.g_pts as pg,
           coalesce(b.best, 0) as best, coalesce(c.cur, 0)::int as cur
    from agg a left join p_best b on b.uid = a.uid left join a_cur c on c.uid = a.uid
),
valued as (
    select s.*, (s.pd + s.pr + s.pl + s.ps + s.pg) as sc,
           case p_metric
               when 'distance' then round(s.dist_km, 1)
               when 'rides'    then s.n_rides::numeric
               when 'longest'  then round(s.longest, 1)
               when 'streak'   then s.best::numeric
               else (s.pd + s.pr + s.pl + s.ps + s.pg)::numeric
           end as v
    from scored s
),
ranked as (
    select valued.*,
           rank() over (order by v desc, sc desc, dist_km desc)::int as rk,
           count(*) over ()::int as total_riders,
           sum(v) over () as total_v
    from valued where v > 0
),
lifetime as (select l.user_id as uid, sum(l.points)::bigint as pts from ride_logs l group by l.user_id)
select r.rk, r.uid, p.display_name, p.username, p.avatar_data,
       r.v, r.sc, round(r.dist_km, 1), r.n_rides, round(r.longest, 1), r.best, r.cur, r.grp_n,
       r.pd, r.pr, r.pl, r.ps, r.pg,
       public.rider_level(coalesce(lt.pts, 0)), r.uid = auth.uid(), r.total_riders, r.total_v
from ranked r
left join profiles p on p.id = r.uid
left join lifetime lt on lt.uid = r.uid
where auth.uid() is not null
  and (r.rk <= least(greatest(p_limit, 3), 100) or r.uid = auth.uid())
order by r.rk, p.display_name;
$$;
revoke all on function public.leaderboard_v2(text, timestamptz, timestamptz, integer) from public, anon;
grant execute on function public.leaderboard_v2(text, timestamptz, timestamptz, integer) to authenticated;

-- Live updates: every recorded ride pings the public "leaderboard" broadcast topic (no personal
-- data beyond who rode and how far, which the board shows anyway). Open boards refresh on it.
create or replace function public.broadcast_ride_logged()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    perform realtime.send(jsonb_build_object('user_id', new.user_id, 'km', round(new.distance_m / 1000.0, 1)),
                          'ride_logged', 'leaderboard', false);
    return new;
exception when others then
    return new;   -- a broadcast hiccup must never block saving the ride
end $$;
drop trigger if exists trg_broadcast_ride_logged on public.ride_logs;
create trigger trg_broadcast_ride_logged after insert on public.ride_logs
    for each row execute function public.broadcast_ride_logged();

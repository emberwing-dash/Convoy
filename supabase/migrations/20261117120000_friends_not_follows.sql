-- 20261117120000_friends_not_follows.sql
-- Convoy moves from "follow" to "friends" (request → accept). Suggestions are now based on
-- friendships: existing friends are hidden, friends-of-friends rank higher ("2 mutual friends"),
-- and the generic "Rider on Convoy" reason is gone (empty reason = nothing shown).
-- The follows table and its data are left in place (unused by the app), nothing is deleted.
create or replace function public.suggested_riders(p_limit integer default 10)
returns table(user_id uuid, display_name text, username text, avatar_data text, reason text,
              total_km numeric, rides_count integer, month_km numeric)
language sql stable security definer set search_path to 'public' as $function$
    with me as (select auth.uid() as id),
    my_friends as (
        select case when f.sender_id = (select id from me) then f.receiver_id else f.sender_id end as uid
        from public.friendships f
        where f.status = 'accepted' and (select id from me) in (f.sender_id, f.receiver_id)
    ),
    crew_mates as (
        select b.user_id as uid, min(c.name) as crew_name, count(distinct b.crew_id) as n
        from public.crew_members a
        join public.crew_members b on b.crew_id = a.crew_id and b.status = 'accepted'
        join public.crews c on c.id = a.crew_id
        where a.user_id = (select id from me) and a.status = 'accepted'
        group by b.user_id
    ),
    co_riders as (
        select b.user_id as uid, count(distinct b.ride_id) as n
        from public.ride_members a
        join public.ride_members b on b.ride_id = a.ride_id and b.status = 'accepted'
        where a.user_id = (select id from me) and a.status = 'accepted'
        group by b.user_id
    ),
    mutuals as (
        select case when f.sender_id = mf.uid then f.receiver_id else f.sender_id end as uid, count(*) as n
        from my_friends mf
        join public.friendships f on f.status = 'accepted' and mf.uid in (f.sender_id, f.receiver_id)
        group by 1
    ),
    stats as (
        select l.user_id as uid, round(sum(l.distance_m) / 1000.0, 1) as km, count(*)::int as rides,
               round(coalesce(sum(l.distance_m) filter (where l.ended_at >= date_trunc('month', now())), 0) / 1000.0, 1) as mkm
        from public.ride_logs l group by l.user_id
    ),
    candidates as (
        select p.id as uid,
               coalesce(cm.n, 0) * 5 + coalesce(cr.n, 0) * 4 + coalesce(mu.n, 0) * 3
                 + case when coalesce(s.mkm, 0) > 0 then 1 else 0 end as weight,
               case when cm.uid is not null then 'In your crew ' || cm.crew_name
                    when cr.uid is not null then 'Rode with you ' || cr.n || case when cr.n = 1 then ' time' else ' times' end
                    when mu.uid is not null then mu.n || ' mutual friend' || case when mu.n = 1 then '' else 's' end
                    when coalesce(s.mkm, 0) > 0 then 'Rode ' || s.mkm || ' km this month'
                    else '' end as reason,
               coalesce(s.km, 0) as km, coalesce(s.rides, 0) as rides, coalesce(s.mkm, 0) as mkm
        from public.profiles p
        left join crew_mates cm on cm.uid = p.id
        left join co_riders cr on cr.uid = p.id
        left join mutuals mu on mu.uid = p.id
        left join stats s on s.uid = p.id
        where p.id <> (select id from me)
          and not exists (select 1 from my_friends f where f.uid = p.id)
    )
    select c.uid, p.display_name, p.username, p.avatar_data, c.reason, c.km, c.rides, c.mkm
    from candidates c join public.profiles p on p.id = c.uid
    where auth.uid() is not null
    order by c.weight desc, c.mkm desc, c.km desc, p.created_at desc
    limit least(greatest(p_limit, 1), 30);
$function$;

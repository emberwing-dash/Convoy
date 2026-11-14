-- Tests for 20261116000000_ride_member_source.sql (runs after crew_social_test.sql, reusing its riders).
\set ON_ERROR_STOP 1
SET client_min_messages = warning;
RESET ROLE;
-- A = admin of crew Weekend Warriors (B is a member), C/D/E are outside the crew.
INSERT INTO public.rides (id, title, organiser_id, code, departs, from_location, to_location)
VALUES ('30000000-0000-0000-0000-000000000000', 'Andhra coast run', 'a0000000-0000-0000-0000-000000000000', 'AND333',
        now() + interval '3 days', 'Vizag, Andhra Pradesh', 'Araku');
SET ROLE authenticated;
SELECT test.as_user('a0000000-0000-0000-0000-000000000000');
-- Organiser row is always 'admin', whatever the app sends.
INSERT INTO public.ride_members (ride_id, user_id, role, status, source)
VALUES ('30000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000', 'organiser', 'accepted', 'friend');
-- Crew invite for a real crew member keeps its crew.
INSERT INTO public.ride_members (ride_id, user_id, role, status, source, crew_id)
VALUES ('30000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-000000000000', 'rider', 'invited', 'crew', 'f0000000-0000-0000-0000-000000000000');
-- Claiming a crew for someone outside it is corrected to a direct invite.
INSERT INTO public.ride_members (ride_id, user_id, role, status, source, crew_id)
VALUES ('30000000-0000-0000-0000-000000000000', 'c0000000-0000-0000-0000-000000000000', 'rider', 'invited', 'crew', 'f0000000-0000-0000-0000-000000000000');
-- 'feed' cannot be claimed without an accepted feed request.
INSERT INTO public.ride_members (ride_id, user_id, role, status, source)
VALUES ('30000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'rider', 'declined', 'feed');
RESET ROLE;
SELECT test.check((SELECT string_agg(user_id::text || '=' || source || ':' || COALESCE(crew_id::text, '-'), ',' ORDER BY user_id)
                   FROM public.ride_members WHERE ride_id = '30000000-0000-0000-0000-000000000000')
  = 'a0000000-0000-0000-0000-000000000000=admin:-,b0000000-0000-0000-0000-000000000000=crew:f0000000-0000-0000-0000-000000000000,'
    'c0000000-0000-0000-0000-000000000000=friend:-,e0000000-0000-0000-0000-000000000000=joined:-', 'sources enforced on insert');
SET ROLE authenticated;
-- The admin cannot relabel a crew rider as a feed joiner.
UPDATE public.ride_members SET source = 'feed' WHERE ride_id = '30000000-0000-0000-0000-000000000000' AND user_id = 'b0000000-0000-0000-0000-000000000000';
RESET ROLE;
SELECT test.check((SELECT source = 'crew' AND crew_id IS NOT NULL FROM public.ride_members
                   WHERE ride_id = '30000000-0000-0000-0000-000000000000' AND user_id = 'b0000000-0000-0000-0000-000000000000'), 'no relabelling');
SET ROLE authenticated;
SELECT public.post_open_ride('30000000-0000-0000-0000-000000000000', 'open', 10);

-- D asks from the feed, C (already invited as a friend) asks with the code, E (declined earlier) asks with the code.
SELECT test.as_user('d0000000-0000-0000-0000-000000000000');
SELECT public.create_ride_join_request('30000000-0000-0000-0000-000000000000', NULL, 'feed');
SELECT test.as_user('c0000000-0000-0000-0000-000000000000');
SELECT public.create_ride_join_request('30000000-0000-0000-0000-000000000000', NULL, 'code');
SELECT test.as_user('e0000000-0000-0000-0000-000000000000');
SELECT public.create_ride_join_request('30000000-0000-0000-0000-000000000000', NULL, 'code');
SELECT test.as_user('a0000000-0000-0000-0000-000000000000');
SELECT public.respond_ride_join_request(request_id, 'accept') FROM public.incoming_ride_join_requests()
 WHERE ride_id = '30000000-0000-0000-0000-000000000000';
RESET ROLE;
SELECT test.check((SELECT source FROM public.ride_members WHERE ride_id = '30000000-0000-0000-0000-000000000000'
                   AND user_id = 'd0000000-0000-0000-0000-000000000000') = 'feed', 'feed joiner tagged');
SELECT test.check((SELECT source || ':' || status FROM public.ride_members WHERE ride_id = '30000000-0000-0000-0000-000000000000'
                   AND user_id = 'c0000000-0000-0000-0000-000000000000') = 'friend:accepted', 'invited friend keeps friend tag');
SELECT test.check((SELECT source FROM public.ride_members WHERE ride_id = '30000000-0000-0000-0000-000000000000'
                   AND user_id = 'e0000000-0000-0000-0000-000000000000') = 'code', 'declined then joined by code');
SET ROLE authenticated;

-- Roster: admin and accepted riders see everyone with crew names; others see nothing.
SELECT test.check((SELECT string_agg(source || COALESCE('/' || crew_name, ''), ',') FROM public.ride_roster('30000000-0000-0000-0000-000000000000'))
                  = 'admin,crew/Weekend Warriors,friend,feed,code', 'roster grouped order');
SELECT test.as_user('d0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT COUNT(*) FROM public.ride_roster('30000000-0000-0000-0000-000000000000')) = 5, 'feed joiner sees roster');
SELECT test.check((SELECT is_me FROM public.ride_roster('30000000-0000-0000-0000-000000000000') WHERE source = 'feed'), 'is_me flag');
SELECT test.as_user('b0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT COUNT(*) FROM public.ride_roster('30000000-0000-0000-0000-000000000000')) = 0, 'invited but not accepted: no roster');
RESET ROLE;
SET ROLE anon;
SELECT test.fails($$SELECT * FROM public.ride_roster('30000000-0000-0000-0000-000000000000')$$, 'permission denied');
RESET ROLE;

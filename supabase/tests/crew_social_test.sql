-- End-to-end tests for 20261115000000_crew_social.sql, run as real API users through RLS.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;

CREATE SCHEMA test;
CREATE FUNCTION test.as_user(p UUID) RETURNS VOID LANGUAGE sql AS
$$ SELECT set_config('request.jwt.claim.sub', p::TEXT, false) $$;
CREATE FUNCTION test.check(ok BOOLEAN, label TEXT) RETURNS VOID LANGUAGE plpgsql AS
$$ BEGIN IF ok IS NOT TRUE THEN RAISE EXCEPTION 'FAILED: %', label; END IF; END $$;
-- Expects the statement to fail with a message containing p_msg.
CREATE FUNCTION test.fails(p_sql TEXT, p_msg TEXT) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    BEGIN EXECUTE p_sql;
    EXCEPTION WHEN others THEN
        IF position(p_msg IN SQLERRM) = 0 THEN RAISE EXCEPTION 'FAILED: % raised "%" not "%"', p_sql, SQLERRM, p_msg; END IF;
        RETURN;
    END;
    RAISE EXCEPTION 'FAILED: expected error "%" from %', p_msg, p_sql;
END $$;
GRANT USAGE ON SCHEMA test TO authenticated, anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA test TO authenticated, anon;

-- Riders: A admin (Kavya), B (Rishav), C (Rohan), D stranger, E (Suman)
INSERT INTO auth.users VALUES ('a0000000-0000-0000-0000-000000000000'), ('b0000000-0000-0000-0000-000000000000'),
  ('c0000000-0000-0000-0000-000000000000'), ('d0000000-0000-0000-0000-000000000000'), ('e0000000-0000-0000-0000-000000000000');
INSERT INTO public.profiles VALUES
  ('a0000000-0000-0000-0000-000000000000', 'kavya', 'Kavya', NULL),
  ('b0000000-0000-0000-0000-000000000000', 'rishav', 'Rishav', NULL),
  ('c0000000-0000-0000-0000-000000000000', 'rohan', 'Rohan', NULL),
  ('d0000000-0000-0000-0000-000000000000', 'dev', 'Dev', NULL),
  ('e0000000-0000-0000-0000-000000000000', 'suman', 'Suman', NULL);
INSERT INTO public.crews (id, name, code, created_by) VALUES
  ('f0000000-0000-0000-0000-000000000000', 'Weekend Warriors', 'WEE123', 'a0000000-0000-0000-0000-000000000000');
INSERT INTO public.crew_members (crew_id, user_id, role, status) VALUES
  ('f0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000', 'admin', 'accepted'),
  ('f0000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-000000000000', 'member', 'accepted');
INSERT INTO public.rides (id, title, organiser_id, code, departs, from_location, to_location, route_coords_json, route_km)
SELECT '10000000-0000-0000-0000-000000000000', 'Nandi Hills sunrise', 'a0000000-0000-0000-0000-000000000000', 'NAN234',
       now() + interval '2 days', 'Hebbal, Bengaluru, Karnataka', 'Nandi Hills, Karnataka',
       (SELECT json_agg(json_build_array(13.0 + i * 0.01, 77.5))::TEXT FROM generate_series(1, 20) i), 61.5;
INSERT INTO public.ride_members (ride_id, user_id, role, status) VALUES
  ('10000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000', 'organiser', 'accepted');

SET ROLE authenticated;

-- Pure helpers
SELECT test.check(public.ride_points(999, false, false) = 0, 'under 1 km earns no bonus');
SELECT test.check(public.ride_points(1000, false, false) = 11, '1 km solo = 1 + 10');
SELECT test.check(public.ride_points(50500, true, true) = 75, '50.5 km hosted group = 50 + 10 + 10 + 5');
SELECT test.check(public.ride_points(50500, false, true) = 60, 'host bonus needs a group');
SELECT test.check(public.rider_level(0) = 1 AND public.rider_level(99) = 1 AND public.rider_level(100) = 2
                  AND public.rider_level(299) = 2 AND public.rider_level(300) = 3 AND public.rider_level(1000) = 5, 'levels');
SELECT test.check(jsonb_array_length(public.route_preview('[[1,1],[2,2]]')) = 0, 'short routes are hidden');
SELECT test.check(public.route_preview('not json') = '[]'::jsonb, 'bad json is hidden');

-- Admin posts the ride to the feed
SELECT test.as_user('b0000000-0000-0000-0000-000000000000');
SELECT test.fails($$SELECT public.post_open_ride('10000000-0000-0000-0000-000000000000', 'x', 4)$$, 'Only the ride admin');
SELECT test.as_user('a0000000-0000-0000-0000-000000000000');
SELECT test.fails($$SELECT public.post_open_ride('10000000-0000-0000-0000-000000000000', 'x', 1)$$, 'Max riders must be between 2');
SELECT test.check(public.post_open_ride('10000000-0000-0000-0000-000000000000', 'Sunrise run, 4:45 start', 3) IS NOT NULL, 'post open ride');
SELECT test.check(public.post_open_ride('10000000-0000-0000-0000-000000000000', 'Edited caption', 3) IS NOT NULL, 're-posting edits');

-- Crew mate sees it with a trimmed route and area-only names; a stranger does not
SELECT test.as_user('b0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT COUNT(*) FROM public.crew_feed()) = 1, 'crew mate sees open ride');
SELECT test.check((SELECT caption FROM public.crew_feed()) = 'Edited caption', 'caption updated');
SELECT test.check((SELECT jsonb_array_length(route_preview) FROM public.crew_feed()) = 16, 'route trimmed 12% each end');
SELECT test.check((SELECT ride_from FROM public.crew_feed()) = 'Hebbal', 'start shown as area only');
SELECT test.check((SELECT members_count = 1 AND max_riders = 3 AND accepts_requests AND my_request_status IS NULL
                   AND NOT i_am_member AND pending_requests = 0 FROM public.crew_feed()), 'open ride state');
SELECT test.as_user('d0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT COUNT(*) FROM public.crew_feed()) = 1, 'feed is community-wide');

-- Requests
SELECT test.as_user('b0000000-0000-0000-0000-000000000000');
SELECT test.check((public.create_ride_join_request('10000000-0000-0000-0000-000000000000', '  Hi Kavya!  ', 'feed') ->> 'note') = 'Hi Kavya!', 'request with trimmed note');
SELECT test.fails($$SELECT public.create_ride_join_request('10000000-0000-0000-0000-000000000000', NULL, 'feed')$$, 'duplicate key');
SELECT test.check((SELECT my_request_status FROM public.crew_feed()) = 'pending', 'feed shows my pending request');
SELECT test.as_user('a0000000-0000-0000-0000-000000000000');
SELECT test.fails($$SELECT public.create_ride_join_request('10000000-0000-0000-0000-000000000000')$$, 'your own ride');
SELECT test.check((SELECT COUNT(*) FROM public.notifications WHERE kind = 'ride_join_request') = 1, 'admin got a request notification');
SELECT test.check((SELECT COUNT(*) FROM public.my_notifications()) = 0, 'actionable requests are not in the info inbox');
SELECT test.check((SELECT note = 'Hi Kavya!' AND display_name = 'Rishav' AND shared_crews = 1 AND members_count = 1 AND max_riders = 3
                   FROM public.incoming_ride_join_requests()), 'incoming request details');
SELECT test.check((SELECT pending_requests FROM public.crew_feed()) = 1, 'admin sees pending count');

SELECT test.as_user('c0000000-0000-0000-0000-000000000000');
INSERT INTO public.follows (follower_id, followee_id) VALUES ('c0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000');
SELECT test.fails($$INSERT INTO public.follows VALUES ('c0000000-0000-0000-0000-000000000000', 'c0000000-0000-0000-0000-000000000000')$$, 'follows_not_self');
SELECT test.fails($$INSERT INTO public.follows (follower_id, followee_id) VALUES ('d0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000')$$, 'row-level security');
SELECT test.check((SELECT COUNT(*) FROM public.crew_feed()) = 1, 'follower sees the post');
SELECT public.create_ride_join_request('10000000-0000-0000-0000-000000000000', NULL, 'feed');
SELECT test.as_user('e0000000-0000-0000-0000-000000000000');
SELECT public.create_ride_join_request('10000000-0000-0000-0000-000000000000');

SELECT test.as_user('a0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT COUNT(*) FROM public.my_notifications() WHERE kind = 'new_follower') = 1, 'new follower notification');
SELECT test.check((SELECT COUNT(*) FROM public.incoming_ride_join_requests()) = 3, 'three pending');
SELECT test.check((public.respond_ride_join_request((SELECT request_id FROM public.incoming_ride_join_requests() WHERE display_name = 'Rishav'), 'accept') ->> 'members_count')::INT = 2, 'accept Rishav');
SELECT test.check((public.respond_ride_join_request((SELECT request_id FROM public.incoming_ride_join_requests() WHERE display_name = 'Rohan'), 'accept') ->> 'members_count')::INT = 3, 'accept Rohan fills the ride');
SELECT test.check((SELECT NOT accepts_requests FROM public.crew_feed()), 'full ride stops taking requests');
SELECT test.check((SELECT COUNT(*) FROM public.notifications WHERE kind = 'ride_join_request' AND read_at IS NULL) = 1, 'handled requests are resolved');
SELECT test.fails($$SELECT public.respond_ride_join_request((SELECT request_id FROM public.incoming_ride_join_requests() WHERE display_name = 'Suman'), 'accept')$$, 'Ride is full');
SELECT test.as_user('d0000000-0000-0000-0000-000000000000');
SELECT test.fails($$SELECT public.create_ride_join_request('10000000-0000-0000-0000-000000000000', NULL, 'feed')$$, 'not taking requests');
SELECT test.fails($$SELECT public.create_ride_join_request('10000000-0000-0000-0000-000000000000')$$, 'Ride is full');
SELECT test.fails($$SELECT public.respond_ride_join_request((SELECT id FROM public.ride_join_requests LIMIT 1), 'accept')$$, 'not found');

SELECT test.as_user('e0000000-0000-0000-0000-000000000000');
SELECT public.cancel_ride_join_request((SELECT id FROM public.ride_join_requests WHERE status = 'pending'));
SELECT test.as_user('a0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT COUNT(*) FROM public.notifications WHERE kind = 'ride_join_request') = 2, 'cancelled request leaves the admin inbox');
SELECT test.check((SELECT COUNT(*) FROM public.incoming_ride_join_requests()) = 0, 'nothing pending');

SELECT test.as_user('b0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT kind FROM public.my_notifications() LIMIT 1) = 'ride_join_accepted'
                  AND (SELECT ride_title FROM public.my_notifications() LIMIT 1) = 'Nandi Hills sunrise', 'requester told they are in');
SELECT test.check((SELECT i_am_member FROM public.crew_feed()), 'feed knows I am in');

-- Recorded rides and points
SELECT test.check((public.record_ride_log('20000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000000', 'Nandi Hills sunrise',
    'Hebbal', 'Nandi Hills', now() - interval '2 hours', now() - interval '1 hour', 58000, 3000, 3600, 92.4, 'abc') ->> 'points')::INT = 78,
    'group rider points 58 + 10 + 10');
SELECT test.check((public.record_ride_log('20000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000000', 'retry',
    'Hebbal', 'Nandi Hills', now() - interval '2 hours', now() - interval '1 hour', 58000, 3000, 3600, 92.4, 'abc') ->> 'title') = 'Nandi Hills sunrise',
    'upload retry is idempotent');
SELECT test.fails($$SELECT public.record_ride_log(gen_random_uuid(), NULL, 'Fake', '', '', now() - interval '1 hour', now(), 300000, 3600, 3600, 100, '')$$, 'not plausible');
SELECT test.fails($$SELECT public.record_ride_log(gen_random_uuid(), NULL, 'Fake', '', '', now() - interval '1 hour', now(), 1000, 3600, 100, 100, '')$$, 'Elapsed time');
SELECT test.fails($$SELECT public.record_ride_log(gen_random_uuid(), NULL, 'Future', '', '', now(), now() + interval '1 hour', 1000, 3600, 3600, 10, '')$$, 'future');
SELECT test.fails($$INSERT INTO public.ride_logs (user_id, client_log_id, title, started_at, ended_at, distance_m, moving_s, elapsed_s)
                    VALUES ('b0000000-0000-0000-0000-000000000000', gen_random_uuid(), 'x', now(), now(), 999999, 1, 1)$$, 'row-level security');
SELECT test.as_user('d0000000-0000-0000-0000-000000000000');
SELECT test.fails($$SELECT public.record_ride_log(gen_random_uuid(), '10000000-0000-0000-0000-000000000000', 'x', '', '', now() - interval '1 hour', now(), 1000, 600, 3600, 10, '')$$, 'not a rider');
SELECT public.record_ride_log(gen_random_uuid(), '99999999-0000-0000-0000-000000000000', 'Solo', 'Home', 'Lake', now() - interval '30 minutes', now(), 12000, 1500, 1800, 61, '');
SELECT test.check((SELECT COUNT(*) FROM public.ride_logs) = 1 AND (SELECT ride_id IS NULL AND points = 22 FROM public.ride_logs), 'stranger only sees own log; unknown ride is solo');
SELECT test.as_user('a0000000-0000-0000-0000-000000000000');
SELECT test.check((public.record_ride_log(gen_random_uuid(), '10000000-0000-0000-0000-000000000000', 'Nandi Hills sunrise',
    'Hebbal', 'Nandi Hills', now() - interval '2 hours', now() - interval '1 hour', 60000, 3600, 3600, 88, '') ->> 'points')::INT = 85,
    'host points 60 + 10 + 10 + 5');

-- Sharing, likes, comments
SELECT test.as_user('b0000000-0000-0000-0000-000000000000');
SELECT public.share_ride_log((SELECT id FROM public.ride_logs), 'Chai at the top');
SELECT test.fails($$SELECT public.share_ride_log(gen_random_uuid(), 'x')$$, 'Ride log not found');
SELECT test.as_user('a0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT distance_m = 58000 AND moving_s = 3000 AND rider_count = 3 AND path_polyline = 'abc'
                   FROM public.crew_feed() WHERE kind = 'ride_log'), 'crew mate recap in feed');
SELECT test.check((public.toggle_post_like((SELECT post_id FROM public.crew_feed() WHERE kind = 'ride_log')) ->> 'liked')::BOOLEAN, 'like');
SELECT test.check(NOT (public.toggle_post_like((SELECT post_id FROM public.crew_feed() WHERE kind = 'ride_log')) ->> 'liked')::BOOLEAN, 'unlike');
SELECT public.toggle_post_like((SELECT post_id FROM public.crew_feed() WHERE kind = 'ride_log'));
SELECT public.add_post_comment((SELECT post_id FROM public.crew_feed() WHERE kind = 'ride_log'), 'Great run!');
SELECT test.fails($$SELECT public.add_post_comment((SELECT post_id FROM public.crew_feed() WHERE kind = 'ride_log'), '   ')$$, 'check constraint');
SELECT test.check((SELECT like_count = 1 AND comment_count = 1 AND liked_by_me FROM public.crew_feed() WHERE kind = 'ride_log'), 'counts');
SELECT test.check((SELECT COUNT(*) FROM public.crew_feed(NULL, 20, 'b0000000-0000-0000-0000-000000000000')) = 1, 'profile feed filter');
SELECT test.as_user('d0000000-0000-0000-0000-000000000000');
SELECT test.fails($$SELECT public.toggle_post_like(gen_random_uuid())$$, 'Post not found');
SELECT test.check((SELECT COUNT(*) FROM public.post_comments_list((SELECT post_id FROM public.crew_feed() WHERE kind = 'ride_log'))) = 1, 'any rider can read comments');
SELECT test.as_user('b0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT COUNT(*) FROM public.my_notifications() WHERE kind IN ('post_like', 'post_comment')) = 2, 'like + comment notified once each');
SELECT test.check((SELECT body FROM public.post_comments_list((SELECT post_id FROM public.crew_feed() WHERE kind = 'ride_log'))) = 'Great run!', 'comments list');
SELECT public.mark_notifications_read(NULL);
SELECT test.check((SELECT COUNT(*) FROM public.my_notifications() WHERE read_at IS NULL) = 0, 'mark read');
SELECT test.as_user('c0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT COUNT(*) FROM public.notifications) = 1, 'RLS: only my own notifications');

-- Leaderboards
SELECT test.check((SELECT string_agg(display_name || ':' || value, ',' ORDER BY rank) FROM public.leaderboard('score', date_trunc('month', now()), NULL, 10))
                  = 'Kavya:85,Rishav:78,Dev:22', 'score board');
SELECT test.check((SELECT string_agg(display_name || ':' || value, ',' ORDER BY rank) FROM public.leaderboard('distance', NULL, NULL, 10))
                  = 'Kavya:60.0,Rishav:58.0,Dev:12.0', 'distance board');
SELECT test.check((SELECT DISTINCT riders_ranked = 3 AND period_total = 130.0 FROM public.leaderboard('distance', NULL, NULL, 10)), 'board totals');
SELECT test.check((SELECT COUNT(*) FROM public.leaderboard('score', now() - interval '10 days', now() - interval '5 days', 10)) = 0, 'empty period');
SELECT test.as_user('d0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT rank = 3 FROM public.leaderboard('score', NULL, NULL, 3) WHERE is_me), 'my row flagged');
SELECT test.fails($$SELECT * FROM public.leaderboard('speed', NULL, NULL, 3)$$, 'Invalid metric');

-- Suggestions and profiles
SELECT test.as_user('b0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT reason FROM public.suggested_riders() WHERE display_name = 'Kavya') = 'In your crew Weekend Warriors', 'crew suggestion');
SELECT test.check((SELECT reason FROM public.suggested_riders() WHERE display_name = 'Rohan') = 'Rode with you 1 time', 'co-rider suggestion');
SELECT test.check((SELECT reason FROM public.suggested_riders() WHERE display_name = 'Dev') = 'Rode 12.0 km this month', 'active rider suggestion');
SELECT test.check((SELECT reason FROM public.suggested_riders() WHERE display_name = 'Suman') = 'Rider on Convoy', 'every real rider can be suggested');
SELECT test.check((SELECT COUNT(*) FROM public.suggested_riders() WHERE display_name = 'Rishav') = 0, 'never suggest me');
INSERT INTO public.follows (follower_id, followee_id) VALUES ('b0000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT COUNT(*) FROM public.suggested_riders() WHERE display_name = 'Kavya') = 0, 'followed riders drop out');
SELECT test.check((SELECT followers = 2 AND i_follow AND NOT follows_me AND total_km = 60.0 AND rides_count = 1
                   AND total_points = 85 AND level = 1 AND shared_crews = 1 FROM public.rider_profile('a0000000-0000-0000-0000-000000000000')), 'rider profile');

-- Ride invitations (live app writes 'invited')
RESET ROLE;
INSERT INTO public.ride_members (ride_id, user_id, role, status)
VALUES ('10000000-0000-0000-0000-000000000000', 'd0000000-0000-0000-0000-000000000000', 'rider', 'invited');
SET ROLE authenticated;
SELECT test.as_user('d0000000-0000-0000-0000-000000000000');
SELECT test.check((public.respond_ride_invitation('10000000-0000-0000-0000-000000000000', false) ->> 'status') = 'declined', 'invitee declines');
SELECT test.fails($$SELECT public.respond_ride_invitation('10000000-0000-0000-0000-000000000000', true)$$, 'only invited members');
SELECT test.fails($$SELECT public.complete_group_ride('10000000-0000-0000-0000-000000000000')$$, 'Only the ride organiser');

-- Finishing the ride removes the open post but keeps recaps
SELECT test.as_user('a0000000-0000-0000-0000-000000000000');
SELECT public.complete_group_ride('10000000-0000-0000-0000-000000000000');
SELECT test.as_user('b0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT string_agg(kind, ',') FROM public.crew_feed()) = 'ride_log', 'finished open ride leaves the feed');
SELECT test.check((SELECT is_completed AND completed_at IS NOT NULL FROM public.rides WHERE id = '10000000-0000-0000-0000-000000000000'), 'completion recorded');
SELECT test.fails($$SELECT public.create_ride_join_request('10000000-0000-0000-0000-000000000000')$$, 'already finished');

-- Grants
RESET ROLE;
SET ROLE anon;
SELECT test.fails($$SELECT * FROM public.crew_feed()$$, 'permission denied');
SELECT test.fails($$SELECT public.complete_group_ride('10000000-0000-0000-0000-000000000000')$$, 'permission denied');
RESET ROLE;

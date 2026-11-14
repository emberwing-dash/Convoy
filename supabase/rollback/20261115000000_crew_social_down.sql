-- Undo for 20261115000000_crew_social.sql on the live Convoy project.
-- Removes only what that migration added and restores the original ride_members status check.
-- WARNING: deletes everything stored in the new tables (ride logs, posts, likes, comments,
-- follows, notifications, join requests). Run only to back the migration out.
BEGIN;

DROP TRIGGER IF EXISTS trg_notify_ride_join_request ON public.ride_join_requests;
DROP TRIGGER IF EXISTS trg_notify_new_follower ON public.follows;
DROP TRIGGER IF EXISTS trg_notify_post_like ON public.post_likes;
DROP TRIGGER IF EXISTS trg_notify_post_comment ON public.post_comments;

DROP FUNCTION IF EXISTS public.record_ride_log(UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, INT, INT, INT, NUMERIC, TEXT);
DROP FUNCTION IF EXISTS public.share_ride_log(UUID, TEXT);
DROP FUNCTION IF EXISTS public.post_open_ride(UUID, TEXT, INT);
DROP FUNCTION IF EXISTS public.close_open_ride(UUID);
DROP FUNCTION IF EXISTS public.create_ride_join_request(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.respond_ride_join_request(UUID, TEXT);
DROP FUNCTION IF EXISTS public.cancel_ride_join_request(UUID);
DROP FUNCTION IF EXISTS public.incoming_ride_join_requests();
DROP FUNCTION IF EXISTS public.respond_ride_invitation(UUID, BOOLEAN);
DROP FUNCTION IF EXISTS public.complete_group_ride(UUID);
DROP FUNCTION IF EXISTS public.my_notifications(INT);
DROP FUNCTION IF EXISTS public.mark_notifications_read(UUID[]);
DROP FUNCTION IF EXISTS public.crew_feed(TIMESTAMPTZ, INT, UUID);
DROP FUNCTION IF EXISTS public.toggle_post_like(UUID);
DROP FUNCTION IF EXISTS public.add_post_comment(UUID, TEXT);
DROP FUNCTION IF EXISTS public.post_comments_list(UUID);
DROP FUNCTION IF EXISTS public.can_see_post(UUID);
DROP FUNCTION IF EXISTS public.leaderboard(TEXT, TIMESTAMPTZ, TIMESTAMPTZ, INT);
DROP FUNCTION IF EXISTS public.suggested_riders(INT);
DROP FUNCTION IF EXISTS public.rider_profile(UUID);
DROP FUNCTION IF EXISTS public.notify_ride_join_request();
DROP FUNCTION IF EXISTS public.notify_new_follower();
DROP FUNCTION IF EXISTS public.notify_post_activity();
DROP FUNCTION IF EXISTS public.accepted_rider_count(UUID);
DROP FUNCTION IF EXISTS public.route_preview(TEXT);
DROP FUNCTION IF EXISTS public.ride_points(INT, BOOLEAN, BOOLEAN);
DROP FUNCTION IF EXISTS public.rider_level(BIGINT);

DROP TABLE IF EXISTS public.notifications;
DROP TABLE IF EXISTS public.post_comments;
DROP TABLE IF EXISTS public.post_likes;
DROP TABLE IF EXISTS public.feed_posts;
DROP TABLE IF EXISTS public.ride_logs;
DROP TABLE IF EXISTS public.follows;
DROP TABLE IF EXISTS public.ride_join_requests;

ALTER TABLE public.rides DROP COLUMN IF EXISTS max_riders;
ALTER TABLE public.rides DROP COLUMN IF EXISTS accepts_requests;

-- Invited rows did not exist before; turn any into pending so the original check holds.
UPDATE public.ride_members SET status = 'pending' WHERE status = 'invited';
ALTER TABLE public.ride_members DROP CONSTRAINT IF EXISTS ride_members_status_check;
ALTER TABLE public.ride_members ADD CONSTRAINT ride_members_status_check
    CHECK (status IN ('pending', 'accepted', 'declined'));

COMMIT;

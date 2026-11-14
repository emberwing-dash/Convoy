-- =============================================================================
-- Migration: 20261115000000_crew_social.sql
-- Crew tab backend: recorded ride logs, follows, feed posts (ride recaps and
-- open rides that accept join requests), likes, comments, a notification inbox
-- with realtime delivery, leaderboards, suggested riders and rider profiles.
--
-- REVIEW BEFORE APPLYING. Requires the existing tables: profiles, rides,
-- ride_members, ride_join_requests (20261104000000), crews, crew_members.
--
-- Rider score (one formula, used everywhere — see public.ride_points):
--   per recorded ride  = floor(km)                       distance points
--                      + 10 if the ride covered >= 1 km  completion bonus
--                      + 10 if it was a group ride (>= 2 accepted riders)
--                      +  5 more if you hosted that group ride
-- Level from all-time points: level n starts at 50 * n * (n - 1) points
--   (Lv1 0, Lv2 100, Lv3 300, Lv4 600, Lv5 1000 …).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Ride columns used by open rides
-- -----------------------------------------------------------------------------
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS max_riders INT
    CHECK (max_riders IS NULL OR max_riders BETWEEN 2 AND 50);
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS accepts_requests BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.ride_join_requests ADD COLUMN IF NOT EXISTS note TEXT
    CHECK (note IS NULL OR char_length(note) <= 200);
ALTER TABLE public.ride_join_requests ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'code'
    CHECK (source IN ('code', 'feed'));

-- -----------------------------------------------------------------------------
-- 1. Recorded rides (GPS distance actually ridden, not the planned route)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ride_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    client_log_id   UUID NOT NULL,                       -- idempotent uploads from the device
    ride_id         UUID REFERENCES public.rides(id) ON DELETE SET NULL,
    title           TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
    start_name      TEXT NOT NULL DEFAULT '' CHECK (char_length(start_name) <= 120),
    end_name        TEXT NOT NULL DEFAULT '' CHECK (char_length(end_name) <= 120),
    started_at      TIMESTAMPTZ NOT NULL,
    ended_at        TIMESTAMPTZ NOT NULL,
    distance_m      INT NOT NULL CHECK (distance_m BETWEEN 0 AND 2000000),
    moving_s        INT NOT NULL CHECK (moving_s >= 0),
    elapsed_s       INT NOT NULL CHECK (elapsed_s >= 0 AND elapsed_s <= 172800),
    max_speed_kmh   NUMERIC(5,1) NOT NULL DEFAULT 0 CHECK (max_speed_kmh BETWEEN 0 AND 300),
    path_polyline   TEXT NOT NULL DEFAULT '' CHECK (char_length(path_polyline) <= 40000),
    rider_count     INT NOT NULL DEFAULT 1 CHECK (rider_count >= 1),
    is_host         BOOLEAN NOT NULL DEFAULT false,
    points          INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ride_logs_time_order CHECK (ended_at >= started_at),
    CONSTRAINT ride_logs_moving_le_elapsed CHECK (moving_s <= elapsed_s),
    CONSTRAINT ride_logs_client_unique UNIQUE (user_id, client_log_id)
);
CREATE INDEX IF NOT EXISTS idx_ride_logs_user_ended ON public.ride_logs (user_id, ended_at DESC);
CREATE INDEX IF NOT EXISTS idx_ride_logs_ended ON public.ride_logs (ended_at);

ALTER TABLE public.ride_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Riders read their own ride logs" ON public.ride_logs;
CREATE POLICY "Riders read their own ride logs" ON public.ride_logs
    FOR SELECT USING (auth.uid() = user_id);
-- Inserts and updates go through record_ride_log() so points and plausibility are server-checked.
DROP POLICY IF EXISTS "Riders delete their own ride logs" ON public.ride_logs;
CREATE POLICY "Riders delete their own ride logs" ON public.ride_logs
    FOR DELETE USING (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- 2. Follows
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.follows (
    follower_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    followee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followee_id),
    CONSTRAINT follows_not_self CHECK (follower_id <> followee_id)
);
CREATE INDEX IF NOT EXISTS idx_follows_followee ON public.follows (followee_id);

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Follows are visible to signed-in riders" ON public.follows;
CREATE POLICY "Follows are visible to signed-in riders" ON public.follows
    FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "Riders follow as themselves" ON public.follows;
CREATE POLICY "Riders follow as themselves" ON public.follows
    FOR INSERT WITH CHECK (auth.uid() = follower_id);
DROP POLICY IF EXISTS "Riders unfollow as themselves" ON public.follows;
CREATE POLICY "Riders unfollow as themselves" ON public.follows
    FOR DELETE USING (auth.uid() = follower_id);

-- -----------------------------------------------------------------------------
-- 3. Feed posts, likes, comments
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.feed_posts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    kind        TEXT NOT NULL CHECK (kind IN ('ride_log', 'open_ride')),
    ride_log_id UUID REFERENCES public.ride_logs(id) ON DELETE CASCADE,
    ride_id     UUID REFERENCES public.rides(id) ON DELETE CASCADE,
    caption     TEXT NOT NULL DEFAULT '' CHECK (char_length(caption) <= 500),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT feed_posts_shape CHECK (
        (kind = 'ride_log'  AND ride_log_id IS NOT NULL) OR
        (kind = 'open_ride' AND ride_id IS NOT NULL)
    )
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_feed_posts_one_per_log  ON public.feed_posts (ride_log_id) WHERE ride_log_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_feed_posts_one_per_ride ON public.feed_posts (ride_id) WHERE kind = 'open_ride';
CREATE INDEX IF NOT EXISTS idx_feed_posts_author_created ON public.feed_posts (author_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.post_likes (
    post_id    UUID NOT NULL REFERENCES public.feed_posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.post_comments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID NOT NULL REFERENCES public.feed_posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    body       TEXT NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_post_comments_post ON public.post_comments (post_id, created_at);

-- Everything is read through the RPCs below, which apply audience rules.
ALTER TABLE public.feed_posts    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_likes    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authors read their own posts" ON public.feed_posts;
CREATE POLICY "Authors read their own posts" ON public.feed_posts FOR SELECT USING (auth.uid() = author_id);
DROP POLICY IF EXISTS "Authors delete their own posts" ON public.feed_posts;
CREATE POLICY "Authors delete their own posts" ON public.feed_posts FOR DELETE USING (auth.uid() = author_id);
DROP POLICY IF EXISTS "Riders delete their own comments" ON public.post_comments;
CREATE POLICY "Riders delete their own comments" ON public.post_comments FOR DELETE USING (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- 4. Notification inbox (written only by triggers; delivered over Realtime)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    actor_id     UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    kind         TEXT NOT NULL CHECK (kind IN ('ride_join_request', 'ride_join_accepted', 'ride_join_declined',
                                               'new_follower', 'post_like', 'post_comment')),
    ride_id      UUID REFERENCES public.rides(id) ON DELETE CASCADE,
    request_id   UUID REFERENCES public.ride_join_requests(id) ON DELETE CASCADE,
    post_id      UUID REFERENCES public.feed_posts(id) ON DELETE CASCADE,
    body         TEXT NOT NULL DEFAULT '',
    read_at      TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON public.notifications (recipient_id, created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Recipients read their notifications" ON public.notifications;
CREATE POLICY "Recipients read their notifications" ON public.notifications
    FOR SELECT USING (auth.uid() = recipient_id);
DROP POLICY IF EXISTS "Recipients delete their notifications" ON public.notifications;
CREATE POLICY "Recipients delete their notifications" ON public.notifications
    FOR DELETE USING (auth.uid() = recipient_id);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
       AND NOT EXISTS (SELECT 1 FROM pg_publication_tables
                       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'notifications') THEN
        EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications';
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 5. Helpers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ride_points(p_distance_m INT, p_is_group BOOLEAN, p_is_host BOOLEAN)
RETURNS INT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_distance_m < 1000 THEN floor(p_distance_m / 1000.0)::INT
           ELSE floor(p_distance_m / 1000.0)::INT + 10
                + CASE WHEN p_is_group THEN 10 ELSE 0 END
                + CASE WHEN p_is_group AND p_is_host THEN 5 ELSE 0 END
           END;
$$;

CREATE OR REPLACE FUNCTION public.rider_level(p_points BIGINT)
RETURNS INT LANGUAGE sql IMMUTABLE AS $$
    -- largest n with 50 * n * (n - 1) <= points
    SELECT GREATEST(1, floor((1 + sqrt(1 + 4 * GREATEST(p_points, 0) / 50.0)) / 2)::INT);
$$;

-- Riders whose posts I may see: me, people I follow, and accepted members of my crews.
CREATE OR REPLACE FUNCTION public.audience_of(p_viewer UUID)
RETURNS TABLE (user_id UUID) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT p_viewer
    UNION SELECT f.followee_id FROM public.follows f WHERE f.follower_id = p_viewer
    UNION SELECT other.user_id
          FROM public.crew_members mine
          JOIN public.crew_members other ON other.crew_id = mine.crew_id AND other.status = 'accepted'
          WHERE mine.user_id = p_viewer AND mine.status = 'accepted';
$$;
REVOKE EXECUTE ON FUNCTION public.audience_of(UUID) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.accepted_rider_count(p_ride_id UUID)
RETURNS INT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COUNT(*)::INT FROM public.ride_members WHERE ride_id = p_ride_id AND status = 'accepted';
$$;
REVOKE EXECUTE ON FUNCTION public.accepted_rider_count(UUID) FROM public, anon, authenticated;

-- Drops the first and last 12% of a planned route so open-ride previews never reveal the exact
-- meeting point or destination address. Input is the rides.route_coords_json text "[[lat,lon],…]".
CREATE OR REPLACE FUNCTION public.route_preview(p_coords TEXT)
RETURNS JSONB LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v JSONB; n INT; cut INT;
BEGIN
    IF p_coords IS NULL OR btrim(p_coords) = '' THEN RETURN '[]'::jsonb; END IF;
    BEGIN v := p_coords::jsonb; EXCEPTION WHEN others THEN RETURN '[]'::jsonb; END;
    IF jsonb_typeof(v) <> 'array' THEN RETURN '[]'::jsonb; END IF;
    n := jsonb_array_length(v);
    IF n < 8 THEN RETURN '[]'::jsonb; END IF;
    cut := GREATEST(1, floor(n * 0.12)::INT);
    RETURN COALESCE((SELECT jsonb_agg(e ORDER BY i) FROM jsonb_array_elements(v) WITH ORDINALITY t(e, i)
                     WHERE i > cut AND i <= n - cut), '[]'::jsonb);
END;
$$;

-- -----------------------------------------------------------------------------
-- 6. Recording rides
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_ride_log(
    p_client_log_id UUID, p_ride_id UUID, p_title TEXT, p_start_name TEXT, p_end_name TEXT,
    p_started_at TIMESTAMPTZ, p_ended_at TIMESTAMPTZ, p_distance_m INT, p_moving_s INT, p_elapsed_s INT,
    p_max_speed_kmh NUMERIC, p_path_polyline TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
    v_user UUID := auth.uid();
    v_ride_id UUID := NULL;
    v_is_host BOOLEAN := false;
    v_riders INT := 1;
    v_points INT;
    v_row public.ride_logs;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Unauthorized: User not authenticated'; END IF;
    IF p_ended_at > now() + interval '10 minutes' THEN RAISE EXCEPTION 'Ride ends in the future'; END IF;
    IF p_started_at < now() - interval '14 days' THEN RAISE EXCEPTION 'Ride is too old to record'; END IF;
    IF abs(p_elapsed_s - extract(epoch FROM (p_ended_at - p_started_at))) > 120 THEN
        RAISE EXCEPTION 'Elapsed time does not match start and end';
    END IF;
    -- 200 km/h average while moving is the plausibility ceiling for a motorcycle ride log.
    IF p_distance_m > 0 AND (p_moving_s = 0 OR p_distance_m::NUMERIC / p_moving_s > 55.6) THEN
        RAISE EXCEPTION 'Distance is not plausible for the time spent moving';
    END IF;

    IF p_ride_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.rides WHERE id = p_ride_id) THEN
        IF NOT EXISTS (SELECT 1 FROM public.rides WHERE id = p_ride_id AND organiser_id = v_user)
           AND NOT EXISTS (SELECT 1 FROM public.ride_members
                           WHERE ride_id = p_ride_id AND user_id = v_user AND status = 'accepted') THEN
            RAISE EXCEPTION 'Forbidden: You are not a rider on this ride';
        END IF;
        v_ride_id := p_ride_id;
        v_is_host := EXISTS (SELECT 1 FROM public.rides WHERE id = p_ride_id AND organiser_id = v_user);
        v_riders  := GREATEST(1, public.accepted_rider_count(p_ride_id));
    END IF;

    v_points := public.ride_points(p_distance_m, v_riders >= 2, v_is_host);

    INSERT INTO public.ride_logs (user_id, client_log_id, ride_id, title, start_name, end_name, started_at, ended_at,
                                  distance_m, moving_s, elapsed_s, max_speed_kmh, path_polyline,
                                  rider_count, is_host, points)
    VALUES (v_user, p_client_log_id, v_ride_id, left(btrim(p_title), 120), left(COALESCE(p_start_name, ''), 120),
            left(COALESCE(p_end_name, ''), 120), p_started_at, p_ended_at, p_distance_m, p_moving_s, p_elapsed_s,
            round(LEAST(GREATEST(p_max_speed_kmh, 0), 300), 1), COALESCE(p_path_polyline, ''),
            v_riders, v_is_host, v_points)
    ON CONFLICT (user_id, client_log_id) DO UPDATE SET client_log_id = EXCLUDED.client_log_id
    RETURNING * INTO v_row;

    RETURN to_jsonb(v_row);
END;
$$;

-- -----------------------------------------------------------------------------
-- 7. Posting
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.share_ride_log(p_ride_log_id UUID, p_caption TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_user UUID := auth.uid(); v_id UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Unauthorized: User not authenticated'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.ride_logs WHERE id = p_ride_log_id AND user_id = v_user) THEN
        RAISE EXCEPTION 'Ride log not found';
    END IF;
    INSERT INTO public.feed_posts (author_id, kind, ride_log_id, caption)
    VALUES (v_user, 'ride_log', p_ride_log_id, left(btrim(COALESCE(p_caption, '')), 500))
    ON CONFLICT (ride_log_id) WHERE ride_log_id IS NOT NULL
    DO UPDATE SET caption = EXCLUDED.caption
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.post_open_ride(p_ride_id UUID, p_caption TEXT, p_max_riders INT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_user UUID := auth.uid(); v_ride RECORD; v_id UUID; v_count INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Unauthorized: User not authenticated'; END IF;
    SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ride not found'; END IF;
    IF v_ride.organiser_id <> v_user THEN RAISE EXCEPTION 'Forbidden: Only the ride admin can post this ride'; END IF;
    IF v_ride.is_completed THEN RAISE EXCEPTION 'This ride has already finished'; END IF;
    v_count := public.accepted_rider_count(p_ride_id);
    IF p_max_riders IS NULL OR p_max_riders < GREATEST(2, v_count) OR p_max_riders > 50 THEN
        RAISE EXCEPTION 'Max riders must be between % and 50', GREATEST(2, v_count);
    END IF;

    UPDATE public.rides SET accepts_requests = true, max_riders = p_max_riders WHERE id = p_ride_id;
    INSERT INTO public.feed_posts (author_id, kind, ride_id, caption)
    VALUES (v_user, 'open_ride', p_ride_id, left(btrim(COALESCE(p_caption, '')), 500))
    ON CONFLICT (ride_id) WHERE kind = 'open_ride'
    DO UPDATE SET caption = EXCLUDED.caption
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.close_open_ride(p_ride_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized: User not authenticated'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.rides WHERE id = p_ride_id AND organiser_id = auth.uid()) THEN
        RAISE EXCEPTION 'Forbidden: Only the ride admin can close requests';
    END IF;
    UPDATE public.rides SET accepts_requests = false WHERE id = p_ride_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 8. Join requests (replaces the 20261104 versions: note, source, capacity, closed rides)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_ride_join_request(UUID);
CREATE OR REPLACE FUNCTION public.create_ride_join_request(p_ride_id UUID, p_note TEXT DEFAULT NULL,
                                                           p_source TEXT DEFAULT 'code')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
    v_user UUID := auth.uid();
    v_ride RECORD;
    v_request RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Unauthorized: User not authenticated'; END IF;
    IF p_source NOT IN ('code', 'feed') THEN RAISE EXCEPTION 'Invalid source'; END IF;

    SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ride not found'; END IF;
    IF v_ride.organiser_id = v_user THEN RAISE EXCEPTION 'Cannot send join request to your own ride'; END IF;
    IF v_ride.is_completed THEN RAISE EXCEPTION 'This ride has already finished'; END IF;
    IF p_source = 'feed' AND NOT v_ride.accepts_requests THEN
        RAISE EXCEPTION 'This ride is not taking requests';
    END IF;
    IF EXISTS (SELECT 1 FROM public.ride_members
               WHERE ride_id = p_ride_id AND user_id = v_user AND status = 'accepted') THEN
        RAISE EXCEPTION 'User is already an accepted member of this ride';
    END IF;
    IF v_ride.max_riders IS NOT NULL AND public.accepted_rider_count(p_ride_id) >= v_ride.max_riders THEN
        RAISE EXCEPTION 'Ride is full';
    END IF;

    INSERT INTO public.ride_join_requests (ride_id, requester_id, organizer_id, status, note, source, created_at, updated_at)
    VALUES (p_ride_id, v_user, v_ride.organiser_id, 'pending',
            NULLIF(left(btrim(COALESCE(p_note, '')), 200), ''), p_source, now(), now())
    RETURNING * INTO v_request;

    RETURN to_jsonb(v_request);
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_ride_join_request(p_request_id UUID, p_action TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
    v_user UUID := auth.uid();
    v_request RECORD;
    v_max INT;
    v_count INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Unauthorized: User not authenticated'; END IF;
    IF p_action NOT IN ('accept', 'decline') THEN RAISE EXCEPTION 'Invalid action: must be accept or decline'; END IF;

    SELECT * INTO v_request FROM public.ride_join_requests WHERE id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ride join request not found'; END IF;
    IF v_request.organizer_id <> v_user THEN
        RAISE EXCEPTION 'Forbidden: Only the trip organizer can respond to join requests';
    END IF;
    IF v_request.status <> 'pending' THEN
        RAISE EXCEPTION 'Request is no longer pending (current status: %)', v_request.status;
    END IF;

    IF p_action = 'accept' THEN
        -- Serialise accepts on the same ride so two admins' taps cannot overfill it.
        SELECT max_riders INTO v_max FROM public.rides WHERE id = v_request.ride_id FOR UPDATE;
        IF v_max IS NOT NULL AND public.accepted_rider_count(v_request.ride_id) >= v_max THEN
            RAISE EXCEPTION 'Ride is full';
        END IF;
        UPDATE public.ride_join_requests SET status = 'accepted', updated_at = now() WHERE id = p_request_id;
        INSERT INTO public.ride_members (ride_id, user_id, role, status)
        VALUES (v_request.ride_id, v_request.requester_id, 'rider', 'accepted')
        ON CONFLICT (ride_id, user_id) DO UPDATE SET role = 'rider', status = 'accepted';
    ELSE
        UPDATE public.ride_join_requests SET status = 'declined', updated_at = now() WHERE id = p_request_id;
    END IF;

    v_count := public.accepted_rider_count(v_request.ride_id);
    -- A full ride stops taking feed requests; remaining pending requests stay for the admin to decline.
    IF v_max IS NOT NULL AND v_count >= v_max THEN
        UPDATE public.rides SET accepts_requests = false WHERE id = v_request.ride_id;
    END IF;

    RETURN jsonb_build_object('request_id', p_request_id, 'ride_id', v_request.ride_id,
                              'requester_id', v_request.requester_id, 'status', p_action || 'ed',
                              'members_count', v_count);
END;
$$;

-- Pending requests on rides I organise, with what the admin needs to decide.
CREATE OR REPLACE FUNCTION public.incoming_ride_join_requests()
RETURNS TABLE (request_id UUID, ride_id UUID, ride_title TEXT, ride_departs TEXT, note TEXT, source TEXT,
               created_at TIMESTAMPTZ, requester_id UUID, display_name TEXT, username TEXT, avatar_data TEXT,
               rides_count INT, total_km NUMERIC, shared_crews INT, rode_together INT,
               members_count INT, max_riders INT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT r.id, r.ride_id, rd.title, rd.departs::TEXT, r.note, r.source, r.created_at, r.requester_id,
           p.display_name, p.username, p.avatar_data,
           (SELECT COUNT(*)::INT FROM public.ride_logs l WHERE l.user_id = r.requester_id),
           (SELECT round(COALESCE(SUM(l.distance_m), 0) / 1000.0, 1) FROM public.ride_logs l WHERE l.user_id = r.requester_id),
           (SELECT COUNT(*)::INT FROM public.crew_members a
              JOIN public.crew_members b ON b.crew_id = a.crew_id AND b.user_id = auth.uid() AND b.status = 'accepted'
             WHERE a.user_id = r.requester_id AND a.status = 'accepted'),
           (SELECT COUNT(*)::INT FROM public.ride_members a
              JOIN public.ride_members b ON b.ride_id = a.ride_id AND b.user_id = auth.uid() AND b.status = 'accepted'
              JOIN public.rides x ON x.id = a.ride_id AND x.is_completed
             WHERE a.user_id = r.requester_id AND a.status = 'accepted'),
           public.accepted_rider_count(r.ride_id), rd.max_riders
    FROM public.ride_join_requests r
    JOIN public.rides rd ON rd.id = r.ride_id
    LEFT JOIN public.profiles p ON p.id = r.requester_id
    WHERE r.organizer_id = auth.uid() AND r.status = 'pending'
    ORDER BY r.created_at DESC;
$$;

-- -----------------------------------------------------------------------------
-- 9. Notification triggers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_ride_join_request() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
        INSERT INTO public.notifications (recipient_id, actor_id, kind, ride_id, request_id, body)
        VALUES (NEW.organizer_id, NEW.requester_id, 'ride_join_request', NEW.ride_id, NEW.id, COALESCE(NEW.note, ''));
    ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
        -- The admin's actionable entry is resolved either way.
        UPDATE public.notifications SET read_at = COALESCE(read_at, now())
         WHERE request_id = NEW.id AND kind = 'ride_join_request';
        IF NEW.status = 'accepted' THEN
            INSERT INTO public.notifications (recipient_id, actor_id, kind, ride_id, request_id)
            VALUES (NEW.requester_id, NEW.organizer_id, 'ride_join_accepted', NEW.ride_id, NEW.id);
        ELSIF NEW.status = 'declined' THEN
            INSERT INTO public.notifications (recipient_id, actor_id, kind, ride_id, request_id)
            VALUES (NEW.requester_id, NEW.organizer_id, 'ride_join_declined', NEW.ride_id, NEW.id);
        ELSIF NEW.status = 'cancelled' THEN
            DELETE FROM public.notifications WHERE request_id = NEW.id AND kind = 'ride_join_request';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_ride_join_request ON public.ride_join_requests;
CREATE TRIGGER trg_notify_ride_join_request AFTER INSERT OR UPDATE OF status ON public.ride_join_requests
    FOR EACH ROW EXECUTE FUNCTION public.notify_ride_join_request();

CREATE OR REPLACE FUNCTION public.notify_new_follower() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    -- Re-following within a day does not notify twice.
    IF NOT EXISTS (SELECT 1 FROM public.notifications WHERE recipient_id = NEW.followee_id AND actor_id = NEW.follower_id
                   AND kind = 'new_follower' AND created_at > now() - interval '1 day') THEN
        INSERT INTO public.notifications (recipient_id, actor_id, kind)
        VALUES (NEW.followee_id, NEW.follower_id, 'new_follower');
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_new_follower ON public.follows;
CREATE TRIGGER trg_notify_new_follower AFTER INSERT ON public.follows
    FOR EACH ROW EXECUTE FUNCTION public.notify_new_follower();

CREATE OR REPLACE FUNCTION public.notify_post_activity() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_author UUID;
BEGIN
    SELECT author_id INTO v_author FROM public.feed_posts WHERE id = NEW.post_id;
    IF v_author IS NULL OR v_author = NEW.user_id THEN RETURN NEW; END IF;
    IF TG_TABLE_NAME = 'post_likes' THEN
        IF NOT EXISTS (SELECT 1 FROM public.notifications WHERE recipient_id = v_author AND actor_id = NEW.user_id
                       AND kind = 'post_like' AND post_id = NEW.post_id) THEN
            INSERT INTO public.notifications (recipient_id, actor_id, kind, post_id)
            VALUES (v_author, NEW.user_id, 'post_like', NEW.post_id);
        END IF;
    ELSE
        INSERT INTO public.notifications (recipient_id, actor_id, kind, post_id, body)
        VALUES (v_author, NEW.user_id, 'post_comment', NEW.post_id, left(NEW.body, 140));
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_post_like ON public.post_likes;
CREATE TRIGGER trg_notify_post_like AFTER INSERT ON public.post_likes
    FOR EACH ROW EXECUTE FUNCTION public.notify_post_activity();
DROP TRIGGER IF EXISTS trg_notify_post_comment ON public.post_comments;
CREATE TRIGGER trg_notify_post_comment AFTER INSERT ON public.post_comments
    FOR EACH ROW EXECUTE FUNCTION public.notify_post_activity();

-- Inbox: informational notifications. Pending join requests come from incoming_ride_join_requests().
CREATE OR REPLACE FUNCTION public.my_notifications(p_limit INT DEFAULT 50)
RETURNS TABLE (id UUID, kind TEXT, created_at TIMESTAMPTZ, read_at TIMESTAMPTZ, body TEXT,
               actor_id UUID, actor_name TEXT, actor_username TEXT, actor_avatar TEXT,
               ride_id UUID, ride_title TEXT, request_id UUID, post_id UUID, i_follow_actor BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT n.id, n.kind, n.created_at, n.read_at, n.body, n.actor_id, p.display_name, p.username, p.avatar_data,
           n.ride_id, r.title, n.request_id, n.post_id,
           EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = auth.uid() AND f.followee_id = n.actor_id)
    FROM public.notifications n
    LEFT JOIN public.profiles p ON p.id = n.actor_id
    LEFT JOIN public.rides r ON r.id = n.ride_id
    WHERE n.recipient_id = auth.uid() AND n.kind <> 'ride_join_request'
    ORDER BY n.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100);
$$;

CREATE OR REPLACE FUNCTION public.mark_notifications_read(p_ids UUID[])
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    UPDATE public.notifications SET read_at = now()
    WHERE recipient_id = auth.uid() AND read_at IS NULL AND (p_ids IS NULL OR id = ANY(p_ids));
$$;

-- -----------------------------------------------------------------------------
-- 10. Feed
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.crew_feed(TIMESTAMPTZ, INT);
-- p_author limits the feed to one rider (their profile page); audience rules still apply.
CREATE OR REPLACE FUNCTION public.crew_feed(p_before TIMESTAMPTZ DEFAULT NULL, p_limit INT DEFAULT 20,
                                            p_author UUID DEFAULT NULL)
RETURNS TABLE (
    post_id UUID, kind TEXT, created_at TIMESTAMPTZ, caption TEXT,
    author_id UUID, author_name TEXT, author_username TEXT, author_avatar TEXT, is_mine BOOLEAN,
    like_count INT, comment_count INT, liked_by_me BOOLEAN,
    -- ride_log posts
    log_title TEXT, start_name TEXT, end_name TEXT, distance_m INT, moving_s INT, max_speed_kmh NUMERIC,
    path_polyline TEXT, rider_count INT, ended_at TIMESTAMPTZ,
    -- open_ride posts
    ride_id UUID, ride_title TEXT, ride_departs TEXT, ride_from TEXT, ride_to TEXT, route_km NUMERIC,
    route_preview JSONB, members_count INT, max_riders INT, accepts_requests BOOLEAN, ride_completed BOOLEAN,
    my_request_status TEXT, i_am_member BOOLEAN, pending_requests INT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH aud AS (SELECT user_id FROM public.audience_of(auth.uid()))
    SELECT fp.id, fp.kind, fp.created_at, fp.caption,
           fp.author_id, p.display_name, p.username, p.avatar_data, fp.author_id = auth.uid(),
           (SELECT COUNT(*)::INT FROM public.post_likes pl WHERE pl.post_id = fp.id),
           (SELECT COUNT(*)::INT FROM public.post_comments pc WHERE pc.post_id = fp.id),
           EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = fp.id AND pl.user_id = auth.uid()),
           l.title, l.start_name, l.end_name, l.distance_m, l.moving_s, l.max_speed_kmh,
           l.path_polyline, l.rider_count, l.ended_at,
           r.id, r.title, r.departs::TEXT,
           -- Area names only: the first comma-separated part, never the street address.
           CASE WHEN r.id IS NULL THEN NULL ELSE split_part(COALESCE(r.from_location, ''), ',', 1) END,
           CASE WHEN r.id IS NULL THEN NULL ELSE split_part(COALESCE(r.to_location, ''), ',', 1) END,
           r.route_km::NUMERIC, CASE WHEN r.id IS NULL THEN NULL ELSE public.route_preview(r.route_coords_json) END,
           CASE WHEN r.id IS NULL THEN NULL ELSE public.accepted_rider_count(r.id) END,
           r.max_riders, r.accepts_requests, r.is_completed,
           (SELECT q.status FROM public.ride_join_requests q
             WHERE q.ride_id = r.id AND q.requester_id = auth.uid() ORDER BY q.created_at DESC LIMIT 1),
           CASE WHEN r.id IS NULL THEN NULL ELSE
             (r.organiser_id = auth.uid() OR EXISTS (SELECT 1 FROM public.ride_members m
               WHERE m.ride_id = r.id AND m.user_id = auth.uid() AND m.status = 'accepted')) END,
           CASE WHEN r.id IS NOT NULL AND r.organiser_id = auth.uid()
                THEN (SELECT COUNT(*)::INT FROM public.ride_join_requests q WHERE q.ride_id = r.id AND q.status = 'pending')
                ELSE 0 END
    FROM public.feed_posts fp
    JOIN aud ON aud.user_id = fp.author_id
    LEFT JOIN public.profiles p ON p.id = fp.author_id
    LEFT JOIN public.ride_logs l ON l.id = fp.ride_log_id
    LEFT JOIN public.rides r ON r.id = fp.ride_id
    WHERE auth.uid() IS NOT NULL
      AND (p_before IS NULL OR fp.created_at < p_before)
      AND (p_author IS NULL OR fp.author_id = p_author)
      -- Finished open rides drop out of the feed; ride recaps stay.
      AND (fp.kind = 'ride_log' OR NOT r.is_completed)
    ORDER BY fp.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 50);
$$;

CREATE OR REPLACE FUNCTION public.can_see_post(p_post_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (SELECT 1 FROM public.feed_posts fp
                   WHERE fp.id = p_post_id AND fp.author_id IN (SELECT user_id FROM public.audience_of(auth.uid())));
$$;

CREATE OR REPLACE FUNCTION public.toggle_post_like(p_post_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_user UUID := auth.uid(); v_liked BOOLEAN;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Unauthorized: User not authenticated'; END IF;
    IF NOT public.can_see_post(p_post_id) THEN RAISE EXCEPTION 'Post not found'; END IF;
    IF EXISTS (SELECT 1 FROM public.post_likes WHERE post_id = p_post_id AND user_id = v_user) THEN
        DELETE FROM public.post_likes WHERE post_id = p_post_id AND user_id = v_user; v_liked := false;
    ELSE
        INSERT INTO public.post_likes (post_id, user_id) VALUES (p_post_id, v_user); v_liked := true;
    END IF;
    RETURN jsonb_build_object('liked', v_liked,
        'like_count', (SELECT COUNT(*) FROM public.post_likes WHERE post_id = p_post_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.add_post_comment(p_post_id UUID, p_body TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized: User not authenticated'; END IF;
    IF NOT public.can_see_post(p_post_id) THEN RAISE EXCEPTION 'Post not found'; END IF;
    INSERT INTO public.post_comments (post_id, user_id, body) VALUES (p_post_id, auth.uid(), btrim(p_body))
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.post_comments_list(p_post_id UUID)
RETURNS TABLE (id UUID, body TEXT, created_at TIMESTAMPTZ, user_id UUID, display_name TEXT,
               username TEXT, avatar_data TEXT, is_mine BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT c.id, c.body, c.created_at, c.user_id, p.display_name, p.username, p.avatar_data, c.user_id = auth.uid()
    FROM public.post_comments c LEFT JOIN public.profiles p ON p.id = c.user_id
    WHERE c.post_id = p_post_id AND public.can_see_post(p_post_id)
    ORDER BY c.created_at ASC
    LIMIT 200;
$$;

-- -----------------------------------------------------------------------------
-- 11. Leaderboard
-- p_metric: 'score' (points) or 'distance' (km). Window [p_from, p_to); NULL p_from = all time.
-- Returns the top p_limit riders plus the caller's own row (flag is_me) when outside the top.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leaderboard(p_metric TEXT, p_from TIMESTAMPTZ, p_to TIMESTAMPTZ, p_limit INT DEFAULT 10)
RETURNS TABLE (rank INT, user_id UUID, display_name TEXT, username TEXT, avatar_data TEXT,
               value NUMERIC, rides INT, level INT, is_me BOOLEAN, riders_ranked INT, period_total NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF p_metric NOT IN ('score', 'distance') THEN RAISE EXCEPTION 'Invalid metric'; END IF;
    RETURN QUERY
    WITH agg AS (
        SELECT l.user_id AS uid,
               CASE WHEN p_metric = 'score' THEN SUM(l.points)::NUMERIC
                    ELSE round(SUM(l.distance_m) / 1000.0, 1) END AS v,
               COUNT(*)::INT AS n
        FROM public.ride_logs l
        WHERE (p_from IS NULL OR l.ended_at >= p_from) AND (p_to IS NULL OR l.ended_at < p_to)
        GROUP BY l.user_id
        HAVING SUM(l.distance_m) > 0
    ), ranked AS (
        SELECT agg.*, RANK() OVER (ORDER BY agg.v DESC)::INT AS rk,
               COUNT(*) OVER ()::INT AS total_riders, SUM(agg.v) OVER () AS total_v
        FROM agg
    ), lifetime AS (
        SELECT l.user_id AS uid, SUM(l.points)::BIGINT AS pts FROM public.ride_logs l GROUP BY l.user_id
    )
    SELECT ranked.rk, ranked.uid, p.display_name, p.username, p.avatar_data, ranked.v, ranked.n,
           public.rider_level(COALESCE(lifetime.pts, 0)), ranked.uid = auth.uid(), ranked.total_riders, ranked.total_v
    FROM ranked
    LEFT JOIN public.profiles p ON p.id = ranked.uid
    LEFT JOIN lifetime ON lifetime.uid = ranked.uid
    WHERE ranked.rk <= LEAST(GREATEST(p_limit, 3), 100) OR ranked.uid = auth.uid()
    ORDER BY ranked.rk, p.display_name;
END;
$$;

-- -----------------------------------------------------------------------------
-- 12. Riders: suggestions, profiles, follow
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.suggested_riders(p_limit INT DEFAULT 10)
RETURNS TABLE (user_id UUID, display_name TEXT, username TEXT, avatar_data TEXT, reason TEXT,
               total_km NUMERIC, rides_count INT, month_km NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH me AS (SELECT auth.uid() AS id),
    crew_mates AS (
        SELECT b.user_id AS uid, MIN(c.name) AS crew_name, COUNT(DISTINCT b.crew_id) AS n
        FROM public.crew_members a
        JOIN public.crew_members b ON b.crew_id = a.crew_id AND b.status = 'accepted'
        JOIN public.crews c ON c.id = a.crew_id
        WHERE a.user_id = (SELECT id FROM me) AND a.status = 'accepted'
        GROUP BY b.user_id
    ),
    co_riders AS (
        SELECT b.user_id AS uid, COUNT(DISTINCT b.ride_id) AS n
        FROM public.ride_members a
        JOIN public.ride_members b ON b.ride_id = a.ride_id AND b.status = 'accepted'
        WHERE a.user_id = (SELECT id FROM me) AND a.status = 'accepted'
        GROUP BY b.user_id
    ),
    friends_of_follows AS (
        SELECT f2.followee_id AS uid, COUNT(*) AS n
        FROM public.follows f1 JOIN public.follows f2 ON f2.follower_id = f1.followee_id
        WHERE f1.follower_id = (SELECT id FROM me)
        GROUP BY f2.followee_id
    ),
    stats AS (
        SELECT l.user_id AS uid, round(SUM(l.distance_m) / 1000.0, 1) AS km, COUNT(*)::INT AS rides,
               round(COALESCE(SUM(l.distance_m) FILTER (WHERE l.ended_at >= date_trunc('month', now())), 0) / 1000.0, 1) AS mkm
        FROM public.ride_logs l GROUP BY l.user_id
    ),
    candidates AS (
        SELECT p.id AS uid,
               COALESCE(cm.n, 0) * 5 + COALESCE(cr.n, 0) * 4 + COALESCE(ff.n, 0) * 3
                 + CASE WHEN COALESCE(s.mkm, 0) > 0 THEN 1 ELSE 0 END AS weight,
               CASE WHEN cm.uid IS NOT NULL THEN 'In your crew ' || cm.crew_name
                    WHEN cr.uid IS NOT NULL THEN 'Rode with you ' || cr.n || CASE WHEN cr.n = 1 THEN ' time' ELSE ' times' END
                    WHEN ff.uid IS NOT NULL THEN 'Followed by ' || ff.n || ' rider' || CASE WHEN ff.n = 1 THEN '' ELSE 's' END || ' you follow'
                    WHEN COALESCE(s.mkm, 0) > 0 THEN 'Rode ' || s.mkm || ' km this month'
                    ELSE NULL END AS reason,
               COALESCE(s.km, 0) AS km, COALESCE(s.rides, 0) AS rides, COALESCE(s.mkm, 0) AS mkm
        FROM public.profiles p
        LEFT JOIN crew_mates cm ON cm.uid = p.id
        LEFT JOIN co_riders cr ON cr.uid = p.id
        LEFT JOIN friends_of_follows ff ON ff.uid = p.id
        LEFT JOIN stats s ON s.uid = p.id
        WHERE p.id <> (SELECT id FROM me)
          AND NOT EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = (SELECT id FROM me) AND f.followee_id = p.id)
    )
    SELECT c.uid, p.display_name, p.username, p.avatar_data, c.reason, c.km, c.rides, c.mkm
    FROM candidates c JOIN public.profiles p ON p.id = c.uid
    WHERE auth.uid() IS NOT NULL AND c.reason IS NOT NULL
    ORDER BY c.weight DESC, c.mkm DESC, c.km DESC, p.display_name
    LIMIT LEAST(GREATEST(p_limit, 1), 30);
$$;

CREATE OR REPLACE FUNCTION public.rider_profile(p_user_id UUID)
RETURNS TABLE (user_id UUID, display_name TEXT, username TEXT, avatar_data TEXT,
               followers INT, following INT, i_follow BOOLEAN, follows_me BOOLEAN,
               total_km NUMERIC, rides_count INT, month_km NUMERIC, month_points INT, total_points BIGINT,
               level INT, shared_crews INT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT p.id, p.display_name, p.username, p.avatar_data,
           (SELECT COUNT(*)::INT FROM public.follows WHERE followee_id = p.id),
           (SELECT COUNT(*)::INT FROM public.follows WHERE follower_id = p.id),
           EXISTS (SELECT 1 FROM public.follows WHERE follower_id = auth.uid() AND followee_id = p.id),
           EXISTS (SELECT 1 FROM public.follows WHERE follower_id = p.id AND followee_id = auth.uid()),
           (SELECT round(COALESCE(SUM(distance_m), 0) / 1000.0, 1) FROM public.ride_logs WHERE user_id = p.id),
           (SELECT COUNT(*)::INT FROM public.ride_logs WHERE user_id = p.id),
           (SELECT round(COALESCE(SUM(distance_m), 0) / 1000.0, 1) FROM public.ride_logs
             WHERE user_id = p.id AND ended_at >= date_trunc('month', now())),
           (SELECT COALESCE(SUM(points), 0)::INT FROM public.ride_logs
             WHERE user_id = p.id AND ended_at >= date_trunc('month', now())),
           (SELECT COALESCE(SUM(points), 0)::BIGINT FROM public.ride_logs WHERE user_id = p.id),
           public.rider_level((SELECT COALESCE(SUM(points), 0)::BIGINT FROM public.ride_logs WHERE user_id = p.id)),
           (SELECT COUNT(*)::INT FROM public.crew_members a
              JOIN public.crew_members b ON b.crew_id = a.crew_id AND b.user_id = auth.uid() AND b.status = 'accepted'
             WHERE a.user_id = p.id AND a.status = 'accepted' AND p.id <> auth.uid())
    FROM public.profiles p
    WHERE p.id = p_user_id AND auth.uid() IS NOT NULL;
$$;

-- -----------------------------------------------------------------------------
-- 13. Grants
-- -----------------------------------------------------------------------------
DO $$
DECLARE f TEXT;
BEGIN
    FOREACH f IN ARRAY ARRAY[
        'record_ride_log(UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, INT, INT, INT, NUMERIC, TEXT)',
        'share_ride_log(UUID, TEXT)', 'post_open_ride(UUID, TEXT, INT)', 'close_open_ride(UUID)',
        'create_ride_join_request(UUID, TEXT, TEXT)', 'respond_ride_join_request(UUID, TEXT)',
        'incoming_ride_join_requests()', 'my_notifications(INT)', 'mark_notifications_read(UUID[])',
        'crew_feed(TIMESTAMPTZ, INT, UUID)', 'can_see_post(UUID)', 'toggle_post_like(UUID)', 'add_post_comment(UUID, TEXT)',
        'post_comments_list(UUID)', 'leaderboard(TEXT, TIMESTAMPTZ, TIMESTAMPTZ, INT)', 'suggested_riders(INT)',
        'rider_profile(UUID)'
    ] LOOP
        EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%s FROM public, anon', f);
        EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', f);
    END LOOP;
END $$;

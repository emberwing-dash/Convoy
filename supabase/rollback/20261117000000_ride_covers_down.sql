-- Undo for 20261117000000_ride_covers.sql: removes cover columns, photo cache, upload policies and restores
-- the previous crew_feed. Uploaded files in the ride-covers bucket are left in place (delete them in the dashboard).
BEGIN;
DROP FUNCTION IF EXISTS public.crew_feed(TIMESTAMPTZ, INT, UUID);
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
           r.max_riders, r.accepts_requests, COALESCE(r.is_completed, false),
           (SELECT q.status FROM public.ride_join_requests q
             WHERE q.ride_id = r.id AND q.requester_id = auth.uid() ORDER BY q.created_at DESC LIMIT 1),
           CASE WHEN r.id IS NULL THEN NULL ELSE
             (r.organiser_id = auth.uid() OR EXISTS (SELECT 1 FROM public.ride_members m
               WHERE m.ride_id = r.id AND m.user_id = auth.uid() AND m.status = 'accepted')) END,
           CASE WHEN r.id IS NOT NULL AND r.organiser_id = auth.uid()
                THEN (SELECT COUNT(*)::INT FROM public.ride_join_requests q WHERE q.ride_id = r.id AND q.status = 'pending')
                ELSE 0 END
    FROM public.feed_posts fp
    LEFT JOIN public.profiles p ON p.id = fp.author_id
    LEFT JOIN public.ride_logs l ON l.id = fp.ride_log_id
    LEFT JOIN public.rides r ON r.id = fp.ride_id
    WHERE auth.uid() IS NOT NULL
      AND (p_before IS NULL OR fp.created_at < p_before)
      AND (p_author IS NULL OR fp.author_id = p_author)
      -- Finished open rides drop out of the feed; ride recaps stay.
      AND (fp.kind = 'ride_log' OR NOT COALESCE(r.is_completed, false))
    ORDER BY fp.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 50);
$$;


REVOKE EXECUTE ON FUNCTION public.crew_feed(TIMESTAMPTZ, INT, UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.crew_feed(TIMESTAMPTZ, INT, UUID) TO authenticated;
DROP FUNCTION IF EXISTS public.set_ride_cover(UUID, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.put_place_photos(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, JSONB);
DROP TABLE IF EXISTS public.place_photos;
DROP POLICY IF EXISTS "Ride admins upload covers" ON storage.objects;
DROP POLICY IF EXISTS "Ride admins replace covers" ON storage.objects;
DROP POLICY IF EXISTS "Ride admins delete covers" ON storage.objects;
ALTER TABLE public.rides DROP COLUMN IF EXISTS cover_source, DROP COLUMN IF EXISTS cover_url,
    DROP COLUMN IF EXISTS cover_credit, DROP COLUMN IF EXISTS cover_license,
    DROP COLUMN IF EXISTS cover_page_url, DROP COLUMN IF EXISTS cover_set_at;
COMMIT;

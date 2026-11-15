-- =============================================================================
-- Migration: 20261117000000_ride_covers.sql
-- Destination cover photos for rides (free sources only).
--
--   cover_source 'wikimedia'  freely licensed photo from Wikimedia Commons (credit + licence kept)
--                'upload'     the ride admin's own photo, stored in the ride-covers bucket
--                'satellite'  no photo found: the app draws a satellite view of the destination
--
-- Only the ride admin can set a cover (set_ride_cover). URLs are restricted to Wikimedia's image
-- hosts (upload. / thumb.wikimedia.org) or this project's ride-covers bucket under the ride's own folder.
-- place_photos caches lookups so each place is searched once for everyone.
-- =============================================================================

ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS cover_source TEXT
    CHECK (cover_source IS NULL OR cover_source IN ('wikimedia', 'upload', 'satellite'));
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS cover_url TEXT CHECK (cover_url IS NULL OR char_length(cover_url) <= 1000);
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS cover_credit TEXT CHECK (cover_credit IS NULL OR char_length(cover_credit) <= 300);
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS cover_license TEXT CHECK (cover_license IS NULL OR char_length(cover_license) <= 100);
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS cover_page_url TEXT CHECK (cover_page_url IS NULL OR char_length(cover_page_url) <= 1000);
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS cover_set_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.set_ride_cover(p_ride_id UUID, p_source TEXT, p_url TEXT, p_credit TEXT,
                                                 p_license TEXT, p_page_url TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized: User not authenticated'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.rides WHERE id = p_ride_id) THEN RAISE EXCEPTION 'Ride not found'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.rides WHERE id = p_ride_id AND organiser_id = auth.uid()) THEN
        RAISE EXCEPTION 'Forbidden: Only the ride admin can change the cover';
    END IF;
    IF p_source NOT IN ('wikimedia', 'upload', 'satellite') THEN RAISE EXCEPTION 'Invalid cover source'; END IF;
    IF p_source = 'wikimedia' AND (p_url IS NULL OR (p_url NOT LIKE 'https://upload.wikimedia.org/%'
                                                     AND p_url NOT LIKE 'https://thumb.wikimedia.org/%')) THEN
        RAISE EXCEPTION 'Invalid cover image';
    END IF;
    IF p_source = 'upload' AND (p_url IS NULL OR p_url NOT LIKE '%/storage/v1/object/public/ride-covers/' || p_ride_id::TEXT || '/%') THEN
        RAISE EXCEPTION 'Invalid cover image';
    END IF;
    IF p_page_url IS NOT NULL AND p_page_url NOT LIKE 'https://commons.wikimedia.org/%' THEN
        RAISE EXCEPTION 'Invalid cover source page';
    END IF;
    UPDATE public.rides SET
        cover_source = p_source,
        cover_url = CASE WHEN p_source = 'satellite' THEN NULL ELSE p_url END,
        cover_credit = CASE WHEN p_source = 'wikimedia' THEN left(p_credit, 300) ELSE NULL END,
        cover_license = CASE WHEN p_source = 'wikimedia' THEN left(p_license, 100) ELSE NULL END,
        cover_page_url = CASE WHEN p_source = 'wikimedia' THEN p_page_url ELSE NULL END,
        cover_set_at = now()
    WHERE id = p_ride_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- Shared lookup cache: one row per place (coordinates rounded to ~100 m + name)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.place_photos (
    place_key  TEXT PRIMARY KEY CHECK (char_length(place_key) <= 200),
    name       TEXT NOT NULL DEFAULT '' CHECK (char_length(name) <= 200),
    lat        DOUBLE PRECISION NOT NULL,
    lon        DOUBLE PRECISION NOT NULL,
    candidates JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(candidates) = 'array' AND jsonb_array_length(candidates) <= 12),
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.place_photos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Signed-in riders read the photo cache" ON public.place_photos;
CREATE POLICY "Signed-in riders read the photo cache" ON public.place_photos FOR SELECT USING (auth.uid() IS NOT NULL);

-- Writes only through here, and only Wikimedia image URLs are accepted.
CREATE OR REPLACE FUNCTION public.put_place_photos(p_place_key TEXT, p_name TEXT, p_lat DOUBLE PRECISION,
                                                   p_lon DOUBLE PRECISION, p_candidates JSONB)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized: User not authenticated'; END IF;
    IF jsonb_typeof(p_candidates) <> 'array' THEN RAISE EXCEPTION 'Invalid candidates'; END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_candidates) c
               WHERE COALESCE(c ->> 'url', '') NOT LIKE 'https://upload.wikimedia.org/%'
                 AND COALESCE(c ->> 'url', '') NOT LIKE 'https://thumb.wikimedia.org/%') THEN
        RAISE EXCEPTION 'Invalid cover image';
    END IF;
    INSERT INTO public.place_photos (place_key, name, lat, lon, candidates, fetched_at)
    VALUES (p_place_key, left(COALESCE(p_name, ''), 200), p_lat, p_lon, p_candidates, now())
    ON CONFLICT (place_key) DO UPDATE SET candidates = EXCLUDED.candidates, name = EXCLUDED.name, fetched_at = now();
END;
$$;

-- -----------------------------------------------------------------------------
-- Storage for admin-uploaded covers: public read, writes only into your own ride's folder
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('ride-covers', 'ride-covers', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = true, file_size_limit = 5242880,
                               allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

DROP POLICY IF EXISTS "Ride admins upload covers" ON storage.objects;
CREATE POLICY "Ride admins upload covers" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'ride-covers' AND EXISTS (
        SELECT 1 FROM public.rides r
        WHERE r.id::TEXT = (storage.foldername(name))[1] AND r.organiser_id = auth.uid()));
DROP POLICY IF EXISTS "Ride admins replace covers" ON storage.objects;
CREATE POLICY "Ride admins replace covers" ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'ride-covers' AND EXISTS (
        SELECT 1 FROM public.rides r
        WHERE r.id::TEXT = (storage.foldername(name))[1] AND r.organiser_id = auth.uid()));
DROP POLICY IF EXISTS "Ride admins delete covers" ON storage.objects;
CREATE POLICY "Ride admins delete covers" ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'ride-covers' AND EXISTS (
        SELECT 1 FROM public.rides r
        WHERE r.id::TEXT = (storage.foldername(name))[1] AND r.organiser_id = auth.uid()));

-- -----------------------------------------------------------------------------
-- Feed: cover photo for open rides and for recaps of server rides, plus an area-level
-- destination point (rounded to ~1 km) for the satellite fallback.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.crew_feed(TIMESTAMPTZ, INT, UUID);
CREATE FUNCTION public.crew_feed(p_before TIMESTAMPTZ DEFAULT NULL, p_limit INT DEFAULT 20,
                                 p_author UUID DEFAULT NULL)
RETURNS TABLE (
    post_id UUID, kind TEXT, created_at TIMESTAMPTZ, caption TEXT,
    author_id UUID, author_name TEXT, author_username TEXT, author_avatar TEXT, is_mine BOOLEAN,
    like_count INT, comment_count INT, liked_by_me BOOLEAN,
    log_title TEXT, start_name TEXT, end_name TEXT, distance_m INT, moving_s INT, max_speed_kmh NUMERIC,
    path_polyline TEXT, rider_count INT, ended_at TIMESTAMPTZ,
    ride_id UUID, ride_title TEXT, ride_departs TEXT, ride_from TEXT, ride_to TEXT, route_km NUMERIC,
    route_preview JSONB, members_count INT, max_riders INT, accepts_requests BOOLEAN, ride_completed BOOLEAN,
    my_request_status TEXT, i_am_member BOOLEAN, pending_requests INT,
    cover_source TEXT, cover_url TEXT, cover_credit TEXT, cover_license TEXT, cover_page_url TEXT,
    dest_lat DOUBLE PRECISION, dest_lon DOUBLE PRECISION)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fp.id, fp.kind, fp.created_at, fp.caption,
           fp.author_id, p.display_name, p.username, p.avatar_data, fp.author_id = auth.uid(),
           (SELECT COUNT(*)::INT FROM public.post_likes pl WHERE pl.post_id = fp.id),
           (SELECT COUNT(*)::INT FROM public.post_comments pc WHERE pc.post_id = fp.id),
           EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = fp.id AND pl.user_id = auth.uid()),
           l.title, l.start_name, l.end_name, l.distance_m, l.moving_s, l.max_speed_kmh,
           l.path_polyline, l.rider_count, l.ended_at,
           r.id, r.title, r.departs::TEXT,
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
                ELSE 0 END,
           c.cover_source, c.cover_url, c.cover_credit, c.cover_license, c.cover_page_url,
           CASE WHEN c.end_lat IS NULL OR (c.end_lat = 0 AND c.end_lon = 0) THEN NULL ELSE round(c.end_lat::NUMERIC, 2)::DOUBLE PRECISION END,
           CASE WHEN c.end_lat IS NULL OR (c.end_lat = 0 AND c.end_lon = 0) THEN NULL ELSE round(c.end_lon::NUMERIC, 2)::DOUBLE PRECISION END
    FROM public.feed_posts fp
    LEFT JOIN public.profiles p ON p.id = fp.author_id
    LEFT JOIN public.ride_logs l ON l.id = fp.ride_log_id
    LEFT JOIN public.rides r ON r.id = fp.ride_id
    -- The ride whose cover the post shows: the open ride itself, or the ride a recap was recorded on.
    LEFT JOIN public.rides c ON c.id = COALESCE(fp.ride_id, l.ride_id)
    WHERE auth.uid() IS NOT NULL
      AND (p_before IS NULL OR fp.created_at < p_before)
      AND (p_author IS NULL OR fp.author_id = p_author)
      AND (fp.kind = 'ride_log' OR NOT COALESCE(r.is_completed, false))
    ORDER BY fp.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 50);
$$;

DO $$
DECLARE f TEXT;
BEGIN
    FOREACH f IN ARRAY ARRAY[
        'set_ride_cover(UUID, TEXT, TEXT, TEXT, TEXT, TEXT)',
        'put_place_photos(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, JSONB)',
        'crew_feed(TIMESTAMPTZ, INT, UUID)'
    ] LOOP
        EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%s FROM public, anon', f);
        EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', f);
    END LOOP;
END $$;

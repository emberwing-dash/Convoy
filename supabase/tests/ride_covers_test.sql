-- Tests for 20261117000000_ride_covers.sql (runs after ride_member_source_test.sql, reusing its riders and ride 3).
\set ON_ERROR_STOP 1
SET client_min_messages = warning;
RESET ROLE;
UPDATE public.rides SET end_lat = 17.686816, end_lon = 83.218482 WHERE id = '30000000-0000-0000-0000-000000000000';
SET ROLE authenticated;

-- Only the admin, only allowed hosts.
SELECT test.as_user('b0000000-0000-0000-0000-000000000000');
SELECT test.fails($$SELECT public.set_ride_cover('30000000-0000-0000-0000-000000000000', 'satellite', NULL, NULL, NULL, NULL)$$, 'Only the ride admin');
SELECT test.as_user('a0000000-0000-0000-0000-000000000000');
SELECT test.fails($$SELECT public.set_ride_cover('30000000-0000-0000-0000-000000000000', 'wikimedia', 'https://evil.example/x.jpg', 'x', 'CC BY', NULL)$$, 'Invalid cover image');
SELECT test.fails($$SELECT public.set_ride_cover('30000000-0000-0000-0000-000000000000', 'upload',
    'https://p.supabase.co/storage/v1/object/public/ride-covers/10000000-0000-0000-0000-000000000000/a.jpg', NULL, NULL, NULL)$$, 'Invalid cover image');
SELECT test.fails($$SELECT public.set_ride_cover('30000000-0000-0000-0000-000000000000', 'wikimedia',
    'https://upload.wikimedia.org/a.jpg', 'x', 'CC BY', 'https://evil.example/')$$, 'Invalid cover source page');
SELECT public.set_ride_cover('30000000-0000-0000-0000-000000000000', 'wikimedia',
    'https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Araku.jpg/1600px-Araku.jpg', 'A. Rao', 'CC BY-SA 4.0',
    'https://commons.wikimedia.org/wiki/File:Araku.jpg');

-- Any signed-in rider sees it on the feed, with the destination rounded to ~1 km.
SELECT test.as_user('d0000000-0000-0000-0000-000000000000');
SELECT test.check((SELECT cover_source = 'wikimedia' AND cover_credit = 'A. Rao' AND dest_lat = 17.69 AND dest_lon = 83.22
                   FROM public.crew_feed() WHERE ride_id = '30000000-0000-0000-0000-000000000000'), 'cover + rounded destination in feed');

-- Upload into the ride's own folder; satellite clears the URL and credit.
SELECT test.as_user('a0000000-0000-0000-0000-000000000000');
SELECT public.set_ride_cover('30000000-0000-0000-0000-000000000000', 'upload',
    'https://p.supabase.co/storage/v1/object/public/ride-covers/30000000-0000-0000-0000-000000000000/c.jpg', 'ignored', 'ignored', NULL);
RESET ROLE;
SELECT test.check((SELECT cover_source = 'upload' AND cover_credit IS NULL FROM public.rides WHERE id = '30000000-0000-0000-0000-000000000000'), 'upload stored without credit');
SET ROLE authenticated;
SELECT public.set_ride_cover('30000000-0000-0000-0000-000000000000', 'satellite', 'https://upload.wikimedia.org/x.jpg', 'x', 'x', NULL);
RESET ROLE;
SELECT test.check((SELECT cover_source = 'satellite' AND cover_url IS NULL FROM public.rides WHERE id = '30000000-0000-0000-0000-000000000000'), 'satellite has no URL');
INSERT INTO storage.buckets (id, name) VALUES ('other', 'other');
SET ROLE authenticated;

-- Storage: admin can write into their ride's folder only.
INSERT INTO storage.objects (bucket_id, name) VALUES ('ride-covers', '30000000-0000-0000-0000-000000000000/cover.jpg');
SELECT test.fails($$INSERT INTO storage.objects (bucket_id, name) VALUES ('ride-covers', '99999999-0000-0000-0000-000000000000/cover.jpg')$$, 'row-level security');
SELECT test.as_user('b0000000-0000-0000-0000-000000000000');
SELECT test.fails($$INSERT INTO storage.objects (bucket_id, name) VALUES ('ride-covers', '30000000-0000-0000-0000-000000000000/x.jpg')$$, 'row-level security');

-- Photo cache: only Wikimedia URLs, readable by signed-in riders.
SELECT test.fails($$SELECT public.put_place_photos('k', 'Araku', 18.3, 82.9, '[{"url":"https://evil.example/a.jpg"}]')$$, 'Invalid cover image');
SELECT public.put_place_photos('18.327,82.877|araku', 'Araku', 18.327, 82.877,
    '[{"url":"https://upload.wikimedia.org/a.jpg","credit":"x"}]');
SELECT test.check((SELECT jsonb_array_length(candidates) FROM public.place_photos WHERE place_key = '18.327,82.877|araku') = 1, 'cache stored');
SELECT test.fails($$INSERT INTO public.place_photos (place_key, lat, lon) VALUES ('x', 1, 1)$$, 'row-level security');
RESET ROLE;
SET ROLE anon;
SELECT test.fails($$SELECT public.set_ride_cover('30000000-0000-0000-0000-000000000000', 'satellite', NULL, NULL, NULL, NULL)$$, 'permission denied');
RESET ROLE;

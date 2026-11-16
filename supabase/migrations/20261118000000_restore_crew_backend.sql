-- 20261118000000_restore_crew_backend.sql
--
-- WHY: "Convoy/Schema/Database Schema.sql" (on main) was run against the live project. It begins with
-- DROP TABLE ... CASCADE on profiles/rides/crews, which also removed every table that depended on them
-- (feed_posts, ride_logs, ride_join_requests, notifications, place_photos, discover_*), then recreated
-- the base tables without the columns this branch adds. The old RPCs survived but now point at missing
-- tables, so Crew showed "Crew features aren't switched on".
--
-- WHAT: purely additive. (1) A compatibility layer so main's shape (posts, follows.following_id,
-- post_comments.author_id) and this branch's shape (feed_posts, follows.followee_id, post_comments.user_id)
-- both work on the same tables. (2) Replays, from supabase_migrations.schema_migrations, the exact SQL of the
-- four migrations that had run on this project (crew_social, crew_social_hardening, ride_member_source,
-- ride_covers). No rows are deleted.
--
-- APPLIED to the live project on 2026-11-16 as two migrations: restore_crew_backend_1_compat and
-- restore_crew_backend_2_replay. Every public function was fingerprinted (md5 of its definition) before and
-- after: all identical, so no newer function bodies were rolled back.
-- 20261102000000_discover_places and 20261104000000_harden_ride_joins were NOT replayed: they were never
-- applied to this project (the first is review-only, the second is marked "must not be applied").

-- ---------------------------------------------------------------------------
-- 1. Compatibility layer
-- ---------------------------------------------------------------------------

-- follows: main writes following_id, this branch writes followee_id. Keep both filled.
ALTER TABLE public.follows ADD COLUMN IF NOT EXISTS followee_id UUID;
UPDATE public.follows SET followee_id = following_id WHERE followee_id IS NULL;
CREATE OR REPLACE FUNCTION public.sync_follow_columns() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    NEW.followee_id  := COALESCE(NEW.followee_id, NEW.following_id);
    NEW.following_id := COALESCE(NEW.following_id, NEW.followee_id);
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_sync_follow_columns ON public.follows;
CREATE TRIGGER trg_sync_follow_columns BEFORE INSERT OR UPDATE ON public.follows
    FOR EACH ROW EXECUTE FUNCTION public.sync_follow_columns();
ALTER TABLE public.follows ALTER COLUMN followee_id SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_follows_pair_followee ON public.follows (follower_id, followee_id);

-- post_comments: main uses author_id, this branch uses user_id. Keep both filled.
ALTER TABLE public.post_comments ADD COLUMN IF NOT EXISTS user_id UUID;
UPDATE public.post_comments SET user_id = author_id WHERE user_id IS NULL;
CREATE OR REPLACE FUNCTION public.sync_comment_columns() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    NEW.user_id   := COALESCE(NEW.user_id, NEW.author_id);
    NEW.author_id := COALESCE(NEW.author_id, NEW.user_id);
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_sync_comment_columns ON public.post_comments;
CREATE TRIGGER trg_sync_comment_columns BEFORE INSERT OR UPDATE ON public.post_comments
    FOR EACH ROW EXECUTE FUNCTION public.sync_comment_columns();
ALTER TABLE public.post_comments ALTER COLUMN user_id SET NOT NULL;

-- Likes and comments can belong to a main "posts" row or a Crew "feed_posts" row, so the single
-- foreign key to posts is replaced by delete triggers on both parents.
ALTER TABLE public.post_likes    DROP CONSTRAINT IF EXISTS post_likes_post_id_fkey;
ALTER TABLE public.post_comments DROP CONSTRAINT IF EXISTS post_comments_post_id_fkey;
CREATE OR REPLACE FUNCTION public.cleanup_post_children() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    DELETE FROM public.post_likes    WHERE post_id = OLD.id;
    DELETE FROM public.post_comments WHERE post_id = OLD.id;
    RETURN OLD;
END $$;
REVOKE EXECUTE ON FUNCTION public.cleanup_post_children() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS trg_cleanup_post_children ON public.posts;
CREATE TRIGGER trg_cleanup_post_children AFTER DELETE ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.cleanup_post_children();

-- ---------------------------------------------------------------------------
-- 2. Replay the migrations that had run on this project (applied as restore_crew_backend_2_replay)
-- ---------------------------------------------------------------------------
-- crew_feed and ride_roster are dropped first because the earlier migrations define older shapes of them;
-- the later migrations in the replay recreate the current versions with their grants.
DROP FUNCTION IF EXISTS public.crew_feed(TIMESTAMPTZ, INT, UUID);
DROP FUNCTION IF EXISTS public.ride_roster(UUID);

DO $replay$
DECLARE
    m RECORD;
BEGIN
    FOR m IN
        SELECT version, name, statements[1] AS sql
        FROM supabase_migrations.schema_migrations
        WHERE version IN ('20261114215957', '20261114220055', '20261114223410', '20261115115804')
        ORDER BY version
    LOOP
        RAISE NOTICE 'Replaying % (%)', m.version, m.name;
        EXECUTE m.sql;
    END LOOP;
END
$replay$;

-- feed_posts exists again: give it the same child cleanup as main's posts.
DROP TRIGGER IF EXISTS trg_cleanup_post_children ON public.feed_posts;
CREATE TRIGGER trg_cleanup_post_children AFTER DELETE ON public.feed_posts
    FOR EACH ROW EXECUTE FUNCTION public.cleanup_post_children();

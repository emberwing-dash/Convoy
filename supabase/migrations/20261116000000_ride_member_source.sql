-- =============================================================================
-- Migration: 20261116000000_ride_member_source.sql
-- Records HOW each rider got onto a ride, so a trip can show its riders grouped
-- (admin / came with a crew / invited friends / from the Crew feed / with the ride code).
--
--   source  'admin'  the organiser
--           'crew'   invited because they belong to crew_id
--           'friend' invited directly by the admin
--           'feed'   asked to join from the Crew feed and was accepted
--           'code'   asked to join with the ride code and was accepted
--           'joined' existed before this migration (unknown route)
--
-- The database enforces the labels (trigger below), so the app cannot mislabel anyone:
-- a 'crew' tag needs a real accepted crew membership; 'feed'/'code' need a matching accepted
-- join request; the organiser row is always 'admin'.
-- =============================================================================

ALTER TABLE public.ride_members ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'joined';
ALTER TABLE public.ride_members DROP CONSTRAINT IF EXISTS ride_members_source_check;
ALTER TABLE public.ride_members ADD CONSTRAINT ride_members_source_check
    CHECK (source IN ('admin', 'crew', 'friend', 'feed', 'code', 'joined'));
ALTER TABLE public.ride_members ADD COLUMN IF NOT EXISTS crew_id UUID REFERENCES public.crews(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_ride_members_crew ON public.ride_members (crew_id) WHERE crew_id IS NOT NULL;

-- Existing organisers are admins; everyone else already on a ride stays 'joined'.
UPDATE public.ride_members SET source = 'admin', crew_id = NULL WHERE role = 'organiser' AND source <> 'admin';

CREATE OR REPLACE FUNCTION public.guard_ride_member_source() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF NEW.role = 'organiser' THEN
        NEW.source := 'admin';
        NEW.crew_id := NULL;
        RETURN NEW;
    END IF;
    IF NEW.source = 'admin' THEN
        NEW.source := 'joined';
    END IF;

    IF NEW.source = 'crew' THEN
        IF NEW.crew_id IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.crew_members cm
            WHERE cm.crew_id = NEW.crew_id AND cm.user_id = NEW.user_id AND cm.status = 'accepted') THEN
            -- Not really in that crew: they were still invited by the admin.
            NEW.source := 'friend';
            NEW.crew_id := NULL;
        END IF;
    ELSE
        NEW.crew_id := NULL;
    END IF;

    IF NEW.source IN ('feed', 'code') AND NOT EXISTS (
        SELECT 1 FROM public.ride_join_requests r
        WHERE r.ride_id = NEW.ride_id AND r.requester_id = NEW.user_id
          AND r.status = 'accepted' AND r.source = NEW.source) THEN
        NEW.source := CASE WHEN TG_OP = 'UPDATE' THEN OLD.source ELSE 'joined' END;
        IF NEW.source <> 'crew' THEN NEW.crew_id := NULL; ELSE NEW.crew_id := OLD.crew_id; END IF;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.guard_ride_member_source() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_guard_ride_member_source ON public.ride_members;
CREATE TRIGGER trg_guard_ride_member_source
    BEFORE INSERT OR UPDATE OF source, crew_id, role ON public.ride_members
    FOR EACH ROW EXECUTE FUNCTION public.guard_ride_member_source();

-- Riders accepted from a join request before this migration get that request's source.
UPDATE public.ride_members m SET source = r.source
FROM public.ride_join_requests r
WHERE r.ride_id = m.ride_id AND r.requester_id = m.user_id AND r.status = 'accepted'
  AND m.role <> 'organiser' AND m.source = 'joined';

-- Accepting a join request now records where the rider came from. If they were already
-- invited by the admin (crew or friend) that stays; a declined/legacy row takes the request's source.
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
        SELECT max_riders INTO v_max FROM public.rides WHERE id = v_request.ride_id FOR UPDATE;
        IF v_max IS NOT NULL AND public.accepted_rider_count(v_request.ride_id) >= v_max THEN
            RAISE EXCEPTION 'Ride is full';
        END IF;
        UPDATE public.ride_join_requests SET status = 'accepted', updated_at = now() WHERE id = p_request_id;
        INSERT INTO public.ride_members (ride_id, user_id, role, status, source)
        VALUES (v_request.ride_id, v_request.requester_id, 'rider', 'accepted', v_request.source)
        ON CONFLICT (ride_id, user_id) DO UPDATE SET
            role = 'rider',
            status = 'accepted',
            source = CASE WHEN public.ride_members.status IN ('declined', 'pending')
                          THEN EXCLUDED.source ELSE public.ride_members.source END;
    ELSE
        UPDATE public.ride_join_requests SET status = 'declined', updated_at = now() WHERE id = p_request_id;
    END IF;
    v_count := public.accepted_rider_count(v_request.ride_id);
    IF v_max IS NOT NULL AND v_count >= v_max THEN
        UPDATE public.rides SET accepts_requests = false WHERE id = v_request.ride_id;
    END IF;
    RETURN jsonb_build_object('request_id', p_request_id, 'ride_id', v_request.ride_id,
                              'requester_id', v_request.requester_id, 'status', p_action || 'ed',
                              'members_count', v_count);
END;
$$;

-- Everyone on a ride, grouped-ready, for the admin and accepted riders only.
-- Crew names come through here because riders from outside a crew cannot read the crews table.
CREATE OR REPLACE FUNCTION public.ride_roster(p_ride_id UUID)
RETURNS TABLE (user_id UUID, display_name TEXT, username TEXT, avatar_data TEXT, role TEXT, status TEXT,
               source TEXT, crew_id UUID, crew_name TEXT, joined_at TIMESTAMPTZ, i_follow BOOLEAN, is_me BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT m.user_id, p.display_name, p.username, p.avatar_data, m.role, m.status, m.source, m.crew_id, c.name,
           m.joined_at,
           EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = auth.uid() AND f.followee_id = m.user_id),
           m.user_id = auth.uid()
    FROM public.ride_members m
    LEFT JOIN public.profiles p ON p.id = m.user_id
    LEFT JOIN public.crews c ON c.id = m.crew_id
    WHERE m.ride_id = p_ride_id
      AND m.status IN ('accepted', 'invited', 'pending')
      AND auth.uid() IS NOT NULL
      AND (EXISTS (SELECT 1 FROM public.rides r WHERE r.id = p_ride_id AND r.organiser_id = auth.uid())
           OR EXISTS (SELECT 1 FROM public.ride_members me
                      WHERE me.ride_id = p_ride_id AND me.user_id = auth.uid() AND me.status = 'accepted'))
    ORDER BY CASE m.source WHEN 'admin' THEN 0 WHEN 'crew' THEN 1 WHEN 'friend' THEN 2
                           WHEN 'feed' THEN 3 WHEN 'code' THEN 4 ELSE 5 END,
             c.name, m.joined_at;
$$;
REVOKE EXECUTE ON FUNCTION public.ride_roster(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.ride_roster(UUID) TO authenticated;

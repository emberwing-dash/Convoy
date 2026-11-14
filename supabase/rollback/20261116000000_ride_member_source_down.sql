-- Undo for 20261116000000_ride_member_source.sql. Restores respond_ride_join_request from 20261115.
BEGIN;
DROP FUNCTION IF EXISTS public.ride_roster(UUID);
DROP TRIGGER IF EXISTS trg_guard_ride_member_source ON public.ride_members;
DROP FUNCTION IF EXISTS public.guard_ride_member_source();
DROP INDEX IF EXISTS public.idx_ride_members_crew;
ALTER TABLE public.ride_members DROP CONSTRAINT IF EXISTS ride_members_source_check;
ALTER TABLE public.ride_members DROP COLUMN IF EXISTS crew_id;
ALTER TABLE public.ride_members DROP COLUMN IF EXISTS source;
CREATE OR REPLACE FUNCTION public.respond_ride_join_request(p_request_id UUID, p_action TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_user UUID := auth.uid(); v_request RECORD; v_max INT; v_count INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Unauthorized: User not authenticated'; END IF;
    IF p_action NOT IN ('accept', 'decline') THEN RAISE EXCEPTION 'Invalid action: must be accept or decline'; END IF;
    SELECT * INTO v_request FROM public.ride_join_requests WHERE id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ride join request not found'; END IF;
    IF v_request.organizer_id <> v_user THEN RAISE EXCEPTION 'Forbidden: Only the trip organizer can respond to join requests'; END IF;
    IF v_request.status <> 'pending' THEN RAISE EXCEPTION 'Request is no longer pending (current status: %)', v_request.status; END IF;
    IF p_action = 'accept' THEN
        SELECT max_riders INTO v_max FROM public.rides WHERE id = v_request.ride_id FOR UPDATE;
        IF v_max IS NOT NULL AND public.accepted_rider_count(v_request.ride_id) >= v_max THEN RAISE EXCEPTION 'Ride is full'; END IF;
        UPDATE public.ride_join_requests SET status = 'accepted', updated_at = now() WHERE id = p_request_id;
        INSERT INTO public.ride_members (ride_id, user_id, role, status)
        VALUES (v_request.ride_id, v_request.requester_id, 'rider', 'accepted')
        ON CONFLICT (ride_id, user_id) DO UPDATE SET role = 'rider', status = 'accepted';
    ELSE
        UPDATE public.ride_join_requests SET status = 'declined', updated_at = now() WHERE id = p_request_id;
    END IF;
    v_count := public.accepted_rider_count(v_request.ride_id);
    IF v_max IS NOT NULL AND v_count >= v_max THEN UPDATE public.rides SET accepts_requests = false WHERE id = v_request.ride_id; END IF;
    RETURN jsonb_build_object('request_id', p_request_id, 'ride_id', v_request.ride_id, 'requester_id', v_request.requester_id,
                              'status', p_action || 'ed', 'members_count', v_count);
END;
$$;
COMMIT;

-- !! NOT APPLIED to the live project, and must not be: its ride_members policies and status check
-- !! would replace the live ones. 20261115000000_crew_social.sql contains the parts the app needs.
-- 20261104000000_harden_ride_joins.sql
-- Hardening Ride Join Codes, Unique Membership Constraints, Dedicated RideJoinRequest Lifecycle,
-- Atomic Backend Approval/Decline RPCs, RLS Column Security, and Ride Completion Integrity.

-- 1. Ensure rides table has a unique index on join code (case-insensitive)
CREATE UNIQUE INDEX IF NOT EXISTS idx_rides_code_unique
ON public.rides (UPPER(code));

-- 2. Ensure ride_members table has unique constraint (one membership per user per ride)
ALTER TABLE public.ride_members
DROP CONSTRAINT IF EXISTS unique_ride_member;

ALTER TABLE public.ride_members
ADD CONSTRAINT unique_ride_member UNIQUE (ride_id, user_id);

-- Status check constraint on ride_members
ALTER TABLE public.ride_members
DROP CONSTRAINT IF EXISTS ride_members_status_check;

ALTER TABLE public.ride_members
ADD CONSTRAINT ride_members_status_check
CHECK (status IN ('invited', 'accepted', 'declined'));

-- 3. Create dedicated ride_join_requests table
CREATE TABLE IF NOT EXISTS public.ride_join_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
    requester_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    organizer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Duplicate pending request protection: at most ONE active pending request per rider per ride
CREATE UNIQUE INDEX IF NOT EXISTS idx_ride_join_requests_unique_pending
ON public.ride_join_requests (ride_id, requester_id)
WHERE status = 'pending';

-- 5. Performance Indexes
CREATE INDEX IF NOT EXISTS idx_rjr_organizer_status ON public.ride_join_requests(organizer_id, status);
CREATE INDEX IF NOT EXISTS idx_rjr_requester_status ON public.ride_join_requests(requester_id, status);
CREATE INDEX IF NOT EXISTS idx_rjr_ride_status ON public.ride_join_requests(ride_id, status);

-- 6A. Row Level Security on ride_join_requests
ALTER TABLE public.ride_join_requests ENABLE ROW LEVEL SECURITY;

-- Requester and Organizer can view their own requests
DROP POLICY IF EXISTS "Users can view relevant ride join requests" ON public.ride_join_requests;
CREATE POLICY "Users can view relevant ride join requests"
ON public.ride_join_requests FOR SELECT
USING (auth.uid() = requester_id OR auth.uid() = organizer_id);

-- Direct client updates/deletes are blocked to guarantee transactional integrity via RPCs
DROP POLICY IF EXISTS "Users cannot directly modify requests" ON public.ride_join_requests;
CREATE POLICY "Users cannot directly modify requests"
ON public.ride_join_requests FOR UPDATE
USING (false);

DROP POLICY IF EXISTS "Users cannot directly delete requests" ON public.ride_join_requests;
CREATE POLICY "Users cannot directly delete requests"
ON public.ride_join_requests FOR DELETE
USING (false);

-- 6B. Row Level Security & Column Security on ride_members
ALTER TABLE public.ride_members ENABLE ROW LEVEL SECURITY;

-- 6B.1 SELECT: Organiser or the user themselves can read
DROP POLICY IF EXISTS "Users can view ride memberships" ON public.ride_members;
CREATE POLICY "Users can view ride memberships"
ON public.ride_members FOR SELECT
USING (
    auth.uid() = user_id 
    OR auth.uid() = (SELECT organiser_id FROM public.rides WHERE id = ride_members.ride_id)
);

-- 6B.2 INSERT: Only the ride organiser can invite members or insert their own initial record
DROP POLICY IF EXISTS "Organisers can insert ride members" ON public.ride_members;
CREATE POLICY "Organisers can insert ride members"
ON public.ride_members FOR INSERT
WITH CHECK (
    -- Organiser creating ride: inserting self as organiser and accepted
    (auth.uid() = user_id AND role = 'organiser' AND status = 'accepted' AND auth.uid() = (SELECT organiser_id FROM public.rides WHERE id = ride_members.ride_id))
    OR
    -- Organiser inviting another user: must have role rider and status invited
    (auth.uid() = (SELECT organiser_id FROM public.rides WHERE id = ride_members.ride_id) AND role = 'rider' AND status = 'invited')
);

-- 6B.3 UPDATE: Users can only update their own invitation status (cannot promote to organiser, cannot change user_id/ride_id)
DROP POLICY IF EXISTS "Users can only update their own invitation status" ON public.ride_members;
CREATE POLICY "Users can only update their own invitation status"
ON public.ride_members FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (
    auth.uid() = user_id 
    AND role = 'rider' 
    AND status IN ('accepted', 'declined')
);

-- 6B.4 DELETE: Organiser can remove riders; riders can leave (organisers cannot leave without closing/transferring)
DROP POLICY IF EXISTS "Users or organisers can delete memberships" ON public.ride_members;
CREATE POLICY "Users or organisers can delete memberships"
ON public.ride_members FOR DELETE
USING (
    (auth.uid() = (SELECT organiser_id FROM public.rides WHERE id = ride_members.ride_id) AND user_id != auth.uid())
    OR
    (auth.uid() = user_id AND role != 'organiser')
);

-- 7. Atomic RPC: create_ride_join_request
CREATE OR REPLACE FUNCTION public.create_ride_join_request(p_ride_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_requester_id UUID;
    v_organizer_id UUID;
    v_request RECORD;
BEGIN
    v_requester_id := auth.uid();
    IF v_requester_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User not authenticated';
    END IF;

    -- Fetch ride and organizer
    SELECT organiser_id INTO v_organizer_id
    FROM public.rides
    WHERE id = p_ride_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ride not found';
    END IF;

    -- Prevent self-join request
    IF v_requester_id = v_organizer_id THEN
        RAISE EXCEPTION 'Cannot send join request to your own ride';
    END IF;

    -- Prevent joining if already accepted member
    IF EXISTS (
        SELECT 1 FROM public.ride_members
        WHERE ride_id = p_ride_id AND user_id = v_requester_id AND status = 'accepted'
    ) THEN
        RAISE EXCEPTION 'User is already an accepted member of this ride';
    END IF;

    -- Insert new pending request (partial index idx_ride_join_requests_unique_pending blocks duplicate pending requests)
    INSERT INTO public.ride_join_requests (ride_id, requester_id, organizer_id, status, created_at, updated_at)
    VALUES (p_ride_id, v_requester_id, v_organizer_id, 'pending', now(), now())
    RETURNING * INTO v_request;

    RETURN to_jsonb(v_request);
END;
$$;

-- 8. Atomic RPC: respond_ride_join_request
CREATE OR REPLACE FUNCTION public.respond_ride_join_request(
    p_request_id UUID,
    p_action TEXT -- 'accept' or 'decline'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_request RECORD;
    v_new_count INT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User not authenticated';
    END IF;

    IF p_action NOT IN ('accept', 'decline') THEN
        RAISE EXCEPTION 'Invalid action: must be accept or decline';
    END IF;

    -- Lock request row to prevent concurrent race conditions
    SELECT * INTO v_request
    FROM public.ride_join_requests
    WHERE id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ride join request not found';
    END IF;

    -- Enforce organizer ownership
    IF v_request.organizer_id != v_user_id THEN
        RAISE EXCEPTION 'Forbidden: Only the trip organizer can respond to join requests';
    END IF;

    -- Verify request is still pending
    IF v_request.status != 'pending' THEN
        RAISE EXCEPTION 'Request is no longer pending (current status: %)', v_request.status;
    END IF;

    IF p_action = 'accept' THEN
        -- 1. Atomically update request status
        UPDATE public.ride_join_requests
        SET status = 'accepted', updated_at = now()
        WHERE id = p_request_id;

        -- 2. Atomically insert or update ride membership
        INSERT INTO public.ride_members (ride_id, user_id, role, status)
        VALUES (v_request.ride_id, v_request.requester_id, 'rider', 'accepted')
        ON CONFLICT (ride_id, user_id)
        DO UPDATE SET role = 'rider', status = 'accepted';

    ELSIF p_action = 'decline' THEN
        -- Update request status without deleting (preserves audit trail)
        UPDATE public.ride_join_requests
        SET status = 'declined', updated_at = now()
        WHERE id = p_request_id;
    END IF;

    SELECT COUNT(*) INTO v_new_count
    FROM public.ride_members
    WHERE ride_id = v_request.ride_id AND status = 'accepted';

    RETURN jsonb_build_object(
        'request_id', p_request_id,
        'ride_id', v_request.ride_id,
        'requester_id', v_request.requester_id,
        'status', p_action || 'ed',
        'members_count', v_new_count
    );
END;
$$;

-- 9. Atomic RPC: cancel_ride_join_request
CREATE OR REPLACE FUNCTION public.cancel_ride_join_request(p_request_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_request RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User not authenticated';
    END IF;

    -- Lock request row
    SELECT * INTO v_request
    FROM public.ride_join_requests
    WHERE id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ride join request not found';
    END IF;

    -- Enforce requester ownership
    IF v_request.requester_id != v_user_id THEN
        RAISE EXCEPTION 'Forbidden: Only the requester can cancel their request';
    END IF;

    IF v_request.status != 'pending' THEN
        RAISE EXCEPTION 'Cannot cancel request with status %', v_request.status;
    END IF;

    UPDATE public.ride_join_requests
    SET status = 'cancelled', updated_at = now()
    WHERE id = p_request_id
    RETURNING * INTO v_request;

    RETURN to_jsonb(v_request);
END;
$$;

-- 10. Atomic RPC: respond_ride_invitation (Narrowly scoped status transition)
CREATE OR REPLACE FUNCTION public.respond_ride_invitation(
    p_ride_id UUID,
    p_accept BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_member RECORD;
    v_new_status TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User not authenticated';
    END IF;

    SELECT * INTO v_member
    FROM public.ride_members
    WHERE ride_id = p_ride_id AND user_id = v_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invitation not found for current user';
    END IF;

    IF v_member.status != 'invited' THEN
        RAISE EXCEPTION 'Membership status is % (only invited members can respond)', v_member.status;
    END IF;

    v_new_status := CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END;

    UPDATE public.ride_members
    SET status = v_new_status
    WHERE ride_id = p_ride_id AND user_id = v_user_id;

    RETURN jsonb_build_object(
        'ride_id', p_ride_id,
        'user_id', v_user_id,
        'status', v_new_status
    );
END;
$$;

-- 11. Atomic RPC: complete_group_ride
ALTER TABLE public.rides 
ADD COLUMN IF NOT EXISTS is_completed BOOLEAN NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.complete_group_ride(p_ride_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_organizer_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User not authenticated';
    END IF;

    SELECT organiser_id INTO v_organizer_id
    FROM public.rides
    WHERE id = p_ride_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ride not found';
    END IF;

    IF v_organizer_id != v_user_id THEN
        RAISE EXCEPTION 'Forbidden: Only the ride organiser can close the group ride';
    END IF;

    UPDATE public.rides
    SET is_completed = true
    WHERE id = p_ride_id;

    RETURN jsonb_build_object(
        'ride_id', p_ride_id,
        'is_completed', true
    );
END;
$$;

-- 12. Security Grants
REVOKE EXECUTE ON FUNCTION public.create_ride_join_request(UUID) FROM public;
GRANT EXECUTE ON FUNCTION public.create_ride_join_request(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.respond_ride_join_request(UUID, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.respond_ride_join_request(UUID, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.cancel_ride_join_request(UUID) FROM public;
GRANT EXECUTE ON FUNCTION public.cancel_ride_join_request(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.respond_ride_invitation(UUID, BOOLEAN) FROM public;
GRANT EXECUTE ON FUNCTION public.respond_ride_invitation(UUID, BOOLEAN) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.complete_group_ride(UUID) FROM public;
GRANT EXECUTE ON FUNCTION public.complete_group_ride(UUID) TO authenticated;

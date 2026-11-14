-- Local stand-in for the parts of the Supabase project these migrations build on.
-- Used only by scripts/test-crew-social.sh against a throwaway local Postgres.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE auth.users (id UUID PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE AS
$$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::UUID $$;
GRANT USAGE ON SCHEMA auth, public TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;

-- Mirrors the live Convoy project (checked 2026-11-15).
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT UNIQUE NOT NULL, display_name TEXT NOT NULL, avatar_data TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE public.rides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), title TEXT NOT NULL, place TEXT, subtitle TEXT, tag TEXT,
    organiser_id UUID NOT NULL REFERENCES public.profiles(id), code TEXT NOT NULL UNIQUE, departs TIMESTAMPTZ NOT NULL,
    distance TEXT, duration TEXT, display_date TEXT, display_time TEXT, from_location TEXT, to_location TEXT,
    stops_json TEXT DEFAULT '[]', style_raw TEXT DEFAULT 'Fastest', route_set BOOLEAN DEFAULT false,
    start_lat DOUBLE PRECISION DEFAULT 0, start_lon DOUBLE PRECISION DEFAULT 0,
    end_lat DOUBLE PRECISION DEFAULT 0, end_lon DOUBLE PRECISION DEFAULT 0, route_coords_json TEXT DEFAULT '[]',
    route_km DOUBLE PRECISION DEFAULT 0, route_minutes INT DEFAULT 0,
    is_completed BOOLEAN DEFAULT false, completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE public.ride_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL REFERENCES public.rides(id),
    user_id UUID NOT NULL REFERENCES public.profiles(id),
    role TEXT NOT NULL DEFAULT 'rider' CHECK (role IN ('organiser', 'rider')),
    status TEXT NOT NULL DEFAULT 'pending',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ride_members_status_check CHECK (status IN ('pending', 'accepted', 'declined')),
    CONSTRAINT ride_members_unique UNIQUE (ride_id, user_id));
CREATE TABLE public.crews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name TEXT NOT NULL, code TEXT NOT NULL UNIQUE,
    created_by UUID NOT NULL REFERENCES public.profiles(id), avatar_data TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE public.crew_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    crew_id UUID NOT NULL REFERENCES public.crews(id),
    user_id UUID NOT NULL REFERENCES public.profiles(id),
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
    invited_by UUID REFERENCES public.profiles(id), created_at TIMESTAMPTZ NOT NULL DEFAULT now());
ALTER TABLE public.rides ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can view rides" ON public.rides FOR SELECT USING (true);
CREATE POLICY "Organiser can update ride" ON public.rides FOR UPDATE USING (auth.uid() = organiser_id) WITH CHECK (auth.uid() = organiser_id);
ALTER TABLE public.ride_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Organiser can update ride member status" ON public.ride_members FOR UPDATE
    USING (EXISTS (SELECT 1 FROM public.rides r WHERE r.id = ride_members.ride_id AND r.organiser_id = auth.uid()));
CREATE POLICY "Ride members can view roster" ON public.ride_members FOR SELECT USING (auth.uid() = user_id);
CREATE PUBLICATION supabase_realtime;

-- Supabase grants table privileges to API roles by default; RLS does the filtering.
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;

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

CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT UNIQUE NOT NULL, display_name TEXT NOT NULL, avatar_data TEXT);
CREATE TABLE public.rides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), title TEXT NOT NULL, place TEXT, subtitle TEXT, tag TEXT,
    organiser_id UUID NOT NULL REFERENCES auth.users(id), code TEXT NOT NULL, departs TIMESTAMPTZ NOT NULL,
    distance TEXT, duration TEXT, display_date TEXT, display_time TEXT, from_location TEXT, to_location TEXT,
    stops_json TEXT, style_raw TEXT, route_set BOOLEAN, start_lat DOUBLE PRECISION, start_lon DOUBLE PRECISION,
    end_lat DOUBLE PRECISION, end_lon DOUBLE PRECISION, route_coords_json TEXT,
    route_km DOUBLE PRECISION, route_minutes INT);
CREATE TABLE public.ride_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id), role TEXT NOT NULL, status TEXT,
    joined_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE public.crews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name TEXT NOT NULL, code TEXT NOT NULL,
    created_by UUID NOT NULL REFERENCES auth.users(id), avatar_data TEXT);
CREATE TABLE public.crew_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    crew_id UUID NOT NULL REFERENCES public.crews(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id), role TEXT NOT NULL, status TEXT NOT NULL,
    invited_by UUID, created_at TIMESTAMPTZ DEFAULT now());

-- Supabase grants table privileges to API roles by default; RLS does the filtering.
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;

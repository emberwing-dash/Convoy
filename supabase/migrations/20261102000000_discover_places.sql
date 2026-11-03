-- =============================================================================
-- Migration: 20261102000000_discover_places.sql
-- Stage 5A: Places Catalogue, Provenance Ledger, and Geodesic Proximity Search
--
-- REVIEW ONLY — DO NOT APPLY TO PRODUCTION UNTIL EXPLICITLY APPROVED
-- =============================================================================

-- 1. Ensure PostGIS is enabled
CREATE EXTENSION IF NOT EXISTS postgis;

-- 2. Master Places Catalogue Table
CREATE TABLE IF NOT EXISTS public.discover_places (
    id TEXT PRIMARY KEY,                                  -- Clean unique slug (e.g. 'in-la-khardung-la' or 'in-dl-red-fort')
    name TEXT NOT NULL,                                   -- Official place name
    region TEXT NOT NULL,                                 -- District / State / UT name
    category TEXT NOT NULL,                               -- Enum: 'hillRoad', 'hillStation', 'waterfall', 'lake', 'beach', 'viewpoint', 'forest', 'historical', 'cafe', 'waterfront'
    location GEOGRAPHY(Point, 4326) NOT NULL,             -- Native WGS84 Geodesic Point (lon, lat)
    summary TEXT NOT NULL DEFAULT '',                     -- Verified lead summary paragraph
    facts JSONB NOT NULL DEFAULT '[]'::jsonb,             -- Structured facts: [{"label": "Hours", "value": "..."}]
    tags TEXT[] NOT NULL DEFAULT '{}',                    -- Editorial and discovery tags
    fame_score FLOAT DEFAULT NULL,                        -- 0.0 to 1.0 (Wikidata/Wikipedia sitelink signal)
    popularity_score FLOAT DEFAULT NULL,                  -- 0.0 to 1.0 (Convoy user engagement)
    photos JSONB NOT NULL DEFAULT '[]'::jsonb,            -- Attributed photos: [{"url": "...", "credit": "...", "license": "...", "description_url": "..."}]
    is_closed BOOLEAN NOT NULL DEFAULT FALSE,
    source TEXT NOT NULL,                                 -- Origin source identifier: 'wikidata', 'wikimedia', 'osm', 'convoy'
    source_url TEXT NOT NULL DEFAULT '',                  -- Provenance URL for auditability
    source_license TEXT NOT NULL DEFAULT 'CC0',           -- Provenance data license
    external_id TEXT DEFAULT NULL,                        -- External identifier (e.g. Wikidata QID: 'Q205626')
    verification_status TEXT NOT NULL DEFAULT 'unverified', -- 'verified', 'unverified', 'flagged' (defaults to unverified for safety)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Ensure column default is strictly 'unverified' even if table already existed
ALTER TABLE public.discover_places 
    ALTER COLUMN verification_status SET DEFAULT 'unverified';

-- 3. Geospatial Index (GIST on GEOGRAPHY ensures fast geodesic distance filtering)
CREATE INDEX IF NOT EXISTS idx_discover_places_location 
    ON public.discover_places USING GIST (location);

-- 4. Attribute Indexes for Fast Filtering and Sorting
CREATE INDEX IF NOT EXISTS idx_discover_places_category 
    ON public.discover_places (category);

CREATE INDEX IF NOT EXISTS idx_discover_places_verification_status 
    ON public.discover_places (verification_status);

CREATE INDEX IF NOT EXISTS idx_discover_places_fame 
    ON public.discover_places (fame_score DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_discover_places_external_id 
    ON public.discover_places (external_id);

-- 5. Provenance Ingestion Ledger
CREATE TABLE IF NOT EXISTS public.discover_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_name TEXT NOT NULL,                            -- e.g. 'wikidata-sparql', 'wikimedia-commons', 'osm-overpass'
    source_license TEXT NOT NULL,                         -- e.g. 'CC0', 'ODbL', 'CC-BY-SA-4.0'
    source_url TEXT NOT NULL,
    record_count INT NOT NULL DEFAULT 0,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 6. Ambiguous Ingestion Match Queue (Human Review Queue)
CREATE TABLE IF NOT EXISTS public.discover_ingestion_review (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id TEXT NOT NULL,
    candidate_name TEXT NOT NULL,
    existing_place_id TEXT REFERENCES public.discover_places(id),
    distance_meters FLOAT NOT NULL,
    conflict_reason TEXT NOT NULL,                        -- 'proximity_ambiguity', 'category_mismatch'
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. Intelligent Auto-Expanding Nearby Search Function
-- NOTE: Uses GEOGRAPHY for exact geodesic distance in meters on the WGS84 spheroid.
-- Uses SECURITY INVOKER because caller permissions and RLS context are respected.
-- search_path is explicitly locked to public, pg_temp to prevent object shadowing.
CREATE OR REPLACE FUNCTION public.discover_places_near(
    origin_lat FLOAT,
    origin_lon FLOAT,
    initial_radius_km FLOAT DEFAULT 25.0,
    min_results INT DEFAULT 6
)
RETURNS TABLE (
    id TEXT,
    name TEXT,
    region TEXT,
    category TEXT,
    lat FLOAT,
    lon FLOAT,
    summary TEXT,
    facts JSONB,
    tags TEXT[],
    fame_score FLOAT,
    popularity_score FLOAT,
    photos JSONB,
    source TEXT,
    source_url TEXT,
    distance_km FLOAT,
    effective_radius_km FLOAT
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
    curr_radius FLOAT := initial_radius_km;
    step_radii FLOAT[] := ARRAY[25.0, 50.0, 100.0, 250.0];
    r FLOAT;
    found_count INT := 0;
    origin_geog GEOGRAPHY;
BEGIN
    -- Validate coordinate inputs against NULL
    IF origin_lat IS NULL OR origin_lon IS NULL THEN
        RAISE EXCEPTION 'Coordinates cannot be NULL';
    END IF;

    -- Validate coordinate inputs against NaN (in IEEE 754 float, NaN != NaN is true)
    IF origin_lat != origin_lat OR origin_lon != origin_lon THEN
        RAISE EXCEPTION 'Coordinates cannot be NaN';
    END IF;

    -- Validate coordinate inputs against out-of-range / Infinity
    IF origin_lat < -90.0 OR origin_lat > 90.0 OR origin_lon < -180.0 OR origin_lon > 180.0 THEN
        RAISE EXCEPTION 'Coordinates out of valid range: lat %, lon % (lat must be [-90, 90], lon [-180, 180])', origin_lat, origin_lon;
    END IF;

    -- Validate initial_radius_km
    IF initial_radius_km IS NULL OR initial_radius_km != initial_radius_km OR initial_radius_km <= 0.0 OR initial_radius_km > 2000.0 THEN
        RAISE EXCEPTION 'Invalid initial_radius_km: %. Must be between 0.1 and 2000 km.', initial_radius_km;
    END IF;

    -- Validate min_results
    IF min_results IS NULL OR min_results <= 0 OR min_results > 100 THEN
        RAISE EXCEPTION 'Invalid min_results: %. Must be between 1 and 100.', min_results;
    END IF;

    -- Construct point as (lon, lat) WGS84 Geodesic Point
    origin_geog := ST_SetSRID(ST_MakePoint(origin_lon, origin_lat), 4326)::geography;

    -- Iterate step expansion until minimum verified result threshold is satisfied
    FOREACH r IN ARRAY step_radii LOOP
        curr_radius := GREATEST(curr_radius, r);
        
        SELECT COUNT(*) INTO found_count
        FROM public.discover_places p
        WHERE NOT p.is_closed
          AND p.verification_status = 'verified'
          AND ST_DWithin(p.location, origin_geog, curr_radius * 1000.0);
          
        IF found_count >= min_results THEN
            EXIT;
        END IF;
    END LOOP;

    RETURN QUERY
    SELECT 
        p.id,
        p.name,
        p.region,
        p.category,
        ST_Y(p.location::geometry)::FLOAT AS lat,
        ST_X(p.location::geometry)::FLOAT AS lon,
        p.summary,
        p.facts,
        p.tags,
        p.fame_score,
        p.popularity_score,
        p.photos,
        p.source,
        p.source_url,
        ROUND((ST_Distance(p.location, origin_geog) / 1000.0)::numeric, 1)::FLOAT AS distance_km,
        curr_radius AS effective_radius_km
    FROM public.discover_places p
    WHERE NOT p.is_closed
      AND p.verification_status = 'verified'
      AND ST_DWithin(p.location, origin_geog, curr_radius * 1000.0)
    ORDER BY distance_km ASC
    LIMIT 50;
END;
$$;

-- 8. Execution and Table Permissions
REVOKE ALL ON FUNCTION public.discover_places_near(FLOAT, FLOAT, FLOAT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.discover_places_near(FLOAT, FLOAT, FLOAT, INT) TO anon, authenticated, service_role;

GRANT SELECT ON public.discover_places TO anon, authenticated;
GRANT ALL ON public.discover_places TO service_role;
GRANT ALL ON public.discover_sources TO service_role;
GRANT ALL ON public.discover_ingestion_review TO service_role;

-- 9. Row Level Security (RLS) Configuration (Safely Repeatable)
ALTER TABLE public.discover_places ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discover_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discover_ingestion_review ENABLE ROW LEVEL SECURITY;

-- Restrict public read access strictly to verified records
DROP POLICY IF EXISTS "Allow public read access to discover_places" ON public.discover_places;
CREATE POLICY "Allow public read access to discover_places" 
    ON public.discover_places FOR SELECT 
    TO anon, authenticated 
    USING (verification_status = 'verified');

-- Allow service_role full read/write access (for ingestion pipeline)
DROP POLICY IF EXISTS "Service role full access to discover_places" ON public.discover_places;
CREATE POLICY "Service role full access to discover_places"
    ON public.discover_places FOR ALL 
    TO service_role 
    USING (true)
    WITH CHECK (true);

-- Provenance & Review tables restricted to service-role / ingestion only
DROP POLICY IF EXISTS "Service role full access to discover_sources" ON public.discover_sources;
CREATE POLICY "Service role full access to discover_sources"
    ON public.discover_sources FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Service role full access to discover_ingestion_review" ON public.discover_ingestion_review;
CREATE POLICY "Service role full access to discover_ingestion_review"
    ON public.discover_ingestion_review FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

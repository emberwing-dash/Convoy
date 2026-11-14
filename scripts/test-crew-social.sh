#!/usr/bin/env bash
# Runs the Crew social migrations against a throwaway local Postgres and executes the SQL tests.
# Never touches the hosted Supabase project.
set -euo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}" LANG="${LANG:-en_US.UTF-8}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
PORT="${PGTEST_PORT:-54329}"
trap 'cat "$WORK/log" 2>/dev/null | tail -5; pg_ctl -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

initdb -D "$WORK/data" -U postgres --auth=trust >/dev/null
pg_ctl -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses=''" -l "$WORK/log" start >/dev/null
for _ in $(seq 1 30); do pg_isready -h "$WORK" -p "$PORT" -U postgres >/dev/null 2>&1 && break; sleep 0.2; done

PSQL=(psql -h "$WORK" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q -X)
"${PSQL[@]}" -c "CREATE DATABASE convoy_test" postgres
"${PSQL[@]}" -f "$ROOT/supabase/tests/stub_base_schema.sql" convoy_test
"${PSQL[@]}" -f "$ROOT/supabase/migrations/20261115000000_crew_social.sql" convoy_test
# Applying twice must be safe.
"${PSQL[@]}" -f "$ROOT/supabase/migrations/20261115000000_crew_social.sql" convoy_test
"${PSQL[@]}" -f "$ROOT/supabase/migrations/20261116000000_ride_member_source.sql" convoy_test
"${PSQL[@]}" -f "$ROOT/supabase/migrations/20261116000000_ride_member_source.sql" convoy_test
"${PSQL[@]}" -f "$ROOT/supabase/tests/crew_social_test.sql" convoy_test
"${PSQL[@]}" -f "$ROOT/supabase/tests/ride_member_source_test.sql" convoy_test
"${PSQL[@]}" -f "$ROOT/supabase/rollback/20261116000000_ride_member_source_down.sql" convoy_test
# The undo script must cleanly back the migration out, and it must be re-appliable afterwards.
"${PSQL[@]}" -f "$ROOT/supabase/rollback/20261115000000_crew_social_down.sql" convoy_test
"${PSQL[@]}" -c "DO \$\$ BEGIN IF to_regclass('public.feed_posts') IS NOT NULL OR to_regclass('public.ride_join_requests') IS NOT NULL THEN RAISE EXCEPTION 'rollback left tables behind'; END IF; END \$\$" convoy_test
"${PSQL[@]}" -f "$ROOT/supabase/migrations/20261115000000_crew_social.sql" convoy_test
"${PSQL[@]}" -f "$ROOT/supabase/migrations/20261116000000_ride_member_source.sql" convoy_test
echo "crew social SQL tests passed"

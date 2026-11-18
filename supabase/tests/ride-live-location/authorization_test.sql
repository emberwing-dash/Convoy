-- authorization_test.sql — Realtime Authorization for private live-ride channels.
-- For: supabase/migrations/20261118010000_ride_live_location_private.sql (must be applied first).
--
-- HOW TO RUN: Supabase Dashboard → SQL Editor → paste this whole file → Run.
--
-- WHAT YOU WILL SEE: an ERROR panel. That is intentional — it is how the test reports and how it
-- guarantees nothing is kept:
--     ERROR: P0001: Live-location authorization test: 22 passed, 0 failed — nothing was saved
--     DETAIL:  PASS … (one line per check)
--     HINT:    This error is deliberate: …
-- "0 failed" = everything is correct. Any "FAIL" line says which check and why.
--
-- WHY IT CANNOT CHANGE PRODUCTION:
--   • The whole test is ONE statement (a DO block). It always ends by raising an error, and Postgres
--     rolls back everything a failed statement did. No BEGIN/COMMIT is used, so the editor's session is
--     never left in an open or failed transaction.
--   • In addition, each test write into realtime.messages runs inside its own sub-block that is undone
--     before the next check (rows also use skip_broadcast = true, and Realtime only delivers committed
--     rows, so nothing is ever sent to any app).
--   • No users, profiles, rides or members are created. Test subjects are read from existing data.
--   • Role / token switches use SET LOCAL and end with the statement.
-- NEEDS: the SQL Editor's default role (postgres).
--
-- WHAT IT TESTS (real Row Level Security on realtime.messages, not only the helper function):
--   member   = an accepted member of ride R          other = a ride the member is NOT on
--   outsider = a profile that is not on ride R       anon  = signed-out client
--   • helper results for member / outsider / no user / other ride / malformed / upper-case / other topics
--   • INSERT (= send broadcast / track presence): allowed for the member on R; blocked (RLS 42501) for the
--     member on another ride, the outsider (broadcast + presence), anon and a malformed topic
--   • SELECT (= receive): a message on R is visible to the member, hidden from the outsider, hidden from
--     the member when authorizing for another ride's topic, hidden from anon
--   • structure: helper not executable by anon; exactly the two policies; no other policies; app switch row

do $test$
declare
  v_ride uuid; v_member uuid; v_outsider uuid; v_other uuid;
  v_id uuid; v_n int; v_state text;
  names text[] := '{}'; oks boolean[] := '{}'; details text[] := '{}';
  report text := ''; failed int := 0;
  topic_r text; topic_o text;
begin
  -- ── Test subjects (read only) ──────────────────────────────────────────────────────────────
  select ride_id into v_ride from public.ride_members where status = 'accepted'
   group by ride_id order by count(*) desc, ride_id limit 1;
  select user_id into v_member from public.ride_members
   where ride_id = v_ride and status = 'accepted' order by user_id limit 1;
  select p.id into v_outsider from public.profiles p
   where not exists (select 1 from public.ride_members m where m.ride_id = v_ride and m.user_id = p.id)
   order by p.id limit 1;
  select x.ride_id into v_other from public.ride_members x
   where x.ride_id <> v_ride
     and not exists (select 1 from public.ride_members y where y.ride_id = x.ride_id and y.user_id = v_member)
   order by x.ride_id limit 1;
  topic_r := 'ride_location_' || v_ride;
  topic_o := 'ride_location_' || v_other;

  names := array_append(names, ('setup: test subjects found (ride, member, outsider, other ride)')::text);
  oks := oks || (v_ride is not null and v_member is not null and v_outsider is not null and v_other is not null);
  details := details || null::text;

  -- ── Helper function, as each caller ────────────────────────────────────────────────────────
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_member, 'role', 'authenticated')::text, true);
  names := array_append(names, ('helper: member → own ride allowed')::text);          oks := oks || public.can_access_ride_topic(topic_r);  details := details || null::text;
  names := array_append(names, ('helper: member → another ride blocked')::text);       oks := oks || not public.can_access_ride_topic(topic_o); details := details || null::text;
  names := array_append(names, ('helper: upper-case topic blocked')::text);            oks := oks || not public.can_access_ride_topic('ride_location_' || upper(v_ride::text)); details := details || null::text;
  names := array_append(names, ('helper: malformed topic → false, no error')::text);   oks := oks || not public.can_access_ride_topic('ride_location_not-a-uuid'); details := details || null::text;
  names := array_append(names, ('helper: other topics (leaderboard, inbox, empty, null) blocked')::text);
  oks := oks || (not public.can_access_ride_topic('leaderboard') and not public.can_access_ride_topic('inbox-' || v_member)
                 and not public.can_access_ride_topic('') and not public.can_access_ride_topic(null));
  details := details || null::text;
  perform set_config('request.jwt.claims', json_build_object('sub', v_outsider, 'role', 'authenticated')::text, true);
  names := array_append(names, ('helper: outsider → ride blocked')::text);             oks := oks || not public.can_access_ride_topic(topic_r);  details := details || null::text;
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  names := array_append(names, ('helper: token without user id → blocked')::text);     oks := oks || not public.can_access_ride_topic(topic_r);  details := details || null::text;
  reset role;

  -- ── Real RLS: member SEND + RECEIVE on own ride; others can't RECEIVE it ──────────────────
  -- One sub-block: the member's message is inserted, read back under each identity, then undone.
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', v_member, 'role', 'authenticated')::text, true);
    perform set_config('realtime.topic', topic_r, true);
    insert into realtime.messages (topic, extension, event, payload, private, skip_broadcast)
    values (topic_r, 'broadcast', 'auth_test', '{"test": true}', true, true)
    returning id into v_id;
    names := array_append(names, ('RLS INSERT: member can send on own ride')::text); oks := oks || true; details := details || null::text;

    select count(*) into v_n from realtime.messages where id = v_id;
    names := array_append(names, ('RLS SELECT: member receives on own ride')::text); oks := oks || (v_n = 1); details := details || (v_n || ' row(s) visible');

    perform set_config('request.jwt.claims', json_build_object('sub', v_outsider, 'role', 'authenticated')::text, true);
    select count(*) into v_n from realtime.messages where id = v_id;
    names := array_append(names, ('RLS SELECT: outsider cannot receive')::text); oks := oks || (v_n = 0); details := details || (v_n || ' row(s) visible');

    perform set_config('request.jwt.claims', json_build_object('sub', v_member, 'role', 'authenticated')::text, true);
    perform set_config('realtime.topic', topic_o, true);
    select count(*) into v_n from realtime.messages where id = v_id;
    names := array_append(names, ('RLS SELECT: member blocked on another ride''s channel')::text); oks := oks || (v_n = 0); details := details || (v_n || ' row(s) visible');

    set local role anon;
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('realtime.topic', topic_r, true);
    select count(*) into v_n from realtime.messages where id = v_id;
    names := array_append(names, ('RLS SELECT: anon cannot receive')::text); oks := oks || (v_n = 0); details := details || (v_n || ' row(s) visible');

    raise exception using errcode = 'P0001', message = 'convoy_probe_undo';
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'convoy_probe_undo' then
        names := array_append(names, ('RLS member probe')::text); oks := oks || false; details := details || sqlerrm;
      end if;
    when others then
      names := array_append(names, ('RLS INSERT: member can send on own ride')::text); oks := oks || false;
      details := details || (sqlstate || ' ' || sqlerrm);
  end;

  -- ── Real RLS: blocked SENDS (must fail with 42501 = row-level security) ───────────────────
  -- member → another ride
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', v_member, 'role', 'authenticated')::text, true);
    perform set_config('realtime.topic', topic_o, true);
    insert into realtime.messages (topic, extension, event, payload, private, skip_broadcast)
    values (topic_o, 'broadcast', 'auth_test', '{"test": true}', true, true);
    raise exception using errcode = 'P0001', message = 'convoy_insert_succeeded';
  exception when others then
    v_state := sqlstate;
    names := array_append(names, ('RLS INSERT: member blocked on another ride')::text);
    oks := oks || (v_state = '42501'); details := details || (v_state || ' ' || sqlerrm);
  end;

  -- outsider → broadcast on ride R
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', v_outsider, 'role', 'authenticated')::text, true);
    perform set_config('realtime.topic', topic_r, true);
    insert into realtime.messages (topic, extension, event, payload, private, skip_broadcast)
    values (topic_r, 'broadcast', 'auth_test', '{"test": true}', true, true);
    raise exception using errcode = 'P0001', message = 'convoy_insert_succeeded';
  exception when others then
    v_state := sqlstate;
    names := array_append(names, ('RLS INSERT: outsider cannot send (broadcast)')::text);
    oks := oks || (v_state = '42501'); details := details || (v_state || ' ' || sqlerrm);
  end;

  -- outsider → presence on ride R
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', v_outsider, 'role', 'authenticated')::text, true);
    perform set_config('realtime.topic', topic_r, true);
    insert into realtime.messages (topic, extension, event, payload, private, skip_broadcast)
    values (topic_r, 'presence', 'presence', '{"test": true}', true, true);
    raise exception using errcode = 'P0001', message = 'convoy_insert_succeeded';
  exception when others then
    v_state := sqlstate;
    names := array_append(names, ('RLS INSERT: outsider cannot track presence')::text);
    oks := oks || (v_state = '42501'); details := details || (v_state || ' ' || sqlerrm);
  end;

  -- anon → broadcast on ride R
  begin
    set local role anon;
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('realtime.topic', topic_r, true);
    insert into realtime.messages (topic, extension, event, payload, private, skip_broadcast)
    values (topic_r, 'broadcast', 'auth_test', '{"test": true}', true, true);
    raise exception using errcode = 'P0001', message = 'convoy_insert_succeeded';
  exception when others then
    v_state := sqlstate;
    names := array_append(names, ('RLS INSERT: anon cannot send')::text);
    oks := oks || (v_state = '42501'); details := details || (v_state || ' ' || sqlerrm);
  end;

  -- member → malformed topic
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', v_member, 'role', 'authenticated')::text, true);
    perform set_config('realtime.topic', 'ride_location_not-a-uuid', true);
    insert into realtime.messages (topic, extension, event, payload, private, skip_broadcast)
    values ('ride_location_not-a-uuid', 'broadcast', 'auth_test', '{"test": true}', true, true);
    raise exception using errcode = 'P0001', message = 'convoy_insert_succeeded';
  exception when others then
    v_state := sqlstate;
    names := array_append(names, ('RLS INSERT: malformed topic blocked')::text);
    oks := oks || (v_state = '42501'); details := details || (v_state || ' ' || sqlerrm);
  end;

  -- ── Structure ───────────────────────────────────────────────────────────────────────────────
  names := array_append(names, ('structure: anon cannot execute the helper')::text);
  oks := oks || not has_function_privilege('anon', 'public.can_access_ride_topic(text)', 'execute');
  details := details || null::text;

  select count(*) into v_n from pg_policies
   where schemaname = 'realtime' and tablename = 'messages'
     and policyname in ('ride members receive live ride messages', 'ride members send live ride messages')
     and roles = '{authenticated}';
  names := array_append(names, ('structure: both live-location policies present (authenticated only)')::text);
  oks := oks || (v_n = 2); details := details || (v_n || ' found');

  select count(*) into v_n from pg_policies
   where schemaname = 'realtime' and tablename = 'messages'
     and policyname not in ('ride members receive live ride messages', 'ride members send live ride messages');
  names := array_append(names, ('structure: no other policies on realtime.messages')::text);
  oks := oks || (v_n = 0); details := details || (v_n || ' other');

  names := array_append(names, ('structure: app switch live_location exists and is OFF')::text);
  oks := oks || exists (select 1 from public.app_config where key = 'live_location' and value ->> 'private' = 'false');
  details := details || (select value::text from public.app_config where key = 'live_location');

  -- ── Report (and roll everything back) ───────────────────────────────────────────────────────
  for i in 1 .. coalesce(array_length(names, 1), 0) loop
    if not oks[i] then failed := failed + 1; end if;
    report := report || format(E'\n%s  %s%s', case when oks[i] then 'PASS' else 'FAIL' end, names[i],
                               coalesce('  [' || details[i] || ']', ''));
  end loop;

  raise exception using
    errcode = 'P0001',
    message = format('Live-location authorization test: %s passed, %s failed — nothing was saved',
                     coalesce(array_length(names, 1), 0) - failed, failed),
    detail  = report,
    hint    = 'This error is deliberate: ending with an error makes Postgres roll back everything the test did.';
end
$test$;

-- Chatbot V2: remote backend switch, beta testers, server-side usage accounting and limits.
-- ADDITIVE ONLY: creates new tables/functions; does not alter or drop anything existing.
-- Rollback of this migration is never required for the V1 chatbot (V1 does not use these objects).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Remote config the app reads (operator switch V1 ↔ V2, no app rebuild needed)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.app_config enable row level security;
drop policy if exists "app_config readable" on public.app_config;
create policy "app_config readable" on public.app_config for select to anon, authenticated using (true);
-- No insert/update/delete policies: only the dashboard / service role can change it.

-- backend: "v1" (current groq-proxy) | "v2" (groq-proxy-v2)
-- rollout: "beta" (only chatbot_beta_testers get v2 when backend = "v2") | "all"
insert into public.app_config (key, value)
values ('chatbot', '{"backend": "v1", "rollout": "beta"}'::jsonb)
on conflict (key) do nothing;

-- Riders who get V2 while rollout = "beta".
create table if not exists public.chatbot_beta_testers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  note text,
  added_at timestamptz not null default now()
);
alter table public.chatbot_beta_testers enable row level security;
drop policy if exists "beta tester reads own row" on public.chatbot_beta_testers;
create policy "beta tester reads own row" on public.chatbot_beta_testers
  for select to authenticated using (user_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Server-side limits & usage (server/service role only — no client policies)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.ai_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.ai_config enable row level security;

-- Adjustable allowances. Generous for normal riders; stops one account from draining the
-- shared provider quota. Edit with: update ai_config set value = jsonb_set(value, '{daily_requests}', '200') where key = 'limits';
insert into public.ai_config (key, value) values ('limits', '{
  "daily_requests": 150,
  "daily_input_tokens": 400000,
  "daily_output_tokens": 120000,
  "per_minute_requests": 10,
  "max_inflight_per_user": 1,
  "max_inflight_global": 12,
  "inflight_stale_seconds": 90
}'::jsonb)
on conflict (key) do nothing;

create table if not exists public.ai_usage_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  requests int not null default 0,
  failed int not null default 0,
  input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  reasoning_tokens bigint not null default 0,
  tool_calls int not null default 0,
  provider_counts jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);
alter table public.ai_usage_daily enable row level security;
drop policy if exists "rider reads own ai usage" on public.ai_usage_daily;
create policy "rider reads own ai usage" on public.ai_usage_daily
  for select to authenticated using (user_id = auth.uid());

create table if not exists public.ai_request_log (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  at timestamptz not null default now(),
  ok boolean,
  provider text,
  error_code text,
  input_tokens int not null default 0,
  output_tokens int not null default 0,
  reasoning_tokens int not null default 0,
  tool_calls int not null default 0,
  latency_ms int
);
create index if not exists ai_request_log_user_at on public.ai_request_log (user_id, at desc);
alter table public.ai_request_log enable row level security;

create table if not exists public.ai_inflight (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now()
);
create index if not exists ai_inflight_user on public.ai_inflight (user_id);
alter table public.ai_inflight enable row level security;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Atomic begin / end (called by groq-proxy-v2 with the service role)
-- ─────────────────────────────────────────────────────────────────────────────
-- Serialised with a transaction-level advisory lock, so concurrent requests (same rider or
-- many riders) cannot both pass a limit check. Day boundaries use India time.
create or replace function public.ai_begin_request(p_user uuid)
returns json language plpgsql volatile security definer set search_path = public as $$
declare
  lim jsonb;
  today date := (now() at time zone 'Asia/Kolkata')::date;
  u public.ai_usage_daily;
  recent int;
  mine int;
  everyone int;
  slot uuid;
begin
  if p_user is null then return json_build_object('ok', false, 'reason', 'unauthenticated'); end if;
  perform pg_advisory_xact_lock(hashtext('convoy_ai_begin'));

  select value into lim from public.ai_config where key = 'limits';
  lim := coalesce(lim, '{}'::jsonb);

  delete from public.ai_inflight
   where started_at < now() - make_interval(secs => coalesce((lim->>'inflight_stale_seconds')::int, 90));

  select * into u from public.ai_usage_daily where user_id = p_user and day = today;
  if found then
    if u.requests >= coalesce((lim->>'daily_requests')::int, 150) then
      return json_build_object('ok', false, 'reason', 'daily_requests');
    end if;
    if u.input_tokens >= coalesce((lim->>'daily_input_tokens')::bigint, 400000)
       or u.output_tokens >= coalesce((lim->>'daily_output_tokens')::bigint, 120000) then
      return json_build_object('ok', false, 'reason', 'daily_tokens');
    end if;
  end if;

  select count(*) into recent from public.ai_request_log
   where user_id = p_user and at > now() - interval '60 seconds';
  if recent >= coalesce((lim->>'per_minute_requests')::int, 10) then
    return json_build_object('ok', false, 'reason', 'per_minute', 'retry_after_s', 20);
  end if;

  select count(*) into mine from public.ai_inflight where user_id = p_user;
  if mine >= coalesce((lim->>'max_inflight_per_user')::int, 1) then
    return json_build_object('ok', false, 'reason', 'duplicate_inflight', 'retry_after_s', 3);
  end if;

  select count(*) into everyone from public.ai_inflight;
  if everyone >= coalesce((lim->>'max_inflight_global')::int, 12) then
    return json_build_object('ok', false, 'reason', 'server_busy', 'retry_after_s', 5);
  end if;

  insert into public.ai_inflight (user_id) values (p_user) returning id into slot;
  insert into public.ai_usage_daily (user_id, day, requests) values (p_user, today, 1)
  on conflict (user_id, day) do update set requests = public.ai_usage_daily.requests + 1, updated_at = now();

  return json_build_object('ok', true, 'slot', slot);
end $$;

create or replace function public.ai_end_request(
  p_slot uuid, p_user uuid, p_ok boolean, p_provider text, p_error_code text,
  p_input int, p_output int, p_reasoning int, p_tool_calls int, p_latency_ms int)
returns void language plpgsql volatile security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  delete from public.ai_inflight where id = p_slot;
  insert into public.ai_request_log (user_id, ok, provider, error_code, input_tokens, output_tokens,
                                     reasoning_tokens, tool_calls, latency_ms)
  values (p_user, p_ok, p_provider, p_error_code, coalesce(p_input, 0), coalesce(p_output, 0),
          coalesce(p_reasoning, 0), coalesce(p_tool_calls, 0), p_latency_ms);
  insert into public.ai_usage_daily (user_id, day) values (p_user, today) on conflict do nothing;
  update public.ai_usage_daily
     set failed = failed + case when p_ok then 0 else 1 end,
         input_tokens = input_tokens + coalesce(p_input, 0),
         output_tokens = output_tokens + coalesce(p_output, 0),
         reasoning_tokens = reasoning_tokens + coalesce(p_reasoning, 0),
         tool_calls = tool_calls + coalesce(p_tool_calls, 0),
         provider_counts = case when p_provider is null then provider_counts
           else jsonb_set(provider_counts, array[p_provider],
                          to_jsonb(coalesce((provider_counts->>p_provider)::int, 0) + 1)) end,
         updated_at = now()
   where user_id = p_user and day = today;
  -- Keep the request log small (7 days).
  delete from public.ai_request_log where at < now() - interval '7 days' and id % 50 = 0;
end $$;

revoke all on function public.ai_begin_request(uuid) from public, anon, authenticated;
revoke all on function public.ai_end_request(uuid, uuid, boolean, text, text, int, int, int, int, int) from public, anon, authenticated;
grant execute on function public.ai_begin_request(uuid) to service_role;
grant execute on function public.ai_end_request(uuid, uuid, boolean, text, text, int, int, int, int, int) to service_role;

-- "Already have an account?" — log back in with your @handle and a 4-digit PIN (MVP).
--
-- The first login to an account sets its PIN; after that the PIN is required, so knowing a public
-- handle is not enough to open someone's account. 5 wrong tries in 15 minutes locks that handle.
-- Only the `handle-login` edge function (service role) can call the check; app users can't read
-- PINs or attempts (RLS on, no policies).

create table if not exists public.account_pins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null,
  updated_at timestamptz not null default now()
);
alter table public.account_pins enable row level security;

create table if not exists public.handle_login_attempts (
  id bigserial primary key,
  username text not null,
  ok boolean not null,
  at timestamptz not null default now()
);
create index if not exists handle_login_attempts_recent on public.handle_login_attempts (username, at desc);
alter table public.handle_login_attempts enable row level security;

create or replace function public.handle_login_check(p_username text, p_pin text)
returns json language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  uname text := public.normalize_username(p_username);
  uid uuid;
  stored text;
  fails int;
begin
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then
    return json_build_object('status', 'bad_pin_format');
  end if;

  select count(*) into fails from public.handle_login_attempts
   where username = uname and not ok and at > now() - interval '15 minutes';
  if fails >= 5 then
    return json_build_object('status', 'locked');
  end if;

  select id into uid from public.profiles where lower(username) = uname;
  if uid is null then
    insert into public.handle_login_attempts (username, ok) values (uname, false);
    return json_build_object('status', 'not_found');
  end if;

  select pin_hash into stored from public.account_pins where user_id = uid;
  if stored is null then
    insert into public.account_pins (user_id, pin_hash) values (uid, crypt(p_pin, gen_salt('bf')));
    insert into public.handle_login_attempts (username, ok) values (uname, true);
    return json_build_object('status', 'ok', 'user_id', uid, 'pin_created', true);
  end if;

  if stored <> crypt(p_pin, stored) then
    insert into public.handle_login_attempts (username, ok) values (uname, false);
    return json_build_object('status', 'wrong_pin', 'tries_left', greatest(0, 4 - fails));
  end if;

  insert into public.handle_login_attempts (username, ok) values (uname, true);
  return json_build_object('status', 'ok', 'user_id', uid, 'pin_created', false);
end $$;

revoke all on function public.handle_login_check(text, text) from public, anon, authenticated;
grant execute on function public.handle_login_check(text, text) to service_role;

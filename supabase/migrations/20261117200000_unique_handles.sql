-- Unique, searchable rider handles + one server-side "claim my profile" step for onboarding.
--
-- Identity: profiles.id (= auth user id) is the permanent account id; everything links to it.
-- Handle:   profiles.username is the public, unique, searchable @handle (lowercase a–z, 0–9, _; 3–20).
-- Name:     profiles.display_name is free text; two riders can share it.
--
-- Nothing existing is rewritten: the format rule is NOT VALID (new/changed handles only).

-- Case-insensitive uniqueness (usernames are already stored lowercase; this guarantees it stays so).
create unique index if not exists profiles_username_lower_key on public.profiles (lower(username));

alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format
  check (username ~ '^[a-z0-9_]{3,20}$') not valid;

-- Same cleaning the app does: lowercase, keep a–z 0–9 _, max 20.
create or replace function public.normalize_username(p text)
returns text language sql immutable set search_path = public as $$
  select left(regexp_replace(lower(coalesce(p, '')), '[^a-z0-9_]', '', 'g'), 20)
$$;

-- Is this handle free for me? (My own current handle counts as free.)
create or replace function public.username_available(p_username text)
returns boolean language sql stable security definer set search_path = public as $$
  select length(public.normalize_username(p_username)) >= 3
     and not exists (
       select 1 from public.profiles
       where lower(username) = public.normalize_username(p_username)
         and id is distinct from auth.uid())
$$;

-- A free handle close to the one asked for: itself if free, else base + digits.
create or replace function public.suggest_username(p_base text)
returns text language plpgsql volatile security definer set search_path = public as $$
declare
  base text := public.normalize_username(p_base);
  cand text;
  i int := 0;
begin
  if length(base) < 3 then base := 'rider'; end if;
  if public.username_available(base) then return base; end if;
  loop
    i := i + 1;
    cand := left(base, case when i <= 10 then 17 else 16 end)
            || (floor(random() * case when i <= 10 then 900 else 9000 end)
                + case when i <= 10 then 100 else 1000 end)::int::text;
    if public.username_available(cand) then return cand; end if;
    if i > 40 then
      return left(base, 12) || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
    end if;
  end loop;
end $$;

-- Onboarding / first sync: create or update MY profile in one step and return the handle I got.
-- New profile: takes the asked handle, or the closest free one. Existing profile: keeps its handle
-- unless a different free one is asked for. Avatar is only replaced when one is sent.
create or replace function public.claim_profile(p_display_name text, p_username text, p_avatar text default null)
returns json language plpgsql volatile security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  want text := public.normalize_username(p_username);
  name text := nullif(btrim(coalesce(p_display_name, '')), '');
  cur public.profiles;
  asked boolean := length(public.normalize_username(p_username)) >= 3;
  final text;
  attempt int := 0;
begin
  if uid is null then raise exception 'unauthenticated' using errcode = '42501'; end if;
  if not asked then want := public.suggest_username(coalesce(name, 'rider')); end if;

  loop
    attempt := attempt + 1;
    begin
      select * into cur from public.profiles where id = uid;
      if found then
        final := case when asked and want <> cur.username and public.username_available(want) then want else cur.username end;
        update public.profiles
           set username = final,
               display_name = coalesce(name, display_name),
               avatar_data = coalesce(p_avatar, avatar_data)
         where id = uid;
      else
        final := case when public.username_available(want) then want else public.suggest_username(want) end;
        insert into public.profiles (id, username, display_name, avatar_data)
        values (uid, final, coalesce(name, 'Rider'), p_avatar);
      end if;
      return json_build_object('id', uid, 'username', final);
    exception when unique_violation then
      -- Someone took that handle a moment ago: pick another and try again.
      if attempt >= 5 then raise; end if;
      -- An existing rider keeps their current handle rather than getting a random one.
      if exists (select 1 from public.profiles where id = uid) then asked := false; end if;
      want := public.suggest_username(want);
    end;
  end loop;
end $$;

revoke all on function public.username_available(text) from public, anon;
revoke all on function public.suggest_username(text) from public, anon;
revoke all on function public.claim_profile(text, text, text) from public, anon;
grant execute on function public.username_available(text) to authenticated;
grant execute on function public.suggest_username(text) to authenticated;
grant execute on function public.claim_profile(text, text, text) to authenticated;

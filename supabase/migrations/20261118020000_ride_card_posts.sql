-- 20261118020000_ride_card_posts.sql
-- Crew feed posts can carry the exact ride card the rider designed in Share Studio.
--
-- Additive only:
--   • feed_posts.card_path (nullable)       — path of the card image in the ride-cards bucket
--   • storage bucket "ride-cards" (public read, 5 MB, PNG/JPEG only)
--   • storage policies: a signed-in rider can add/replace/delete files only in their own folder
--     "<their user id>/…"; nobody else can write there
--   • set_post_card(post, path)  — author only, path must be in the author's own folder
--   • post_cards(ids)            — card paths for posts (the feed already decides which posts you see)
--
-- Rollback:
--   drop function if exists public.post_cards(uuid[]);
--   drop function if exists public.set_post_card(uuid, text);
--   drop policy if exists "Riders upload own ride cards" on storage.objects;
--   drop policy if exists "Riders replace own ride cards" on storage.objects;
--   drop policy if exists "Riders delete own ride cards" on storage.objects;
--   alter table public.feed_posts drop column if exists card_path;
--   (the bucket can stay; empty it in the dashboard before deleting it if wanted)

alter table public.feed_posts add column if not exists card_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ride-cards', 'ride-cards', true, 5242880, array['image/png', 'image/jpeg'])
on conflict (id) do nothing;

drop policy if exists "Riders upload own ride cards" on storage.objects;
create policy "Riders upload own ride cards" on storage.objects for insert to authenticated
  with check (bucket_id = 'ride-cards' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "Riders replace own ride cards" on storage.objects;
create policy "Riders replace own ride cards" on storage.objects for update to authenticated
  using (bucket_id = 'ride-cards' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "Riders delete own ride cards" on storage.objects;
create policy "Riders delete own ride cards" on storage.objects for delete to authenticated
  using (bucket_id = 'ride-cards' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Attach a card image to one of your own posts.
create or replace function public.set_post_card(p_post_id uuid, p_path text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'unauthenticated'; end if;
  if p_path is null or split_part(p_path, '/', 1) <> v_uid::text or p_path like '%..%' then
    raise exception 'card must be in your own folder';
  end if;
  update public.feed_posts set card_path = p_path where id = p_post_id and author_id = v_uid;
  if not found then raise exception 'post not found'; end if;
end $$;

revoke all on function public.set_post_card(uuid, text) from public, anon;
grant execute on function public.set_post_card(uuid, text) to authenticated;

-- Card paths for a page of feed posts.
create or replace function public.post_cards(p_ids uuid[])
returns table (post_id uuid, card_path text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.card_path from public.feed_posts p
  where p.id = any(p_ids) and p.card_path is not null
  limit 200
$$;

revoke all on function public.post_cards(uuid[]) from public, anon;
grant execute on function public.post_cards(uuid[]) to authenticated;

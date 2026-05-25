-- Clóset (Add to Closet): tabla + bucket público con carpetas por usuario (como vehicle-media).

create table if not exists public.closet_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  brand text,
  category text not null,
  image_url text not null,
  original_crop_url text,
  source_outfit_url text,
  bounding_box jsonb,
  is_draft boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists closet_items_user_created_idx
  on public.closet_items (user_id, created_at desc);

alter table public.closet_items enable row level security;

drop policy if exists "Users manage their own closet_items" on public.closet_items;
create policy "Users manage their own closet_items"
  on public.closet_items
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Bucket: lectura pública para URLs directas; escritura solo carpeta = user id
insert into storage.buckets (id, name, public)
values ('closet-images', 'closet-images', true)
on conflict (id) do update set public = true;

drop policy if exists storage_closet_images_insert on storage.objects;
create policy storage_closet_images_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'closet-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists storage_closet_images_select on storage.objects;
create policy storage_closet_images_select
  on storage.objects
  for select
  to public
  using (bucket_id = 'closet-images');

drop policy if exists storage_closet_images_update on storage.objects;
create policy storage_closet_images_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'closet-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'closet-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists storage_closet_images_delete on storage.objects;
create policy storage_closet_images_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'closet-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

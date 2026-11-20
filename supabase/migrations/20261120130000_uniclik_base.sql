-- Base del proyecto propio de Uniclick («uniclik», jfgppqpmojewdthstjxh). Ya aplicada.
-- El catálogo se copió después desde el proyecto de CarHub (148 filas, sin dueño).
create table if not exists public.upsoled_products (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  brand text,
  sku text,
  description text,
  price numeric(10,2) not null default 0,
  compare_at_price numeric(10,2),
  currency text not null default 'USD',
  image text,
  images text[] not null default '{}',
  main_image_url text,
  category text,
  tags text[] not null default '{}',
  condition text not null default 'new',
  collection text,
  sizes text[] not null default '{}',
  in_stock boolean not null default true,
  quantity integer,
  user_id uuid references auth.users(id) on delete set null,
  organization_id uuid,
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  shopify_id bigint,
  shopify_handle text,
  product_type text,
  shopify_tags_raw text,
  source text not null default 'sneakpeekmiami'
);
create unique index if not exists upsoled_products_shopify_id_uidx on public.upsoled_products (shopify_id) where shopify_id is not null;
create index if not exists upsoled_products_product_type_idx on public.upsoled_products (product_type);
create index if not exists upsoled_products_source_idx on public.upsoled_products (source);
create index if not exists upsoled_products_category_idx on public.upsoled_products (category);
create index if not exists upsoled_products_brand_idx on public.upsoled_products (brand);
create index if not exists upsoled_products_in_stock_idx on public.upsoled_products (in_stock);
create index if not exists upsoled_products_user_id_idx on public.upsoled_products (user_id);
create index if not exists upsoled_products_organization_idx on public.upsoled_products (organization_id);
create index if not exists upsoled_products_created_at_idx on public.upsoled_products (created_at desc);

create or replace function public.upsoled_products_set_updated_at() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
drop trigger if exists upsoled_products_set_updated_at_trg on public.upsoled_products;
create trigger upsoled_products_set_updated_at_trg before update on public.upsoled_products
  for each row execute function public.upsoled_products_set_updated_at();

alter table public.upsoled_products enable row level security;
create policy upsoled_products_public_read on public.upsoled_products for select to public using (true);
create policy upsoled_products_owner_insert on public.upsoled_products for insert to authenticated with check ((select auth.uid()) = user_id);
create policy upsoled_products_owner_update on public.upsoled_products for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy upsoled_products_owner_delete on public.upsoled_products for delete to authenticated using ((select auth.uid()) = user_id);
alter publication supabase_realtime add table public.upsoled_products;

create table if not exists public.user_apns_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_token text not null,
  updated_at timestamptz not null default now(),
  unique (user_id, device_token)
);
create index if not exists user_apns_devices_user_id_idx on public.user_apns_devices (user_id);
alter table public.user_apns_devices enable row level security;
create policy user_apns_devices_select_own on public.user_apns_devices for select to authenticated using ((select auth.uid()) = user_id);
create policy user_apns_devices_insert_own on public.user_apns_devices for insert to authenticated with check ((select auth.uid()) = user_id);
create policy user_apns_devices_update_own on public.user_apns_devices for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy user_apns_devices_delete_own on public.user_apns_devices for delete to authenticated using ((select auth.uid()) = user_id);

create or replace function public.get_my_company_id() returns uuid
language sql stable set search_path to 'public' as $$ select null::uuid $$;

insert into storage.buckets (id, name, public) values ('product-media', 'product-media', true) on conflict (id) do nothing;
create policy storage_product_media_select on storage.objects for select to public using (bucket_id = 'product-media');
create policy storage_product_media_insert on storage.objects for insert to authenticated with check (bucket_id = 'product-media' and (storage.foldername(name))[1] = (auth.uid())::text);
create policy storage_product_media_update on storage.objects for update to authenticated using (bucket_id = 'product-media' and (storage.foldername(name))[1] = (auth.uid())::text) with check (bucket_id = 'product-media' and (storage.foldername(name))[1] = (auth.uid())::text);

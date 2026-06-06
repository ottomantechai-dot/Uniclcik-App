-- Bucket público `product-media` para las fotos de productos subidas desde la
-- app iOS Upsoled (formulario "Nuevo producto"). La web sneakpeekmiami lee la
-- URL pública directamente desde la columna image/main_image_url/images.
--
-- Convención de ruta: `{user_id}/{uuid}.jpg` → la primera carpeta es el dueño,
-- igual que en `vehicle-media`, para que la policy de INSERT valide propiedad.
--
-- Idempotente.

insert into storage.buckets (id, name, public)
values ('product-media', 'product-media', true)
on conflict (id) do update set public = true;

-- Lectura pública (cualquiera puede ver las fotos del catálogo).
drop policy if exists storage_product_media_select on storage.objects;
create policy storage_product_media_select
  on storage.objects
  for select
  to public
  using (
    bucket_id = 'product-media'
  );

-- Subida: solo usuarios autenticados, y solo dentro de su propia carpeta.
drop policy if exists storage_product_media_insert on storage.objects;
create policy storage_product_media_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'product-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Actualización (upsert de la misma ruta): mismo dueño.
drop policy if exists storage_product_media_update on storage.objects;
create policy storage_product_media_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'product-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'product-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

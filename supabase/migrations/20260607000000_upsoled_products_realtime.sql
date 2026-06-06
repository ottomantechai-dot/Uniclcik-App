-- Habilita Supabase Realtime para `upsoled_products`.
--
-- Objetivo: que la web (sneakpeekmiami, Next.js) reciba en vivo los
-- INSERT / UPDATE / DELETE que hace la app iOS "Upsoled", sin recargar.
-- El hook cliente `useRealtimeCatalog` se suscribe a esta tabla.
--
-- Idempotente: se puede aplicar varias veces sin error.

-- 1) REPLICA IDENTITY FULL: asegura que los eventos DELETE/UPDATE incluyan
--    la fila completa en el payload de Realtime (no solo la PK).
alter table public.upsoled_products replica identity full;

-- 2) Añade la tabla a la publicación de Realtime si aún no está.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'upsoled_products'
  ) then
    alter publication supabase_realtime add table public.upsoled_products;
  end if;
end $$;

-- NOTA sobre seguridad: Realtime respeta las políticas RLS de SELECT. La web
-- usa la clave anon, así que debe existir una policy que permita SELECT a
-- `anon` sobre public.upsoled_products (ya existe, porque la web lee el
-- catálogo). Si en el futuro se restringe el SELECT, los eventos Realtime
-- dejarán de llegar al cliente anon.

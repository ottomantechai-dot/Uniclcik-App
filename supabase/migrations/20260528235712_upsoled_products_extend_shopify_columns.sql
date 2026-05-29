-- Columnas explícitas para no perder datos del catálogo Sneak Peek / Shopify
-- (antes sólo vivían dentro de metadata jsonb).

alter table public.upsoled_products
    add column if not exists shopify_id bigint,
    add column if not exists shopify_handle text,
    add column if not exists product_type text,
    add column if not exists shopify_tags_raw text,
    add column if not exists source text not null default 'sneakpeekmiami';

comment on column public.upsoled_products.shopify_id        is 'ID numérico del producto en Shopify.';
comment on column public.upsoled_products.shopify_handle      is 'Handle Shopify (suele coincidir con slug).';
comment on column public.upsoled_products.product_type      is 'Tipo Shopify: Hoodie, Shoes, T-Shirt, etc.';
comment on column public.upsoled_products.shopify_tags_raw    is 'Tags Shopify en texto crudo (CSV).';
comment on column public.upsoled_products.source              is 'Origen del catálogo: sneakpeekmiami, app, etc.';

create unique index if not exists upsoled_products_shopify_id_uidx
    on public.upsoled_products (shopify_id)
    where shopify_id is not null;

create index if not exists upsoled_products_product_type_idx
    on public.upsoled_products (product_type);

create index if not exists upsoled_products_source_idx
    on public.upsoled_products (source);

-- Marca todo el catálogo Sneak Peek como inventario visible en «Your stock».
-- La app iOS filtra por `app_listing_section = 'user_stock'` en Tu stock;
-- la pestaña Marketplace/Sold puede seguir leyendo el catálogo completo.

alter table public.upsoled_products
    add column if not exists app_listing_section text not null default 'user_stock';

comment on column public.upsoled_products.app_listing_section is
    'user_stock = Tu stock (app); marketplace = solo pestaña Marketplace/Sold.';

create index if not exists upsoled_products_app_listing_section_idx
    on public.upsoled_products (app_listing_section);

-- Mueve el catálogo actual (Sold/Marketplace) al inventario de usuario.
update public.upsoled_products
set app_listing_section = 'user_stock'
where coalesce(app_listing_section, 'marketplace') <> 'user_stock';

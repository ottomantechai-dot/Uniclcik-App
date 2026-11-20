# Supabase de Uniclick

Desde el 20 de noviembre de 2026 Uniclick tiene su propio proyecto de Supabase, separado del de CarHub.

| | |
|---|---|
| Nombre | `uniclik` |
| Identificador | `jfgppqpmojewdthstjxh` |
| Región | us-east-1 |
| Organización | carhub |
| Dirección | https://jfgppqpmojewdthstjxh.supabase.co |

## Qué tiene

- `upsoled_products`: el catálogo (148 productos con sus precios de mercado), con lectura pública y escritura solo del dueño de cada fila.
- `user_apns_devices`: el token de avisos del iPhone de cada usuario.
- `get_my_company_id()`: devuelve vacío; en Uniclick no hay empresas.
- Carpeta de archivos `product-media` para las fotos que suben los usuarios.
- Función `marketplace-gateway`. Necesita sus claves en Edge Functions → Secrets: `KICKSDB_API_KEY`, `EBAY_CLIENT_ID` y `EBAY_CLIENT_SECRET`.

## Qué no se trajo

- Las cuentas de usuario: el proyecto arranca sin usuarios y cada persona se registra de nuevo.
- Las tablas del concesionario (vehículos, leads, chat de equipo…). Siguen solo en el proyecto de CarHub (`fwdfhbgcurimqufbwkux`), que no se ha tocado.

Las migraciones antiguas de esta carpeta son del proyecto compartido con CarHub; la base del proyecto nuevo es `migrations/20261120130000_uniclik_base.sql`.

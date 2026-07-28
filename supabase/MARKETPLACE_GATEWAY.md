# Gateway de marketplaces

La app iOS consulta `marketplace-gateway`, una Edge Function autenticada. Las
claves de KicksDB y eBay viven en Supabase y no se incluyen en `Info.plist`,
`xcconfig` ni en el binario de la App Store.

## Fuentes activadas

- StockX y GOAT: catálogo, producto, precios y tallas mediante KicksDB.
- Flight Club: precios por talla mediante el Unified API de KicksDB (requiere
  que el plan contratado incluya ese endpoint).
- eBay: listados nuevos con Authenticity Guarantee mediante Browse API y OAuth
  `client_credentials`.

Estas son conexiones de **lectura de mercado**. Publicar anuncios, sincronizar
inventario o gestionar pedidos necesita OAuth de vendedor y aprobación
específica de cada marketplace. No se debe pedir la contraseña de GOAT/Alias
dentro de Uniclick.

## Despliegue

1. Instala la CLI de Supabase e inicia sesión.
2. Crea `supabase/.env.marketplace.local` (está ignorado por git):

   ```dotenv
   KICKSDB_API_KEY=...
   EBAY_CLIENT_ID=...
   EBAY_CLIENT_SECRET=...
   ```

3. Vincula el proyecto y sube los secrets:

   ```bash
   supabase link --project-ref fwdfhbgcurimqufbwkux
   supabase secrets set --env-file supabase/.env.marketplace.local
   ```

4. Despliega la función con verificación JWT:

   ```bash
   supabase functions deploy marketplace-gateway
   ```

No uses `--no-verify-jwt` para esta función.

## Prueba rápida

Con un JWT válido de usuario:

```bash
curl \
  -H "Authorization: Bearer $UNICLICK_USER_JWT" \
  -H "Content-Type: application/json" \
  -d '{"operation":"status"}' \
  "https://fwdfhbgcurimqufbwkux.supabase.co/functions/v1/marketplace-gateway"
```

La respuesta `data` marca qué proveedores tienen sus secrets configurados.

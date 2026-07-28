# Guía de pruebas — Upsoled comparador (resultado esperado)

**Leyenda:** ✅ debería pasar · ⚠️ pasa con matiz/a vigilar · ❌ fallará (esperado) · 🔑 requiere acción tuya

> Requisitos previos: iOS compilado en Xcode con `KICKSDB_API_KEY` + `EBAY_CLIENT_*` puestas (ya están). Web con `KICKSDB_API_KEY` en `.env.local` (🔑 pendiente).

---

## 1. Conexiones / fuentes
- **StockX conectado y mostrando datos** → ✅
- **GOAT conectado y mostrando datos** → ✅
- **Flight Club / Alias** → ❌ **No conectado** — requiere el Starter de pago de KicksDB. No aparecerá. (Esperado.)
- **eBay conectado y mostrando datos** → ✅ (verificado en vivo: 212 resultados Authenticity Guaranteed)

## 2. Landing page (web)
- **Se muestran precios claramente** → ✅ 🔑 (necesita la key web; sin ella la sección sale sin datos)
- **Ver Valor de compra** → ✅
- **Ver Bid** → ❌ No existe en las fuentes; no se muestra. (Esperado.)
- **Ver Valor de venta (Sell)** → ❌ Aún no en la landing (dato de ventas es Premium). (Esperado.)
- **Info fácil de entender** → ✅ (a validar visualmente)

## 3. Comparación de precios
- **Mismo producto, valores por plataforma** → ✅ StockX + GOAT + eBay
- **Los precios coinciden con la fuente original** → ⚠️ **Ojo:** KicksDB en plan free **cachea ~24h**, así que StockX/GOAT pueden ir ligeramente desfasados respecto al sitio en vivo. **eBay sí es en vivo.** Para tiempo real haría falta el plan Pro.
- **Se actualizan al cambiar talla/modelo** → ✅ (recarga por talla, eBay incluido)

## 4. eBay / Authenticity Guaranteed
- **Solo productos con Authenticity Guaranteed** → ✅ (filtro `qualifiedPrograms:{AUTHENTICITY_GUARANTEE}` verificado)
- **No aparecen listings normales sin autenticación** → ✅ (el filtro lo garantiza a nivel API)
- **Filtro funciona en distintas tallas y modelos** → ⚠️ La talla se **parsea del título** del listado (eBay no la da estructurada), así que en algún listado raro puede no acertar la talla. El filtro de Authenticity sí es 100% fiable.

## 5. Casos de prueba
- **Sneaker popular** (ej. `DZ5485-100`, "Jordan 4 Black Cat") → ✅ debería traer todo
- **Sneaker con poca disponibilidad** → ⚠️ puede no encontrarse o traer pocas tallas → muestra estado vacío claro
- **Probar varias tallas** → ✅
- **Comparar StockX, GOAT, Flight Club/Alias, eBay** → 🟡 **3 de 4** (Flight Club ausente hasta el plan de pago)
- **Plataforma sin datos** → ✅ no rompe: muestra "—" en esa plataforma y sigue con las demás

## 6. Errores / UX
- **Si no hay precio, mensaje claro** → ✅ ("—", "Sin resultados para ese modelo…")
- **Si falla una conexión, no rompe** → ✅ cada plataforma falla de forma independiente (la otra sigue)
- **Carga rápida en landing** → ⚠️ la sección comparadora hace una consulta a KicksDB (~1-2 s, con spinner); el resto de la home ya está optimizado (rápido)
- **Diseño usable en móvil y desktop** → ✅ web responsive (Tailwind); app iOS nativa

---

## Resumen de lo que SÍ o NO pasará el checklist
**Pasará:** StockX, GOAT, eBay (con AG), comparación por talla, actualización al cambiar talla, manejo de errores/sin datos, diseño responsive.

**Fallará (esperado, no es bug):**
- Flight Club/Alias (requiere plan de pago)
- Bid (no existe en las fuentes)
- Sell en la landing (dato Premium)
- "4 plataformas" → de momento 3

**A vigilar:** desfase de ~24h en precios StockX/GOAT (cache del plan free) y el parseo de talla en eBay.

## Para que la web pase el punto 2
Añade en `~/Downloads/sneakpeekmiami/.env.local`:
```
KICKSDB_API_KEY=KICKS-REEMPLAZAR-CON-CLAVE-NUEVA
```
y `npm run dev`.

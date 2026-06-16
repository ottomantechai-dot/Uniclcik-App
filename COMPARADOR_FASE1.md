# Comparador de mercado — Fase 1 (iOS)

**Fecha:** 30 may 2026 · **Alcance entregado:** comparador de precios **por talla** entre **StockX y GOAT** (vía KicksDB), dentro de Upsoled.

## Qué se construyó

**Motor** (`KicksDBClient.fetchComparison`, en `Views/ClosetViews.swift`):
- Consulta StockX y GOAT **en paralelo**, reutilizando el `search`/`detail` y la heurística de nombres (`nameQueryVariants`) que ya existían.
- Pide el detalle con variantes y arma un mapa **talla → lowest ask (precio de compra real)** por plataforma.
- Normaliza tallas US ("US M 10" / "10" / "10.5") para poder cruzar plataformas (`MarketComparison.normalizeSize`).
- Modelos nuevos: `MarketComparison`, `MarketPlatformQuote`, `MarketSizeRow`. Si una plataforma falla, la otra sigue.

**Vista** (`MarketComparatorView`):
- Buscador por **SKU o nombre**.
- **Mejor compra global** destacada (plataforma + talla + precio).
- **Selector de talla** (chips). Para la talla elegida, muestra cada plataforma con su **precio de compra**, resalta la **más barata**, y calcula el **spread entre plataformas** ($ y %). Es la señal de arbitraje del MVP.
- Muestra la media del modelo por plataforma como referencia.

**Entrada:** botón (icono de barras) en la barra superior de la pestaña **Marketplace** → abre el comparador como sheet.

## Importante (honestidad del dato)
KicksDB Standard (plan free) expone **lowest ask** y `avg/min/max`, pero **NO** "bid" (mejor oferta) ni "última venta" reales — solo asks y conteo de ventas. Por eso:
- **Buy (compra)** y **spread** = datos reales, funcionando ya.
- **Bid** y **Sell** = quedan como "no disponible" en la UI, con la estructura lista para enchufar **eBay** (sold listings) o un **plan de pago / sales endpoint** cuando estén.

## Cómo probar
1. Abre Upsoled → pestaña **Marketplace** → icono de barras (arriba izq.).
2. Escribe un SKU exacto (ej. `DZ5485-100`) o un nombre (ej. `Jordan 4 Black Cat`) → **Comparar**.
3. Cambia de talla y observa el precio de compra por plataforma + spread.
> Requiere `KICKSDB_API_KEY` en `DeveloperSettings.local.xcconfig` (ya la tienes).

## Notas de implementación
- Todo el código nuevo va dentro de archivos **ya registrados** en el `.xcodeproj` (`ClosetViews.swift`, `UpsoledProductsView.swift`) para que compile sin tocar `project.pbxproj`. Si en el futuro quieres separarlo en `MarketComparator.swift`, habrá que añadir ese archivo al target en Xcode.
- No se modificó el motor de precios existente (`fetchAggregated`) ni la tarjeta de precios del Closet: el comparador es aditivo.

---

## Roadmap del resto de prioridades (para seguir por fases)

**Fase 2 — Normalización y duplicados (Prioridad 1): ✅ HECHA.**
- `MarketComparison.normalizeSKU` unifica SKUs entre plataformas (GOAT con espacios "854866 019" ↔ StockX con guiones "854866-019").
- **Alineación/dedupe:** tras el primer match, el motor elige un **SKU canónico** y **reconsulta** la plataforma que no coincida por ese SKU, garantizando que StockX y GOAT comparen el MISMO producto. Si la reconsulta no encuentra nada, conserva el match original.
- **Aviso de mismatch:** si las plataformas devuelven SKUs distintos, banner naranja con el SKU de cada una. Si coinciden, sello verde "Mismo producto · SKU X".
- **Disponibilidad por talla:** "Disponible en N de M plataformas" en la tarjeta de cada talla.
- **Frescura:** "actualizado ahora / hace X" con la marca de tiempo de la consulta.

**Fase 3 — eBay (Prioridad 4):** cuando Production esté habilitado, `EbayPriceService` con **Browse API** filtrando: solo **Authenticity Guaranteed**, **sin subastas** (`buyingOptions=FIXED_PRICE`), **sin usados** (`conditionIds=1000`), y descartando listings incompletos/duplicados. Enchufa al comparador como 3ª columna y rellena "Sell/Buy" de eBay.

**Fase 4 — Métricas y ROI (Prioridad 6):** margen potencial de reventa, ROI estimado, nº de ofertas por plataforma, timestamp de actualización.

**Fase 5 — Landing web (Prioridad 2):** llevar best buy/sell/bid + diferencias a la web Sneak Peek Miami (requiere persistir los precios agregados en Supabase o un endpoint que el front consuma).

**Fase 6 — Alertas (Prioridad 5):** push (APNs, ya integrado) cuando un producto baje de X, aparezca una talla, o haya arbitraje entre plataformas.

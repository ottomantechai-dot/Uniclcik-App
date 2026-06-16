# Estado del MVP — Upsoled comparador de precios

**Fecha:** 16 jun 2026
**Leyenda:** ✅ Listo · 🟡 Parcial · ⏳ Código listo, datos requieren plan de pago · ❌ No / no factible

> Nota: todo el iOS está escrito y revisado pero **pendiente de compilar en Xcode** (no tengo Xcode en este entorno). eBay sí está **verificado en vivo** (212 resultados reales).

---

## Prioridad 1 — Integraciones y datos
| Item | Estado |
|---|---|
| Conectar StockX | ✅ Listo (KicksDB) |
| Conectar GOAT | ✅ Listo (KicksDB) |
| Conectar eBay | ✅ Listo y **verificado en vivo** |
| Conectar Flight Club / Alias | ❌ Requiere **Starter de pago** de KicksDB |
| Calidad y frecuencia de actualización | 🟡 Muestro frescura de la consulta; falta la cadencia de refresco de la fuente |
| Disponibilidad por talla | ✅ Listo |
| Identificación de duplicados entre plataformas | ✅ Listo (alineación por SKU canónico + re-consulta) |
| Normalización de nombres y SKUs | ✅ Listo |

## Prioridad 2 — Landing Page (web)
| Item | Estado |
|---|---|
| Mejor precio de compra | ✅ Listo (requiere KicksDB key en `.env.local` web) |
| Mejor precio de venta (Sell) | ❌ Aún no en la landing (el dato de ventas es Premium) |
| Mejor bid | ❌ No existe fuente |
| Diferencia % entre plataformas | ✅ Listo |
| Ahorro potencial | ✅ Listo |

## Prioridad 3 — Comparador de mercado
| Item | Estado |
|---|---|
| StockX vs GOAT vs Flight Club vs eBay | 🟡 StockX + GOAT + **eBay** ✅ · Flight Club ❌ (pago) |
| Precio más bajo resaltado | ✅ Listo |
| Precio más alto resaltado | 🟡 Se calcula, no se resalta visualmente fuerte |
| Spread entre compra y venta | 🟡 Hago spread **entre plataformas** (compra vs compra); compra-venta necesita Sell real |
| Historial de precios | ⏳ Código + gráfica listos; datos con plan Premium |

## Prioridad 4 — eBay
| Item | Estado |
|---|---|
| Solo Authenticity Guaranteed | ✅ Listo y verificado |
| Excluir subastas activas | ✅ Listo (solo precio fijo) |
| Excluir productos usados | ✅ Listo (solo nuevos) |
| Filtrar listings duplicados / incompletos | 🟡 Descarto sin precio; falta dedup entre listados eBay |

## Prioridad 5 — Alertas
| Item | Estado |
|---|---|
| Alerta cuando baja de cierto precio | ✅ Listo |
| Alerta cuando aparece una talla | ✅ Listo |
| Alerta de arbitraje entre plataformas | ✅ Listo |
| Funcionamiento en segundo plano fiable | 🟡 Chequea al abrir la app; background fiable necesita poller en servidor |

## Prioridad 6 — Métricas
| Item | Estado |
|---|---|
| Última actualización de datos | ✅ Listo |
| Número de ofertas por plataforma | ✅ Listo |
| Margen potencial de reventa | ✅ Listo |
| ROI estimado para revendedores | ✅ Listo |

---

## Objetivo MVP
| # | Objetivo | Estado |
|---|---|---|
| 1 | Conectar las 4 plataformas principales | 🟡 **3 de 4** (falta Flight Club, de pago) |
| 2 | Mostrar Buy, Bid y Sell | 🟡 Buy ✅ · Sell ⏳ (código, plan) · Bid ❌ (no existe) |
| 3 | Comparar precios por talla | ✅ Listo |
| 4 | Validar eBay Authenticity Guaranteed | ✅ Listo y verificado |
| 5 | Landing clara para captar usuarios | ✅ Listo (requiere key web) |

---

## Lo único que falta y depende de TI (no de mí)
1. **Compilar en Xcode** (Cmd+Shift+K → Run) → verificación final de todo el iOS.
2. **Activar el Starter de KicksDB** → enciende **Flight Club** + **Sell/historial** (mismo plan).
3. **Poner `KICKSDB_API_KEY` en `~/Downloads/sneakpeekmiami/.env.local`** → enciende la landing web.

## No factible con las fuentes actuales
- **Bid (mejor oferta)**: ni KicksDB ni eBay lo exponen limpio. Necesitaría otra fuente de datos.

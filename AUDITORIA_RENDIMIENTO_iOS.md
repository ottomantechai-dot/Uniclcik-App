# Auditoría de rendimiento — Upsoled iOS (CarDashboardApp)

**Fecha:** 30 may 2026 · **Alcance:** app SwiftUI en `~/Downloads/Upsoled/CarDashboardApp` (~40k líneas, 135 archivos Swift).
**Objetivo:** máxima fluidez (scroll, animaciones, batería) **sin cambiar ninguna funcionalidad ni el aspecto visual**.

> Estado: **APLICADO** (30 may 2026). Se aplicaron C1, C2, C3, M1, M2, M3, M4 y verificaciones B4. Cambios sin alterar funcionalidad ni diseño visible. Pendiente compilar en Xcode (el entorno de auditoría no compila Swift). Detalle de lo aplicado al final del documento.

---

## Resumen ejecutivo

La app ya tiene buena infraestructura (caché L1 en memoria `ImageCacheService`, caché L2 en disco en `CarUIImageLoader`, carga remota async con deduplicación en `StockImageLoader`). El problema es que **el grid principal del clóset y varias filas/celdas NO la usan correctamente**: decodifican imágenes a resolución completa, de forma síncrona, en el hilo principal, durante el scroll. Eso es la causa #1 de tirones.

El segundo foco es **trabajo continuo que nunca se pausa**: un vídeo de fondo que sigue reproduciéndose y un fondo con gradiente animado a 30 fps, además de timers de refresco que no paran al ir a segundo plano. Eso castiga batería y CPU/GPU constantemente.

Hay 3 arreglos que se llevan ~80% de la mejora percibida:

1. **Downsample + carga asíncrona de las miniaturas locales del clóset** (grid de inventario).
2. **Pausar el vídeo de fondo y el fondo animado** cuando no están activos.
3. **Dejar de decodificar imágenes solo para comprobar si existen** (usar `FileManager.fileExists`).

Ninguno cambia comportamiento ni diseño visible.

---

## CRÍTICO (causa directa de tirones — máximo impacto en fluidez)

### C1 · Miniaturas locales del clóset: sin downsample y decode síncrono en main thread
- **Dónde:** `Services/ImageCacheService.swift` + `Views/StockSearchScannerViews.swift:20-27` (`StockImageLoader.cachedLocalImage`) + `Models/ImageStore.swift:50-53` (`ImageStore.load`). Consumido por `ClosetDiskThumbnail` (`Views/ClosetViews.swift:43-58`), que pinta cada celda del grid de inventario.
- **Qué pasa:** en cache-miss (primer scroll, o tras evicción), cada celda llama `ImageStore.load` → `UIImage(contentsOfFile:)` que **decodifica la foto a resolución completa en el hilo principal**. Además guarda en memoria la imagen **a tamaño completo** (la ruta remota sí hace downsample a 176 px; la local no). Fotos de 3000×3000 ≈ 36 MB cada una llenan el límite de 150 MB en pocas celdas → evicciones constantes → vuelta a decodificar → más tirones.
- **Impacto:** tirones notorios al hacer scroll por el clóset, sobre todo la primera pasada y en inventarios grandes.
- **Fix (sin tocar funciones):**
  - En `cachedLocalImage`, hacer downsample del bitmap local a ~max 400 px (con `CGImageSourceCreateThumbnailAtIndex`, igual que ya hace `CarUIImageLoader.downsample`) **antes** de guardarlo en caché.
  - Convertir `ClosetDiskThumbnail` en carga **asíncrona**: pintar placeholder y cargar la miniatura en `.task(priority: .utility)` fuera del hilo principal; al terminar, asignar a un `@State`. La imagen se ve igual; solo deja de bloquear el scroll.

### C2 · `ImageStore.load(...)` síncrono dentro de `body` en muchas filas/celdas
- **Dónde:** 37 usos. Casos en caliente de scroll: `Views/MainTabView.swift:543` y `:648` (filas de *Vendido*/Archivo), `Views/DashboardView.swift:662-664` (miniatura último vendido), `Views/ClosetDetailAndLooksViews.swift:1534-1544` (chips de portada), `Views/ClosetViews.swift:2794` (`thumb(for:)`).
- **Qué pasa:** mismo problema que C1 pero saltándose incluso la caché en memoria: decodifican a resolución completa en cada render.
- **Impacto:** micro-stutters al abrir/scrollear Vendido, Inicio y detalle de prenda.
- **Fix:** enrutar todas esas cargas por `ClosetDiskThumbnail`/`cachedLocalImage` (ya cacheado + downsampleado tras C1), o por un pequeño helper async. Cero cambio visual.

### C3 · Vídeo de fondo de Inicio que nunca se pausa
- **Dónde:** `Design/DashboardHomeVideoBackdrop.swift:29-43`. `AVQueuePlayer` + `AVPlayerLooper`, `updateUIView` vacío; solo para en `dismantleUIView` (cuando SwiftUI destruye la vista, lo cual **no** ocurre al cambiar de pestaña).
- **Qué pasa:** el vídeo sigue decodificando 24-30 fps aunque el usuario esté en otra pestaña o la app pase a segundo plano.
- **Impacto:** consumo de GPU/CPU y batería constante, calentamiento.
- **Fix:** pausar/reanudar según `@Environment(\.scenePhase)` (pausar si `!= .active`) y, opcionalmente, cuando la pestaña Inicio no está seleccionada. Métodos `play()`/`pause()` en la `UIView` y llamada desde `updateUIView`. No cambia el aspecto cuando está visible.

---

## MEDIO (mejora fluidez/batería; bajo riesgo)

### M1 · Fondo `RevolutBackgroundView` animado a 30 fps sin pausa
- **Dónde:** `Design/RevolutBackgroundView.swift:18` (`TimelineView(.animation(minimumInterval: 1/30, paused: false))`). Usado en `SearchView`, `LeadsListView`, `ChatView`.
- **Qué pasa:** recalcula 16 puntos SIMD + trig + asigna nuevos `Color` cada frame, también con la app inactiva o la vista tapada por un sheet.
- **Fix:** `paused: scenePhase != .active`. Visualmente idéntico cuando se usa.

### M2 · Refresco periódico de comunidad no se pausa en segundo plano
- **Dónde:** `ViewModels/DashboardCommunityViewModel.swift:19-26` (`Timer.publish(every: 15…)`); arrancado en `MainTabView.onAppear`.
- **Qué pasa:** golpea Supabase cada 15 s aunque la app esté en background.
- **Fix:** parar en `scenePhase == .background` y reanudar en `.active`. Mantiene la funcionalidad de refresco en vivo.

### M3 · `DateFormatter` creado en cada render de mensaje
- **Dónde:** `Views/ChatConversationView.swift:~1423` (`currentTimeString()`).
- **Qué pasa:** `DateFormatter()` es caro de instanciar; aquí se crea por mensaje.
- **Fix:** `static let` cacheado. Mismo formato de salida.

### M4 · Comprobar existencia de imagen decodificándola entera
- **Dónde:** `Models/ImageStore.swift:71-85` (`lookRibbonThumbnailRelativePath` llama `load()` solo para testar `!= nil`); `Views/ClosetDetailAndLooksViews.swift:~1568` (`ribbonCoverCandidates`).
- **Qué pasa:** decodifica imágenes completas únicamente para saber si el archivo existe.
- **Fix:** usar `FileManager.default.fileExists(atPath:)`. Resultado idéntico, coste casi nulo.

### M5 · Filtrado/orden/agrupado pesado dentro de `body`
- **Dónde:** `Views/ClosetViews.swift:193-213` (`filteredActiveClosetItems`, `filteredCatalogProducts`), `:294-335` (`buildStockCategoryBreakdowns`), `:356-365`; `Views/MainTabView.swift:242-265` (`filteredSales`, `filterItems` en SoldView).
- **Qué pasa:** O(n) con `.lowercased()/.contains()/.sorted()` se recomputan en cada repintado durante el scroll.
- **Fix:** memoizar en `@State` recalculando solo en `.onChange` de los inputs (búsqueda/filtros), o mover el cómputo al ViewModel. Sin cambio de comportamiento.

### M6 · Timer de auto-spin a 30 fps en el capturador 360
- **Dónde:** `Views/ClosetDetailAndLooksViews.swift:~2365` (`Timer.scheduledTimer(1/30)` → `MainActor.run`).
- **Qué pasa:** 30 updates/s al main thread mientras esa vista está activa.
- **Fix:** sustituir por `TimelineView(.animation)` (se pausa solo fuera de pantalla). Misma animación.

---

## BAJO (pulido; aplicar si se quiere exprimir)

- **B1 · `ForEach(Array(...enumerated()), id: \.offset)`** en varios sitios (`ClosetDetailAndLooksViews.swift:2716`, `ClosetViews.swift:1164/1177/2342`, waveform en `ChatConversationView.swift:1694`). Usar id estable (`\.element.id` o el propio valor) evita reconstrucción de identidades.
- **B2 · Sombras de radio grande por celda** (`.shadow(radius: 10-12)` en filas de `MainTabView.swift`/`ClosetViews.swift`). Bajar radio a 4-6 o cachear con `.drawingGroup()` en tarjetas estáticas.
- **B3 · Animaciones de entrada** que pueden re-evaluarse (`EntranceAnimation`/`SoldEntranceAnimation`). Asegurar que corren una sola vez con `@State hasAnimated`.
- **B4 · `DashboardViewModel` (telemetría de coche, timer 1.5 s con `withAnimation`)** parece **código muerto** (sin `@StateObject`/instancia activa encontrada). Verificar y, si no se usa, no arranca el timer. Es legacy del CRM de coches.
- **B5 · Higiene del repo (no es runtime):** múltiples carpetas de build en el repo (`.derivedData*`, `.cliBuild*`, `.runBuild*`) y PNGs grandes sueltos en la raíz (`zapatos.png` 2.3 MB, `oji.png` 2 MB, `ko\`mp.png` 1 MB). No afecta a la app en ejecución pero infla el repo y los tiempos de indexado de Xcode.

---

## Plan de aplicación sugerido (de mayor impacto / menor riesgo)

**Fase 1 — Quick wins de fluidez (riesgo muy bajo, gran efecto):**
C1, C2 (imágenes del clóset async + downsample), M4 (existencia con `fileExists`), C3 + M1 + M2 (pausar vídeo, fondo animado y polling según `scenePhase`), M3 (formatter estático).

**Fase 2 — Memoización y limpieza (riesgo bajo):**
M5 (memoizar filtros), M6 (auto-spin a `TimelineView`), B1, B2, B3.

**Fase 3 — Opcional:**
B4 (confirmar y desactivar timer muerto), B5 (higiene de repo).

Todo se puede compilar y validar por fases. Recomiendo aplicar Fase 1 y que pruebes el scroll del clóset antes de seguir.

---

---

## Cambios aplicados (resumen técnico)

**Núcleo de imágenes (C1):**
- `Views/StockSearchScannerViews.swift` · `StockImageLoader`: nuevo `downsampledLocalImage(relativePath:maxSide:)` que decodifica desde disco con `CGImageSource` (sin cargar el bitmap completo); `cachedLocalImage` ahora hace downsample antes de cachear; nuevo `cachedLocalImageAsync` que decodifica en `Task.detached(priority:.utility)`.
- `Views/ClosetViews.swift` y `Views/ClosetDetailAndLooksViews.swift` · `ClosetDiskThumbnail`: carga asíncrona con `@State` + `.task(id:)`, mostrando hit de caché al instante (sin parpadeo). Es la celda del grid principal del clóset.

**Rutas de display por caché (C2):**
- `MainTabView.swift` (filas Vendido/Archivo), `DashboardView.swift` (miniatura último vendido), `ClosetDetailAndLooksViews.swift` (chip de portada) y `ClosetViews.swift` (`thumb`) pasan de `ImageStore.load` directo a `StockImageLoader.cachedLocalImage` (cacheado + downsampleado).

**Existencia sin decodificar (M4):**
- `Models/ImageStore.swift`: nuevo `exists(_:)` con `FileManager.fileExists`. Sustituye `ImageStore.load(...) != nil` en `lookRibbonThumbnailRelativePath`, `ClosetProductMetadata`, `ClosetDetailAndLooksViews` (x2) y `GeminiService`.

**Trabajo continuo pausado:**
- `Design/DashboardHomeVideoBackdrop.swift` (C3): vídeo pausa/reanuda según `scenePhase` (`pausePlayback()`/`resume()`), sigue parando en `dismantle`.
- `Design/RevolutBackgroundView.swift` (M1): `MeshGradient` 30 fps con `paused: scenePhase != .active`.
- `Views/MainTabView.swift` + `DashboardCommunityViewModel` (M2): el polling de comunidad (15 s) se detiene en `background/inactive` y se reanuda en `active`.

**Formatters estáticos (M3):**
- `ChatConversationView.swift`: `timeFormatter` estático reutilizado en `currentTimeString` y `formatChatTime` (antes creaba `DateFormatter` por mensaje).
- `CarsView.swift`: `priceFormatter` estático.

**Verificado / sin acción (B4):** `DashboardViewModel` (telemetría de coche, timer 1.5 s) está definido pero **nunca se instancia** → código muerto sin coste en runtime.

**Deferido a propósito (riesgo > beneficio, o cambia diseño):**
- M5 (memoizar filtros): recomputar filtros sobre unos cientos de ítems es mucho más barato que decodificar imágenes; el refactor con invalidación atada a `@Query` tiene riesgo real de regresión. No es el cuello de botella.
- M6 (auto-spin a `TimelineView`): ese `Timer` ya tiene start/stop explícito y solo corre en la captura 360 mientras gira. Migrarlo reestructura el control de captura con beneficio marginal.
- B2 (reducir radios de sombra / `drawingGroup`): cambiaría el aspecto visual, que pediste no tocar.
- B1 (ids `\.offset` → `\.element`): en tiras con rutas potencialmente repetidas, ids duplicados podrían fallar; beneficio bajo.

> **Siguiente paso recomendado:** abrir en Xcode, `Cmd+Shift+K` (Clean) y compilar. Si Xcode no detecta cambios, borra DerivedData (`rm -rf ~/Library/Developer/Xcode/DerivedData/Upsoled-*`). Probar el scroll del clóset en dispositivo real con ≥100 prendas.

---

### Cómo verificar la mejora
- Xcode → Debug → **Instruments → Animation Hitches / Time Profiler** durante scroll del clóset (antes/después).
- Activar **Color Hitches / FPS** y comprobar caída de decodes en main thread.
- Probar en un dispositivo real (no solo simulador) con un inventario de ≥100 prendas.

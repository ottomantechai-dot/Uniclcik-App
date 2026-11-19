import AudioToolbox
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UserNotifications
import Vision

// MARK: - Paleta modo claro

enum ClosetFlowPalette {
    static let secondaryText = Color.black.opacity(0.55)
    static let mutedBackground = Color(.secondarySystemBackground)
    static let darkerPillFill = Color(white: 0.22)
    static let destructive = Color(red: 229 / 255, green: 57 / 255, blue: 53 / 255)
}

private struct ClosetEmptySegmentProgressBar: View {
    let filledCount: Int
    let segmentCount: Int

    init(filledCount: Int, segmentCount: Int = 5) {
        self.segmentCount = max(1, segmentCount)
        self.filledCount = min(self.segmentCount, max(0, filledCount))
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<segmentCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(i < filledCount ? Color.black : Color.black.opacity(0.12))
                    .frame(height: 8)
            }
        }
    }
}

/// Token para `.sheet(item:)` al flujo 360° en borrador guardarropa.
private struct Shoe360DraftSheetPieceID: Identifiable, Hashable {
    let pieceID: UUID
    var id: UUID { pieceID }
}

// MARK: - Miniatura desde ImageStore

private struct ClosetDiskThumbnail: View {
    let relativePath: String
    var maxPixelSide: CGFloat = 296
    var fillFrame: Bool = false

    @State private var image: UIImage?
    @State private var loadFailed = false

    init(relativePath: String, maxPixelSide: CGFloat = 296, fillFrame: Bool = false) {
        self.relativePath = relativePath
        self.maxPixelSide = maxPixelSide
        self.fillFrame = fillFrame
        let key = StockImageLoader.localCacheKey(relativePath, maxSide: maxPixelSide)
        _image = State(initialValue: ImageCacheService.shared.image(forKey: key))
    }

    var body: some View {
        Group {
            if let ui = image {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: fillFrame ? .fill : .fit)
            } else if loadFailed || relativePath.isEmpty {
                Image(systemName: "photo")
                    .font(.system(size: fillFrame ? 20 : 24))
                    .foregroundStyle(Color.black.opacity(0.18))
            } else {
                ZStack {
                    Color.white
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.black.opacity(0.35))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .clipped()
        .task(id: "\(relativePath)-\(Int(maxPixelSide))") {
            guard image == nil else { return }
            guard !relativePath.isEmpty else {
                loadFailed = true
                return
            }
            if let loaded = await StockImageLoader.cachedLocalImageAsync(
                relativePath: relativePath,
                maxSide: maxPixelSide
            ) {
                image = loaded
                loadFailed = false
            } else {
                loadFailed = true
            }
        }
    }
}

// MARK: - Cámara

/// Picker para escanear un zapato: usa la cámara si está disponible; si no (simulador), la galería.
struct SneakerCameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    final class Delegate: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: SneakerCameraPicker
        init(_ parent: SneakerCameraPicker) { self.parent = parent }
        func imagePickerController(_ _: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = (info[.originalImage] as? UIImage)?.closetFlattenedOrientation()
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ _: UIImagePickerController) { parent.dismiss() }
    }

    func makeCoordinator() -> Delegate { Delegate(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ _: UIImagePickerController, context _: Context) {}
}

struct ClosetUIImagePickerBridge: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    final class Delegate: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ClosetUIImagePickerBridge

        init(_ parent: ClosetUIImagePickerBridge) { self.parent = parent }

        func imagePickerController(
            _ _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = (info[.originalImage] as? UIImage)?.closetFlattenedOrientation()
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ _: UIImagePickerController) {
            parent.dismiss()
        }
    }

    func makeCoordinator() -> Delegate { Delegate(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ _: UIImagePickerController, context _: Context) {}
}

extension UIImage {
    /// Upright orientation + white backdrop cleanup for closet uploads.
    func closetFlattenedOrientation() -> UIImage {
        ClosetPhotoExports.normalizedClosetProductImage(self)
    }
}

// MARK: - Pestaña clóset + sheet entrada

struct ClosetView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var addFlow: AddToClosetFlowViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter
    @Query(sort: \ClosetItem.createdAt, order: .reverse) private var closetItems: [ClosetItem]
    /// Catálogo Supabase (`upsoled_products`): mismos productos que la pestaña Marketplace/Sold.
    @StateObject private var catalogVM = UpsoledProductsViewModel()

    /// Active inventory only — sold items live under the Sold tab.
    private var activeClosetItems: [ClosetItem] {
        closetItems.filter(\.isActiveInStock)
    }

    @State private var closetSelectionMode = false

    private struct StockRemovalRequest: Identifiable {
        let id = UUID()
        let closetIDs: Set<UUID>
        let catalogIDs: Set<UUID>

        var totalCount: Int { closetIDs.count + catalogIDs.count }
    }

    @State private var closetSelectedIDs = Set<UUID>()
    @State private var catalogSelectedIDs = Set<UUID>()
    @State private var showBulkCategorySheet = false
    @State private var catalogDetailBusy = false
    @State private var removalRequest: StockRemovalRequest?
    @State private var permanentDeleteItem: ClosetItem?
    @State private var marketPrefetchBusy = false

    /// Ficha grande de una prenda (estudio) — push en el stack de Your stock.
    @State private var garmentDetailItemID: UUID?
    @State private var stockSearchOpen = false

    @State private var stockSearchText = ""
    @FocusState private var stockSearchFocused: Bool
    @State private var stockFilters = StockBrowseFilters()
    @State private var showStockFiltersSheet = false
    @AppStorage("stockLayoutMode") private var stockLayoutModeRaw = StockLayoutMode.list.rawValue
    @State private var scanLookupPayload: StockScanLookupPayload?
    @State private var scanLookupBusy = false
    @State private var showStockBarcodeScanner = false

    private var stockLayoutModeBinding: Binding<StockLayoutMode> {
        Binding(
            get: { StockLayoutMode(rawValue: stockLayoutModeRaw) ?? .grid },
            set: { stockLayoutModeRaw = $0.rawValue }
        )
    }

    private var stockSearchQuery: String {
        stockSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func itemMatchesStockSearch(_ item: ClosetItem, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let blob = [
            item.brand ?? "",
            item.name,
            item.catalogDisplayName,
            item.skuText ?? "",
            item.resolvedSKU ?? "",
            item.colorLabel ?? "",
            item.sizeText ?? "",
            item.category.displayName,
        ]
        .joined(separator: " ")
        .lowercased()
        return blob.contains(query)
    }

    private var filteredActiveClosetItems: [ClosetItem] {
        var items = activeClosetItems
            .filter { !Self.stockHiddenCategoryKeys.contains(StockFilterEngine.closetCategoryKey($0)) }
        if !stockSearchQuery.isEmpty {
            items = items.filter { itemMatchesStockSearch($0, query: stockSearchQuery) }
        }
        items = items.filter { StockFilterEngine.matches(stockFilters, closetItem: $0) }
        return StockFilterEngine.sortClosetItems(items, by: stockFilters.sort)
    }

    private var filteredCatalogProducts: [UpsoledProduct] {
        var products = catalogVM.products
            .filter { !Self.stockHiddenCategoryKeys.contains(StockFilterEngine.catalogCategoryKey($0)) }
        if !stockSearchQuery.isEmpty {
            products = products.filter { product in
                product.name.lowercased().contains(stockSearchQuery)
                    || (product.brand ?? "").lowercased().contains(stockSearchQuery)
                    || (product.sku ?? "").lowercased().contains(stockSearchQuery)
            }
        }
        products = products.filter { StockFilterEngine.matches(stockFilters, catalogProduct: $0) }
        return StockFilterEngine.sortCatalogProducts(products, by: stockFilters.sort)
    }

    /// Catálogo sin filas que ya están representadas por un `ClosetItem` activo enlazado.
    private var stockCatalogProductsExcludingClosetDuplicates: [UpsoledProduct] {
        let activeClosetIDs = Set(activeClosetItems.map(\.id))
        let closetIdentityKeys = stockClosetIdentityKeys(from: filteredActiveClosetItems)

        return filteredCatalogProducts.filter { product in
            if let linkedClosetId = CatalogClosetBridge.closetItemId(forCatalogProduct: product.id),
               activeClosetIDs.contains(linkedClosetId) {
                return false
            }
            if let key = stockCatalogIdentityKey(for: product),
               closetIdentityKeys.contains(key) {
                return false
            }
            return true
        }
    }

    private func stockClosetIdentityKey(for item: ClosetItem) -> String? {
        let sku = (item.skuText ?? item.resolvedSKU ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !sku.isEmpty else { return nil }
        let size = StockSizeDisplay.normalizedStorage(from: item.sizeText) ?? ""
        return "\(sku)|\(size)"
    }

    private func stockCatalogIdentityKey(for product: UpsoledProduct) -> String? {
        let sku = (product.sku ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !sku.isEmpty else { return nil }
        let size = product.sizes
            .compactMap { StockSizeDisplay.normalizedStorage(from: $0) }
            .first ?? ""
        return "\(sku)|\(size)"
    }

    private func stockClosetIdentityKeys(from items: [ClosetItem]) -> Set<String> {
        Set(items.compactMap { stockClosetIdentityKey(for: $0) })
    }

    /// Closet sin entradas repetidas (mismo SKU+talla o mismo enlace de catálogo).
    private var stockClosetItemsExcludingCatalogDuplicates: [ClosetItem] {
        var seenCatalogLinks = Set<UUID>()
        var seenIdentityKeys = Set<String>()
        var unique: [ClosetItem] = []

        for item in filteredActiveClosetItems {
            if let catalogId = CatalogClosetBridge.catalogProductId(forClosetItem: item.id) {
                guard !seenCatalogLinks.contains(catalogId) else { continue }
                seenCatalogLinks.insert(catalogId)
            }
            if let identityKey = stockClosetIdentityKey(for: item) {
                guard !seenIdentityKeys.contains(identityKey) else { continue }
                seenIdentityKeys.insert(identityKey)
            }
            unique.append(item)
        }

        return unique
    }

    private var hasCatalogStock: Bool { !catalogVM.products.isEmpty }
    private var hasAnyStockContent: Bool { !activeClosetItems.isEmpty || hasCatalogStock }

    private struct UnifiedStockSection: Identifiable {
        let key: String
        let emoji: String
        let title: String
        let closetItems: [ClosetItem]
        let catalogProducts: [UpsoledProduct]

        var id: String { key }

        var itemCount: Int {
            closetItems.count + catalogProducts.reduce(0) { $0 + max(1, $1.quantity ?? 1) }
        }

        var totalValueUSD: Double {
            let closet = closetItems.reduce(0.0) { $0 + $1.stockValueUSD }
            let catalog = catalogProducts.reduce(0.0) { $0 + $1.stockValueUSD }
            return closet + catalog
        }
    }

    private var filteredUnifiedStockSections: [UnifiedStockSection] {
        let closet = StockFilterEngine.sortClosetItems(
            stockClosetItemsExcludingCatalogDuplicates,
            by: stockFilters.sort
        )
        let catalog = StockFilterEngine.sortCatalogProducts(
            stockCatalogProductsExcludingClosetDuplicates,
            by: stockFilters.sort
        )
        guard !closet.isEmpty || !catalog.isEmpty else { return [] }

        return [
            UnifiedStockSection(
                key: "all",
                emoji: "👟",
                title: "Your stock",
                closetItems: closet,
                catalogProducts: catalog
            ),
        ]
    }

    private var stockImagePrefetchToken: String {
        let closetPaths = stockClosetItemsExcludingCatalogDuplicates.map(\.id.uuidString).joined(separator: "|")
        let catalogIDs = stockCatalogProductsExcludingClosetDuplicates.map(\.id.uuidString).joined(separator: "|")
        return "\(stockLayoutModeRaw)#\(closetPaths)#\(catalogIDs)"
    }

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(minimum: 148), spacing: 12),
        GridItem(.flexible(minimum: 148), spacing: 12),
    ]

    private static let stockHiddenCategoryKeys: Set<String> = [
        ClothingCategory.bags.rawValue,
    ]

    private static let stockSummaryCategoryOrder: [String] = [
        ClothingCategory.shoes.rawValue,
        ClothingCategory.tops.rawValue,
        ClothingCategory.dressesJumpsuits.rawValue,
        ClothingCategory.pantsSkirts.rawValue,
        ClothingCategory.coats.rawValue,
        ClothingCategory.accessories.rawValue,
        ClothingCategory.underwear.rawValue,
        "clothing", "vintage", "new-drops", "other",
    ]

    private func catalogCategoryPresentation(_ raw: String?) -> (key: String, emoji: String, title: String) {
        let key = (raw ?? "other").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "shoes": return ("shoes", "👞", "Shoes")
        case "clothing": return ("clothing", "👔", "Clothing")
        case "accessories": return ("accessories", "⌚", "Accessories")
        case "vintage": return ("vintage", "🕰️", "Vintage")
        case "new-drops", "new_drops": return ("new-drops", "✨", "New drops")
        case "tops": return (ClothingCategory.tops.rawValue, ClothingCategory.tops.emoji, ClothingCategory.tops.displayName)
        case "bags": return (ClothingCategory.bags.rawValue, ClothingCategory.bags.emoji, ClothingCategory.bags.displayName)
        default:
            if let cat = ClothingCategory(rawValue: key) {
                return (cat.rawValue, cat.emoji, cat.displayName)
            }
            let title = key.replacingOccurrences(of: "-", with: " ").capitalized
            return (key.isEmpty ? "other" : key, "📦", title.isEmpty ? "Other" : title)
        }
    }

    /// Meta de onboarding: barra de 5 segmentos hasta tener 5 prendas guardadas.
    private static let closetStarterGarmentGoal: Int = 5

    private var showsClosetStarterProgress: Bool {
        activeClosetItems.count < Self.closetStarterGarmentGoal && !hasCatalogStock
    }

    private func closetStarterProgressLabel() -> String {
        let n = activeClosetItems.count
        if n == 0 {
            return L10n.tr("closet.progressGoalIntro")
        }
        let remaining = Self.closetStarterGarmentGoal - n
        guard remaining >= 2 else {
            return L10n.tr("closet.progressGreatRemainingOne")
        }
        return String(format: L10n.tr("closet.progressGreatRemainingPlural"), Int64(remaining))
    }

    private var draftBannerCount: Int { ClosetLocalDraftStore.pendingCount }

    /// Espacio bajo la rejilla para banner de borradores y barra de eliminar en bloque.
    private var marketPrefetchKey: String {
        filteredActiveClosetItems
            .filter { $0.marketPriceNeedsRefresh && $0.hasStyleForMarketLookup }
            .prefix(24)
            .map(\.id.uuidString)
            .joined(separator: "|")
    }

    private var bottomInsetForClosetGrid: CGFloat {
        var h: CGFloat
        if draftBannerCount > 0 {
            h = 148
        } else if !hasAnyStockContent {
            h = 100
        } else {
            h = 72
        }
        if closetSelectionMode, !closetSelectedIDs.isEmpty || !catalogSelectedIDs.isEmpty {
            h += 88
        }
        return h
    }

    /// Barra flotante de arriba: el contenido pasa por detrás. El buscador y los filtros son botones
    /// redondos junto a la foto de perfil; el campo de búsqueda solo aparece al tocar la lupa.
    private var stockTopChrome: some View {
        VStack(spacing: 8) {
            AppTopBar(title: "Sneakers") {
                if hasAnyStockContent {
                    Button {
                        withAnimation(.snappy(duration: 0.28)) { stockSearchOpen.toggle() }
                        stockSearchFocused = stockSearchOpen
                        if !stockSearchOpen { stockSearchText = "" }
                    } label: { TopBarGlassButton(systemImage: stockSearchOpen ? "xmark" : "magnifyingglass") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Search")
                    Menu {
                        Button { showStockFiltersSheet = true } label: { Label("Filters", systemImage: "line.3.horizontal.decrease") }
                        Button { showStockBarcodeScanner = true } label: { Label("Scan a box", systemImage: "barcode.viewfinder") }
                        NavigationLink { SaleReportsHistoryView() } label: { Label("Sale reports", systemImage: "doc.text.magnifyingglass") }
                        Section("Sort") {
                            ForEach(StockSortOrder.allCases) { order in
                                Button { stockFilters.sort = order } label: {
                                    if stockFilters.sort == order { Label(order.menuLabel, systemImage: "checkmark") } else { Text(order.menuLabel) }
                                }
                            }
                        }
                    } label: { TopBarGlassButton(systemImage: "slider.horizontal.3") }
                        .accessibilityLabel("Filters and sort")
                }
            }
            if hasAnyStockContent, stockSearchOpen {
                StockBrowseSearchBar(
                    searchText: $stockSearchText,
                    searchFocused: $stockSearchFocused,
                    onScanBarcode: { showStockBarcodeScanner = true }
                )
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if closetSelectionMode {
                stockFilterSortToolbar.padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 10)
        .background {
            LinearGradient(colors: [.white, .white.opacity(0.92), .white.opacity(0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
    }

    private func openAddStockFlow(openPipeline: Bool = false) {
        if openPipeline {
            tabRouter.addTabOpenPipeline = true
        }
        ClosetAnalytics.named("add_to_closet_opened")
        tabRouter.showAddStockFlow = true
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        Color.clear
                            .frame(height: 60 + (stockSearchOpen ? 60 : 0) + (closetSelectionMode ? 44 : 0))
                            .id("stockScrollTop")
                        productsTabContent
                    }
                }
                .refreshable {
                    await catalogVM.reload()
                }
                .onChange(of: stockFilters.quickCategory) { _, _ in
                    withAnimation(.easeOut(duration: 0.28)) {
                        scrollProxy.scrollTo("stockScrollTop", anchor: .top)
                    }
                }
                .onChange(of: stockFilters.categoryKeys) { _, _ in
                    withAnimation(.easeOut(duration: 0.28)) {
                        scrollProxy.scrollTo("stockScrollTop", anchor: .top)
                    }
                }
            }
            .overlay(alignment: .top) { stockTopChrome }

            if draftBannerCount > 0 {
                draftResumeBanner
            }

            if closetSelectionMode, !closetSelectedIDs.isEmpty || !catalogSelectedIDs.isEmpty {
                stockBulkActionBar
            }
        }
        .navigationTitle(L10n.tr("closet.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(garmentDetailItemID == nil && !tabRouter.showAddStockFlow ? .hidden : .visible, for: .navigationBar)
        .preferredColorScheme(.light)
        .task {
            ClosetInventoryRepair.normalizeSoldFlags(in: modelContext)
            ClosetInventoryRepair.backfillSKUFromNames(in: modelContext)
            catalogVM.fetchLimit = 750
            await catalogVM.reload()
        }
        .task(id: marketPrefetchKey) {
            await prefetchStockMarketPrices()
        }
        .task(id: stockImagePrefetchToken) {
            await prefetchStockImages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closetInventoryDidChange)) { _ in
            Task { await catalogVM.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .upsoledCatalogDidChange)) { _ in
            Task { await catalogVM.reload() }
        }
        .toastOverlay(
            message: Binding(
                get: { addFlow.toast },
                set: { addFlow.toast = $0 }
            ))
        .navigationDestination(isPresented: $tabRouter.showAddStockFlow) {
            AddToStockTabView()
                .environmentObject(addFlow)
                .environmentObject(tabRouter)
                .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: tabRouter.showAddStockFlow) { _, showing in
            if !showing {
                tabRouter.addTabOpenPipeline = false
            }
        }
        .onChange(of: tabRouter.showAddStockFlow || garmentDetailItemID != nil) { _, detail in tabRouter.barHidden = detail }
        .navigationDestination(item: $garmentDetailItemID) { itemID in
            if let item = closetItems.first(where: { $0.id == itemID }) {
                ClosetGarmentDetailView(item: item)
            } else {
                ContentUnavailableView("Item not found", systemImage: "archivebox")
            }
        }
        .sheet(isPresented: $showBulkCategorySheet) {
            BulkStockCategorySheet(
                selectionCount: closetSelectedIDs.count + catalogSelectedIDs.count,
                onApplyClothing: { applyBulkCategory($0) }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showStockFiltersSheet) {
            StockBrowseFiltersSheet(
                filters: $stockFilters,
                layoutMode: stockLayoutModeBinding,
                closetItems: activeClosetItems,
                catalogProducts: catalogVM.products
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $scanLookupPayload) { payload in
            StockScanResultSheet(
                payload: payload,
                onViewStockItem: { id in
                    scanLookupPayload = nil
                    if let item = activeClosetItems.first(where: { $0.id == id }) {
                        garmentDetailItemID = item.id
                    }
                },
                onDismiss: { scanLookupPayload = nil }
            )
            .presentationDetents([.height(420), .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showStockBarcodeScanner) {
            StockBarcodeScannerScreen(
                onCode: { code in
                    showStockBarcodeScanner = false
                    Task { await handleScannedCode(code) }
                },
                onCancel: { showStockBarcodeScanner = false }
            )
        }
        .overlay {
            if scanLookupBusy || catalogDetailBusy {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView(catalogDetailBusy ? "Opening item…" : L10n.tr("price.searching"))
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                }
            }
        }
        .confirmationDialog(
            (removalRequest?.totalCount ?? 0) <= 1
                ? L10n.tr("sold.removalDialogTitle")
                : L10n.tr("sold.removalBulkTitle"),
            isPresented: Binding(
                get: { removalRequest != nil },
                set: { if !$0 { removalRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.tr("sold.removalDiscontinuedAction"), role: .destructive) {
                if let request = removalRequest {
                    Task { await applyStockRemoval(reason: .discontinued, request: request) }
                }
                removalRequest = nil
            }
            Button(L10n.tr("common.close"), role: .cancel) {
                removalRequest = nil
            }
        } message: {
            Text(
                (removalRequest?.totalCount ?? 0) <= 1
                    ? L10n.tr("sold.removalDialogMessage")
                    : L10n.tr("sold.removalBulkMessage")
            )
        }
        .alert(
            L10n.tr("sold.deletePermanently"),
            isPresented: Binding(
                get: { permanentDeleteItem != nil },
                set: { if !$0 { permanentDeleteItem = nil } }
            )
        ) {
            Button(L10n.tr("sold.deletePermanently"), role: .destructive) {
                if let item = permanentDeleteItem {
                    permanentlyDeleteClosetItem(item)
                }
                permanentDeleteItem = nil
            }
            Button(L10n.tr("common.close"), role: .cancel) {
                permanentDeleteItem = nil
            }
        } message: {
            Text(L10n.tr("sold.deletePermanentlyConfirm"))
        }
    }

    /// Estado vacío: layout tipo banner (referencia onboarding) — vídeo 16:9 visible completo (`resizeAspectFit`).
    @ViewBuilder
    private var closetEmptyOnboardingDesign: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                LoopingMutedBundledVideoView(
                    resourceName: "video-portada",
                    fileExtension: "mp4",
                    videoGravity: .resizeAspect
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(4)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9.0, contentMode: .fit)
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                Text(closetStarterProgressLabel())
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black)
                    .fixedSize(horizontal: false, vertical: true)
                ClosetEmptySegmentProgressBar(
                    filledCount: min(Self.closetStarterGarmentGoal, activeClosetItems.count),
                    segmentCount: Self.closetStarterGarmentGoal
                )
            }
            .padding(.horizontal, 16)

            Button {
                openAddStockFlow()
            } label: {
                Text(L10n.tr("closet.addWide"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Capsule(style: .continuous).fill(Color.black))
                    .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    /// Progreso 5 prendas cuando ya hay prendas pero aún falta llegar al objetivo (encima de la rejilla).
    private var closetStarterProgressStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(closetStarterProgressLabel())
                .font(.system(size: 15))
                .foregroundStyle(Color.black)
                .fixedSize(horizontal: false, vertical: true)
            ClosetEmptySegmentProgressBar(
                filledCount: min(Self.closetStarterGarmentGoal, activeClosetItems.count),
                segmentCount: Self.closetStarterGarmentGoal
            )
            Button {
                openAddStockFlow()
            } label: {
                Text(L10n.tr("closet.addWide"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Capsule(style: .continuous).fill(Color.black))
                    .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Text(L10n.tr("closet.starterReminderPartial"))
                .font(.system(size: 13))
                .foregroundStyle(ClosetFlowPalette.secondaryText)
        }
        .padding(.horizontal, 16)
    }

    private var stockFilterSortToolbar: some View {
        Group {
            if closetSelectionMode {
                HStack(spacing: 10) {
                    Button {
                        closetSelectionMode = false
                        closetSelectedIDs.removeAll()
                        catalogSelectedIDs.removeAll()
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.72))
                    }
                    .buttonStyle(.plain)

                    Text("\(closetSelectedIDs.count + catalogSelectedIDs.count) selected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))

                    Spacer(minLength: 0)

                    stockSortMenu
                }
            } else {
                StockBrowseFilterSortBar(filters: $stockFilters) {
                    showStockFiltersSheet = true
                }
            }
        }
    }

    private var stockSortMenu: some View {
        Menu {
            ForEach(StockSortOrder.allCases) { order in
                Button {
                    stockFilters.sort = order
                } label: {
                    if stockFilters.sort == order {
                        Label(order.menuLabel, systemImage: "checkmark")
                    } else {
                        Text(order.menuLabel)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Sort by: \(stockFilters.sort.menuLabel)")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.06)))
        }
    }

    private var stockBulkActionBar: some View {
        VStack(spacing: 10) {
            Button {
                showBulkCategorySheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tag.fill")
                    Text("Change category (\(closetSelectedIDs.count + catalogSelectedIDs.count))")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black))
            }
            .buttonStyle(.plain)

            if !closetSelectedIDs.isEmpty || !catalogSelectedIDs.isEmpty {
                Button {
                    removalRequest = StockRemovalRequest(
                        closetIDs: closetSelectedIDs,
                        catalogIDs: catalogSelectedIDs
                    )
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "trash.fill")
                        Text("Remove (\(closetSelectedIDs.count + catalogSelectedIDs.count))")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ClosetFlowPalette.destructive))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 94)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    @MainActor
    private func openCatalogDetail(_ product: UpsoledProduct) {
        Task {
            catalogDetailBusy = true
            defer { catalogDetailBusy = false }
            let item = await CatalogClosetBridge.ensureClosetItem(for: product, in: modelContext)
            garmentDetailItemID = item.id
            ClosetAnalytics.named("closet_item_detail_open")
        }
    }

    @MainActor
    private func applyBulkCategory(_ category: ClothingCategory) {
        let closetItemsToUpdate = closetItems.filter { closetSelectedIDs.contains($0.id) }
        for item in closetItemsToUpdate {
            item.categoryRaw = category.rawValue
            CatalogClosetBridge.syncClosetItemEditsToCatalog(item)
        }
        try? modelContext.save()

        let catalogIds = catalogSelectedIDs
        for product in catalogVM.products where catalogIds.contains(product.id) {
            var draft = ProductDraft.from(product)
            draft.category = CatalogClosetBridge.catalogCategoryString(from: category)
            catalogVM.persistEditLocally(product, draft: draft)
        }

        closetSelectedIDs.removeAll()
        catalogSelectedIDs.removeAll()
        closetSelectionMode = false
        showBulkCategorySheet = false
    }

    /// Quita ficheros, SwiftData y fila vinculada en Supabase.
    private func permanentlyDeleteClosetItem(_ item: ClosetItem) {
        let id = item.id
        Task {
            await CatalogClosetBridge.deleteLinkedCatalogProduct(forClosetItem: id)
            await MainActor.run {
                ClosetInventoryRepair.permanentlyDeleteClosetItem(item, in: modelContext)
                ClosetAnalytics.named("closet_item_deleted")
            }
        }
    }

    private func purgeClosetItemFiles(_ item: ClosetItem) {
        ClosetInventoryRepair.purgeClosetItemFiles(item)
    }

    @MainActor
    private func applyStockRemoval(reason: StockRemovalReason, request: StockRemovalRequest) async {
        var processedCloset = Set<UUID>()

        for id in request.closetIDs {
            guard let item = closetItems.first(where: { $0.id == id }) else { continue }
            if reason == .discontinued {
                await CatalogClosetBridge.deleteLinkedCatalogProduct(forClosetItem: id)
                ClosetInventoryRepair.permanentlyDeleteClosetItem(item, in: modelContext)
            } else {
                applyRemovalReason(reason, to: item)
                await CatalogClosetBridge.deleteLinkedCatalogProduct(forClosetItem: id)
            }
            processedCloset.insert(id)
        }

        for productId in request.catalogIDs {
            if reason == .discontinued {
                if let linked = CatalogClosetBridge.closetItemId(forCatalogProduct: productId),
                   let item = closetItems.first(where: { $0.id == linked }),
                   !processedCloset.contains(linked) {
                    await CatalogClosetBridge.deleteLinkedCatalogProduct(forClosetItem: linked)
                    ClosetInventoryRepair.permanentlyDeleteClosetItem(item, in: modelContext)
                    processedCloset.insert(linked)
                }
                await catalogVM.deleteProduct(id: productId)
            } else if let linked = CatalogClosetBridge.closetItemId(forCatalogProduct: productId),
               let item = closetItems.first(where: { $0.id == linked }),
               !processedCloset.contains(linked) {
                applyRemovalReason(reason, to: item)
                processedCloset.insert(linked)
            } else if let product = catalogVM.products.first(where: { $0.id == productId }) {
                let item = await CatalogClosetBridge.ensureClosetItem(for: product, in: modelContext)
                applyRemovalReason(reason, to: item)
                processedCloset.insert(item.id)
            }
            if reason != .discontinued {
                await catalogVM.deleteProduct(id: productId)
            }
        }

        if reason != .discontinued {
            try? modelContext.save()
        }
        await catalogVM.reload()
        closetSelectedIDs.removeAll()
        catalogSelectedIDs.removeAll()
        closetSelectionMode = false

        switch reason {
        case .sold:
            addFlow.showToast(L10n.tr("sold.removalSoldToast"))
        case .discontinued:
            addFlow.showToast(L10n.tr("sold.removedToast"))
        }
        ClosetAnalytics.named("closet_stock_removed", params: "reason:\(reason.rawValue)")
    }

    private func applyRemovalReason(_ reason: StockRemovalReason, to item: ClosetItem) {
        switch reason {
        case .sold:
            item.isSold = true
            item.soldAt = Date()
            item.deletedAt = nil
            item.deletionReasonRaw = nil
        case .discontinued:
            item.isSold = false
            item.soldAt = nil
            item.deletedAt = Date()
            item.deletionReasonRaw = StockRemovalReason.discontinued.rawValue
        }
    }

    /// Productos · stock por categorías.
    @ViewBuilder
    private var productsTabContent: some View {
        if showsClosetStarterProgress, activeClosetItems.isEmpty {
            closetEmptyOnboardingDesign
                .padding(.bottom, bottomInsetForClosetGrid)
        } else if showsClosetStarterProgress {
            closetStarterProgressStrip
        }

        if hasAnyStockContent,
           stockClosetItemsExcludingCatalogDuplicates.isEmpty,
           stockCatalogProductsExcludingClosetDuplicates.isEmpty {
            Text(stockFilters.isActive || !stockSearchQuery.isEmpty
                ? "No items match your filters."
                : L10n.tr("closet.searchEmpty"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 24)
        }

        if catalogVM.isLoading, catalogVM.products.isEmpty, activeClosetItems.isEmpty {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }

        if !filteredUnifiedStockSections.isEmpty {
            if stockLayoutModeBinding.wrappedValue == .list {
                unifiedStockListContent
            } else {
                unifiedStockGridContent
            }
        }
    }

    private func unifiedSectionHeader(_ section: UnifiedStockSection, edgeToEdge: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.black)
            Spacer(minLength: 8)
            Text(PieceMarketPrice.formatUSD(Int(section.totalValueUSD.rounded())))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.72))
            Text("\(section.itemCount)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.42))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
        .padding(.horizontal, edgeToEdge ? 10 : 16)
    }

    private var unifiedStockGridContent: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(filteredUnifiedStockSections) { section in
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(section.closetItems) { item in
                        closetCell(item)
                            .id("\(item.id)-\(item.priceText ?? "")-\(item.purchasePriceText ?? "")")
                            .padding(.top, 10)
                    }
                    ForEach(section.catalogProducts) { product in
                        UpsoledProductCard(
                            product: product,
                            selectionMode: closetSelectionMode,
                            isSelected: catalogSelectedIDs.contains(product.id)
                        ) {
                            if closetSelectionMode {
                                toggleCatalogSelection(product)
                            } else {
                                openCatalogDetail(product)
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
        .padding(.bottom, bottomInsetForClosetGrid)
    }

    private var unifiedStockListContent: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(filteredUnifiedStockSections) { section in
                ForEach(section.closetItems) { item in
                    closetListRow(item)
                        .id("\(item.id)-\(item.priceText ?? "")-\(item.purchasePriceText ?? "")-\(item.marketPriceJSON ?? "")")
                }

                ForEach(section.catalogProducts) { product in
                    catalogListRow(product)
                }
            }

            StockMarketplaceListLiveFooter()
        }
        .padding(.bottom, bottomInsetForClosetGrid)
    }

    @MainActor
    private func prefetchStockImages() async {
        // El giro 360° de los primeros zapatos se baja por adelantado: al abrirlos ya giran.
        let spinNames = activeClosetItems.filter { $0.category == .shoes }.prefix(14).map { [$0.catalogDisplayName, $0.name] }
        Task.detached(priority: .utility) {
            for names in spinNames { await Shoe360Loader.prefetch(titles: names) }
        }
        let listMaxSide: CGFloat = stockLayoutModeBinding.wrappedValue == .list ? 168 : 296
        let remoteMaxSide: CGFloat = stockLayoutModeBinding.wrappedValue == .list ? 168 : 296

        let closetPaths = stockClosetItemsExcludingCatalogDuplicates.map { ImageStore.displayRelativePath(for: $0) }
        let catalogURLs = stockCatalogProductsExcludingClosetDuplicates.compactMap(\.primaryImageURL)

        async let localPrefetch = StockImageLoader.prefetchLocalImages(
            relativePaths: closetPaths,
            maxSide: listMaxSide
        )
        async let remotePrefetch = StockImageLoader.prefetchURLImages(
            urls: catalogURLs,
            maxSide: remoteMaxSide
        )
        _ = await (localPrefetch, remotePrefetch)
    }

    @MainActor
    private func handleScannedCode(_ code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        scanLookupBusy = true
        defer { scanLookupBusy = false }
        scanLookupPayload = await StockScanLookupService.lookup(
            code: trimmed,
            stock: activeClosetItems
        )
    }

    private func toggleClosetSelection(_ item: ClosetItem) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if closetSelectedIDs.contains(item.id) {
                closetSelectedIDs.remove(item.id)
            } else {
                closetSelectedIDs.insert(item.id)
            }
        }
    }

    private func toggleCatalogSelection(_ product: UpsoledProduct) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if catalogSelectedIDs.contains(product.id) {
                catalogSelectedIDs.remove(product.id)
            } else {
                catalogSelectedIDs.insert(product.id)
            }
        }
    }

    private func stockListBrandLine(_ brand: String?) -> String {
        let trimmed = brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.lowercased() != "unknown brand" else {
            return "Unknown Brand"
        }
        return trimmed
    }

    private func closetListRow(_ item: ClosetItem) -> some View {
        let selected = closetSelectedIDs.contains(item.id)
        return StockMarketplaceListRow(
            brandLine: stockListBrandLine(item.brand),
            nameLine: item.catalogDisplayName,
            sizeLabel: item.cardSizeLabel,
            fallbackPrice: item.cardPriceLabel,
            marketPrice: item.marketPrice,
            marketplaceSegment: StockCategoryMarketplaceCatalog.segment(for: item),
            preferredPlatform: stockFilters.preferredMarketplacePlatform,
            stockValueUSD: item.stockValueUSD,
            purchaseUSD: item.purchaseValueUSD,
            askingUSD: ClosetItem.parsePriceUSD(from: item.priceText),
            profitUSD: item.cardProfitUSDLabel,
            profitPct: item.cardProfitPercentLabel,
            isLoss: item.isProjectedLoss,
            showProfitBadge: item.hasPricingForProfit,
            selectionMode: closetSelectionMode,
            isSelected: selected
        ) {
            if closetSelectionMode {
                toggleClosetSelection(item)
            } else {
                garmentDetailItemID = item.id
                ClosetAnalytics.named("closet_item_detail_open")
            }
        } image: {
            ClosetDiskThumbnail(
                relativePath: ImageStore.displayRelativePath(for: item),
                maxPixelSide: 168,
                fillFrame: false
            )
        }
    }

    private func catalogListRow(_ product: UpsoledProduct) -> some View {
        let selected = catalogSelectedIDs.contains(product.id)
        return StockMarketplaceListRow(
            brandLine: stockListBrandLine(product.brand),
            nameLine: product.name,
            sizeLabel: product.cardSizeLabel,
            fallbackPrice: product.cardPriceLabel,
            marketPrice: nil,
            marketplaceSegment: StockCategoryMarketplaceCatalog.segment(for: product),
            preferredPlatform: stockFilters.preferredMarketplacePlatform,
            stockValueUSD: product.stockValueUSD,
            purchaseUSD: product.purchaseCostUSD,
            askingUSD: product.price,
            profitUSD: product.cardProfitUSDLabel,
            profitPct: product.cardProfitPercentLabel,
            isLoss: product.isProjectedLoss,
            showProfitBadge: product.hasPricingForProfit,
            selectionMode: closetSelectionMode,
            isSelected: selected
        ) {
            if closetSelectionMode {
                toggleCatalogSelection(product)
            } else {
                openCatalogDetail(product)
            }
        } image: {
            StockCachedRemoteImage(
                url: product.primaryImageURL,
                maxPixelSide: 168,
                fillFrame: false
            )
        }
    }

    private var draftResumeBanner: some View {
        Button {
            let decoded = ClosetLocalDraftStore.decoded()
            addFlow.resumePersistedDrafts(decoded: decoded)
            openAddStockFlow(openPipeline: true)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Draft items")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(draftBannerCount) pending items")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.92))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 36)
    }

    private func closetCell(_ item: ClosetItem) -> some View {
        let selected = closetSelectedIDs.contains(item.id)
        return VStack(spacing: 9) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color.white

                    ClosetDiskThumbnail(
                        relativePath: ImageStore.displayRelativePath(for: item),
                        maxPixelSide: 296,
                        fillFrame: false
                    )
                        .padding(4)

                    VStack {
                        Spacer()
                        HStack(alignment: .bottom) {
                            if let size = item.cardSizeLabel {
                                Text(size)
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.black.opacity(0.78)))
                            }
                            Spacer(minLength: 4)
                            if let price = item.cardPriceLabel {
                                Text(price)
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.black.opacity(0.78)))
                            }
                        }
                        .padding(8)
                    }
                    .allowsHitTesting(false)

                    if closetSelectionMode {
                        Color.black.opacity(selected ? 0.12 : 0)
                            .animation(.easeInOut(duration: 0.18), value: selected)

                        VStack {
                            HStack {
                                Spacer()
                                ZStack {
                                    Circle()
                                        .fill(selected ? Color.black : Color.white.opacity(0.95))
                                        .frame(width: 28, height: 28)
                                        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
                                    if !selected {
                                        Circle().stroke(Color.black.opacity(0.35), lineWidth: 1.5)
                                            .frame(width: 28, height: 28)
                                    } else {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(Color.white)
                                    }
                                }
                                .padding(8)
                            }
                            Spacer()
                        }
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.18), value: selected)
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                if item.hasPricingForProfit, !closetSelectionMode {
                    closetProfitCornerBadge(item)
                        .offset(x: 2, y: -10)
                }
            }
            .frame(maxWidth: .infinity)

            let brandLine = item.brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Text(brandLine.isEmpty ? "Unknown Brand" : brandLine)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(Color.black.opacity(0.55))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            if let sku = item.cardSKULabel {
                Text(sku)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }

            Text(item.catalogDisplayName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.88))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if closetSelectionMode {
                toggleClosetSelection(item)
            } else {
                garmentDetailItemID = item.id
                ClosetAnalytics.named("closet_item_detail_open")
            }
        }
        .contextMenu {
            if !closetSelectionMode {
                Button {
                    closetSelectionMode = true
                    toggleClosetSelection(item)
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    removalRequest = StockRemovalRequest(closetIDs: [item.id], catalogIDs: [])
                } label: {
                    Label(L10n.tr("closet.removeItem"), systemImage: "trash")
                }
            }
        }
    }

    @MainActor
    private func prefetchStockMarketPrices() async {
        guard !marketPrefetchBusy else { return }
        let candidates = filteredActiveClosetItems
            .filter { $0.marketPriceNeedsRefresh && $0.hasStyleForMarketLookup }
            .prefix(24)
        guard !candidates.isEmpty else { return }

        marketPrefetchBusy = true
        defer { marketPrefetchBusy = false }

        for item in candidates {
            guard !Task.isCancelled else { break }
            do {
                let estimate = try await PieceMarketPrice.lookupForItem(
                    item,
                    useWebSearch: false
                )
                item.applyMarketPrice(estimate)
                try? modelContext.save()
            } catch {
                continue
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    }

    @ViewBuilder
    private func closetProfitCornerBadge(_ item: ClosetItem) -> some View {
        StockProfitCornerBadge(
            usdLabel: item.cardProfitUSDLabel,
            pctLabel: item.cardProfitPercentLabel,
            isLoss: item.isProjectedLoss
        )
    }
}

// MARK: - Producto 360° (cualquier categoría · galería o captura guiada)

/// Pantalla puente: categoría, nombre + `ShoeMultiAngleCaptureView`.
struct ClosetShoe360FlowView: View {
    var prefilledCapturedInCanonicalOrder: [UIImage]? = nil
    var initialCategory: ClothingCategory = .shoes

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var productCategory: ClothingCategory
    @State private var productName: String

    init(
        prefilledCapturedInCanonicalOrder: [UIImage]? = nil,
        initialCategory: ClothingCategory = .shoes
    ) {
        self.prefilledCapturedInCanonicalOrder = prefilledCapturedInCanonicalOrder
        self.initialCategory = initialCategory
        _productCategory = State(initialValue: initialCategory)
        _productName = State(initialValue: initialCategory == .shoes ? "Shoes" : "New product")
    }

    private var trimmedName: String {
        let t = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "New product" : t
    }

    private var isPrivateFlow: Bool { prefilledCapturedInCanonicalOrder == nil }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    isPrivateFlow
                        ? "Choose the product type, then capture front, right side, back, and left. AI generates professional white-background catalog photos for each angle."
                        : "Photos were taken in the order you chose in the gallery — tap an angle to correct it."
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Product type")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                    Menu {
                        ForEach(ClothingCategory.allCases, id: \.rawValue) { cat in
                            Button {
                                productCategory = cat
                            } label: {
                                Text("\(cat.emoji) \(cat.displayName)")
                            }
                        }
                    } label: {
                        HStack {
                            Text("\(productCategory.emoji) \(productCategory.displayName)")
                                .foregroundStyle(Color.black)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(Color.black.opacity(0.42))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground)))
                    }
                }

                TextField("Product name", text: $productName)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)

            ShoeMultiAngleCaptureView(
                garmentName: trimmedName,
                productCategory: productCategory,
                prefilledCapturedInAngleOrder: prefilledCapturedInCanonicalOrder,
                showsCloseButton: false,
                onOrderedPathsCommitted: saveToCloset
            )
            .id("\(prefilledCapturedInCanonicalOrder?.count.description ?? "private")-\(productCategory.rawValue)")
        }
        .navigationTitle(isPrivateFlow ? "Product · 360° studio" : "360° from gallery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.tr("common.close")) { dismiss() }
                    .foregroundStyle(Color.black)
            }
        }
        .preferredColorScheme(.light)
        .background(Color.white)
    }

    private func saveToCloset(paths: [String]) {
        guard paths.count == ShoeAngle.allCases.count else { return }
        let frontIdx = ShoeAngle.front.rawValue
        let imageFile = paths.indices.contains(frontIdx) ? paths[frontIdx] : paths[0]

        var paletteJSON: String?
        if let ui = ImageStore.load(imageFile) {
            let hexes = ColorPaletteExtractor.extract(from: ui, count: 5)
            if let data = try? JSONEncoder().encode(hexes),
               let s = String(data: data, encoding: .utf8) {
                paletteJSON = s
            }
        }

        let row = ClosetItem(
            name: trimmedName,
            brand: "Unknown Brand",
            priceText: nil,
            colorPaletteJSON: paletteJSON,
            dressCodesRaw: nil,
            seasonsRaw: nil,
            aiColorsJSON: nil,
            multiAngleFilenamesJSON: nil,
            galleryCoverRelativePath: imageFile,
            category: productCategory,
            imageFilename: imageFile,
            originalCropFilename: nil,
            sourceOutfitFilename: nil,
            boundingBox: nil,
            isDraft: false
        )
        row.multiAngleFilenames = paths
        modelContext.insert(row)
        try? modelContext.save()
        Task {
            await enrichSavedProductMetadata(row: row, coverPath: imageFile)
        }
        ClosetAnalytics.named(
            isPrivateFlow ? "closet_product360_private_saved" : "closet_product360_gallery_saved",
            params: "cat:\(productCategory.rawValue)"
        )
        dismiss()
    }

    @MainActor
    private func enrichSavedProductMetadata(row: ClosetItem, coverPath: String) async {
        guard GeminiService.apiKeyConfigured else { return }
        do {
            let meta = try await GeminiService.shared.enrichGarmentMetadata(
                cropRelativePath: coverPath,
                category: row.category,
                provisionalName: row.name
            )
            if !meta.brand.isEmpty { row.brand = meta.brand }
            if row.category == .shoes, !meta.sku.isEmpty {
                row.skuText = meta.sku.uppercased()
                let split = SneakerSKU.splitNameAndSKU(from: row.name)
                if split.sku != nil, !split.name.isEmpty {
                    row.name = split.name
                }
            }
            if !meta.sizeText.isEmpty { row.sizeText = meta.sizeText }
            if !meta.colorLabel.isEmpty { row.colorLabel = meta.colorLabel }
            if !meta.productDescription.isEmpty { row.productDescription = meta.productDescription }
            if !meta.priceText.isEmpty { row.priceText = meta.priceText }
            if !meta.listingPlatforms.isEmpty { row.listingPlatforms = meta.listingPlatforms }
            try? modelContext.save()
        } catch {
            // Metadatos opcionales al guardar producto directo.
        }
    }
}

// MARK: - Ropa / complementos · lookbook (entradas paralelas sin outfit)

struct ClosetGarmentLookbookStandaloneFlowView: View {
    /// Categorías con lookbook tipo catálogo; el calzado sigue usando «Zapatos solo tuyos (360°)».
    private static let categoryChoices: [ClothingCategory] = ClothingCategory.allCases.filter { $0 != .shoes }

    /// Miniatura válida sólo hasta guardar la primera foto de IA de estudio — se borra si el usuario abandona antes.
    private static func provisionalPlaceholderCropPath() throws -> String {
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw NSError(domain: "ClosetGarmentLookbookStandalone", code: -1)
        }
        return try ImageStore.save(
            data,
            inFolder: "crops",
            filename: "pending_lookbook_\(UUID().uuidString.lowercased()).jpg")
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var garmentName = ""
    @State private var category: ClothingCategory = .tops
    @State private var draftRow: ClosetItem?

    private var trimmedName: String {
        let t = garmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "New item" : t
    }

    var body: some View {
        Group {
            if let row = draftRow {
                GarmentLookbookCaptureView(
                    item: row,
                    onAbortStandaloneDraftNotYetSaved: abandonStandaloneDraft
                )
            } else {
                garmentLookbookIntroForm
            }
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var garmentLookbookIntroForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    "Shirts, pants, socks, and belts use this flow instead of shoes "
                        + "(360° view is separate). After creating the item you'll take 5 photos of your piece front, back, and details; "
                        + "Gemini will create catalog views (white background) plus lifestyle scenes."
                )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.52))

                TextField("Name (e.g. blue denim shirt)", text: $garmentName)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.black)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Item type").font(.subheadline.weight(.semibold))
                    Menu {
                        ForEach(Self.categoryChoices, id: \.rawValue) { cat in
                            Button {
                                category = cat
                            } label: {
                                HStack {
                                    Text("\(cat.emoji) \(cat.displayName)")
                                    Spacer(minLength: 8)
                                    if cat == category {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("\(category.emoji) \(category.displayName)")
                                .foregroundStyle(Color.black)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(Color.black.opacity(0.42))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
                    }
                }

                Button {
                    guard draftRow == nil else { return }
                    do {
                        let path = try Self.provisionalPlaceholderCropPath()
                        let row = ClosetItem(
                            name: trimmedName,
                            brand: "Unknown Brand",
                            category: category,
                            imageFilename: path,
                            originalCropFilename: path,
                            isDraft: false
                        )
                        modelContext.insert(row)
                        try? modelContext.save()
                        draftRow = row
                        ClosetAnalytics.named("closet_ropa_lookbook_draft_started", params: "cat:\(category.rawValue)")
                    } catch {
                        // Silenciar; siguiente intento válido
                    }
                } label: {
                    Label("Go to 5 photos", systemImage: "camera.aperture")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black))
                }
                .padding(.top, 6)
            }
            .padding(20)
        }
        .navigationTitle("Apparel — lookbook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.tr("common.close")) { dismiss() }
                    .foregroundStyle(Color.black)
            }
        }
    }

    private func abandonStandaloneDraft(_ item: ClosetItem) {
        ImageStore.deleteIfExists(item.imageFilename)
        if let oc = item.originalCropFilename { ImageStore.deleteIfExists(oc) }
        for p in item.lookbookStudio { ImageStore.deleteIfExists(p) }
        for p in item.lookbookLifestyle { ImageStore.deleteIfExists(p) }
        modelContext.delete(item)
        try? modelContext.save()
        ClosetAnalytics.named("closet_ropa_lookbook_draft_abort")
    }
}

// MARK: - Pipeline fullscreen

struct AddToClosetPipelineView: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var flow: AddToClosetFlowViewModel

    @State private var savingAll = false
    @State private var editingPieceId: UUID?
    /// Caché de estimación de precio por pieza (resultado de OpenAI).
    @State private var priceEstimates: [UUID: PieceMarketPrice] = [:]
    /// IDs de piezas con consulta en curso.
    @State private var priceLookupBusy: Set<UUID> = []
    @AppStorage("openaiAPIKey") private var openaiAPIKey: String = ""
    @State private var editNameDraft = ""
    @State private var categoryPickerPieceID: UUID?
    @State private var shoe360DraftSheetPieceID: Shoe360DraftSheetPieceID?
    @State private var prettifyBusy = Set<UUID>()
    /// Sheet 360° mostrado automáticamente al menos una vez por pieza; se resetea si completas ángulos o cambias categoría.
    @State private var offeredShoe360DraftWizardPieceIDs = Set<UUID>()
    /// Retaso único ante varios cambios seguidos en el borrador.
    @State private var shoe360WizardDelayTask: Task<Void, Never>?
    /// Micro-animación al guardar todas (efecto de escala solicitado).
    @State private var saveAllBump = false

    /// Gemini u OpenAI: al menos uno habilita el lote «Generar» (Prettify intenta Gemini primero).
    private var studioBatchAvailable: Bool {
        GeminiService.apiKeyConfigured
    }

    private var shoePiecesAutoWizardFingerprint: String {
        flow.pieces
            .map { "\($0.id.uuidString)|\($0.category?.rawValue ?? "-")|\($0.shoe360Complete)|\($0.name)" }
            .sorted()
            .joined(separator: ";")
    }

    /// Hay zapatos en revisión pendientes del flujo guiado de 4 ángulos.
    private var hasIncompleteShoesInReview: Bool {
        flow.phase == .review &&
            flow.pieces.contains(where: { $0.category == .shoes && !$0.shoe360Complete })
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !flow.uploadRows.isEmpty {
                        uploadingSection
                    }
                    if flow.phase == .review, !flow.pieces.isEmpty {
                        reviewSection
                    }
                    if flow.phase == .idle, flow.uploadRows.isEmpty, flow.pieces.isEmpty {
                        idleHint
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Review items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    closePipelineTapped()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await flow.generateAllStudio() }
                } label: {
                    HStack(spacing: 5) {
                        if flow.isGeneratingStudioBatch {
                            ProgressView().scaleEffect(0.82).tint(.white)
                            Text("Generating…")
                        } else {
                            Image(systemName: "sparkles")
                            Text(flow.studioBatchInvocationFinished ? "Regenerar ✨" : "Generar ✨")
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black))
                }
                .disabled(
                    flow.phase != .review || flow.pieces.isEmpty || flow.isGeneratingStudioBatch
                        || !studioBatchAvailable)

                Button {
                    Task { await saveAllTapped() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                        Text("Add all")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        flow.canSaveAll && !flow.isGeneratingStudioBatch ? Color.black : Color(.tertiaryLabel)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(flow.canSaveAll && !flow.isGeneratingStudioBatch ? Color(.secondarySystemBackground) : Color(.tertiarySystemFill))
                    )
                }
                .disabled(!flow.canSaveAll || savingAll || flow.isGeneratingStudioBatch)
                .scaleEffect(saveAllBump ? 0.96 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.66), value: saveAllBump)
            }
        }
        .alert("Item name", isPresented: Binding(
            get: { editingPieceId != nil },
            set: { if !$0 { editingPieceId = nil } }
        )) {
            TextField("Nombre", text: $editNameDraft)
            Button("Save") {
                guard let id = editingPieceId, let ix = flow.pieces.firstIndex(where: { $0.id == id }) else { return }
                flow.pieces[ix].name = editNameDraft
                editingPieceId = nil
            }
            Button("Cancel", role: .cancel) { editingPieceId = nil }
        }
        .sheet(isPresented: Binding(
            get: { categoryPickerPieceID != nil },
            set: { if !$0 { categoryPickerPieceID = nil } }
        )) {
            if let cid = categoryPickerPieceID {
                categoryPickerSheet(pieceID: cid)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $shoe360DraftSheetPieceID) { token in
            NavigationStack {
                ShoeMultiAngleCaptureView(
                    garmentName:
                        flow.pieces.first(where: { $0.id == token.pieceID })?.name ?? "Product",
                    productCategory: flow.pieces.first(where: { $0.id == token.pieceID })?.category ?? .shoes
                ) { paths in
                    flow.applyShoe360Catalog(orderedPrettyPaths: paths, pieceID: token.pieceID)
                }
            }
            .presentationDragIndicator(.visible)
            .presentationDetents([.large])
        }
        .toastOverlay(
            message: Binding(
                get: { flow.toast },
                set: { flow.toast = $0 }
            ))
        .onChange(of: shoePiecesAutoWizardFingerprint) { _, _ in
            queueAutoShoe360WizardDeferred()
        }
        .onAppear {
            queueAutoShoe360WizardDeferred()
        }
        .onChange(of: categoryPickerPieceID) { _, id in
            if id == nil {
                queueAutoShoe360WizardDeferred()
            }
        }
    }

    private func closePipelineTapped() {
        shoe360WizardDelayTask?.cancel()
        shoe360WizardDelayTask = nil
        if !flow.pieces.isEmpty {
            flow.persistPiecesForLater()
        }
        flow.clearEphemeralPresentationState()
        isPresented = false
        dismiss()
    }

    private func queueAutoShoe360WizardDeferred() {
        shoe360WizardDelayTask?.cancel()
        shoe360WizardDelayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled else { return }
            defer { shoe360WizardDelayTask = nil }
            guard flow.phase == .review else { return }
            guard shoe360DraftSheetPieceID == nil, categoryPickerPieceID == nil else { return }
            for piece in flow.pieces where piece.shoe360Complete {
                offeredShoe360DraftWizardPieceIDs.remove(piece.id)
            }
            guard let candidate = flow.pieces.first(where: {
                $0.category == .shoes &&
                    !$0.shoe360Complete &&
                    !offeredShoe360DraftWizardPieceIDs.contains($0.id)
            }) else { return }
            offeredShoe360DraftWizardPieceIDs.insert(candidate.id)
            shoe360DraftSheetPieceID = Shoe360DraftSheetPieceID(pieceID: candidate.id)
        }
    }

    @ViewBuilder
    private var idleHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "tshirt.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.black.opacity(0.18))
            Text("Detected items will appear here after you choose your photos.")
                .multilineTextAlignment(.center)
                .foregroundStyle(ClosetFlowPalette.secondaryText)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private var uploadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.black)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(flow.uploadRows) { row in
                    ZStack {
                        Image(uiImage: row.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 100)
                            .clipped()
                            .cornerRadius(12)

                        if !row.finished {
                            Color.white.opacity(0.5)
                            ProgressView().tint(.black)
                        }
                    }
                    .aspectRatio(0.92, contentMode: .fit)
                    .cornerRadius(12)
                }
            }
        }
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.97).combined(with: .opacity),
                removal: .opacity))
        .animation(.spring(response: 0.52, dampingFraction: 0.82), value: flow.uploadRows.count)
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.black)

            if hasIncompleteShoesInReview {
                HStack(alignment: .top, spacing: 10) {
                    Text("👞")
                        .font(.system(size: 20))
                    Text(
                        "For shoes, the app will open the 360° view with 4 guided photos "
                            + "(frontal, lateral derecho, trasera y lateral izquierdo)."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                }
            }

            ForEach(Array(flow.pieces.enumerated()), id: \.element.id) { _, piece in
                pieceCard(piece)
                    .transition(
                        .asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity))
            }
            .animation(.spring(response: 0.52, dampingFraction: 0.84), value: flow.pieces.map(\.id))
        }
    }

    private func pieceCard(_ piece: ClosetDraftPiece) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                thumb(for: piece)
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        editingPieceId = piece.id
                        editNameDraft = piece.name
                    } label: {
                        HStack(spacing: 6) {
                            Text(piece.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.black)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.42))
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)

                    brandField(
                        Binding(
                            get: {
                                if let ix = flow.pieces.firstIndex(where: { $0.id == piece.id }) {
                                    return flow.pieces[ix].brand
                                }
                                return ""
                            },
                            set: { newVal in
                                guard let ix = flow.pieces.firstIndex(where: { $0.id == piece.id }) else { return }
                                flow.pieces[ix].brand = newVal
                            }))

                    Divider().foregroundStyle(Color.black.opacity(0.06))

                    categoryRow(piece)

                    draftPricingFields(piece)
                }
            }

            HStack(spacing: 10) {
                if piece.category == .shoes {
                    miniPill(
                        title: piece.shoe360Complete ? "Edit 360° view" : "360° view 👞",
                        foreground: Color.black.opacity(0.88),
                        background: ClosetFlowPalette.mutedBackground
                    ) {
                        shoe360DraftSheetPieceID = Shoe360DraftSheetPieceID(pieceID: piece.id)
                    }
                    .opacity(flow.generatingPieceIDs.contains(piece.id) ? 0.35 : 1)
                    .disabled(flow.generatingPieceIDs.contains(piece.id))
                } else {
                    miniPill(
                        title: prettifyBusy.contains(piece.id) ? "… Prettify" : "Prettify ✨",
                        foreground: Color.black.opacity(0.88),
                        background: ClosetFlowPalette.mutedBackground
                    ) {
                        prettifyBusy.insert(piece.id)
                        Task {
                            await flow.prettify(pieceID: piece.id)
                            prettifyBusy.remove(piece.id)
                        }
                    }
                    .opacity(prettifyBlocked(piece) ? 0.35 : 1)
                    .disabled(prettifyBlocked(piece))
                }

                miniPill(title: "Add ✓", foreground: Color.white, background: Color.black) {
                    do {
                        try flow.insertOne(pieceID: piece.id, modelContext: modelContext)
                    } catch {
                        flow.showToast(error.localizedDescription)
                    }
                }
                .opacity(piece.category != nil && piece.isCatalogImageReady ? 1 : 0.35)
                .disabled(piece.category == nil || !piece.isCatalogImageReady)
            }

            if piece.prettifyFailedBadge {
                Text("Generation failed")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(ClosetFlowPalette.destructive)
            } else if flow.phase == .review, piece.prettifiedRelativePath == nil,
                      piece.category != .shoes,
                      !flow.generatingPieceIDs.contains(piece.id)
            {
                Text("Not generated")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
            }

            if piece.category == .shoes, !piece.shoe360Complete,
               !flow.generatingPieceIDs.contains(piece.id)
            {
                Text("Shoes: capture front, right, back, and left before saving.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ClosetFlowPalette.destructive.opacity(0.92))
            }

            // Estimación de precio de mercado con OpenAI
            priceEstimateRow(piece)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                flow.removeDraftPiece(id: piece.id)
                prettifyBusy.remove(piece.id)
                offeredShoe360DraftWizardPieceIDs.remove(piece.id)
                if editingPieceId == piece.id {
                    editingPieceId = nil
                }
                if categoryPickerPieceID == piece.id {
                    categoryPickerPieceID = nil
                }
                if shoe360DraftSheetPieceID?.pieceID == piece.id {
                    shoe360DraftSheetPieceID = nil
                }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ClosetFlowPalette.destructive)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove from draft")
            .padding(8)
        }
    }

    private func draftPricingFields(_ piece: ClosetDraftPiece) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pricing")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.45))

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paid")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.45))
                    TextField("Purchase", text: Binding(
                        get: {
                            flow.pieces.first(where: { $0.id == piece.id })?.purchasePriceText ?? ""
                        },
                        set: { newVal in
                            guard let ix = flow.pieces.firstIndex(where: { $0.id == piece.id }) else { return }
                            flow.pieces[ix].purchasePriceText = newVal
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Asking")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.45))
                    TextField("Listing", text: Binding(
                        get: {
                            flow.pieces.first(where: { $0.id == piece.id })?.priceText ?? ""
                        },
                        set: { newVal in
                            guard let ix = flow.pieces.firstIndex(where: { $0.id == piece.id }) else { return }
                            flow.pieces[ix].priceText = newVal
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                }
            }
        }
    }

    private func prettifyBlocked(_ piece: ClosetDraftPiece) -> Bool {
        prettifyBusy.contains(piece.id) || flow.generatingPieceIDs.contains(piece.id)
    }

    // MARK: - Estimación de precio con OpenAI

    @ViewBuilder
    private func priceEstimateRow(_ piece: ClosetDraftPiece) -> some View {
        let isBusy = priceLookupBusy.contains(piece.id)
        let canQuery = !piece.name.trimmingCharacters(in: .whitespaces).isEmpty

        if let est = priceEstimates[piece.id] {
            // Resultado: card más rica con gráfico + cambio %
            priceResultCard(est, piece: piece, isBusy: isBusy)
        } else if isBusy {
            // Loading
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color(red: 0.20, green: 0.45, blue: 0.85))
                Text("Fetching market price…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.60))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
            }
        } else {
            // CTA inicial
            Button {
                Task { await runPriceLookup(for: piece) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 13, weight: .bold))
                    Text("Look up market price")
                        .font(.system(size: 13, weight: .bold))
                    Spacer(minLength: 0)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.30, green: 0.55, blue: 0.95),
                                    Color(red: 0.14, green: 0.36, blue: 0.85),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.30), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(!canQuery)
            .opacity(canQuery ? 1 : 0.45)
        }
    }

    /// Campo inline para que el usuario introduzca su talla y refresque la consulta.
    /// Actualiza `flow.pieces[idx].sizeText`, así la talla se persiste con la pieza.
    private func sizeFilterField(piece: ClosetDraftPiece, isBusy: Bool) -> some View {
        let binding = Binding<String>(
            get: { piece.sizeText },
            set: { newValue in
                if let idx = flow.pieces.firstIndex(where: { $0.id == piece.id }) {
                    flow.pieces[idx].sizeText = newValue
                }
            }
        )
        return HStack(spacing: 8) {
            Image(systemName: "ruler")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.85))
            Text("TALLA")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color.black.opacity(0.45))
            TextField("US 10 · EU 44 · 10.5", text: binding)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .onSubmit {
                    Task { await runPriceLookup(for: piece) }
                }
            if !piece.sizeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await runPriceLookup(for: piece) }
                } label: {
                    Text("Aplicar")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(Color(red: 0.20, green: 0.45, blue: 0.85))
                        }
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.18), lineWidth: 1)
                }
        }
    }

    private func priceResultCard(_ est: PieceMarketPrice, piece: ClosetDraftPiece, isBusy: Bool) -> some View {
        let sizeBinding = Binding<String>(
            get: { piece.sizeText },
            set: { newValue in
                if let idx = flow.pieces.firstIndex(where: { $0.id == piece.id }) {
                    flow.pieces[idx].sizeText = newValue
                }
            }
        )
        return ShoeMarketPriceCardView(
            estimate: est,
            sizeText: sizeBinding,
            isBusy: isBusy,
            onRefresh: { Task { await runPriceLookup(for: piece) } },
            onApplySize: { Task { await runPriceLookup(for: piece) } },
            onApplyMarketPrice: {
                guard let idx = flow.pieces.firstIndex(where: { $0.id == piece.id }) else { return }
                flow.pieces[idx].priceText = PieceMarketPrice.formatUSD(est.avg)
                flow.persistPiecesForLater()
            }
        )
    }

    private func runPriceLookup(for piece: ClosetDraftPiece) async {
        // Reúne posibles queries: SKU explícito, SKU detectado en el nombre, nombre del modelo.
        let typedSKU = piece.skuText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let extractedSKU = SneakerSKU.extract(from: piece.name)?.uppercased() ?? ""
        let cleanName = piece.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let brand = piece.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let composedName: String = {
            if cleanName.isEmpty { return brand }
            if brand.isEmpty || cleanName.lowercased().contains(brand.lowercased()) {
                return cleanName
            }
            return "\(brand) \(cleanName)"
        }()

        // Query principal: SKU si lo hay (mejor precisión), si no el nombre.
        let primaryQuery: String = {
            if !typedSKU.isEmpty { return typedSKU }
            if !extractedSKU.isEmpty { return extractedSKU }
            return composedName
        }()
        // Query de fallback (lo que use GOAT si por SKU no encuentra).
        let fallbackQuery: String? = {
            // Si el principal ya es el nombre, no hace falta fallback.
            if primaryQuery == composedName { return nil }
            return composedName.isEmpty ? nil : composedName
        }()

        guard !primaryQuery.isEmpty else {
            await MainActor.run {
                flow.showToast("Add a name or SKU to look up market price.")
            }
            return
        }

        priceLookupBusy.insert(piece.id)
        defer { priceLookupBusy.remove(piece.id) }

        // 1) Intenta KicksDB primero — consulta StockX + GOAT en paralelo.
        //    Pasamos el nombre del modelo como query secundaria porque GOAT a menudo
        //    no encuentra por SKU pero sí por nombre.
        if KicksDBClient.isConfigured {
            // Talla del usuario: si la ha rellenado, la pasamos para que filtre por esa.
            let size = piece.sizeText.trimmingCharacters(in: .whitespacesAndNewlines)
            let sizeQuery: String? = size.isEmpty ? nil : size

            do {
                if let estimate = try await KicksDBClient.fetchAggregated(query: primaryQuery, fallbackQuery: fallbackQuery, sizeQuery: sizeQuery) {
                    await MainActor.run {
                        priceEstimates[piece.id] = estimate
                    }
                    return
                }
                // KicksDB respondió pero ninguna plataforma encontró el producto → cae a OpenAI
            } catch {
                // KicksDB falló (rate limit, error red, etc.) → cae a OpenAI con aviso
                await MainActor.run {
                    flow.showToast("KicksDB: \(error.localizedDescription) · usando OpenAI")
                }
            }
        }

        // 2) Fallback: OpenAI con web_search (más caro pero siempre disponible)
        do {
            let estimate = try await PieceMarketPrice.fetchStyleFromInternet(
                styleCode: primaryQuery,
                brand: piece.brand.isEmpty ? nil : piece.brand,
                category: piece.category?.displayName ?? "Shoes",
                sizeText: piece.sizeText.isEmpty ? nil : piece.sizeText,
                apiKey: openaiAPIKey,
                useWebSearch: true
            )
            await MainActor.run {
                priceEstimates[piece.id] = estimate
                if let data = try? JSONEncoder().encode(estimate),
                   let json = String(data: data, encoding: .utf8),
                   let idx = flow.pieces.firstIndex(where: { $0.id == piece.id }) {
                    flow.pieces[idx].marketPriceJSON = json
                    if flow.pieces[idx].priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        flow.pieces[idx].priceText = PieceMarketPrice.formatUSD(estimate.avg)
                    }
                }
            }
        } catch {
            await MainActor.run {
                flow.showToast("Market price: \(error.localizedDescription)")
            }
        }
    }

    private func formatEUR(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: amount)) ?? "\(amount)")
    }

    private func thumb(for piece: ClosetDraftPiece) -> some View {
        let path = piece.prettifiedRelativePath ?? piece.originalCropRelativePath
        let busy = prettifyBusy.contains(piece.id) || flow.generatingPieceIDs.contains(piece.id)
        return ZStack {
            Color.white
            if let ui = StockImageLoader.cachedLocalImage(relativePath: path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                ProgressView().tint(.black)
            }
            if busy {
                Color.white.opacity(0.55)
                ProgressView().tint(.black)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func categoryRow(_ piece: ClosetDraftPiece) -> some View {
        Button {
            categoryPickerPieceID = piece.id
        } label: {
            if let cat = piece.category {
                HStack {
                    Text(cat.emoji).font(.system(size: 18))
                    Text(cat.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black)
                    Spacer()
                }
            } else {
                Text("Select category")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(ClosetFlowPalette.destructive)
            }
        }
        .buttonStyle(.plain)
    }

    private func brandField(_ binding: Binding<String>) -> some View {
        TextField("Agregar marca", text: binding)
            .font(.system(size: 14))
            .foregroundStyle(Color.black.opacity(0.88))
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
            }
    }

    private func miniPill(
        title: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Capsule().fill(background))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func categoryPickerSheet(pieceID: UUID) -> some View {
        NavigationStack {
            List {
                ForEach(ClothingCategory.allCases, id: \.self) { cat in
                    Button {
                        if let ix = flow.pieces.firstIndex(where: { $0.id == pieceID }) {
                            let prev = flow.pieces[ix].category
                            flow.pieces[ix].category = cat
                            if prev == .shoes && cat != .shoes {
                                flow.discardDraftShoeAngles(at: ix)
                                offeredShoe360DraftWizardPieceIDs.remove(pieceID)
                            }
                            categoryPickerPieceID = nil
                        }
                    } label: {
                        HStack {
                            Text(cat.emoji).font(.system(size: 20))
                            Text(cat.displayName)
                                .foregroundStyle(Color.black)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { categoryPickerPieceID = nil }
                }
            }
        }
    }

    private func saveAllTapped() async {
        guard flow.canSaveAll else { return }
        savingAll = true
        saveAllBump = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { saveAllBump = false }

        defer { savingAll = false }
        do {
            try flow.insertAll(modelContext: modelContext)
            flow.resetClearingDraftFile()
            isPresented = false
            dismiss()
        } catch {
            flow.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Toast ligero

private struct ToastBannerModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func toastOverlay(message: Binding<String?>) -> some View {
        modifier(ToastBannerModifier(message: message))
    }
}

// MARK: - Estimación de precio de pieza (OpenAI)

struct PieceMarketPrice: Codable {
    let avg: Int
    let min: Int
    let max: Int
    /// 6 puntos cronológicos (de más antiguo a más reciente), en USD (combinado).
    let history: [Double]
    /// Desglose por plataforma cuando hay datos (StockX, GOAT, etc.). Vacío si la
    /// estimación viene de una sola fuente (p.ej. OpenAI fallback). No se persiste en JSON.
    let platforms: [PlatformPrice]
    /// Título del producto realmente emparejado en el marketplace (ej. "adidas Yeezy Boost 350 V2 Onyx").
    /// Permite al usuario ver si la búsqueda devolvió EXACTAMENTE su colorway.
    let matchedTitle: String?
    /// SKU del producto emparejado, si la fuente lo provee.
    let matchedSKU: String?
    /// Si los precios son de una talla concreta (ej. "10", "EU 43"), aquí se guarda
    /// para que la UI muestre "talla X" en lugar de "media".
    let sizeUsed: String?

    private enum CodingKeys: String, CodingKey {
        case avg, min, max, history
        case platforms, matchedTitle, matchedSKU, sizeUsed
    }

    init(avg: Int, min: Int, max: Int, history: [Double], platforms: [PlatformPrice] = [], matchedTitle: String? = nil, matchedSKU: String? = nil, sizeUsed: String? = nil) {
        self.avg = avg
        self.min = min
        self.max = max
        self.history = history
        self.platforms = platforms
        self.matchedTitle = matchedTitle
        self.matchedSKU = matchedSKU
        self.sizeUsed = sizeUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        avg = try container.decode(Int.self, forKey: .avg)
        min = try container.decode(Int.self, forKey: .min)
        max = try container.decode(Int.self, forKey: .max)
        history = try container.decode([Double].self, forKey: .history)
        platforms = try container.decodeIfPresent([PlatformPrice].self, forKey: .platforms) ?? []
        matchedTitle = try container.decodeIfPresent(String.self, forKey: .matchedTitle)
        matchedSKU = try container.decodeIfPresent(String.self, forKey: .matchedSKU)
        sizeUsed = try container.decodeIfPresent(String.self, forKey: .sizeUsed)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(avg, forKey: .avg)
        try container.encode(min, forKey: .min)
        try container.encode(max, forKey: .max)
        try container.encode(history, forKey: .history)
        if !platforms.isEmpty {
            try container.encode(platforms, forKey: .platforms)
        }
        try container.encodeIfPresent(matchedTitle, forKey: .matchedTitle)
        try container.encodeIfPresent(matchedSKU, forKey: .matchedSKU)
        try container.encodeIfPresent(sizeUsed, forKey: .sizeUsed)
    }

    /// Cambio porcentual entre el primer y último punto del histórico.
    var changePercent: Double {
        guard history.count >= 2, let first = history.first, first > 0, let last = history.last else { return 0 }
        return ((last - first) / first) * 100
    }

    /// `true` si la tendencia es alcista.
    var isUp: Bool { changePercent >= 0 }
}

/// Datos de una plataforma concreta para el desglose de PieceMarketPrice.
struct PlatformPrice: Identifiable, Codable, Equatable {
    var id: String { name }
    let name: String      // "StockX", "GOAT"
    let avg: Int
    let history: [Double] // misma longitud que history del combinado

    var color: Color {
        Self.brandColor(for: name)
    }

    init(name: String, color: Color = .gray, avg: Int, history: [Double]) {
        self.name = name
        self.avg = avg
        self.history = history
    }

    static func brandColor(for name: String) -> Color {
        switch name.uppercased() {
        case "STOCKX":        return Color(red: 0.00, green: 0.60, blue: 0.30)
        case "GOAT", "ALIAS": return Color(red: 0.10, green: 0.10, blue: 0.10)
        case "FLIGHT CLUB":   return Color(red: 0.85, green: 0.10, blue: 0.15)
        case "EBAY":          return Color(red: 0.20, green: 0.45, blue: 0.85)
        case "GRAILED":       return Color.black
        case "TCG COLLECTOR": return Color(red: 0.12, green: 0.22, blue: 0.48)
        case "POSHMARK":      return Color(red: 0.47, green: 0.09, blue: 0.20)
        default:              return Color.gray
        }
    }
}

// MARK: - Platform breakdown UI

/// Badge con el "logo" estilizado de la plataforma (StockX / GOAT / Flight Club).
/// Usa una pastilla circular con el color de marca y la inicial de la plataforma
/// para que la fuente del precio sea obvia incluso sin assets externos.
struct PlatformBrandBadge: View {
    let name: String
    let color: Color
    var size: CGFloat = 18

    /// Carácter mostrado dentro de la insignia. Mantiene 1 char salvo para
    /// "FC" (Flight Club) que se ve mejor con 2 letras.
    private var glyph: String {
        switch name.uppercased() {
        case "STOCKX":      return "X"
        case "GOAT":        return "G"
        case "FLIGHT CLUB": return "FC"
        default:            return String(name.prefix(1)).uppercased()
        }
    }

    /// Color del texto dentro del badge: blanco sobre fondos oscuros, negro
    /// sobre el verde de StockX para mejor legibilidad.
    private var glyphColor: Color {
        name.uppercased() == "STOCKX" ? .black : .white
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(glyph)
                .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
                .foregroundStyle(glyphColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.35), radius: 3, y: 1)
    }
}

/// Pill por plataforma: logo + nombre + precio.
struct PlatformPriceTag: View {
    let platform: PlatformPrice
    let formatted: String

    var body: some View {
        HStack(spacing: 7) {
            PlatformBrandBadge(name: platform.name, color: platform.color, size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(platform.name.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.black.opacity(0.55))
                Text(formatted)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(platform.color.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(platform.color.opacity(0.30), lineWidth: 1)
                }
        }
        .shadow(color: platform.color.opacity(0.10), radius: 4, y: 1)
    }
}

/// Rich market price card shared by draft review and garment detail.
struct ShoeMarketPriceCardView: View {
    let estimate: PieceMarketPrice
    @Binding var sizeText: String
    var isBusy: Bool = false
    var lastUpdated: Date? = nil
    var onRefresh: () -> Void
    var onApplySize: () -> Void
    var onApplyMarketPrice: (() -> Void)? = nil

    private var tint: Color {
        estimate.isUp
            ? Color(red: 0.20, green: 0.70, blue: 0.45)
            : Color(red: 0.92, green: 0.30, blue: 0.30)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.30, green: 0.55, blue: 0.95), Color(red: 0.14, green: 0.36, blue: 0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("MARKET PRICE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.black.opacity(0.55))
                Spacer(minLength: 0)
                if let lastUpdated {
                    Text(lastUpdated, format: .relative(presentation: .named))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.38))
                }
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.10)))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }

            if let matched = estimate.matchedTitle, !matched.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.75))
                    Text(matched)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if let sku = estimate.matchedSKU, !sku.isEmpty {
                        Text("· \(sku)")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.4)
                            .foregroundStyle(Color.black.opacity(0.40))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, -2)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(PieceMarketPrice.formatUSD(estimate.avg))
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.92))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text(estimate.sizeUsed != nil
                            ? (StockSizeDisplay.cardLabel(from: estimate.sizeUsed) ?? "size \(estimate.sizeUsed!)")
                            : "average")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(Color.black.opacity(0.45))
                            .padding(.bottom, 4)
                    }
                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(red: 0.18, green: 0.65, blue: 0.40))
                            Text("From \(PieceMarketPrice.formatUSD(estimate.min))")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.70))
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.35))
                            Text("Up to \(PieceMarketPrice.formatUSD(estimate.max))")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.45))
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 3) {
                    Image(systemName: estimate.isUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .heavy))
                    Text(String(format: "%@%.1f%%",
                                estimate.isUp ? "+" : "",
                                estimate.changePercent))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(tint.opacity(0.14))
                }
            }

            marketSizeField

            PriceTrendSparkline(
                points: estimate.history,
                isUp: estimate.isUp,
                platforms: []
            )
            .frame(height: 48)

            if !estimate.platforms.isEmpty {
                HStack(spacing: 8) {
                    ForEach(estimate.platforms) { platform in
                        PlatformPriceTag(platform: platform, formatted: PieceMarketPrice.formatUSD(platform.avg))
                    }
                    Spacer(minLength: 0)
                }
            }

            if let onApplyMarketPrice, estimate.avg > 0 {
                Button(action: onApplyMarketPrice) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                        Text("Use \(PieceMarketPrice.formatUSD(estimate.avg)) as asking price")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.08), .clear],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.35),
                                Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.15),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .shadow(color: tint.opacity(0.12), radius: 14, y: 5)
            .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
        }
    }

    private var marketSizeField: some View {
        HStack(spacing: 6) {
            Text("🇺🇸U.S")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.72))
            TextField("11", text: $sizeText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .onSubmit(onApplySize)
            if !sizeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: onApplySize) {
                    Text("Apply")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(Color(red: 0.20, green: 0.45, blue: 0.85))
                        }
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.18), lineWidth: 1)
                }
        }
    }
}

extension PieceMarketPrice {

    /// Envoltura del endpoint /v1/responses. Tiene `output_text` con la respuesta final.
    private struct ResponsesEnvelope: Decodable {
        let output_text: String?
        struct OutputItem: Decodable {
            let type: String?
            let content: [ContentBlock]?
        }
        struct ContentBlock: Decodable {
            let type: String?
            let text: String?
        }
        let output: [OutputItem]?

        /// Devuelve el texto final, prefiriendo `output_text` y cayendo a recorrer `output`.
        var finalText: String? {
            if let t = output_text, !t.isEmpty { return t }
            return output?
                .flatMap { $0.content ?? [] }
                .compactMap { $0.text }
                .joined(separator: "\n")
                .nilIfEmpty
        }
    }

    private struct OAPriceJSON: Decodable {
        let avg_eur: Double
        let min_eur: Double
        let max_eur: Double
        let history_eur: [Double]?
    }

    /// Lee la API key desde el mismo sitio que el resto del proyecto:
    /// `OPENAI_API_KEY` del Info.plist (cargado del xcconfig). Cae a
    /// @AppStorage("openaiAPIKey") como respaldo si no está en el plist.
    static var resolvedAPIKey: String? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        let stored = UserDefaults.standard.string(forKey: "openaiAPIKey") ?? ""
        return stored.isEmpty ? nil : stored
    }

    private static var resolvedModel: String {
        if let m = Bundle.main.object(forInfoDictionaryKey: "OPENAI_MODEL") as? String {
            let t = m.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return "gpt-4o-mini"
    }

    /// Live web lookups work more reliably on gpt-4o than mini.
    private static var webSearchModel: String { "gpt-4o" }

    /// Tries the secure marketplace gateway, then OpenAI web search.
    @MainActor
    static func lookupForItem(
        _ item: ClosetItem,
        useWebSearch: Bool = true
    ) async throws -> PieceMarketPrice {
        let queries = item.marketLookupQueries
        guard !queries.isEmpty else {
            throw NSError(domain: "PieceMarketPrice", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Add a Style / SKU code (e.g. DD1391-101) to look up market price."
            ])
        }

        let primaryQuery = queries[0]
        let fallbackQuery: String? = queries.count > 1 ? queries[1] : nil
        let sizeQuery = item.sizeText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sizeFilter = (sizeQuery?.isEmpty == false) ? sizeQuery : nil

        if KicksDBClient.isConfigured {
            if let estimate = try await KicksDBClient.fetchAggregated(
                query: primaryQuery,
                fallbackQuery: fallbackQuery,
                sizeQuery: sizeFilter
            ) {
                return estimate
            }
        }

        guard useWebSearch else {
            let skuHint = item.resolvedSKU.map { " (\($0))" } ?? ""
            throw NSError(domain: "PieceMarketPrice", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No market price found\(skuHint). Use the real Style / SKU (e.g. AO4567-001), not an internal code."
            ])
        }

        let style = item.resolvedSKU ?? queries[0]
        return try await fetchStyleFromInternet(
            styleCode: style,
            brand: item.brand,
            category: item.category.displayName,
            sizeText: item.sizeText,
            useWebSearch: useWebSearch
        )
    }

    static func fetchStyleFromInternet(
        styleCode: String,
        brand: String?,
        category: String,
        sizeText: String? = nil,
        apiKey: String = "",
        useWebSearch: Bool = true
    ) async throws -> PieceMarketPrice {
        let style = styleCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !style.isEmpty else {
            throw NSError(domain: "PieceMarketPrice", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Style / SKU code is required."
            ])
        }

        let brandLine = brand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? "Brand: \(brand!.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            : ""
        let sizeLine = sizeText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? "Size: \(sizeText!.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            : ""

        let userPrompt = """
        Search the internet on StockX, GOAT, Flight Club, and eBay for this exact STYLE / SKU code:
        \(style)
        \(brandLine)\(sizeLine)Category: \(category)

        Use the style code in your web search. Return the current resale price range in USD for this exact colorway/style.
        """

        if useWebSearch {
            do {
                return try await fetchViaResponsesWebSearch(
                    query: userPrompt,
                    category: category,
                    key: try resolveEffectiveKey(fallback: apiKey),
                    styleCode: style
                )
            } catch {
                return try await fetchViaChatCompletions(
                    query: userPrompt,
                    category: category,
                    key: try resolveEffectiveKey(fallback: apiKey),
                    styleCode: style
                )
            }
        }

        return try await fetchViaChatCompletions(
            query: userPrompt,
            category: category,
            key: try resolveEffectiveKey(fallback: apiKey),
            styleCode: style
        )
    }

    /// Llama a OpenAI para estimar precio de mercado. Por defecto usa Chat Completions
    /// (más barato). Con `useWebSearch: true` intenta web search y cae a Chat si falla.
    static func fetchFromOpenAI(
        query: String,
        category: String,
        apiKey: String = "",
        useWebSearch: Bool = false
    ) async throws -> PieceMarketPrice {
        let effectiveKey = try resolveEffectiveKey(fallback: apiKey)

        if useWebSearch {
            do {
                return try await fetchViaResponsesWebSearch(
                    query: query,
                    category: category,
                    key: effectiveKey
                )
            } catch {
                return try await fetchViaChatCompletions(
                    query: query,
                    category: category,
                    key: effectiveKey
                )
            }
        }

        return try await fetchViaChatCompletions(
            query: query,
            category: category,
            key: effectiveKey
        )
    }

    private static func resolveEffectiveKey(fallback: String) throws -> String {
        if let k = resolvedAPIKey {
            return k
        }
        if !fallback.isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw NSError(domain: "PieceMarketPrice", code: 401, userInfo: [
            NSLocalizedDescriptionKey: "Missing OPENAI_API_KEY in DeveloperSettings.local.xcconfig"
        ])
    }

    private static func openAIError(statusCode: Int, data: Data) -> NSError {
        if statusCode == 429 {
            return NSError(domain: "OpenAI", code: 429, userInfo: [
                NSLocalizedDescriptionKey: "OpenAI quota exceeded. Check billing at platform.openai.com."
            ])
        }
        let bodyStr = String(data: data, encoding: .utf8) ?? ""
        return NSError(domain: "OpenAI", code: statusCode, userInfo: [
            NSLocalizedDescriptionKey: "HTTP \(statusCode) · \(bodyStr.prefix(160))"
        ])
    }

    /// Identifica un zapato O prenda de una foto con OpenAI (ChatGPT, gpt-4o visión).
    /// `corrections` son ejemplos de correcciones previas del usuario para que la IA aprenda.
    static func identifySneaker(in image: UIImage, corrections: String = "") async throws -> (model: String, sku: String) {
        guard let key = resolvedAPIKey, key.hasPrefix("sk-") else {
            throw NSError(domain: "OpenAI", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Falta la API key de OpenAI. Añádela en Ajustes (API key) o en DeveloperSettings.local.xcconfig."
            ])
        }
        // Reducimos la imagen para no enviar payloads enormes.
        let maxSide: CGFloat = 1024
        let scale = Swift.min(1, maxSide / Swift.max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "OpenAI", code: 400, userInfo: [NSLocalizedDescriptionKey: "No se pudo procesar la foto"])
        }
        let dataURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        var prompt = """
        You are a world-class expert in sneakers AND streetwear/clothing identification (StockX/GOAT/Grailed level).
        Identify the EXACT item in this photo. It can be a SNEAKER or a CLOTHING item (tee, hoodie, jacket, pants, etc.).
        - For sneakers: "model" = brand + silhouette + colorway (e.g. "Nike Dunk Low Viotech"); "sku" = official style code if visible/known (e.g. DH6927-100), else "".
        - For clothing: "model" = brand + item + colorway/collection (e.g. "Supreme Box Logo Hoodie Black FW23"); "sku" = "".
        Look carefully at logos, shape, materials, colorway and any tags. Be confident and ALWAYS return your single best guess — never refuse or say "unknown".
        Respond ONLY with JSON: {"model":"...","sku":"..."}.
        """
        if !corrections.isEmpty {
            prompt += "\n\n" + corrections
        }

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": dataURL]],
                ],
            ]],
            "response_format": ["type": "json_object"],
            "temperature": 0.2,
            "max_tokens": 200,
        ]
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw openAIError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, data: data)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String,
              let cdata = content.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: cdata) as? [String: Any]
        else { throw NSError(domain: "OpenAI", code: 502, userInfo: [NSLocalizedDescriptionKey: "Respuesta no válida de OpenAI"]) }
        let model = (obj["model"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sku = (obj["sku"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return (model, sku)
    }

    private static var priceInstructions: String {
        """
        You are a resale pricing analyst for sneakers and fashion. Search StockX, GOAT, and eBay \
        using the exact STYLE / SKU code provided (e.g. DD1391-101). Return ONLY a valid JSON \
        object (no markdown) with this exact shape:
        {"avg_eur": number, "min_eur": number, "max_eur": number, "history_eur": [number, number, number, number, number, number]}
        Even though fields are named `_eur`, values must be in USD. history_eur is 6 points from \
        oldest to newest (month -5 to current). Base prices on real listings for that exact style code.
        """
    }

    private static func fetchViaChatCompletions(
        query: String,
        category: String,
        key: String,
        styleCode: String? = nil
    ) async throws -> PieceMarketPrice {
        guard key.hasPrefix("sk-") else {
            throw NSError(domain: "PieceMarketPrice", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid key (must start with sk-)"
            ])
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 25

        let body: [String: Any] = [
            "model": resolvedModel,
            "messages": [
                ["role": "system", "content": priceInstructions],
                ["role": "user", "content": query]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.2
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw openAIError(statusCode: http.statusCode, data: data)
        }

        struct ChatEnvelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }

        let envelope = try JSONDecoder().decode(ChatEnvelope.self, from: data)
        guard let rawText = envelope.choices.first?.message.content, !rawText.isEmpty else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Empty response"
            ])
        }
        return try parsePriceJSON(from: rawText)
    }

    private static func fetchViaResponsesWebSearch(
        query: String,
        category: String,
        key: String,
        styleCode: String? = nil
    ) async throws -> PieceMarketPrice {
        guard key.hasPrefix("sk-") else {
            throw NSError(domain: "PieceMarketPrice", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid key (must start with sk-)"
            ])
        }

        let url = URL(string: "https://api.openai.com/v1/responses")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let body: [String: Any] = [
            "model": webSearchModel,
            "input": [
                ["role": "system", "content": priceInstructions],
                ["role": "user", "content": query]
            ],
            "tools": [["type": "web_search"]],
            "tool_choice": "auto",
            "temperature": 0.2
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw openAIError(statusCode: http.statusCode, data: data)
        }

        let envelope = try JSONDecoder().decode(ResponsesEnvelope.self, from: data)
        guard let rawText = envelope.finalText else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Empty response"
            ])
        }
        return try parsePriceJSON(from: rawText)
    }

    private static func parsePriceJSON(from rawText: String) throws -> PieceMarketPrice {
        guard let jsonRange = extractFirstJSONObject(in: rawText),
              let jsonData = String(rawText[jsonRange]).data(using: .utf8) else {
            throw NSError(domain: "OpenAI", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Could not parse price JSON · \(rawText.prefix(120))"
            ])
        }

        let parsed = try JSONDecoder().decode(OAPriceJSON.self, from: jsonData)
        let avgValue = parsed.avg_eur
        let history: [Double] = {
            let h = parsed.history_eur ?? []
            if h.count >= 2 { return h }
            return Array(repeating: avgValue, count: 6)
        }()

        return PieceMarketPrice(
            avg: Int(parsed.avg_eur.rounded()),
            min: Int(parsed.min_eur.rounded()),
            max: Int(parsed.max_eur.rounded()),
            history: history
        )
    }

    /// Encuentra el primer objeto JSON balanceado dentro de un texto y devuelve
    /// su rango. Útil cuando el modelo añade prosa o bloques markdown alrededor.
    private static func extractFirstJSONObject(in text: String) -> Range<String.Index>? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = start
        while index < text.endIndex {
            let c = text[index]
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 {
                    let end = text.index(after: index)
                    return start..<end
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Mini gráfico de tendencia

/// Sparkline para visualizar la evolución del precio. Pinta una línea
/// principal (color azul/verde/rojo según tendencia) más, opcionalmente, una
/// línea adicional por plataforma para comparar.
struct PriceTrendSparkline: View {
    /// Serie principal (combinada/promedio). Se pinta con relleno + línea gruesa.
    let points: [Double]
    let isUp: Bool
    /// Series por plataforma. Se pintan como líneas finas superpuestas.
    var platforms: [PlatformPrice] = []

    var body: some View {
        GeometryReader { geo in
            // Para que todas las series compartan eje Y, normalizamos contra el
            // mismo dominio (min/max de TODAS las series combinadas).
            let allValues = points + platforms.flatMap { $0.history }
            let domain = computeDomain(allValues)
            let normalizedMain = normalize(points, domain: domain)
            let stepX = normalizedMain.count > 1
                ? geo.size.width / CGFloat(normalizedMain.count - 1)
                : geo.size.width
            let tint: Color = isUp
                ? Color(red: 0.20, green: 0.70, blue: 0.45)
                : Color(red: 0.92, green: 0.30, blue: 0.30)

            ZStack {
                // 1) Área bajo la línea principal (gradiente del color de tendencia)
                Path { p in
                    guard let first = normalizedMain.first else { return }
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    p.addLine(to: CGPoint(x: 0, y: first * geo.size.height))
                    for (i, v) in normalizedMain.enumerated().dropFirst() {
                        p.addLine(to: CGPoint(x: stepX * CGFloat(i), y: v * geo.size.height))
                    }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.28), tint.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // 3) Línea principal (promedio combinado)
                Path { p in
                    guard let first = normalizedMain.first else { return }
                    p.move(to: CGPoint(x: 0, y: first * geo.size.height))
                    for (i, v) in normalizedMain.enumerated().dropFirst() {
                        p.addLine(to: CGPoint(x: stepX * CGFloat(i), y: v * geo.size.height))
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                // 4) Punto final destacado en la línea principal
                if let last = normalizedMain.last {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.4))
                        .position(x: geo.size.width, y: last * geo.size.height)
                }
            }
        }
    }

    private func computeDomain(_ values: [Double]) -> (min: Double, max: Double) {
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        return (minV, max(maxV, minV + 0.0001))
    }

    /// Normaliza al rango [0, 1] invertido contra un dominio compartido.
    private func normalize(_ values: [Double], domain: (min: Double, max: Double)) -> [CGFloat] {
        let range = max(0.0001, domain.max - domain.min)
        return values.map { CGFloat(1 - (($0 - domain.min) / range)) }
    }
}

// MARK: - KicksDB client (precios reales de StockX/GOAT/Flight Club)

/// Cliente para la API REST de kicks.dev. Consulta varias plataformas en
/// paralelo y agrega el resultado. En el plan free obtenemos precios reales
/// (avg/min/max); el histórico es premium y se sintetiza alrededor del avg.
enum KicksDBClient {
    /// Plataformas soportadas en el plan free (mapeo a path de KicksDB).
    enum Platform: String, CaseIterable {
        case stockx
        case goat
        case flightclub
    }

    /// Las credenciales se resuelven exclusivamente en Supabase.
    static var isConfigured: Bool { MarketplaceGatewayService.isAvailable }

    private struct SearchEnvelope: Decodable {
        let data: [ProductHit]?
    }

    struct ProductHit: Decodable {
        /// StockX devuelve UUID string. GOAT devuelve Int. Lo normalizamos a String.
        let id: String?
        let slug: String?
        /// StockX: "title". GOAT: nil (usa "name").
        let title: String?
        /// GOAT: "name" del producto. StockX: nil (usa "title").
        let name: String?
        let brand: String?
        let model: String?
        let image: String?
        let sku: String?
        /// Algunos endpoints usan `style_id` en lugar de `sku`.
        let style_id: String?
        let min_price: Double?
        let max_price: Double?
        let avg_price: Double?
        /// Para GOAT: variantes con `lowest_ask`. Usado para inferir avg/min/max si no vienen directos.
        let variants: [Variant]?
        /// GOAT/KicksDB suele devolver el precio en céntimos en estos campos cuando el
        /// search no incluye `avg_price` ni `variants`.
        let lowest_price_cents: Int?
        let retail_price_cents: Int?

        struct Variant: Decodable {
            let lowest_ask: Double?
            /// GOAT también devuelve `available`; algunas variantes tienen `lowest_ask: null`
            /// y `available: false`. Las filtramos por precio > 0.
            let available: Bool?
            /// Talla del variant. StockX devuelve "US M 10" / "EU 44" / etc. en `size`,
            /// GOAT devuelve "10" / "10.5".
            let size: String?

            private enum CodingKeys: String, CodingKey {
                case lowest_ask, available, size
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                // lowest_ask puede venir como Int (GOAT: 202), Double (StockX a veces), o null.
                if let d = try? c.decode(Double.self, forKey: .lowest_ask) {
                    lowest_ask = d
                } else if let i = try? c.decode(Int.self, forKey: .lowest_ask) {
                    lowest_ask = Double(i)
                } else {
                    lowest_ask = nil
                }
                available = try? c.decode(Bool.self, forKey: .available)
                // size puede ser String ("10") o Double (10.5 en GOAT). Aceptamos ambos.
                if let s = try? c.decode(String.self, forKey: .size) {
                    size = s
                } else if let d = try? c.decode(Double.self, forKey: .size) {
                    size = d == floor(d) ? String(Int(d)) : String(d)
                } else if let i = try? c.decode(Int.self, forKey: .size) {
                    size = String(i)
                } else {
                    size = nil
                }
            }
        }

        /// Devuelve cualquier SKU que el hit traiga (sku, style_id), normalizado.
        /// GOAT devuelve los SKU con espacio en lugar de guion ("854866 019"); lo
        /// dejamos tal cual para mostrarlo y la comparación lo normaliza.
        var resolvedSKU: String? {
            let raw = sku ?? style_id
            return raw?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Nombre legible del producto, priorizando StockX `title` y cayendo en GOAT `name`.
        var displayName: String? {
            if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
            if let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
            return nil
        }

        private enum CodingKeys: String, CodingKey {
            case id, slug, title, name, brand, model, image, sku, style_id
            case min_price, max_price, avg_price, variants
            case lowest_price_cents, retail_price_cents
            // Variantes del campo de imagen según plataforma (StockX/GOAT/unified).
            case image_url, main_picture_url, grid_picture_url, original_picture_url, picture_url, thumbnail_url
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // id puede ser String (StockX UUID) o Int (GOAT). Aceptamos ambos.
            if let s = try? c.decode(String.self, forKey: .id) {
                id = s
            } else if let i = try? c.decode(Int.self, forKey: .id) {
                id = String(i)
            } else {
                id = nil
            }
            slug = try? c.decode(String.self, forKey: .slug)
            title = try? c.decode(String.self, forKey: .title)
            name = try? c.decode(String.self, forKey: .name)
            brand = try? c.decode(String.self, forKey: .brand)
            model = try? c.decode(String.self, forKey: .model)
            // Imagen: probamos varios nombres de campo (StockX/GOAT/unified usan distintos).
            let imageKeys: [CodingKeys] = [.image, .image_url, .main_picture_url, .grid_picture_url, .original_picture_url, .picture_url, .thumbnail_url]
            image = imageKeys.compactMap { try? c.decode(String.self, forKey: $0) }.first { !$0.isEmpty }
            sku = try? c.decode(String.self, forKey: .sku)
            style_id = try? c.decode(String.self, forKey: .style_id)
            min_price = try? c.decode(Double.self, forKey: .min_price)
            max_price = try? c.decode(Double.self, forKey: .max_price)
            avg_price = try? c.decode(Double.self, forKey: .avg_price)
            variants = try? c.decode([Variant].self, forKey: .variants)
            lowest_price_cents = try? c.decode(Int.self, forKey: .lowest_price_cents)
            retail_price_cents = try? c.decode(Int.self, forKey: .retail_price_cents)
        }
    }

    /// ¿Esta query parece un SKU/style code (ej. "FQ7929-100", "DD1391-101", "CU9981-001")?
    /// Heurística: contiene un guion + dígitos al final o tiene formato de código alfanumérico corto.
    static func looksLikeSKU(_ q: String) -> Bool {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !t.contains(" "), t.count <= 16 else { return false }
        // Patrón típico Nike/Jordan: 2-4 letras + 3-5 dígitos + guion opcional + 2-4 dígitos.
        let pattern = "^[A-Z0-9]{2,6}-?[A-Z0-9]{2,5}$"
        return t.range(of: pattern, options: .regularExpression) != nil
    }

    /// Compara una talla buscada por el usuario con la talla devuelta por una variant.
    /// Acepta formatos como "10", "10.5", "EU 44", "US 10", "US M 10". Compara extrayendo
    /// solo los números y comparándolos numéricamente, tolerante a prefijos/sufijos.
    static func sizeMatches(_ query: String, _ variantSize: String?) -> Bool {
        guard let variantSize = variantSize else { return false }
        func extractNumber(_ s: String) -> Double? {
            // Coge el ÚLTIMO número del string (StockX a veces da "US M 10"; queremos "10").
            let pattern = #"(\d+(?:\.\d+)?)"#
            var lastMatch: Double? = nil
            let nsString = s as NSString
            let regex = try? NSRegularExpression(pattern: pattern)
            regex?.enumerateMatches(in: s, range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
                if let r = match?.range, let d = Double(nsString.substring(with: r)) {
                    lastMatch = d
                }
            }
            return lastMatch
        }
        guard let q = extractNumber(query), let v = extractNumber(variantSize) else { return false }
        return abs(q - v) < 0.01
    }

    /// Compara dos códigos de SKU/estilo ignorando mayúsculas, guiones y espacios.
    static func skuMatches(_ a: String, _ b: String?) -> Bool {
        guard let b = b else { return false }
        func norm(_ s: String) -> String {
            s.uppercased()
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: " ", with: "")
        }
        return norm(a) == norm(b)
    }

    /// Verifica que un hit obtenido por búsqueda de nombre (fallback) sea realmente
    /// relevante para lo que el usuario pidió. Evita aceptar productos que comparten
    /// algún término pero son zapatillas distintas (p.ej. "Air Ship" cuando se pidió
    /// "Air Jordan 4").
    ///
    /// Criterios:
    /// 1. Si la query contiene un número de modelo (1-3 dígitos como "4", "350"),
    ///    el título del hit debe contener ese mismo número como palabra completa.
    /// 2. Al menos una palabra significativa de la query (>=4 letras, no stopword)
    ///    debe aparecer en el título/slug del hit.
    static func hitIsRelevant(_ hit: ProductHit, to query: String) -> Bool {
        // Buscamos coincidencias en title (StockX), name (GOAT) Y slug.
        let title = ((hit.title ?? "") + " " + (hit.name ?? "") + " " + (hit.slug ?? "")).lowercased()
        let q = query.lowercased()

        // 1) Número de modelo (1-3 dígitos)
        if let range = q.range(of: #"\b\d{1,3}\b"#, options: .regularExpression) {
            let modelNum = String(q[range])
            let pattern = "\\b\(modelNum)\\b"
            if title.range(of: pattern, options: .regularExpression) == nil {
                return false
            }
        }

        // 2) Solape de palabras significativas (al menos 1 coincidencia)
        let stopwords: Set<String> = [
            "nike", "adidas", "jordan", "retro", "shoes",
            "size", "edition", "the", "and", "with"
        ]
        let words: [String] = q.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { w in
                w.count >= 4 &&
                !stopwords.contains(w) &&
                !w.allSatisfy { $0.isNumber }
            }
        if !words.isEmpty {
            let matched = words.contains(where: { title.contains($0) })
            if !matched { return false }
        }
        return true
    }

    /// Limpia la query antes de mandarla a KicksDB. `(Men's)`, apóstrofes y paréntesis
    /// hacen que la API devuelva HTTP 500 (`search failed`), así que los quitamos.
    static func sanitizeQuery(_ q: String) -> String {
        var s = q
        // Marca propia de la tienda que NO existe en StockX/GOAT y ensucia el emparejado.
        let storeNoise = ["sneak peek luxury", "sneak peek lux", "sneakpeek", "sneak peek"]
        for n in storeNoise {
            s = s.replacingOccurrences(of: n, with: " ", options: [.caseInsensitive])
        }
        s = s.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression) // (Men's), (GS), (W)…
        s = s.replacingOccurrences(of: #"[’'`´]"#, with: "", options: .regularExpression)       // apóstrofes
        s = s.replacingOccurrences(of: #"[^A-Za-z0-9\s\-./]"#, with: " ", options: .regularExpression) // otros símbolos raros
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)          // espacios colapsados
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? q.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }

    /// Palabras distintivas de la query (color/modelo), ignorando marcas y genéricos.
    static func significantWords(_ query: String) -> [String] {
        let stopwords: Set<String> = ["nike", "adidas", "jordan", "retro", "shoes", "size", "edition", "the", "and", "with", "air"]
        return query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 && !stopwords.contains($0) && !$0.allSatisfy(\.isNumber) }
    }

    /// De varios resultados elige el que DE VERDAD coincide (no el primero a ciegas).
    /// Si ninguno es relevante devuelve nil → la tabla muestra "—" en vez del precio de otro zapato.
    static func bestMatch(_ hits: [ProductHit], to query: String) -> ProductHit? {
        let relevant = hits.filter { hitIsRelevant($0, to: query) }
        guard !relevant.isEmpty else { return nil }
        let words = significantWords(query)
        if words.isEmpty { return relevant.first }
        func score(_ h: ProductHit) -> Int {
            let t = ((h.title ?? "") + " " + (h.name ?? "") + " " + (h.slug ?? "")).lowercased()
            var s = words.filter { t.contains($0) }.count * 2
            // Penaliza variantes de niño (GS/PS/TD) para preferir la talla de hombre.
            if t.range(of: #"\b(gs|ps|td|toddler|infant|youth|kids?)\b"#, options: .regularExpression) != nil { s -= 3 }
            return s
        }
        return relevant.max { score($0) < score($1) }
    }

    /// Quita palabras de relleno que confunden la búsqueda de KicksDB ("Air", "Retro", años).
    /// Ej.: "Air Jordan 3 Retro Wolf Grey" → "Jordan 3 Wolf Grey" (que SÍ encuentra el producto).
    static func simplifyQuery(_ q: String) -> String {
        let filler: Set<String> = ["air", "retro", "og", "mid", "low", "high", "shoes"]
        let words = q.split(separator: " ").map(String.init).filter { w in
            if filler.contains(w.lowercased()) { return false }
            if w.count == 4, let y = Int(w), y > 1980, y < 2035 { return false }
            return true
        }
        let out = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return out.isEmpty ? q : out
    }

    private static func searchOnce(platform: Platform, query: String) async throws -> ProductHit? {
        let hits = try await MarketplaceGatewayService.kicksSearch(
            platform: platform,
            query: query,
            limit: 20
        )
        if hits.isEmpty { return nil }
        if significantWords(query).isEmpty { return hits.first } // SKU o query genérica
        return bestMatch(hits, to: query)
    }

    /// Busca el MEJOR hit relevante; si la query completa falla, reintenta simplificada.
    static func search(platform: Platform, query: String) async throws -> ProductHit? {
        let cleaned = sanitizeQuery(query)
        if let hit = try await searchOnce(platform: platform, query: cleaned) { return hit }
        let simplified = simplifyQuery(cleaned)
        if simplified != cleaned, !simplified.isEmpty {
            return try await searchOnce(platform: platform, query: simplified)
        }
        return nil
    }

    /// Sugerencias para autocompletar mientras se escribe (lista ligera de modelos que coinciden).
    static func suggest(_ query: String, limit: Int = 6) async -> [ComparatorSuggestion] {
        let cleaned = sanitizeQuery(query)
        guard cleaned.count >= 2 else { return [] }
        let hits = (try? await MarketplaceGatewayService.kicksSearch(
            platform: .stockx,
            query: cleaned,
            limit: limit
        )) ?? []
        var seen = Set<String>()
        return hits.compactMap { h in
            let title = [h.displayName, h.title, h.name].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            guard !title.isEmpty, seen.insert(title.lowercased()).inserted else { return nil }
            return ComparatorSuggestion(
                id: h.id ?? h.slug ?? title,
                title: title,
                sku: h.resolvedSKU,
                imageURL: h.image.flatMap { URL(string: $0) },
                query: h.resolvedSKU ?? title
            )
        }
    }

    /// Para GOAT necesitamos llamar al endpoint de detalle (`/products/{slug}`)
    /// porque el search no incluye `variants[].lowest_ask`. Para StockX, las variants
    /// requieren `?display[variants]=true`.
    static func detail(platform: Platform, slugOrID: String) async throws -> ProductHit? {
        try await MarketplaceGatewayService.kicksDetail(
            platform: platform,
            productKey: slugOrID
        )
    }

    /// Extrae avg/min/max de un hit. StockX viene con campos directos (avg_price);
    /// GOAT suele dar `variants[].lowest_ask` en el endpoint de detalle, o
    /// `lowest_price_cents` / `retail_price_cents` (en céntimos) en el search.
    /// Devolvemos lo mejor que podamos reconstruir.
    private static func extractPrices(from hit: ProductHit) -> (avg: Double, min: Double, max: Double)? {
        // 1) avg/min/max directos (StockX search)
        if let avg = hit.avg_price, avg > 0 {
            return (
                avg,
                hit.min_price ?? avg * 0.85,
                hit.max_price ?? avg * 1.15
            )
        }
        // 2) Variants con lowest_ask (GOAT detail, StockX con variants)
        let asks = (hit.variants ?? []).compactMap { $0.lowest_ask }.filter { $0 > 0 }
        if !asks.isEmpty {
            let avg = asks.reduce(0, +) / Double(asks.count)
            return (avg, asks.min() ?? avg, asks.max() ?? avg)
        }
        // 3) Precio único en céntimos (GOAT search). Sin rango real, sintetizamos
        //    ±15% alrededor del único punto.
        if let cents = hit.lowest_price_cents, cents > 0 {
            let p = Double(cents) / 100.0
            let retail = hit.retail_price_cents.map { Double($0) / 100.0 }
            let maxV = retail.map { Swift.max($0, p * 1.20) } ?? (p * 1.20)
            return (p, p * 0.92, maxV)
        }
        return nil
    }

    /// Color de marca para cada plataforma en el chart.
    private static func brandColor(_ p: Platform) -> Color {
        switch p {
        case .stockx:     return Color(red: 0.00, green: 0.60, blue: 0.30) // verde StockX
        case .goat:       return Color(red: 0.10, green: 0.10, blue: 0.10) // negro GOAT
        case .flightclub: return Color(red: 0.85, green: 0.10, blue: 0.15) // rojo FC
        }
    }

    private static func brandDisplayName(_ p: Platform) -> String {
        switch p {
        case .stockx:     return "StockX"
        case .goat:       return "GOAT"
        case .flightclub: return "Flight Club"
        }
    }

    /// A partir de un nombre largo ("Nike Nigel Sylvester x Air Jordan 4 Retro") genera
    /// variantes más cortas y limpias para mejorar las posibilidades de que GOAT lo
    /// encuentre. Devuelve duplicadas eliminadas, en orden de "más específica" a más amplia.
    static func nameQueryVariants(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "  ", with: " ")
            guard !t.isEmpty else { return }
            if !results.contains(where: { $0.lowercased() == t.lowercased() }) {
                results.append(t)
            }
        }

        // 1) Tal cual
        add(trimmed)

        // 2) Sin "Nike " inicial
        var t2 = trimmed
        for prefix in ["Nike ", "Adidas ", "Jordan Brand "] {
            if t2.lowercased().hasPrefix(prefix.lowercased()) {
                t2 = String(t2.dropFirst(prefix.count))
                add(t2)
                break
            }
        }

        // 3) Reemplazar " x " por " " (collabs: "Nigel Sylvester x Air Jordan 4")
        if trimmed.lowercased().contains(" x ") {
            add(trimmed.replacingOccurrences(of: " x ", with: " "))
            add(t2.replacingOccurrences(of: " x ", with: " "))
        }

        // 4) Sin palabras "filler" comunes que confunden la búsqueda
        for filler in [" Retro", " Boost", " OG", " SP", " PE"] {
            let cleaned = trimmed.replacingOccurrences(of: filler, with: "", options: .caseInsensitive)
            if cleaned != trimmed { add(cleaned) }
        }
        // Combinaciones (sin "Adidas " y sin "Boost")
        let t3 = t2.replacingOccurrences(of: " Boost", with: "", options: .caseInsensitive)
        add(t3)

        // 5) Sólo lo de antes de la primera "x" (a menudo es el nombre del colaborador): "Nigel Sylvester"
        if let xRange = trimmed.range(of: " x ", options: .caseInsensitive) {
            add(String(trimmed[..<xRange.lowerBound]))
        }

        // 6) Sólo lo de después de la última "x": "Air Jordan 4"
        if let xRange = trimmed.range(of: " x ", options: [.caseInsensitive, .backwards]) {
            add(String(trimmed[xRange.upperBound...]))
        }

        // 7) Sin la última palabra (suele ser la colorway: "Onyx", "Zebra", "Mocha")
        //    Aplicado a varias formas para que GOAT pueda encontrar el modelo sin colorway.
        for base in [trimmed, t2, t3] {
            let tokens = base.split(separator: " ")
            if tokens.count >= 3 {
                add(tokens.dropLast().joined(separator: " "))
            }
            if tokens.count >= 4 {
                add(tokens.dropLast(2).joined(separator: " "))
            }
        }

        return results
    }

    /// Sintetiza 6 puntos plausibles alrededor de un avg, con variación derivada
    /// del rango min-max para que cada plataforma tenga su curva propia.
    private static func synthesizeHistory(avg: Double, min minV: Double, max maxV: Double) -> [Double] {
        let range = max(maxV - minV, avg * 0.10)
        return [
            avg - range * 0.22,
            avg - range * 0.14,
            avg - range * 0.05,
            avg + range * 0.06,
            avg + range * 0.02,
            avg,
        ]
    }

    /// Consulta StockX + GOAT en paralelo y agrega. Flight Club requiere plan
    /// paid en KicksDB (devuelve "route not available for this key type" en
    /// free tier), así que solo se incluye si tienes plan paid.
    /// Devuelve también el desglose por plataforma (`platforms`) para que la UI
    /// pueda mostrar líneas separadas en el chart.
    static func fetchAggregated(query: String, fallbackQuery: String? = nil, sizeQuery: String? = nil) async throws -> PieceMarketPrice? {
        guard isConfigured else {
            throw NSError(domain: "KicksDB", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "El gateway de marketplaces no está disponible."
            ])
        }

        // Lanza las plataformas free-tier en paralelo y conserva qué plataforma
        // produjo cada hit para poder construir el desglose.
        async let stockxTask: ProductHit? = try? search(platform: .stockx, query: query)
        async let goatSearchTask: ProductHit? = try? search(platform: .goat, query: query)

        var stockxHit = await stockxTask
        var goatSearchHit = await goatSearchTask

        print("[KicksDB] query=\(query) fallback=\(fallbackQuery ?? "-")")
        if let s = stockxHit {
            print("[KicksDB] StockX hit: slug=\(s.slug ?? "nil") sku=\(s.resolvedSKU ?? "-") avg=\(s.avg_price ?? -1) min=\(s.min_price ?? -1) max=\(s.max_price ?? -1) variants=\(s.variants?.count ?? 0)")
        } else {
            print("[KicksDB] StockX: sin hit")
        }
        if let g = goatSearchHit {
            print("[KicksDB] GOAT search: name=\(g.displayName ?? "nil") slug=\(g.slug ?? "nil") id=\(g.id ?? "nil") sku=\(g.resolvedSKU ?? "-") avg=\(g.avg_price ?? -1) lowestCents=\(g.lowest_price_cents ?? -1) variants=\(g.variants?.count ?? 0)")
        } else {
            print("[KicksDB] GOAT: sin hit con la query principal")
        }

        // Si la query era un SKU, validamos que el hit devuelto corresponda. Si no, descartamos
        // el hit y reintentamos con el nombre (para no devolver un sneaker distinto al pedido).
        let queryIsSKU = looksLikeSKU(query)
        if queryIsSKU, let s = stockxHit, !skuMatches(query, s.resolvedSKU) {
            print("[KicksDB] StockX SKU mismatch: pidió \(query), devolvió \(s.resolvedSKU ?? "nil") · descartando hit")
            stockxHit = nil
        }
        if queryIsSKU, let g = goatSearchHit, !skuMatches(query, g.resolvedSKU) {
            print("[KicksDB] GOAT SKU mismatch: pidió \(query), devolvió \(g.resolvedSKU ?? "nil") · descartando hit")
            goatSearchHit = nil
        }

        // Variantes de nombre para reintentar cuando el SKU falla o no produce match.
        let fallbackVariants: [String] = {
            var seed: [String] = []
            if let f = fallbackQuery, !f.isEmpty { seed.append(f) }
            if let t = stockxHit?.displayName { seed.append(t) }
            // Si la query principal NO es un SKU, también la usamos como semilla — útil cuando
            // el usuario pone el nombre directamente sin SKU (StockX puede haber dado otra colorway
            // pero GOAT podría tener la genérica).
            if !queryIsSKU { seed.append(query) }
            return seed.flatMap { nameQueryVariants($0) }
                .reduce(into: [String]()) { acc, x in
                    if !acc.contains(where: { $0.lowercased() == x.lowercased() }) { acc.append(x) }
                }
        }()

        // Query "canónica" para validar relevancia: si la query es un SKU usamos el
        // fallback (nombre del modelo) que el usuario nos pasó; si no, la propia query.
        let relevanceQuery = queryIsSKU
            ? (fallbackQuery?.isEmpty == false ? fallbackQuery! : query)
            : query

        // StockX retry con variantes si no tenemos hit válido.
        if stockxHit == nil && !fallbackVariants.isEmpty {
            for alt in fallbackVariants where alt.lowercased() != query.lowercased() {
                print("[KicksDB] StockX retry con: \(alt)")
                if let retry = try? await search(platform: .stockx, query: alt) {
                    if hitIsRelevant(retry, to: relevanceQuery) {
                        print("[KicksDB] StockX retry hit OK: slug=\(retry.slug ?? "nil") sku=\(retry.resolvedSKU ?? "-") avg=\(retry.avg_price ?? -1)")
                        stockxHit = retry
                        break
                    } else {
                        print("[KicksDB] StockX retry irrelevante: slug=\(retry.slug ?? "nil") · descartado")
                    }
                }
            }
            if stockxHit == nil { print("[KicksDB] StockX retry: sin hit relevante") }
        }

        // GOAT retry con variantes si no tenemos hit válido.
        if goatSearchHit == nil && !fallbackVariants.isEmpty {
            for alt in fallbackVariants where alt.lowercased() != query.lowercased() {
                print("[KicksDB] GOAT retry con: \(alt)")
                do {
                    if let retry = try await search(platform: .goat, query: alt) {
                        if hitIsRelevant(retry, to: relevanceQuery) {
                            print("[KicksDB] GOAT retry hit OK: slug=\(retry.slug ?? "nil") sku=\(retry.resolvedSKU ?? "-") avg=\(retry.avg_price ?? -1) lowestCents=\(retry.lowest_price_cents ?? -1) variants=\(retry.variants?.count ?? 0)")
                            goatSearchHit = retry
                            break
                        } else {
                            print("[KicksDB] GOAT retry irrelevante: slug=\(retry.slug ?? "nil") · descartado")
                        }
                    }
                } catch {
                    print("[KicksDB] GOAT retry ERROR para '\(alt)': \(error.localizedDescription)")
                }
            }
            if goatSearchHit == nil { print("[KicksDB] GOAT retry: sin hit relevante") }
        }

        // Pedimos detail SIEMPRE cuando hay sizeQuery (para tener variants y filtrar por talla),
        // y para GOAT también cuando el search no trae precio (caso normal: search nunca lleva variants).
        let needSizeFilter = (sizeQuery?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)

        var goatHit: ProductHit? = goatSearchHit
        if let searchHit = goatSearchHit, (extractPrices(from: searchHit) == nil || needSizeFilter) {
            let slugOrID = searchHit.slug ?? searchHit.id
            if let key = slugOrID, !key.isEmpty {
                do {
                    if let detailHit = try await detail(platform: .goat, slugOrID: key) {
                        let asks = (detailHit.variants ?? []).compactMap { $0.lowest_ask }.filter { $0 > 0 }
                        print("[KicksDB] GOAT detail OK: variants=\(detailHit.variants?.count ?? 0) asksConPrecio=\(asks.count)")
                        goatHit = detailHit
                    }
                } catch {
                    print("[KicksDB] GOAT detail error: \(error.localizedDescription)")
                }
            }
        }

        // StockX detail con variants — solo lo pedimos si necesitamos filtrar por talla,
        // porque el search ya nos da avg/min/max para el caso general.
        var stockxDetail: ProductHit? = stockxHit
        if needSizeFilter, let searchHit = stockxHit {
            let slugOrID = searchHit.slug ?? searchHit.id
            if let key = slugOrID, !key.isEmpty {
                do {
                    if let detailHit = try await detail(platform: .stockx, slugOrID: key) {
                        let asks = (detailHit.variants ?? []).compactMap { $0.lowest_ask }.filter { $0 > 0 }
                        print("[KicksDB] StockX detail OK: variants=\(detailHit.variants?.count ?? 0) asksConPrecio=\(asks.count)")
                        stockxDetail = detailHit
                    }
                } catch {
                    print("[KicksDB] StockX detail error: \(error.localizedDescription)")
                }
            }
        }

        var platforms: [PlatformPrice] = []
        var allAvgs: [Double] = []
        var allMins: [Double] = []
        var allMaxs: [Double] = []
        var sizeUsed: String? = nil

        // Helper: dado un hit con variants, devuelve el lowest_ask de la talla que coincide
        // o nil si no se encuentra esa talla.
        func sizeSpecificAsk(_ hit: ProductHit?, size: String) -> Double? {
            guard let variants = hit?.variants else { return nil }
            for v in variants {
                if sizeMatches(size, v.size), let ask = v.lowest_ask, ask > 0 {
                    return ask
                }
            }
            return nil
        }

        // StockX
        if needSizeFilter, let size = sizeQuery,
           let sizedAsk = sizeSpecificAsk(stockxDetail, size: size) {
            // Tenemos un precio específico de esa talla en StockX
            allAvgs.append(sizedAsk); allMins.append(sizedAsk); allMaxs.append(sizedAsk)
            platforms.append(PlatformPrice(
                name: brandDisplayName(.stockx),
                color: brandColor(.stockx),
                avg: Int(sizedAsk.rounded()),
                history: synthesizeHistory(avg: sizedAsk, min: sizedAsk * 0.92, max: sizedAsk * 1.10)
            ))
            sizeUsed = size
            print("[KicksDB] StockX talla \(size) → $\(Int(sizedAsk.rounded()))")
        } else if let hit = stockxHit, let p = extractPrices(from: hit) {
            allAvgs.append(p.avg); allMins.append(p.min); allMaxs.append(p.max)
            platforms.append(PlatformPrice(
                name: brandDisplayName(.stockx),
                color: brandColor(.stockx),
                avg: Int(p.avg.rounded()),
                history: synthesizeHistory(avg: p.avg, min: p.min, max: p.max)
            ))
        }

        // GOAT
        if needSizeFilter, let size = sizeQuery,
           let sizedAsk = sizeSpecificAsk(goatHit, size: size) {
            allAvgs.append(sizedAsk); allMins.append(sizedAsk); allMaxs.append(sizedAsk)
            platforms.append(PlatformPrice(
                name: brandDisplayName(.goat),
                color: brandColor(.goat),
                avg: Int(sizedAsk.rounded()),
                history: synthesizeHistory(avg: sizedAsk, min: sizedAsk * 0.92, max: sizedAsk * 1.10)
            ))
            sizeUsed = size
            print("[KicksDB] GOAT talla \(size) → $\(Int(sizedAsk.rounded()))")
        } else if let hit = goatHit, let p = extractPrices(from: hit) {
            allAvgs.append(p.avg); allMins.append(p.min); allMaxs.append(p.max)
            platforms.append(PlatformPrice(
                name: brandDisplayName(.goat),
                color: brandColor(.goat),
                avg: Int(p.avg.rounded()),
                history: synthesizeHistory(avg: p.avg, min: p.min, max: p.max)
            ))
        }

        guard !allAvgs.isEmpty else { return nil }

        let avg = allAvgs.reduce(0, +) / Double(allAvgs.count)
        let minV = allMins.min() ?? avg
        let maxV = allMaxs.max() ?? avg

        // Producto emparejado: preferimos el nombre de StockX (suelen ser más limpios),
        // si no, el de GOAT. Si solo tenemos slug, lo "humanizamos" reemplazando guiones.
        let matchedTitle: String? = {
            if let t = stockxHit?.displayName { return t }
            if let t = goatHit?.displayName { return t }
            if let s = stockxHit?.slug ?? goatHit?.slug, !s.isEmpty {
                return s.replacingOccurrences(of: "-", with: " ").capitalized
            }
            return nil
        }()
        let matchedSKU = stockxHit?.resolvedSKU ?? goatHit?.resolvedSKU

        return PieceMarketPrice(
            avg: Int(avg.rounded()),
            min: Int(minV.rounded()),
            max: Int(maxV.rounded()),
            history: synthesizeHistory(avg: avg, min: minV, max: maxV),
            platforms: platforms,
            matchedTitle: matchedTitle,
            matchedSKU: matchedSKU,
            sizeUsed: sizeUsed
        )
    }
}

// MARK: - Comparador de mercado por talla (StockX + GOAT vía KicksDB)

/// Cotización de una plataforma para un producto concreto.
/// `asksBySize` mapea talla normalizada → lowest ask (precio de compra) en USD.
/// Bid (mejor oferta) y última venta NO están disponibles vía KicksDB Standard; se dejan
/// como opcionales para enchufar otra fuente (eBay, sales endpoint o plan paid) más adelante.
struct MarketPlatformQuote: Identifiable {
    let platform: String
    let color: Color
    let matchedTitle: String?
    let matchedSKU: String?
    let productURL: URL?
    /// talla normalizada → lowest ask (compra)
    let asksBySize: [String: Double]
    let avg: Double?
    let lowestAsk: Double?
    let highestAsk: Double?
    /// Para los endpoints Premium (ventas/unified): clave de plataforma, slug y product ID (UUID).
    var platformKey: String = ""
    var slug: String?
    var productID: String?
    var imageURL: URL?
    var id: String { platform }
}

/// Punto de historial de ventas diario (Sell). Requiere plan KicksDB con datos de ventas (Premium).
struct DailySalePoint: Identifiable {
    let date: Date
    let avg: Double
    let orders: Int
    var id: Date { date }
}

/// Fila de comparación para una talla concreta: precio de compra por plataforma.
struct MarketSizeRow: Identifiable {
    let size: String
    /// plataforma → lowest ask
    let asks: [String: Double]
    var id: String { size }

    var cheapest: (platform: String, price: Double)? {
        asks.min { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
    var priciest: (platform: String, price: Double)? {
        asks.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
    /// Diferencia absoluta entre la plataforma más cara y la más barata para esta talla.
    var spread: Double? {
        guard let lo = cheapest?.price, let hi = priciest?.price, hi > lo else { return nil }
        return hi - lo
    }
    var spreadPercent: Double? {
        guard let lo = cheapest?.price, lo > 0, let s = spread else { return nil }
        return s / lo * 100
    }
}

/// Resultado completo del comparador para un producto.
struct MarketComparison {
    let query: String
    let platforms: [MarketPlatformQuote]
    let sizes: [String]
    let rows: [MarketSizeRow]
    /// Momento en que se trajeron los datos (frescura).
    let fetchedAt: Date
    /// `true` si todas las plataformas con SKU apuntan al MISMO producto (SKU normalizado igual).
    let skuAligned: Bool

    var matchedTitle: String? { platforms.compactMap(\.matchedTitle).first }
    /// Nombres para buscar el giro 360°: primero el de StockX, que es quien publica esas fotos.
    var spinTitles: [String] {
        let stockx = platforms.first { $0.platform.lowercased().contains("stockx") }?.matchedTitle
        return ([stockx] + platforms.map(\.matchedTitle)).compactMap { $0 }
    }
    var matchedSKU: String? { platforms.compactMap(\.matchedSKU).first }
    /// Imagen del producto (la primera plataforma que la traiga).
    var imageURL: URL? { platforms.compactMap(\.imageURL).first }

    /// SKUs normalizados distintos detectados entre plataformas (para avisar de posible mismatch).
    var distinctSKUs: [String] {
        var seen: [String] = []
        for p in platforms {
            guard let sku = p.matchedSKU.map(MarketComparison.normalizeSKU), !sku.isEmpty else { continue }
            if !seen.contains(sku) { seen.append(sku) }
        }
        return seen
    }

    /// Normaliza un SKU para comparar entre plataformas: GOAT usa espacios ("854866 019"),
    /// StockX guiones ("854866-019"). Quitamos todo lo no alfanumérico y subimos a mayúsculas.
    static func normalizeSKU(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    static func skuEquals(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        let na = normalizeSKU(a), nb = normalizeSKU(b)
        return !na.isEmpty && na == nb
    }

    /// Mejor precio de compra global: la talla más barata en cualquier plataforma.
    var bestBuyOverall: (platform: String, size: String, price: Double)? {
        var best: (platform: String, size: String, price: Double)?
        for row in rows {
            if let c = row.cheapest, best == nil || c.price < best!.price {
                best = (c.platform, row.size, c.price)
            }
        }
        return best
    }

    /// Nº de ofertas (tallas con stock) por plataforma.
    var offersByPlatform: [(platform: String, count: Int)] {
        platforms.map { ($0.platform, $0.asksBySize.count) }
    }

    /// Mejor arbitraje cruzando plataformas: comprar barato en una y vender en la más cara
    /// (misma talla). Margen bruto y ROII (sin comisiones).
    var bestArbitrage: (size: String, buyPlatform: String, sellPlatform: String, buy: Double, sell: Double, margin: Double, roi: Double)? {
        typealias Arb = (size: String, buyPlatform: String, sellPlatform: String, buy: Double, sell: Double, margin: Double, roi: Double)
        // Mediana de precios para descartar tallas con asks disparados (tallas raras/extremas).
        let lows = rows.compactMap { $0.cheapest?.price }.filter { $0 > 0 }.sorted()
        let median = lows.isEmpty ? 0 : lows[lows.count / 2]
        func scan(strict: Bool) -> Arb? {
            var best: Arb?
            for row in rows {
                guard let lo = row.cheapest, let hi = row.priciest, hi.price > lo.price, lo.price > 0 else { continue }
                if strict, median > 0 {
                    // Ignora precios disparados vs la mediana (no son oportunidades reales).
                    if lo.price > median * 2.2 || hi.price > median * 2.5 { continue }
                    // Ignora tallas raras grandes (US > 13.5), poco líquidas.
                    if let n = Double(row.size), n > 13.5 { continue }
                }
                let margin = hi.price - lo.price
                if best == nil || margin > best!.margin {
                    best = (row.size, lo.platform, hi.platform, lo.price, hi.price, margin, margin / lo.price * 100)
                }
            }
            return best
        }
        return scan(strict: true) ?? scan(strict: false)
    }

    /// Normaliza una talla a su número US para poder cruzar plataformas
    /// ("US M 10" / "10" / "10.5" → "10" / "10.5"). Devuelve nil si parece talla EU.
    static func normalizeSize(_ raw: String) -> String? {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lower.isEmpty else { return nil }
        // "us m 10", "us w 5.5"
        if let r = lower.range(of: #"us\s*[mw]?\s*[0-9]+(\.5)?"#, options: .regularExpression) {
            if let n = lower[r].range(of: #"[0-9]+(\.5)?"#, options: .regularExpression) {
                return canonicalNumber(String(lower[r][n]))
            }
        }
        // Pura: "10" / "10.5"
        if lower.range(of: #"^[0-9]+(\.5)?$"#, options: .regularExpression) != nil {
            return canonicalNumber(lower)
        }
        // Tallas EU explícitas: no las cruzamos con US para no mezclar manzanas y peras.
        if lower.contains("eu") { return nil }
        // Último recurso: primer número decimal.
        if let r = lower.range(of: #"[0-9]+(\.5)?"#, options: .regularExpression) {
            return canonicalNumber(String(lower[r]))
        }
        return nil
    }

    private static func canonicalNumber(_ s: String) -> String {
        guard let d = Double(s) else { return s }
        return d == d.rounded() ? String(Int(d)) : String(d)
    }
}

extension KicksDBClient {
    /// Comparador StockX + GOAT por talla. Reutiliza `search`/`detail` y la heurística de
    /// nombres existentes. Lanza solo si falta la API key; si una plataforma falla, la otra
    /// sigue. Devuelve nil si ninguna encuentra el producto.
    static func fetchComparison(query: String, fallbackQuery: String? = nil) async throws -> MarketComparison? {
        guard isConfigured else {
            throw NSError(domain: "KicksDB", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "El gateway de marketplaces no está disponible."
            ])
        }

        // Primer pase: cada plataforma resuelve con la query del usuario, en paralelo.
        async let stockx0 = quote(for: .stockx, query: query, fallbackQuery: fallbackQuery)
        async let goat0 = quote(for: .goat, query: query, fallbackQuery: fallbackQuery)
        var sQuote = await stockx0
        var gQuote = await goat0

        // SKU canónico: el primero que parezca un style code real (StockX suele ser más limpio,
        // GOAT trae espacios). Sirve para forzar que ambas plataformas comparen el MISMO producto.
        let candidateSKUs = [sQuote?.matchedSKU, gQuote?.matchedSKU].compactMap { $0 }
        let canonicalSKU = candidateSKUs.first(where: { looksLikeSKU($0) }) ?? candidateSKUs.first

        // Alineación (dedupe entre plataformas): si una plataforma no coincide con el SKU canónico,
        // se reconsulta POR SKU. Si la reconsulta no encuentra nada, se conserva el match original.
        if let canon = canonicalSKU {
            if !MarketComparison.skuEquals(sQuote?.matchedSKU, canon),
               let realigned = await quote(for: .stockx, query: canon, fallbackQuery: nil) {
                sQuote = realigned
            }
            if !MarketComparison.skuEquals(gQuote?.matchedSKU, canon),
               let realigned = await quote(for: .goat, query: canon, fallbackQuery: nil) {
                gQuote = realigned
            }
        }

        // Flight Club vía Unified API (KicksDB trae el ask real por talla + el link a flightclub.com).
        // Probamos el slug de StockX y el de GOAT para encontrar los datos.
        var fcQuote: MarketPlatformQuote?
        for slug in [sQuote?.slug, gQuote?.slug].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            guard let fcPrices = try? await unifiedShopPrices(slug: slug, shop: "flightclub"), !fcPrices.isEmpty else { continue }
            let vals = fcPrices.values.sorted()
            fcQuote = MarketPlatformQuote(
                platform: brandDisplayName(.flightclub),
                color: brandColor(.flightclub),
                matchedTitle: sQuote?.matchedTitle ?? gQuote?.matchedTitle,
                matchedSKU: sQuote?.matchedSKU ?? gQuote?.matchedSKU,
                productURL: nil,
                asksBySize: fcPrices,
                avg: vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count),
                lowestAsk: vals.first,
                highestAsk: vals.last,
                platformKey: "flightclub",
                slug: slug
            )
            break
        }

        // Si una plataforma matcheó OTRO producto (SKU distinto Y nivel de precio absurdo vs la otra),
        // la descartamos: mejor mostrar menos plataformas que un precio de un zapato equivocado.
        if let s = sQuote, let g = gQuote,
           !MarketComparison.skuEquals(s.matchedSKU, g.matchedSKU) {
            let sLevel = s.avg ?? s.lowestAsk ?? 0
            let gLevel = g.avg ?? g.lowestAsk ?? 0
            if sLevel > 0, gLevel > 0 {
                if gLevel > sLevel * 3 { gQuote = nil }        // GOAT disparado → GOAT es el equivocado
                else if sLevel > gLevel * 3 { sQuote = nil }   // StockX disparado → StockX es el equivocado
            }
        }

        let quotes = [sQuote, gQuote, fcQuote].compactMap { $0 }
        guard !quotes.isEmpty else { return nil }

        // Conjunto de tallas presentes en alguna plataforma, ordenadas numéricamente.
        var sizeSet = Set<String>()
        for q in quotes { sizeSet.formUnion(q.asksBySize.keys) }
        let sizes = sizeSet.sorted { (Double($0) ?? 0) < (Double($1) ?? 0) }

        let rows: [MarketSizeRow] = sizes.map { size in
            var asks: [String: Double] = [:]
            for q in quotes where q.asksBySize[size] != nil {
                asks[q.platform] = q.asksBySize[size]
            }
            // Descarta precios claramente irreales para esa talla (outlier vs la mediana baja):
            // p.ej. GOAT $2,059 cuando StockX/Flight Club están en ~$70 (producto mal emparejado).
            let vals = asks.values.sorted()
            if vals.count >= 2 {
                let ref = vals[(vals.count - 1) / 2]   // mediana baja
                if ref > 0 {
                    asks = asks.filter { _, p in p <= ref * 4 && p >= ref / 4 }
                }
            }
            return MarketSizeRow(size: size, asks: asks)
        }

        // Alineado si todas las plataformas con SKU comparten el mismo SKU normalizado.
        let skusPresent = quotes.compactMap { $0.matchedSKU.map(MarketComparison.normalizeSKU) }.filter { !$0.isEmpty }
        let skuAligned = skusPresent.count >= 2 ? Set(skusPresent).count == 1 : true
        // Muchos zapatos (p.ej. Air Force 1 White) tienen VARIOS SKUs para el mismo modelo. Si los
        // NOMBRES coinciden casi igual, es el mismo zapato aunque el código difiera → no avisamos.
        let titleWords = quotes.compactMap { $0.matchedTitle?.lowercased() }.map {
            Set($0.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 3 })
        }
        let titlesSameModel: Bool = {
            guard let first = titleWords.first, titleWords.count >= 2 else { return false }
            return titleWords.allSatisfy { $0.symmetricDifference(first).count <= 1 }
        }()
        let aligned = skuAligned || titlesSameModel

        return MarketComparison(
            query: query,
            platforms: quotes,
            sizes: sizes,
            rows: rows,
            fetchedAt: Date(),
            skuAligned: aligned
        )
    }

    /// Historial de ventas DIARIO (Sell) de un producto. Endpoint `/{platform}/products/{slug}/sales/daily`.
    /// ⚠️ Es un **Premium Feature** de KicksDB: en plan free devuelve error y aquí []. Listo para
    /// activarse al subir a un plan con datos de ventas (Starter+).
    /// Historial de ventas diario. ⚠️ El endpoint exige el **product ID (UUID)**, no el slug (el slug da 422).
    static func dailySales(platformKey: String, productID: String) async -> [DailySalePoint] {
        guard isConfigured, !platformKey.isEmpty, !productID.isEmpty else { return [] }
        do {
            let rows = try await MarketplaceGatewayService.kicksDailySales(
                platform: platformKey,
                productID: productID
            )
            let iso = ISO8601DateFormatter()
            let points: [DailySalePoint] = rows.compactMap { row in
                guard let avg = row.avgAmount,
                      avg > 0,
                      let dateString = row.date,
                      let date = iso.date(from: dateString)
                else { return nil }
                return DailySalePoint(date: date, avg: avg, orders: row.orders ?? 0)
            }
            return points.sorted { $0.date < $1.date }
        } catch {
            return []
        }
    }

    /// Precios por talla de una tienda concreta (ej. "flightclub") vía **Unified API** (Premium).
    /// Endpoint: `/v3/unified/products/{slug}` → entradas con `shop_name` y `prices` (talla→precio).
    static func unifiedShopPrices(slug: String, shop: String) async throws -> [String: Double] {
        guard isConfigured, !slug.isEmpty else { return [:] }
        let prices = try await MarketplaceGatewayService.kicksUnifiedPrices(
            slug: slug,
            shop: shop
        )
        var result: [String: Double] = [:]
        for (size, price) in prices where price > 0 {
            result[MarketComparison.normalizeSize(size) ?? size] = price
        }
        return result
    }

    /// Construye la cotización de una plataforma. No lanza: ante cualquier error devuelve nil.
    private static func quote(for platform: Platform, query: String, fallbackQuery: String?) async -> MarketPlatformQuote? {
        do {
            var hit = try await search(platform: platform, query: query)
            if hit == nil, let fb = fallbackQuery, !fb.trimmingCharacters(in: .whitespaces).isEmpty {
                hit = try await search(platform: platform, query: fb)
            }
            if hit == nil {
                for variant in nameQueryVariants(query) {
                    if let h = try await search(platform: platform, query: variant) { hit = h; break }
                }
            }
            guard let found = hit else { return nil }

            // Detalle con variantes (lowest_ask por talla).
            var detailHit: ProductHit?
            if let key = found.slug ?? found.id {
                detailHit = try await detail(platform: platform, slugOrID: key)
            }
            let variants = detailHit?.variants ?? found.variants ?? []

            var asksBySize: [String: Double] = [:]
            for v in variants {
                guard let ask = v.lowest_ask, ask > 0,
                      let rawSize = v.size,
                      let size = MarketComparison.normalizeSize(rawSize) else { continue }
                if let existing = asksBySize[size] {
                    asksBySize[size] = Swift.min(existing, ask)
                } else {
                    asksBySize[size] = ask
                }
            }

            let stats = extractPrices(from: detailHit ?? found)
            let askValues = asksBySize.values.sorted()
            let productURL: URL? = found.slug.flatMap { slug in
                switch platform {
                case .stockx:     return URL(string: "https://stockx.com/\(slug)")
                case .goat:       return URL(string: "https://www.goat.com/sneakers/\(slug)")
                case .flightclub: return URL(string: "https://www.flightclub.com/\(slug)")
                }
            }

            return MarketPlatformQuote(
                platform: brandDisplayName(platform),
                color: brandColor(platform),
                matchedTitle: found.displayName,
                matchedSKU: found.resolvedSKU,
                productURL: productURL,
                asksBySize: asksBySize,
                avg: stats?.avg,
                lowestAsk: askValues.first ?? stats?.min,
                highestAsk: askValues.last ?? stats?.max,
                platformKey: platform.rawValue,
                slug: found.slug ?? found.id,
                productID: found.id,
                imageURL: found.image.flatMap { URL(string: $0) }
            )
        } catch {
            print("[Comparador] \(platform.rawValue) error: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Vista del comparador por talla

struct ComparatorSuggestion: Identifiable {
    let id: String
    let title: String
    let sku: String?
    let imageURL: URL?
    let query: String   // lo que se manda a comparar (SKU si existe, si no el nombre)
}

// MARK: - Buscador de oportunidades (arbitraje entre plataformas sobre tu watchlist)

struct OpportunitiesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var watchlist = WatchlistStore.shared
    @State private var results: [Opportunity] = []
    @State private var loading = false
    @State private var scanned = false

    struct Opportunity: Identifiable {
        let id = UUID()
        let name: String
        let size: String
        let buyPlatform: String
        let sellPlatform: String
        let buy: Double
        let sell: Double
        let margin: Double
        let roi: Double
        let imageURL: URL?
    }

    private let green = Color(red: 0.13, green: 0.55, blue: 0.30)
    private func usd(_ v: Double) -> String { PieceMarketPrice.formatUSD(Int(v.rounded())) }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Analizando \(watchlist.items.count) modelos de tu watchlist…")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if watchlist.items.isEmpty {
                    ContentUnavailableView("Añade favoritos primero", systemImage: "star",
                        description: Text("Guarda modelos con la estrella ★ en la ficha de precios y aquí verás dónde hay ganancia entre plataformas."))
                } else if results.isEmpty {
                    ContentUnavailableView("Sin oportunidades ahora", systemImage: "chart.line.flattrend.xyaxis",
                        description: Text("Ninguno de tus favoritos tiene un spread interesante entre plataformas en este momento. Vuelve más tarde."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            Text("Comprar barato en una plataforma y vender caro en otra. Bruto, sin comisiones ni envío.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(results) { oppCard($0) }
                        }.padding(16)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Oportunidades")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await scan() } } label: {
                        if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }.disabled(loading || watchlist.items.isEmpty)
                }
            }
            .task { if !scanned { await scan() } }
        }
        .preferredColorScheme(.light)
    }

    private func scan() async {
        loading = true
        defer { loading = false; scanned = true }
        var found: [Opportunity] = []
        for item in watchlist.items {
            guard let comp = (try? await KicksDBClient.fetchComparison(query: item.query)) ?? nil,
                  let arb = comp.bestArbitrage, arb.roi >= 8, arb.margin >= 15 else { continue }
            found.append(Opportunity(
                name: comp.matchedTitle ?? item.displayName, size: arb.size,
                buyPlatform: arb.buyPlatform, sellPlatform: arb.sellPlatform,
                buy: arb.buy, sell: arb.sell, margin: arb.margin, roi: arb.roi, imageURL: comp.imageURL
            ))
        }
        results = found.sorted { $0.margin > $1.margin }
    }

    private func oppCard(_ o: Opportunity) -> some View {
        HStack(spacing: 12) {
            StockCachedRemoteImage(url: o.imageURL)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.05), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(o.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text("talla \(o.size)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Text("\(usd(o.buy)) \(o.buyPlatform) → \(usd(o.sell)) \(o.sellPlatform)")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text("+\(usd(o.margin))").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(green)
                Text("\(Int(o.roi))% ROI").font(.system(size: 10, weight: .semibold)).foregroundStyle(green.opacity(0.8))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

/// Esquinas tipo visor de escáner (4 marcas en L).
private struct ScannerCorners: View {
    var color: Color
    var body: some View {
        GeometryReader { geo in
            let len: CGFloat = 30
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: len)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: len, y: 0))
                p.move(to: CGPoint(x: w - len, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: len))
                p.move(to: CGPoint(x: w, y: h - len)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - len, y: h))
                p.move(to: CGPoint(x: len, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - len))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .shadow(color: color.opacity(0.8), radius: 6)
        }
    }
}

/// Estilo de fila con feedback al pulsar (resalte + leve escala).
private struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.black.opacity(0.05) : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MarketComparatorView: View {
    @Environment(\.dismiss) private var dismiss

    let initialFallback: String?
    let initialSizes: [String]

    @State private var queryText: String
    @State private var comparison: MarketComparison?
    @State private var selectedSize: String?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var didAutoRun = false
    // eBay (Browse API) — opcional; solo activo si hay credenciales configuradas.
    @State private var ebayListing: EbayListing?
    @State private var ebayLoading = false
    @State private var showCreateAlert = false
    @ObservedObject private var alertStore = PriceAlertStore.shared
    // Sell / historial (KicksDB sales · Premium)
    @State private var sellPoints: [DailySalePoint] = []
    @State private var sellLoading = false
    // Autocompletado mientras se escribe
    @State private var suggestions: [ComparatorSuggestion] = []
    @State private var suggestTask: Task<Void, Never>?
    @State private var suppressSuggest = false
    @State private var suggestLoading = false
    @FocusState private var searchFocused: Bool
    // Escáner de zapato por foto (Gemini Vision)
    @State private var showScanner = false
    @State private var scanImage: UIImage?
    @State private var scanning = false
    @State private var scanStatus = ""
    @State private var scanLineDown = false
    @State private var lastScanGuess = ""
    @State private var showCorrection = false
    @State private var correctionText = ""
    @State private var showCorrections = false

    init(initialQuery: String = "", initialFallback: String? = nil, initialSizes: [String] = []) {
        self.initialFallback = initialFallback
        self.initialSizes = initialSizes
        _queryText = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        searchBar
                        if suggestLoading && suggestions.isEmpty {
                            suggestionsSkeleton
                                .transition(.opacity)
                        } else if !suggestions.isEmpty {
                            suggestionsList
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.easeOut(duration: 0.22), value: suggestions.count)
                    .animation(.easeOut(duration: 0.2), value: suggestLoading)
                    .onChange(of: queryText) { _, newValue in scheduleSuggest(newValue) }

                    Group {
                        if isLoading {
                            ProgressView("Consultando StockX y GOAT…")
                                .padding(.top, 36)
                        } else if let error = errorText {
                            infoCard(error, system: "exclamationmark.triangle.fill", tint: .orange)
                        } else if let comp = comparison {
                            resultsSection(comp)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            infoCard("Escribe un SKU (ej. DZ5485-100) o el nombre del modelo y pulsa Comparar.",
                                     system: "magnifyingglass", tint: .secondary)
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: comparison?.query)
                    .animation(.easeOut(duration: 0.2), value: isLoading)

                    if !lastScanGuess.isEmpty && comparison != nil && !scanning {
                        Button {
                            correctionText = ""
                            showCorrection = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle")
                                Text("No es este — corregir y enseñar a la IA")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Comparador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if comparison != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showCreateAlert = true
                        } label: {
                            Image(systemName: "bell.badge")
                        }
                        .accessibilityLabel("Crear alerta de precio")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showCorrections = true } label: {
                        Image(systemName: "brain.head.profile")
                    }
                    .accessibilityLabel("Lo que aprendió la IA")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showCorrections) { ScanCorrectionsView() }
            .sheet(isPresented: $showCreateAlert) {
                if let comp = comparison {
                    CreatePriceAlertSheet(
                        store: alertStore,
                        query: comp.matchedSKU ?? comp.query,
                        displayName: comp.matchedTitle ?? comp.query,
                        sizes: comp.sizes
                    )
                }
            }
            .task {
                guard !didAutoRun else { return }
                didAutoRun = true
                if !queryText.trimmingCharacters(in: .whitespaces).isEmpty {
                    await runSearch()
                }
            }
            .sheet(isPresented: $showScanner) {
                SneakerCameraPicker(image: $scanImage).ignoresSafeArea()
            }
            .onChange(of: scanImage) { _, img in
                guard img != nil else { return }
                Task { await scanAndIdentify() }
            }
            .overlay { if scanning { scanOverlay } }
            .alert("¿Cuál es el modelo correcto?", isPresented: $showCorrection) {
                TextField("Ej. Nike Dunk Low Viotech", text: $correctionText)
                    .textInputAutocapitalization(.words)
                Button("Buscar y enseñar") { applyCorrection() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("La IA guardará tu corrección y aprenderá para no repetir el error.")
            }
        }
        .preferredColorScheme(.light)
    }

    /// Guarda la corrección (la IA aprende) y busca el modelo correcto.
    private func applyCorrection() {
        let right = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !right.isEmpty else { return }
        ScanCorrectionStore.shared.add(wrong: lastScanGuess, right: right)
        lastScanGuess = ""
        suppressSuggest = true
        queryText = right
        correctionText = ""
        Task { await runSearch() }
    }

    /// Feedback al escanear: "bip" + vibración (éxito) o tono suave + error.
    private func scanFeedback(success: Bool) {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(success ? .success : .error)
        AudioServicesPlaySystemSound(success ? 1057 : 1053) // 1057 = Tink, 1053 = tono suave
    }

    /// Lee con OCR (Vision, en el dispositivo) el STYLE CODE de la etiqueta de la caja.
    /// Determinista: no "adivina" como la IA. Ej. devuelve "DZ5485-612" si está impreso.
    private func recognizeStyleCode(in image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { req, _ in
                    let lines = (req.results as? [VNRecognizedTextObservation])?
                        .compactMap { $0.topCandidates(1).first?.string } ?? []
                    let text = lines.joined(separator: " ").uppercased()
                    // Patrones de style code: letras+dígitos-3díg (DZ5485-612, CT8532-100) o 6díg-3díg (555088-063).
                    let patterns = [
                        #"\b[A-Z]{1,3}[A-Z0-9]{3,5}-[0-9]{3}\b"#,
                        #"\b[0-9]{6}-[0-9]{3}\b"#,
                        #"\b[A-Z0-9]{6}-[0-9]{3}\b"#,
                    ]
                    for p in patterns {
                        if let r = text.range(of: p, options: .regularExpression) {
                            cont.resume(returning: String(text[r])); return
                        }
                    }
                    cont.resume(returning: nil)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                do {
                    try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Identifica el zapato/prenda de la foto y lanza la búsqueda de precio.
    @MainActor
    private func scanAndIdentify() async {
        guard let img = scanImage else { return }
        scanning = true
        scanLineDown = false
        scanStatus = "Leyendo código de la caja…"
        defer { scanning = false; scanImage = nil }

        // 1) Si hay un STYLE CODE legible en la etiqueta (DZ5485-612), lo usamos: exacto, sin errores.
        if let code = await recognizeStyleCode(in: img), KicksDBClient.looksLikeSKU(code) {
            lastScanGuess = ""   // fue lectura exacta, no una suposición de IA
            scanStatus = "Código leído: \(code)"
            scanFeedback(success: true)
            try? await Task.sleep(nanoseconds: 450_000_000)
            suppressSuggest = true
            queryText = code
            await runSearch()
            return
        }

        // 2) Si no hay código legible, identificamos por imagen con la IA.
        scanStatus = "Identificando con IA…"
        do {
            let result = try await PieceMarketPrice.identifySneaker(in: img, corrections: ScanCorrectionStore.shared.promptHint)
            let q = !result.sku.isEmpty && KicksDBClient.looksLikeSKU(result.sku) ? result.sku : result.model
            guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
                scanStatus = "No pude identificarlo"
                scanFeedback(success: false)
                try? await Task.sleep(nanoseconds: 900_000_000)
                return
            }
            lastScanGuess = result.model
            scanStatus = "Encontrado: \(result.model)"
            scanFeedback(success: true)
            try? await Task.sleep(nanoseconds: 500_000_000)
            queryText = result.model.isEmpty ? q : result.model
            suppressSuggest = true
            await runSearch()
        } catch {
            scanStatus = "No se pudo identificar (\(error.localizedDescription))"
            scanFeedback(success: false)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
    }

    /// Overlay con animación de escaneo mientras la IA identifica el zapato.
    private var scanOverlay: some View {
        let found = scanStatus.lowercased().hasPrefix("encontrado")
        let failed = scanStatus.lowercased().hasPrefix("no ")
        let accent: Color = failed ? .orange : .green
        return ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 26) {
                Text("ESCÁNER IA")
                    .font(.system(size: 11, weight: .heavy)).tracking(2)
                    .foregroundStyle(.white.opacity(0.45))

                ZStack {
                    if let img = scanImage {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 260, height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    // Línea de escaneo (se oculta al terminar)
                    if !found && !failed {
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, accent, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 260, height: 3)
                            .shadow(color: accent, radius: 12)
                            .offset(y: scanLineDown ? 148 : -148)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: scanLineDown)
                    }
                    // Esquinas tipo visor de escáner
                    ScannerCorners(color: accent)
                        .frame(width: 278, height: 318)
                        .opacity(scanLineDown ? 1 : 0.4)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: scanLineDown)
                }
                .frame(width: 260, height: 300)
                .shadow(color: accent.opacity(0.45), radius: 26)

                // Estado en píldora con check/spinner
                HStack(spacing: 10) {
                    if found {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(.green)
                    } else if failed {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15)).foregroundStyle(.orange)
                    } else {
                        ProgressView().tint(.white)
                    }
                    Text(scanStatus.isEmpty ? "Identificando con IA…" : scanStatus)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            }
            .padding(32)
        }
        .transition(.opacity)
        .onAppear { scanLineDown = true }
    }

    // MARK: Subvistas

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(searchFocused ? Color.accentColor : .secondary)
            TextField("SKU o nombre del modelo", text: $queryText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { Task { await runSearch() } }
            if !queryText.isEmpty {
                Button {
                    queryText = ""
                    suggestions = []
                    suggestLoading = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
            Button {
                searchFocused = false
                showScanner = true
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Escanear zapato")
            Button {
                Task { await runSearch() }
            } label: {
                Text("Comparar").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(queryText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(searchFocused ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1.5)
                )
        )
        .animation(.easeOut(duration: 0.18), value: searchFocused)
        .animation(.easeOut(duration: 0.18), value: queryText.isEmpty)
    }

    /// Lista de sugerencias (autocompletado) que aparece mientras escribes.
    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { s in
                Button { pickSuggestion(s) } label: {
                    HStack(spacing: 11) {
                        StockCachedRemoteImage(url: s.imageURL)
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                            if let sku = s.sku, !sku.isEmpty {
                                Text(sku).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor.opacity(0.7))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableRowStyle())
                if s.id != suggestions.last?.id { Divider().padding(.leading, 67) }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.05), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 5)
        )
    }

    /// Pide sugerencias con un pequeño retardo (debounce) para no llamar a la API en cada letra.
    private func scheduleSuggest(_ text: String) {
        suggestTask?.cancel()
        if suppressSuggest { suppressSuggest = false; suggestions = []; suggestLoading = false; return }
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { suggestions = []; suggestLoading = false; return }
        suggestLoading = true
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            let result = await KicksDBClient.suggest(q)
            guard !Task.isCancelled else { return }
            await MainActor.run { suggestions = result; suggestLoading = false }
        }
    }

    /// Al tocar una sugerencia: rellena el campo y compara ese modelo exacto.
    private func pickSuggestion(_ s: ComparatorSuggestion) {
        suggestTask?.cancel()
        searchFocused = false
        suggestions = []
        suggestLoading = false
        suppressSuggest = true
        queryText = s.query
        Task { await runSearch() }
    }

    /// Skeleton mientras llegan las sugerencias.
    private var suggestionsSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06)).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.06)).frame(width: 160, height: 11)
                        RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.04)).frame(width: 80, height: 9)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                if i < 2 { Divider().padding(.leading, 62) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    @ViewBuilder
    private func resultsSection(_ comp: MarketComparison) -> some View {
        VStack(spacing: 12) {
            if let img = comp.imageURL {
                StockCachedRemoteImage(url: img)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                    )
            }
            VStack(spacing: 5) {
                Text(comp.matchedTitle ?? comp.query)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let sku = comp.matchedSKU {
                    Text("SKU \(sku)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("\(comp.platforms.count) plataforma(s) · \(comp.sizes.count) tallas con stock · \(Self.freshness(comp.fetchedAt))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)

        skuStatusBanner(comp)

        if let best = comp.bestBuyOverall {
            bestBuyBanner(best)
        }

        metricsCard(comp)

        if comp.sizes.isEmpty {
            infoCard("Se encontró el producto pero ninguna plataforma devolvió precios por talla ahora mismo.",
                     system: "questionmark.circle", tint: .secondary)
        } else {
            sizeSelector(comp.sizes)
            if let size = currentSize(comp), let row = comp.rows.first(where: { $0.size == size }) {
                // Incluye eBay en la rejilla solo si el listado encontrado es de ESA talla.
                let ebayForSize: Double? = (ebayListing?.sizeAspect == size) ? ebayListing?.price : nil
                sizeComparisonCard(row, platforms: comp.platforms, ebayPrice: ebayForSize)
                payoutCard(row, platforms: comp.platforms, ebayPrice: ebayForSize)
            }
        }

        if EbayPriceService.isConfigured {
            ebayCard(comp)
        }

        salesCard(comp)

        infoCard("Compra = lowest ask real de StockX/GOAT. Bid (mejor oferta) y última venta no los expone KicksDB; eBay aporta listados verificados (Authenticity Guaranteed) cuando hay credenciales.",
                 system: "info.circle", tint: .secondary)
    }

    @ViewBuilder
    private func ebayCard(_ comp: MarketComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                Text("eBay · Authenticity Guaranteed")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if ebayLoading { ProgressView() }
            }
            if let listing = ebayListing {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(listing.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                        if let s = listing.sizeAspect {
                            Text("Talla \(s)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(Self.usd(listing.price))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                }
                if let url = listing.url {
                    Link(destination: url) {
                        Text("Ver listado en eBay")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                    }
                }
            } else if !ebayLoading {
                Text("Sin listados nuevos verificados para esta talla ahora mismo.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
        .task(id: "\(comp.query)|\(currentSize(comp) ?? "-")") {
            await loadEbayIfNeeded(comp)
        }
    }

    @MainActor
    private func loadEbayIfNeeded(_ comp: MarketComparison) async {
        guard EbayPriceService.isConfigured else { return }
        ebayLoading = true
        ebayListing = nil
        defer { ebayLoading = false }
        let q = comp.matchedSKU ?? comp.matchedTitle ?? comp.query
        do {
            ebayListing = try await EbayPriceService.lowestListing(query: q, size: currentSize(comp))
        } catch {
            ebayListing = nil
        }
    }

    @ViewBuilder
    private func skuStatusBanner(_ comp: MarketComparison) -> some View {
        if comp.platforms.count >= 2 {
            if comp.skuAligned, let sku = comp.matchedSKU {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.30))
                    Text("Mismo producto en ambas plataformas · SKU \(sku)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.13, green: 0.55, blue: 0.30).opacity(0.10)))
            } else if comp.distinctSKUs.count > 1 {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Posible mismatch: las plataformas devolvieron SKUs distintos. Verifica que sea el mismo modelo.")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        ForEach(comp.platforms) { p in
                            if let sku = p.matchedSKU {
                                Text("\(p.platform): \(sku)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
            }
        }
    }

    private static func freshness(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 5 { return "ahora" }
        if secs < 60 { return "hace \(secs)s" }
        return "hace \(secs / 60) min"
    }

    @ViewBuilder
    private func metricsCard(_ comp: MarketComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MÉTRICAS")
                .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                .foregroundStyle(.secondary)

            // Ofertas por plataforma
            HStack(spacing: 16) {
                ForEach(comp.offersByPlatform, id: \.platform) { item in
                    VStack(spacing: 2) {
                        Text("\(item.count)").font(.system(size: 18, weight: .heavy, design: .rounded))
                        Text(item.platform).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text("ofertas").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()

            // Margen / ROI de arbitraje (mejor oportunidad entre plataformas)
            if let arb = comp.bestArbitrage {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Margen potencial de reventa").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Self.usd(arb.margin)) · \(String(format: "%.0f", arb.roi))% ROI")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.30))
                    }
                    Text("Talla \(arb.size): comprar en \(arb.buyPlatform) (\(Self.usd(arb.buy))) → vender en \(arb.sellPlatform) (\(Self.usd(arb.sell)))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Bruto, sin comisiones de plataforma ni envío.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            } else {
                Text("Sin diferencia de precio entre plataformas para calcular margen.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            ComparisonSaleReportButton(comparison: comp)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func bestBuyBanner(_ best: (platform: String, size: String, price: Double)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill").font(.system(size: 18)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("MEJOR COMPRA").font(.system(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
                Text("\(best.platform) · talla \(best.size)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            Spacer()
            Text(Self.usd(best.price)).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 0.13, green: 0.55, blue: 0.30)))
    }

    private func sizeSelector(_ sizes: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sizes, id: \.self) { size in
                    let active = currentSizeValue == size
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.68)) { selectedSize = size }
                    } label: {
                        Text(size)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? Color.white : Color.primary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(
                                Capsule().fill(active ? Color.accentColor : Color(.secondarySystemBackground))
                                    .shadow(color: active ? Color.accentColor.opacity(0.4) : .clear, radius: 6, y: 2)
                            )
                            .scaleEffect(active ? 1.08 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private struct SizeEntry: Identifiable {
        let name: String
        let color: Color
        let price: Double?
        let avg: Double?
        var id: String { name }
    }

    /// "¿Dónde gano más vendiendo?" — payout neto tras comisiones por plataforma, para esta talla.
    private func payoutCard(_ row: MarketSizeRow, platforms: [MarketPlatformQuote], ebayPrice: Double?) -> some View {
        var prices: [Double] = platforms.compactMap { row.asks[$0.platform] }.filter { $0 > 0 }
        if let e = ebayPrice, e > 0 { prices.append(e) }
        let sorted = prices.sorted()
        let ref = sorted.isEmpty ? 0 : sorted[(sorted.count - 1) / 2]   // precio de venta de referencia (mediana)
        var payouts: [(name: String, color: Color, net: Double)] = platforms.map {
            (name: $0.platform, color: $0.color, net: PlatformFees.net(price: ref, platform: $0.platform))
        }
        if ebayPrice != nil {
            payouts.append((name: "eBay", color: Color(red: 0.20, green: 0.45, blue: 0.85), net: PlatformFees.net(price: ref, platform: "eBay")))
        }
        payouts.sort { $0.net > $1.net }
        let maxNet = payouts.first?.net ?? 1
        let best = payouts.first?.name
        let green = Color(red: 0.13, green: 0.55, blue: 0.30)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("¿DÓNDE GANAS MÁS VENDIENDO?")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.5).foregroundStyle(.secondary)
                Spacer()
                if let s = currentSizeValue { Text("talla \(s)").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            if ref <= 0 {
                Text("Sin precio de referencia para esta talla.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ForEach(payouts.indices, id: \.self) { i in
                    let p = payouts[i]
                    let frac = maxNet > 0 ? CGFloat(p.net / maxNet) : 0
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Circle().fill(p.color).frame(width: 9, height: 9)
                            Text(p.name).font(.system(size: 14, weight: .bold))
                            if p.name == best {
                                Text("MÁS PAGA").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Capsule().fill(green.opacity(0.15))).foregroundStyle(green)
                            }
                            Spacer()
                            Text("cobras \(Self.usd(p.net))")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(p.name == best ? green : .primary)
                                .contentTransition(.numericText())
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.05)).frame(height: 9)
                                Capsule().fill(LinearGradient(colors: [p.color, p.color.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(8, g.size.width * frac), height: 9)
                            }
                        }.frame(height: 9)
                        Text("vende a \(Self.usd(ref)) · −\(PlatformFees.ratePercent(p.name))% comisión")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Text("Comisiones aproximadas; ajustables.")
                    .font(.system(size: 9)).foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func sizeComparisonCard(_ row: MarketSizeRow, platforms: [MarketPlatformQuote], ebayPrice: Double?) -> some View {
        // Entradas combinadas: StockX/GOAT (KicksDB) + eBay si hay precio para esta talla.
        var entries: [SizeEntry] = platforms.map {
            SizeEntry(name: $0.platform, color: $0.color, price: row.asks[$0.platform], avg: $0.avg)
        }
        if let e = ebayPrice {
            entries.append(SizeEntry(name: "eBay", color: Color(red: 0.20, green: 0.45, blue: 0.85), price: e, avg: nil))
        }
        let priced = entries.compactMap { $0.price }
        let cheapestPrice = priced.min()
        let dearestPrice = priced.max()
        let spread: Double? = {
            guard let lo = cheapestPrice, let hi = dearestPrice, hi > lo else { return nil }
            return hi - lo
        }()
        let spreadPct: Double? = {
            guard let lo = cheapestPrice, lo > 0, let s = spread else { return nil }
            return s / lo * 100
        }()

        return VStack(spacing: 12) {
            ForEach(entries) { e in
                let isCheapest = e.price != nil && e.price == cheapestPrice
                HStack(spacing: 12) {
                    Circle().fill(e.color).frame(width: 10, height: 10)
                    Text(e.name).font(.system(size: 15, weight: .semibold))
                    if isCheapest {
                        Text("MÁS BARATO")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(Color(red: 0.13, green: 0.55, blue: 0.30).opacity(0.15)))
                            .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.30))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(e.price.map(Self.usd) ?? "—")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .contentTransition(.numericText())
                            .foregroundStyle(isCheapest ? Color(red: 0.13, green: 0.55, blue: 0.30) : .primary)
                        if let avg = e.avg {
                            Text("media \(Self.usd(avg))").font(.system(size: 10)).foregroundStyle(.secondary)
                        } else if e.name == "eBay" {
                            Text("Authenticity Guar.").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()

            HStack {
                Label("Disponible en", systemImage: "shippingbox")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text("\(priced.count) de \(entries.count) plataformas")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            HStack {
                Label("Spread entre plataformas", systemImage: "arrow.left.and.right")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if let s = spread, let pct = spreadPct {
                    Text("\(Self.usd(s)) · \(String(format: "%.0f", pct))%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.30))
                } else {
                    Text("—").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func infoCard(_ text: String, system: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: system).foregroundStyle(tint).font(.system(size: 15))
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    @ViewBuilder
    private func salesCard(_ comp: MarketComparison) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Ventas recientes (Sell)", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                if sellLoading { ProgressView() }
            }
            if let last = sellPoints.last {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Última venta media").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("\(sellPoints.count) días de historial").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(Self.usd(last.avg)).font(.system(size: 18, weight: .heavy, design: .rounded))
                }
                sparkline(sellPoints.map(\.avg)).frame(height: 34)
            } else if !sellLoading {
                Text("Historial de ventas: requiere un plan KicksDB con datos de ventas (Premium).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
        .task(id: comp.query) { await loadSales(comp) }
    }

    private func sparkline(_ values: [Double]) -> some View {
        GeometryReader { geo in
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 1)
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = values.count > 1 ? geo.size.width * CGFloat(i) / CGFloat(values.count - 1) : 0
                    let y = geo.size.height * (1 - CGFloat((v - minV) / range))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color(red: 0.13, green: 0.55, blue: 0.30), lineWidth: 2)
        }
    }

    @MainActor
    private func loadSales(_ comp: MarketComparison) async {
        // Ventas: preferimos StockX; el endpoint exige el product ID (UUID), no el slug.
        let q = comp.platforms.first(where: { $0.platformKey == "stockx" && $0.productID != nil })
            ?? comp.platforms.first(where: { ($0.platformKey == "stockx" || $0.platformKey == "goat") && $0.productID != nil })
        guard let quote = q, let pid = quote.productID else { sellPoints = []; return }
        sellLoading = true
        sellPoints = []
        defer { sellLoading = false }
        sellPoints = await KicksDBClient.dailySales(platformKey: quote.platformKey, productID: pid)
    }

    // MARK: Lógica

    private var currentSizeValue: String? { selectedSize }

    private func currentSize(_ comp: MarketComparison) -> String? {
        selectedSize ?? comp.sizes.first
    }

    @MainActor
    private func runSearch() async {
        let q = queryText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        suggestTask?.cancel()
        suggestions = []
        suggestLoading = false
        searchFocused = false
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            if let result = try await KicksDBClient.fetchComparison(query: q, fallbackQuery: initialFallback) {
                comparison = result
                let normalizedInit = initialSizes.compactMap { MarketComparison.normalizeSize($0) }
                selectedSize = normalizedInit.first(where: { result.sizes.contains($0) }) ?? result.sizes.first
            } else {
                comparison = nil
                errorText = "No se encontró el producto en StockX ni GOAT. Prueba con el SKU exacto (ej. DZ5485-100)."
            }
        } catch {
            comparison = nil
            errorText = error.localizedDescription
        }
    }

    private static func usd(_ value: Double) -> String {
        let f = MarketComparatorView.usdFormatter
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value.rounded()))"
    }

    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")
        return f
    }()
}

// MARK: - eBay (Browse API) — listados Authenticity Guaranteed, nuevos, precio fijo

/// Un listado relevante de eBay (nuevo, precio fijo, Authenticity Guaranteed).
struct EbayListing: Identifiable {
    let id: String
    let title: String
    let price: Double
    let currency: String
    let url: URL?
    let sizeAspect: String?
}

/// Cliente de la Browse API de eBay a través del gateway autenticado de Supabase.
enum EbayPriceService {
    static var isConfigured: Bool { MarketplaceGatewayService.isAvailable }

    /// Busca listados **nuevos**, **precio fijo** y con **Authenticity Guarantee**, ordenados por precio.
    static func lowestListings(query: String, limit: Int = 30) async throws -> [EbayListing] {
        let items = try await MarketplaceGatewayService.ebaySearch(
            query: KicksDBClient.sanitizeQuery(query),
            limit: limit,
            profile: "sneakers"
        )
        let listings: [EbayListing] = items.compactMap { item in
            guard item.price > 0 else { return nil }
            let title = item.title
            // Descarta basura típica de eBay: zapatos sueltos, tallas de niño, cajas vacías, etc.
            guard !isJunkTitle(title) else { return nil }
            let rawAspect = item.aspects.first {
                $0.name.lowercased().contains("size")
            }?.value
            return EbayListing(
                id: item.id.isEmpty ? UUID().uuidString : item.id,
                title: title,
                price: item.price,
                currency: item.currency,
                url: item.url.flatMap { URL(string: $0) },
                // Talla normalizada: del campo estructurado si existe, si no parseada del título.
                sizeAspect: detectSize(aspect: rawAspect, title: title)
            )
        }
        return listings.sorted { $0.price < $1.price }
    }

    /// Filtra basura típica en cartas: proxys, reprints, códigos digitales, lotes, jumbo, custom…
    static func isJunkCardTitle(_ title: String) -> Bool {
        let t = " " + title.lowercased() + " "
        let bad = ["proxy", "reprint", "custom", "jumbo", "oversized", "sticker", "metal card",
                   "fake", "replica", "raffle", "break", "mystery", " lot ", "lot of", "playtest",
                   "orica", "digital", "ptcgo", "online code", "code card", "not real", "repro"]
        return bad.contains { t.contains($0) }
    }

    /// Precio representativo (mediana) de una CARTA en eBay. Filtra basura por título y acota a una
    /// banda alrededor del precio de referencia (TCGplayer) para no contar $1 de proxys ni $9.999 de PSA10.
    static func cardLowestPrice(query: String, keyword: String? = nil, anchor: Double? = nil) async -> Double? {
        guard let items = try? await MarketplaceGatewayService.ebaySearch(
            query: query,
            limit: 50,
            profile: "cards"
        ) else { return nil }
        var prices: [Double] = []
        for item in items {
            let v = item.price
            guard v >= 5 else { continue }
            let title = item.title.lowercased()
            if let kw = keyword?.lowercased(), !kw.isEmpty, !title.contains(kw) { continue }
            if isJunkCardTitle(title) { continue }
            if let a = anchor, a > 0, (v < a * 0.25 || v > a * 4) { continue } // banda en torno al precio real
            prices.append(v)
        }
        guard !prices.isEmpty else { return nil }
        prices.sort()
        return prices[prices.count / 2] // mediana
    }

    /// Filtra listados de eBay que NO son el sneaker de adulto completo: zapatos sueltos,
    /// tallas de niño/bebé (TD/PS/GS/Y/youth/toddler/kids), reemplazos, cajas vacías, displays.
    static func isJunkTitle(_ title: String) -> Bool {
        let t = " " + title.lowercased() + " "
        let badPhrases = [
            "single shoe", "left foot", "right foot", "left only", "right only", "one shoe",
            "replacement", "display", "empty box", "box only", "no shoes", "for parts",
            "custom", "painted", "sample", "promo sample"
        ]
        if badPhrases.contains(where: { t.contains($0) }) { return true }
        // Tokens de talla de niño/joven (con separadores para no pillar palabras dentro de otras).
        let kidTokens = [" td ", " ps ", " gs ", " td)", " ps)", " gs)", "(td", "(ps", "(gs",
                         " toddler", " infant", " youth", " kids", " child", " preschool", " gradeschool",
                         "5y", "6y", "7y", "3.5y", "4y", "4.5y", "5.5y", "6.5y"]
        if kidTokens.contains(where: { t.contains($0) }) { return true }
        return false
    }

    /// Detecta la talla US (normalizada) de un listado: primero el aspecto estructurado;
    /// si no, la parsea del título ("size 10", "sz 10.5", "Men 6.5", "US 9"). Acota a un
    /// rango plausible de tallas (3–18) para no confundir con años o cantidades.
    private static func detectSize(aspect: String?, title: String) -> String? {
        if let aspect, let n = MarketComparison.normalizeSize(aspect) { return n }
        let t = title.lowercased()
        let patterns = [
            #"(?:size|sz|us|men|women|wmns|w|m)\s*([0-9]{1,2}(?:\.5)?)"#,
            #"\b([0-9]{1,2}(?:\.5)?)\b"#,
        ]
        for pat in patterns {
            guard let r = t.range(of: pat, options: .regularExpression),
                  let n = t[r].range(of: #"[0-9]{1,2}(?:\.5)?"#, options: .regularExpression) else { continue }
            let num = String(t[r][n])
            if let d = Double(num), d >= 3, d <= 18 {
                return d == d.rounded() ? String(Int(d)) : String(d)
            }
        }
        return nil
    }

    /// El listado más barato que cumple los filtros. Si se pasa `size`, intenta una talla
    /// concreta usando el aspecto "Size" del listado; si hay aspectos pero ninguno de esa
    /// talla, devuelve nil (no hay esa talla); si no hay aspectos, cae al global más barato.
    static func lowestListing(query: String, size: String?) async throws -> EbayListing? {
        let all = try await lowestListings(query: query)
        guard let size, let norm = MarketComparison.normalizeSize(size) else {
            return all.first
        }
        let sized = all.filter {
            guard let asp = $0.sizeAspect, let ln = MarketComparison.normalizeSize(asp) else { return false }
            return ln == norm
        }
        if let best = sized.first { return best }
        let anyHasSizeAspect = all.contains { $0.sizeAspect != nil }
        return anyHasSizeAspect ? nil : all.first
    }
}

// MARK: - Alertas de precio (P5) — store local (UserDefaults) + notificaciones locales

enum PriceAlertType: String, Codable, CaseIterable, Identifiable {
    case priceDrop, priceRise, sizeAvailable, arbitrage
    var id: String { rawValue }
    var label: String {
        switch self {
        case .priceDrop:     return "Baja de precio (comprar)"
        case .priceRise:     return "Sube de precio (vender)"
        case .sizeAvailable: return "Aparece una talla"
        case .arbitrage:     return "Arbitraje entre plataformas"
        }
    }
    var icon: String {
        switch self {
        case .priceDrop:     return "arrow.down.circle.fill"
        case .priceRise:     return "arrow.up.circle.fill"
        case .sizeAvailable: return "shoe.fill"
        case .arbitrage:     return "arrow.left.arrow.right.circle.fill"
        }
    }
}

struct PriceAlert: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var query: String
    var displayName: String
    var type: PriceAlertType
    var targetPrice: Double?
    var targetSize: String?
    var minMarginPercent: Double?
    var isActive: Bool = true
    var lastTriggeredAt: Date?
    var lastValue: Double?
}

@MainActor
final class PriceAlertStore: ObservableObject {
    static let shared = PriceAlertStore()
    @Published private(set) var alerts: [PriceAlert] = []
    private let key = "upsoled.priceAlerts.v1"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PriceAlert].self, from: data) else { return }
        alerts = decoded
    }
    private func save() {
        if let data = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    func add(_ a: PriceAlert) { alerts.insert(a, at: 0); save() }
    func remove(_ a: PriceAlert) { alerts.removeAll { $0.id == a.id }; save() }
    func toggle(_ a: PriceAlert) {
        guard let i = alerts.firstIndex(where: { $0.id == a.id }) else { return }
        alerts[i].isActive.toggle(); save()
    }
    func update(_ a: PriceAlert) {
        guard let i = alerts.firstIndex(where: { $0.id == a.id }) else { return }
        alerts[i] = a; save()
    }
}

// MARK: - Watchlist (favoritos para seguir su precio sin tenerlos en stock)

struct WatchItem: Codable, Identifiable, Equatable {
    var id: String { query.lowercased() }
    var query: String
    var displayName: String
    var addedAt: Date = Date()
}

@MainActor
final class WatchlistStore: ObservableObject {
    static let shared = WatchlistStore()
    @Published private(set) var items: [WatchItem] = []
    private let key = "upsoled.watchlist.v1"

    init() { load() }
    func load() {
        guard let d = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([WatchItem].self, from: d) else { return }
        items = arr
    }
    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
    func contains(_ query: String) -> Bool {
        items.contains { $0.query.lowercased() == query.lowercased() }
    }
    func toggle(query: String, displayName: String) {
        if let i = items.firstIndex(where: { $0.query.lowercased() == query.lowercased() }) {
            items.remove(at: i)
        } else {
            items.insert(WatchItem(query: query, displayName: displayName), at: 0)
        }
        save()
    }
    func remove(_ item: WatchItem) { items.removeAll { $0.id == item.id }; save() }
}

// MARK: - Correcciones del escáner (la IA aprende de tus "no es este")

struct ScanCorrection: Codable, Identifiable {
    var id = UUID()
    var wrong: String
    var right: String
    var date: Date = Date()
}

@MainActor
final class ScanCorrectionStore: ObservableObject {
    static let shared = ScanCorrectionStore()
    @Published private(set) var items: [ScanCorrection] = []
    private let key = "upsoled.scanCorrections.v1"

    init() { load() }
    func load() {
        guard let d = UserDefaults.standard.data(forKey: key),
              let a = try? JSONDecoder().decode([ScanCorrection].self, from: d) else { return }
        items = a
    }
    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
    func add(wrong: String, right: String) {
        let r = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty, r.lowercased() != wrong.lowercased() else { return }
        items.insert(ScanCorrection(wrong: wrong, right: r), at: 0)
        if items.count > 40 { items = Array(items.prefix(40)) }
        save()
    }
    func remove(_ c: ScanCorrection) { items.removeAll { $0.id == c.id }; save() }
    func clearAll() { items.removeAll(); save() }
    /// Texto que se inyecta al prompt para que la IA no repita errores pasados.
    var promptHint: String {
        let recent = items.prefix(8)
        guard !recent.isEmpty else { return "" }
        return "Learn from these past user corrections (do NOT repeat these mistakes):\n"
            + recent.map { "- An item you might call '\($0.wrong)' was actually '\($0.right)'." }.joined(separator: "\n")
    }
}

/// Pantalla "Lo que aprendió la IA": ver y borrar las correcciones del escáner.
struct ScanCorrectionsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ScanCorrectionStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView(
                        "Sin correcciones",
                        systemImage: "brain.head.profile",
                        description: Text("Cuando uses «No es este» al escanear, lo que le enseñes a la IA aparecerá aquí.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(store.items) { c in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11)).foregroundStyle(.green)
                                        Text(c.right).font(.system(size: 14, weight: .semibold))
                                    }
                                    Text("La IA decía: \(c.wrong)")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                            .onDelete { idx in idx.map { store.items[$0] }.forEach(store.remove) }
                        } footer: {
                            Text("La IA usa estas correcciones para no repetir errores al escanear.")
                        }
                    }
                }
            }
            .navigationTitle("Lo que aprendió la IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                if !store.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Borrar todo", role: .destructive) { store.clearAll() }
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

enum PriceAlertNotifications {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
    static func fire(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: "alert-\(id)-\(Int(Date().timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

enum PriceAlertChecker {
    private static func money(_ v: Double) -> String { "$\(Int(v.rounded()))" }

    /// Evalúa una alerta contra el mercado actual (StockX+GOAT). Devuelve si se cumple + mensaje + valor.
    @MainActor
    static func evaluate(_ alert: PriceAlert) async -> (met: Bool, message: String, value: Double?) {
        guard let comp = try? await KicksDBClient.fetchComparison(query: alert.query) else {
            return (false, "", nil)
        }
        switch alert.type {
        case .priceDrop:
            let price: Double?
            if let size = alert.targetSize, let norm = MarketComparison.normalizeSize(size),
               let row = comp.rows.first(where: { $0.size == norm }) {
                price = row.cheapest?.price
            } else {
                price = comp.bestBuyOverall?.price
            }
            guard let p = price, let target = alert.targetPrice else { return (false, "", price) }
            return p <= target
                ? (true, "\(alert.displayName) a \(money(p)) (≤ \(money(target)))", p)
                : (false, "", p)
        case .priceRise:
            let price: Double?
            if let size = alert.targetSize, let norm = MarketComparison.normalizeSize(size),
               let row = comp.rows.first(where: { $0.size == norm }) {
                price = row.cheapest?.price
            } else {
                price = comp.bestBuyOverall?.price
            }
            guard let p = price, let target = alert.targetPrice else { return (false, "", price) }
            return p >= target
                ? (true, "Hora de vender: \(alert.displayName) a \(money(p)) (≥ \(money(target)))", p)
                : (false, "", p)
        case .sizeAvailable:
            guard let size = alert.targetSize, let norm = MarketComparison.normalizeSize(size) else { return (false, "", nil) }
            if let row = comp.rows.first(where: { $0.size == norm }), let c = row.cheapest {
                return (true, "Talla \(norm) de \(alert.displayName): \(money(c.price)) en \(c.platform)", c.price)
            }
            return (false, "", nil)
        case .arbitrage:
            guard let arb = comp.bestArbitrage else { return (false, "", nil) }
            let threshold = alert.minMarginPercent ?? 15
            return arb.roi >= threshold
                ? (true, "Arbitraje \(Int(arb.roi))% en \(alert.displayName): \(money(arb.buy)) (\(arb.buyPlatform)) → \(money(arb.sell)) (\(arb.sellPlatform))", arb.margin)
                : (false, "", arb.margin)
        }
    }

    /// Recorre alertas activas, notifica las que se cumplan (anti-spam: máx 1 cada 6h por alerta).
    @MainActor
    static func checkAll() async {
        await checkAll(store: .shared)
    }

    @MainActor
    static func checkAll(store: PriceAlertStore) async {
        for alert in store.alerts where alert.isActive {
            let r = await evaluate(alert)
            guard r.met else { continue }
            if let last = alert.lastTriggeredAt, Date().timeIntervalSince(last) < 6 * 3600 { continue }
            PriceAlertNotifications.fire(title: "Upsoled · Alerta de precio", body: r.message, id: alert.id.uuidString)
            var updated = alert
            updated.lastTriggeredAt = Date()
            updated.lastValue = r.value
            store.update(updated)
        }
    }
}

// MARK: - Alertas: crear y listar

struct CreatePriceAlertSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PriceAlertStore
    let query: String
    let displayName: String
    let sizes: [String]

    @State private var type: PriceAlertType = .priceDrop
    @State private var priceText = ""
    @State private var selectedSize = ""
    @State private var marginText = "15"

    var body: some View {
        NavigationStack {
            Form {
                Section("Producto") {
                    Text(displayName).font(.system(size: 14, weight: .semibold))
                    Text(query).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                Section("Tipo de alerta") {
                    Picker("Tipo", selection: $type) {
                        ForEach(PriceAlertType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                Section("Condición") {
                    switch type {
                    case .priceDrop:
                        HStack {
                            Text("Avísame si baja de")
                            Spacer()
                            TextField("$", text: $priceText)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                        }
                        if !sizes.isEmpty { sizePicker }
                    case .priceRise:
                        HStack {
                            Text("Avísame si sube de")
                            Spacer()
                            TextField("$", text: $priceText)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                        }
                        if !sizes.isEmpty { sizePicker }
                    case .sizeAvailable:
                        sizePicker
                    case .arbitrage:
                        HStack {
                            Text("ROI mínimo %")
                            Spacer()
                            TextField("15", text: $marginText)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 60)
                        }
                    }
                }
            }
            .navigationTitle("Nueva alerta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Crear") { create() }.disabled(!canCreate) }
            }
        }
        .preferredColorScheme(.light)
    }

    private var sizePicker: some View {
        Picker("Size", selection: $selectedSize) {
            Text("Cualquiera").tag("")
            ForEach(sizes, id: \.self) { Text($0).tag($0) }
        }
    }

    private var canCreate: Bool {
        switch type {
        case .priceDrop:     return Double(priceText) != nil
        case .priceRise:     return Double(priceText) != nil
        case .sizeAvailable: return !selectedSize.isEmpty
        case .arbitrage:     return Double(marginText) != nil
        }
    }

    private func create() {
        var a = PriceAlert(query: query, displayName: displayName, type: type)
        switch type {
        case .priceDrop:
            a.targetPrice = Double(priceText)
            a.targetSize = selectedSize.isEmpty ? nil : selectedSize
        case .priceRise:
            a.targetPrice = Double(priceText)
            a.targetSize = selectedSize.isEmpty ? nil : selectedSize
        case .sizeAvailable:
            a.targetSize = selectedSize
        case .arbitrage:
            a.minMarginPercent = Double(marginText)
        }
        store.add(a)
        Task { await PriceAlertNotifications.requestAuthorization() }
        dismiss()
    }
}

struct PriceAlertsListView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PriceAlertStore
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Group {
                if store.alerts.isEmpty {
                    ContentUnavailableView(
                        "Sin alertas",
                        systemImage: "bell.slash",
                        description: Text("Créalas desde el comparador para avisarte de bajadas de precio, tallas o arbitraje.")
                    )
                } else {
                    List {
                        ForEach(store.alerts) { alert in row(alert) }
                            .onDelete { idx in idx.map { store.alerts[$0] }.forEach(store.remove) }
                    }
                }
            }
            .navigationTitle("Alertas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { checking = true; await PriceAlertChecker.checkAll(store: store); checking = false }
                    } label: {
                        if checking { ProgressView() } else { Text("Comprobar") }
                    }
                    .disabled(checking || store.alerts.isEmpty)
                }
            }
            .task { await PriceAlertChecker.checkAll(store: store) }
        }
        .preferredColorScheme(.light)
    }

    private func row(_ alert: PriceAlert) -> some View {
        HStack(spacing: 12) {
            Image(systemName: alert.type.icon)
                .foregroundStyle(Color(red: 0.14, green: 0.36, blue: 0.75))
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(conditionText(alert)).font(.system(size: 11)).foregroundStyle(.secondary)
                if let last = alert.lastTriggeredAt {
                    Text("Avisado \(last.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { alert.isActive }, set: { _ in store.toggle(alert) }))
                .labelsHidden()
        }
    }

    private func conditionText(_ a: PriceAlert) -> String {
        switch a.type {
        case .priceDrop:     return "Baja de $\(Int(a.targetPrice ?? 0))" + (a.targetSize.map { " · talla \($0)" } ?? "")
        case .priceRise:     return "Vende si sube de $\(Int(a.targetPrice ?? 0))" + (a.targetSize.map { " · talla \($0)" } ?? "")
        case .sizeAvailable: return "Aparece talla \(a.targetSize ?? "?")"
        case .arbitrage:     return "Arbitraje ≥ \(Int(a.minMarginPercent ?? 15))% ROI"
        }
    }
}

// MARK: - Bulk category picker

private struct BulkStockCategorySheet: View {
    let selectionCount: Int
    let onApplyClothing: (ClothingCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Apply category to \(selectionCount) items")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                }

                Section("Category") {
                    ForEach(ClothingCategory.allCases, id: \.rawValue) { cat in
                        Button {
                            onApplyClothing(cat)
                            dismiss()
                        } label: {
                            HStack {
                                Text("\(cat.emoji) \(cat.displayName)")
                                    .foregroundStyle(Color.black)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Change category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}


// MARK: - Informe de venta desde el comparador

/// Botón que abre el informe de venta del producto comparado (con selector de talla).
struct ComparisonSaleReportButton: View {
    let comparison: MarketComparison
    @State private var report: SaleReport?

    var body: some View {
        Button {
            report = SaleReport.from(comparison: comparison)
        } label: {
            Label("Sale report and listing", systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .fullScreenCover(item: $report) { item in
            SaleReportView(report: item, sizes: comparison.sizes) { size, cost in
                SaleReport.from(comparison: comparison, size: size, costUSD: cost)
            }
        }
    }
}

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

// MARK: - Paleta modo claro

private enum ClosetFlowPalette {
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

    var body: some View {
        Group {
            if let ui = StockImageLoader.cachedLocalImage(relativePath: relativePath) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.white
            }
        }
        .background(Color.white)
    }
}

// MARK: - Cámara

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
    fileprivate func closetFlattenedOrientation() -> UIImage {
        ClosetPhotoExports.normalizedClosetProductImage(self)
    }
}

// MARK: - Pestaña clóset + sheet entrada

struct ClosetView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var addFlow: AddToClosetFlowViewModel
    @EnvironmentObject private var goatVM: GoatAccountViewModel
    @Query(sort: \ClosetItem.createdAt, order: .reverse) private var closetItems: [ClosetItem]
    /// Catálogo Supabase (`upsoled_products`): mismos productos que la pestaña Marketplace/Sold.
    @StateObject private var catalogVM = UpsoledProductsViewModel()

    /// Active inventory only — sold items live under the Sold tab.
    private var activeClosetItems: [ClosetItem] {
        closetItems.filter(\.isActiveInStock)
    }

    @State private var showAddMenuSheet = false
    @State private var showCamera = false
    @State private var showGalleryPickSheet = false
    @State private var pickedGalleryItems: [PhotosPickerItem] = []
    @State private var cameraImage: UIImage?
    @State private var showPipeline = false

    private struct StockRemovalRequest: Identifiable {
        let id = UUID()
        let closetIDs: Set<UUID>
        let catalogIDs: Set<UUID>

        var totalCount: Int { closetIDs.count + catalogIDs.count }
    }

    @State private var closetSelectionMode = false
    @State private var closetSelectedIDs = Set<UUID>()
    @State private var catalogSelectedIDs = Set<UUID>()
    @State private var showBulkCategorySheet = false
    @State private var catalogDetailBusy = false
    @State private var removalRequest: StockRemovalRequest?
    @State private var permanentDeleteItem: ClosetItem?

    /// Ficha grande de una prenda (estudio).
    @State private var garmentDetailSheetItem: ClosetItem?
    @State private var showCreateLookSheet = false

    /// Tras elegir exactamente 4 fotos: elegir «outfit» o «zapatos 360°».
    @State private var stagingFiveGalleryImages: [UIImage] = []
    @State private var showFivePhotosUseModeSheet = false
    /// Fullscreen vista 360° cuando el usuario elige usar 4 fotos como zapatos (galería).
    @State private var showShoe360FiveGalleryFlow = false
    @State private var shoe360FiveGalleryImagesPrepared: [UIImage] = []
    /// Zapatos foto a foto desde el FAB (sin obligar al flujo de outfit / galería).
    @State private var showPrivateShoe360Flow = false
    /// Ropa lookbook foto a foto: camisetas, pantalones, cintos, calcetines, etc. (no zapatos).
    @State private var showPrivateGarmentLookbookFlow = false
    @State private var stockSearchText = ""
    @FocusState private var stockSearchFocused: Bool
    @State private var stockFilters = StockBrowseFilters()
    @State private var showStockFiltersSheet = false
    @AppStorage("stockLayoutMode") private var stockLayoutModeRaw = StockLayoutMode.grid.rawValue
    @State private var showBarcodeScanner = false
    @State private var scanLookupPayload: StockScanLookupPayload?
    @State private var scanLookupBusy = false

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
        if !stockSearchQuery.isEmpty {
            items = items.filter { itemMatchesStockSearch($0, query: stockSearchQuery) }
        }
        items = items.filter { StockFilterEngine.matches(stockFilters, closetItem: $0) }
        return StockFilterEngine.sortClosetItems(items, by: stockFilters.sort)
    }

    private var filteredCatalogProducts: [UpsoledProduct] {
        var products = catalogVM.products
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

    private var hasCatalogStock: Bool { !catalogVM.products.isEmpty }
    private var hasAnyStockContent: Bool { !activeClosetItems.isEmpty || hasCatalogStock }

    private var filteredClosetStockSections: [ClosetStockSection] {
        let grouped = Dictionary(grouping: filteredActiveClosetItems) { $0.category }
        return Self.stockCategoryPresentationOrder.compactMap { cat in
            guard let arr = grouped[cat], !arr.isEmpty else { return nil }
            let sorted = StockFilterEngine.sortClosetItems(arr, by: stockFilters.sort)
            return ClosetStockSection(category: cat, items: sorted)
        }
    }

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(minimum: 148), spacing: 12),
        GridItem(.flexible(minimum: 148), spacing: 12),
    ]

    /// Orden visual del armario por categoría (solo se pintan bloques con prendas).
    private static let stockCategoryPresentationOrder: [ClothingCategory] = [
        .tops, .dressesJumpsuits, .pantsSkirts, .coats, .shoes, .bags, .accessories, .underwear,
    ]

    private struct ClosetStockSection: Identifiable {
        var id: String { category.rawValue }
        let category: ClothingCategory
        let items: [ClosetItem]

        var totalValueUSD: Double {
            items.reduce(0) { $0 + $1.stockValueUSD }
        }
    }

    private struct StockCategoryBreakdown: Identifiable {
        let id: String
        let emoji: String
        let title: String
        let count: Int
        let valueUSD: Double
    }

    private static let stockSummaryCategoryOrder: [String] = [
        ClothingCategory.shoes.rawValue,
        ClothingCategory.tops.rawValue,
        ClothingCategory.dressesJumpsuits.rawValue,
        ClothingCategory.pantsSkirts.rawValue,
        ClothingCategory.coats.rawValue,
        ClothingCategory.bags.rawValue,
        ClothingCategory.accessories.rawValue,
        ClothingCategory.underwear.rawValue,
        "clothing", "vintage", "new-drops", "other",
    ]

    private var stockCategoryBreakdowns: [StockCategoryBreakdown] {
        buildStockCategoryBreakdowns(
            closetItems: filteredActiveClosetItems,
            catalogProducts: filteredCatalogProducts
        )
    }

    private var stockGrandTotalCount: Int {
        let closet = filteredActiveClosetItems.count
        let catalog = filteredCatalogProducts.reduce(0) { $0 + max(1, $1.quantity ?? 1) }
        return closet + catalog
    }

    private var stockGrandTotalValueUSD: Double {
        let closet = filteredActiveClosetItems.reduce(0.0) { $0 + $1.stockValueUSD }
        let catalog = filteredCatalogProducts.reduce(0.0) { $0 + $1.stockValueUSD }
        return closet + catalog
    }

    private var stockClosetInvestedUSD: Double {
        filteredActiveClosetItems.reduce(0.0) { $0 + $1.purchaseValueUSD }
    }

    private var stockClosetProfitUSD: Double {
        filteredActiveClosetItems.reduce(0.0) { $0 + $1.projectedProfitUSD }
    }

    private func buildStockCategoryBreakdowns(
        closetItems: [ClosetItem],
        catalogProducts: [UpsoledProduct]
    ) -> [StockCategoryBreakdown] {
        var buckets: [String: (emoji: String, title: String, count: Int, value: Double)] = [:]

        func add(key: String, emoji: String, title: String, units: Int = 1, value: Double) {
            var bucket = buckets[key] ?? (emoji, title, 0, 0)
            bucket.count += units
            bucket.value += value
            buckets[key] = bucket
        }

        for item in closetItems {
            let cat = item.category
            add(key: cat.rawValue, emoji: cat.emoji, title: cat.displayName, value: item.stockValueUSD)
        }

        for product in catalogProducts {
            let meta = catalogCategoryPresentation(product.category)
            add(
                key: meta.key,
                emoji: meta.emoji,
                title: meta.title,
                units: max(1, product.quantity ?? 1),
                value: product.stockValueUSD
            )
        }

        let orderedKeys = Self.stockSummaryCategoryOrder.filter { buckets[$0] != nil }
        let extraKeys = buckets.keys.filter { !Self.stockSummaryCategoryOrder.contains($0) }.sorted()
        return (orderedKeys + extraKeys).compactMap { key in
            guard let b = buckets[key] else { return nil }
            return StockCategoryBreakdown(
                id: key,
                emoji: b.emoji,
                title: b.title,
                count: b.count,
                valueUSD: b.value
            )
        }
    }

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

    private var filteredCatalogStockSections: [(meta: (key: String, emoji: String, title: String), products: [UpsoledProduct])] {
        let grouped = Dictionary(grouping: filteredCatalogProducts) { catalogCategoryPresentation($0.category).key }
        let orderedKeys = Self.stockSummaryCategoryOrder.filter { grouped[$0] != nil }
        let extraKeys = grouped.keys.filter { !Self.stockSummaryCategoryOrder.contains($0) }.sorted()
        return (orderedKeys + extraKeys).compactMap { key in
            guard let products = grouped[key], !products.isEmpty else { return nil }
            let sorted = StockFilterEngine.sortCatalogProducts(products, by: stockFilters.sort)
            return (catalogCategoryPresentation(key), sorted)
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

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                if hasAnyStockContent {
                    StockBrowseSearchBar(
                        searchText: $stockSearchText,
                        layoutMode: stockLayoutModeBinding,
                        onScan: { showBarcodeScanner = true },
                        searchFocused: $stockSearchFocused
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .background(Color.white)

                    stockSelectionToolbar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                        .background(Color.white)

                    StockBrowseFilterStrip(filters: $stockFilters) {
                        showStockFiltersSheet = true
                    }
                    .padding(.bottom, stockLayoutModeBinding.wrappedValue == .list ? 6 : 10)
                    .background(Color.white)

                    if stockLayoutModeBinding.wrappedValue == .list {
                        StockBrowseFilterSortBar(filters: $stockFilters) {
                            showStockFiltersSheet = true
                        }
                        .padding(.bottom, 10)
                        .background(Color.white)
                    }
                }

                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            Color.clear
                                .frame(height: 1)
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
            }

            if draftBannerCount > 0 {
                draftResumeBanner
            }

            if closetSelectionMode, !closetSelectedIDs.isEmpty || !catalogSelectedIDs.isEmpty {
                stockBulkActionBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .onReceive(NotificationCenter.default.publisher(for: .upsoledPresentAddToClosetMenu)) { _ in
            showAddMenuSheet = true
        }
        .task {
            ClosetInventoryRepair.normalizeSoldFlags(in: modelContext)
            ClosetInventoryRepair.backfillSKUFromNames(in: modelContext)
            catalogVM.fetchLimit = 750
            await catalogVM.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closetInventoryDidChange)) { _ in
            Task { await catalogVM.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .upsoledCatalogDidChange)) { _ in
            Task { await catalogVM.reload() }
        }
        .sheet(isPresented: $showAddMenuSheet) {
            addToClosetIntroSheet
                .presentationDragIndicator(.visible)
                .presentationDetents([.height(720)])
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: consumeCameraPickIfNeeded) {
            ClosetUIImagePickerBridge(image: $cameraImage)
                .background(Color.black)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showGalleryPickSheet) {
            NavigationStack {
                VStack(spacing: 22) {
                    Text(
                        "Choose up to 5 photos. With exactly 4 you can pick a 360° shoe view (front, right, back, left, in order) or analyze an outfit with the photos you choose."
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(ClosetFlowPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                    PhotosPicker(
                        selection: $pickedGalleryItems,
                        maxSelectionCount: 5,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Open photos", systemImage: "photo.on.rectangle.angled")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)

                    Button {
                        Task { await ingestPhotoPickerItems(pickedGalleryItems) }
                    } label: {
                        Label("Continue", systemImage: "arrow.forward.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.black.opacity(0.82))
                    .disabled(pickedGalleryItems.isEmpty)

                    Text("Select photos and tap Continue (pick 4 in order for 360° shoes or another amount for an outfit).")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.black.opacity(0.42))
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .navigationTitle("Gallery")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.tr("common.close")) {
                            pickedGalleryItems.removeAll()
                            showGalleryPickSheet = false
                        }
                    }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showPipeline) {
            AddToClosetPipelineView(isPresented: $showPipeline)
                .environmentObject(addFlow)
                .preferredColorScheme(.light)
        }
        .fullScreenCover(isPresented: $showShoe360FiveGalleryFlow, onDismiss: {
            shoe360FiveGalleryImagesPrepared = []
        }) {
            if shoe360FiveGalleryImagesPrepared.count == ShoeAngle.allCases.count {
                ClosetShoe360FlowView(prefilledCapturedInCanonicalOrder: shoe360FiveGalleryImagesPrepared)
                    .preferredColorScheme(.light)
            }
        }
        .fullScreenCover(isPresented: $showPrivateShoe360Flow) {
            ClosetShoe360FlowView()
                .preferredColorScheme(.light)
        }
        .fullScreenCover(isPresented: $showPrivateGarmentLookbookFlow) {
            ClosetGarmentLookbookStandaloneFlowView()
                .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showFivePhotosUseModeSheet) {
            fivePhotosUseModeSheet
                .presentationDragIndicator(.visible)
                .presentationDetents([.height(380)])
                .presentationBackground(Color.white)
                .preferredColorScheme(.light)
        }
        .toastOverlay(
            message: Binding(
                get: { addFlow.toast },
                set: { addFlow.toast = $0 }
            ))
        .sheet(isPresented: $showCreateLookSheet) {
            CreateLookComposerView()
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
                .preferredColorScheme(.light)
        }
        .sheet(item: $garmentDetailSheetItem) { item in
            ClosetGarmentDetailView(item: item)
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
                .preferredColorScheme(.light)
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
                closetItems: activeClosetItems,
                catalogProducts: catalogVM.products
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showBarcodeScanner) {
            StockBarcodeScannerScreen(
                onCode: { code in
                    showBarcodeScanner = false
                    stockSearchText = code
                    Task { await handleScannedCode(code) }
                },
                onCancel: { showBarcodeScanner = false }
            )
        }
        .sheet(item: $scanLookupPayload) { payload in
            StockScanResultSheet(
                payload: payload,
                onViewStockItem: { id in
                    scanLookupPayload = nil
                    if let item = activeClosetItems.first(where: { $0.id == id }) {
                        garmentDetailSheetItem = item
                    }
                },
                onDismiss: { scanLookupPayload = nil }
            )
            .presentationDetents([.height(340), .medium])
            .presentationDragIndicator(.visible)
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
            Button(L10n.tr("sold.removalSoldAction")) {
                if let request = removalRequest {
                    Task { await applyStockRemoval(reason: .sold, request: request) }
                }
                removalRequest = nil
            }
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

    private var fivePhotosUseModeSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("4 photos selected")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.black)

                Text(
                    "Shoes? Photos 1→4 map to: front, right side, back, and left side. "
                        + "You can correct any angle afterward."
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.52))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

                VStack(spacing: 11) {
                    Button {
                        let snap = stagingFiveGalleryImages
                        stagingFiveGalleryImages = []
                        showFivePhotosUseModeSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                            shoe360FiveGalleryImagesPrepared = snap
                            showShoe360FiveGalleryFlow = true
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text("👞 Shoes — 360° view")
                                .font(.system(size: 17, weight: .semibold))
                            Text("4 photos = smooth drag rotation (seamless transition between views)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(Color.black)
                        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white))
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        let snap = stagingFiveGalleryImages
                        stagingFiveGalleryImages = []
                        showFivePhotosUseModeSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                            showPipeline = true
                            addFlow.beginProcessing(images: snap)
                        }
                    } label: {
                        Text("Detect garments in outfit")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 26).fill(ClosetFlowPalette.darkerPillFill))
                    }
                    .buttonStyle(.plain)
                }

                Button("Cancel", role: .cancel) {
                    stagingFiveGalleryImages = []
                    showFivePhotosUseModeSheet = false
                }
                .font(.system(size: 15))

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .navigationTitle("Use your 4 photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) {
                        stagingFiveGalleryImages = []
                        showFivePhotosUseModeSheet = false
                    }
                    .foregroundStyle(Color.black)
                }
            }
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
                ClosetAnalytics.named("add_to_closet_opened")
                showAddMenuSheet = true
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
                ClosetAnalytics.named("add_to_closet_opened")
                showAddMenuSheet = true
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

    private var stockSelectionToolbar: some View {
        HStack(spacing: 12) {
            Button {
                if closetSelectionMode {
                    closetSelectionMode = false
                    closetSelectedIDs.removeAll()
                    catalogSelectedIDs.removeAll()
                } else {
                    closetSelectionMode = true
                }
            } label: {
                Text(closetSelectionMode ? "Done" : "Select")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)

            if closetSelectionMode {
                Text("\(closetSelectedIDs.count + catalogSelectedIDs.count) selected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
            }

            Spacer()
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
            garmentDetailSheetItem = item
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
        if hasAnyStockContent, stockGrandTotalCount > 0 {
            stockSummaryCard
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }

        if showsClosetStarterProgress, activeClosetItems.isEmpty {
            closetEmptyOnboardingDesign
                .padding(.bottom, bottomInsetForClosetGrid)
        } else if showsClosetStarterProgress {
            closetStarterProgressStrip
        }

        if hasAnyStockContent, filteredActiveClosetItems.isEmpty, filteredCatalogProducts.isEmpty {
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

        if !filteredCatalogProducts.isEmpty {
            if stockLayoutModeBinding.wrappedValue == .list {
                flatCatalogListSection
            } else {
                catalogStockSection
            }
        }

        if !filteredActiveClosetItems.isEmpty {
            if stockLayoutModeBinding.wrappedValue == .list {
                flatClosetListSection
            } else {
                sectionedClosetStockContent
            }
        }
    }

    private var sectionedClosetStockContent: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(filteredClosetStockSections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(section.category.emoji) \(section.category.displayName)")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.black)
                        Spacer(minLength: 8)
                        Text(PieceMarketPrice.formatUSD(Int(section.totalValueUSD.rounded())))
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.72))
                        Text("\(section.items.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.42))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 16)

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(section.items) { item in
                            closetCell(item)
                                .id("\(item.id)-\(item.priceText ?? "")-\(item.purchasePriceText ?? "")")
                                .padding(.top, 10)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .padding(.bottom, bottomInsetForClosetGrid)
    }

    private var flatClosetListSection: some View {
        LazyVStack(spacing: 0) {
            if !filteredCatalogProducts.isEmpty {
                Divider()
                    .overlay(Color.black.opacity(0.08))
            }
            ForEach(Array(filteredActiveClosetItems.enumerated()), id: \.element.id) { index, item in
                closetListRow(item)
                    .id("\(item.id)-\(item.priceText ?? "")-\(item.purchasePriceText ?? "")")
                if index < filteredActiveClosetItems.count - 1 {
                    StockMarketplaceListDivider()
                }
            }
        }
        .padding(.bottom, bottomInsetForClosetGrid)
    }

    private var flatCatalogListSection: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredCatalogProducts.enumerated()), id: \.element.id) { index, product in
                catalogListRow(product)
                if index < filteredCatalogProducts.count - 1 {
                    StockMarketplaceListDivider()
                }
            }
        }
        .padding(.bottom, filteredActiveClosetItems.isEmpty ? bottomInsetForClosetGrid : 0)
    }

    /// Catálogo Supabase agrupado por categoría (misma tarjeta que Marketplace).
    private var catalogStockSection: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(filteredCatalogStockSections, id: \.meta.key) { section in
                VStack(alignment: .leading, spacing: 10) {
                    catalogSectionHeader(
                        emoji: section.meta.emoji,
                        title: section.meta.title,
                        count: section.products.count,
                        valueUSD: section.products.reduce(0) { $0 + $1.stockValueUSD }
                    )

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(section.products) { product in
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
                    .padding(.horizontal, 8)
                }
            }
        }
        .padding(.bottom, filteredActiveClosetItems.isEmpty ? bottomInsetForClosetGrid : 0)
    }

    private func catalogSectionHeader(emoji: String, title: String, count: Int, valueUSD: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(emoji) \(title)")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.black)
            Spacer(minLength: 8)
            Text(PieceMarketPrice.formatUSD(Int(valueUSD.rounded())))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.72))
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.42))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
    }

    private var stockSummaryCard: some View {
        let invested = stockClosetInvestedUSD
        let profit = stockClosetProfitUSD

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL STOCK")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Color.black.opacity(0.45))
                    Text(PieceMarketPrice.formatUSD(Int(stockGrandTotalValueUSD.rounded())))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.black)
                    Text("\(stockGrandTotalCount) items · all categories")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.48))
                }
                Spacer(minLength: 0)
                if invested > 0 || profit != 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        if invested > 0 {
                            Text(PieceMarketPrice.formatUSD(Int(invested.rounded())))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.55))
                            Text("Invested")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.42))
                        }
                        if profit != 0 || invested > 0 {
                            Text(profit >= 0 ? "+\(PieceMarketPrice.formatUSD(Int(profit.rounded())))" : "−\(PieceMarketPrice.formatUSD(Int(abs(profit).rounded())))")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(profit >= 0 ? Color(red: 0.20, green: 0.70, blue: 0.45) : Color(red: 0.92, green: 0.30, blue: 0.30))
                            Text("Potential profit")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.42))
                        }
                    }
                }
            }

            if !stockCategoryBreakdowns.isEmpty {
                VStack(spacing: 0) {
                    ForEach(stockCategoryBreakdowns) { row in
                        HStack(spacing: 10) {
                            Text(row.emoji)
                                .font(.system(size: 16))
                            Text(row.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.82))
                            Spacer(minLength: 8)
                            Text("\(row.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.45))
                                .frame(minWidth: 22, alignment: .trailing)
                            Text(PieceMarketPrice.formatUSD(Int(row.valueUSD.rounded())))
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.88))
                                .frame(minWidth: 56, alignment: .trailing)
                        }
                        .padding(.vertical, 9)
                        if row.id != stockCategoryBreakdowns.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
        }
    }

    @MainActor
    private func handleScannedCode(_ code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        scanLookupBusy = true
        defer { scanLookupBusy = false }
        scanLookupPayload = await StockScanLookupService.lookup(
            code: trimmed,
            stock: activeClosetItems,
            goatVM: goatVM
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
            seriesLine: stockListBrandLine(item.brand),
            nameLine: item.catalogDisplayName,
            price: item.cardPriceLabel,
            size: item.cardSizeLabel,
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
                garmentDetailSheetItem = item
                ClosetAnalytics.named("closet_item_detail_open")
            }
        } image: {
            ClosetDiskThumbnail(relativePath: ImageStore.displayRelativePath(for: item))
        }
    }

    private func catalogListRow(_ product: UpsoledProduct) -> some View {
        let selected = catalogSelectedIDs.contains(product.id)
        return StockMarketplaceListRow(
            seriesLine: stockListBrandLine(product.brand),
            nameLine: product.name,
            price: product.cardPriceLabel,
            size: product.cardSizeLabel,
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
            StockCachedRemoteImage(url: product.primaryImageURL)
        }
    }

    private var draftResumeBanner: some View {
        Button {
            let decoded = ClosetLocalDraftStore.decoded()
            addFlow.resumePersistedDrafts(decoded: decoded)
            showPipeline = true
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

    private var addToClosetIntroSheet: some View {
        VStack(spacing: 14) {
            Text(L10n.tr("closet.addSheetTitle"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)

            Text(L10n.tr("closet.addSheetPhotoHint"))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 11) {
                HStack(spacing: 11) {
                    Button {
                        showAddMenuSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            showGalleryPickSheet = true
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 22, weight: .semibold))
                            Text("Gallery")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Up to 5 photos")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .foregroundStyle(Color.black)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showAddMenuSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            showCamera = true
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 22, weight: .semibold))
                            Text("Camera")
                                .font(.system(size: 16, weight: .semibold))
                            Text("One photo instantly")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .foregroundStyle(Color.black)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }

                shoePrivateStandalonePill

                garmentPrivateStandalonePill
            }
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .presentationBackground(Color.white)
    }

    /// Entrada aparte del outfit de galería: subir sólo zapatos y decidir foto por ángulo.
    private var shoePrivateStandalonePill: some View {
        Button {
            ClosetAnalytics.named("closet_shoe360_private_opened")
            showAddMenuSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                showPrivateShoe360Flow = true
            }
        } label: {
            HStack(spacing: 14) {
                Image("BannerZapatos")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 74, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your shoes only (360°)")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color.white)
                    Text("Front, right side, back, and left: tap each side and add or change its photo.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.88)))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    /// Entrada paralela «Zapatos 360»: ropa/complementos sin calzado → 5 referencias guiadas → 10 vistas IA estudio + lifestyle.
    private var garmentPrivateStandalonePill: some View {
        Button {
            ClosetAnalytics.named("closet_ropa_lookbook_standalone_opened")
            showAddMenuSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                showPrivateGarmentLookbookFlow = true
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.22)))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Apparel · AI lookbook")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color.white)
                    Text(
                        "Shirts, pants, socks, belts… 5 guide photos "
                            + "(front, back, details) and we generate catalog and lifestyle images you can swipe through.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.74)))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func closetCell(_ item: ClosetItem) -> some View {
        let selected = closetSelectedIDs.contains(item.id)
        return VStack(spacing: 9) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color.white

                    ClosetDiskThumbnail(relativePath: ImageStore.displayRelativePath(for: item))
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
                garmentDetailSheetItem = item
                ClosetAnalytics.named("closet_item_detail_open")
            }
        }
        .contextMenu {
            if !closetSelectionMode {
                Button(role: .destructive) {
                    removalRequest = StockRemovalRequest(closetIDs: [item.id], catalogIDs: [])
                } label: {
                    Label(L10n.tr("closet.removeItem"), systemImage: "trash")
                }
            }
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

    @MainActor
    private func consumeCameraPickIfNeeded() {
        defer { cameraImage = nil }
        guard let img = cameraImage else { return }
        pickedGalleryItems.removeAll()
        showGalleryPickSheet = false
        showPipeline = true
        addFlow.beginProcessing(images: [img])
    }

    @MainActor
    private func ingestPhotoPickerItems(_ items: [PhotosPickerItem]) async {
        var images = [UIImage]()
        for pi in items {
            if let data = try? await pi.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                images.append(ui.closetFlattenedOrientation())
            }
        }
        guard !images.isEmpty else {
            pickedGalleryItems.removeAll()
            showGalleryPickSheet = false
            return
        }
        pickedGalleryItems.removeAll()
        showGalleryPickSheet = false
        if images.count == ShoeAngle.allCases.count {
            stagingFiveGalleryImages = images
            showFivePhotosUseModeSheet = true
        } else {
            showPipeline = true
            addFlow.beginProcessing(images: images)
        }
    }
}

// MARK: - Zapatos 360° (galería o solo zapatos / “privados”)

/// Pantalla puente: nombre + `ShoeMultiAngleCaptureView`. Opcionalmente trae las 4 fotos ya ordenadas desde galería; si es `nil`, configuración foto a foto.
private struct ClosetShoe360FlowView: View {
    var prefilledCapturedInCanonicalOrder: [UIImage]? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var shoeName = "Zapatos"

    private var trimmedName: String {
        let t = shoeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Zapatos" : t
    }

    private var isPrivateFlow: Bool { prefilledCapturedInCanonicalOrder == nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        isPrivateFlow
                            ? "Tap each angle (front, right, back, left) and use Camera or Gallery to set that view. Here you decide which photo is each side of the shoe."
                            : "Photos were taken in the order you chose in the gallery — tap an angle to correct it."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    TextField("Nombre del zapato", text: $shoeName)
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
                    prefilledCapturedInAngleOrder: prefilledCapturedInCanonicalOrder,
                    showsCloseButton: false,
                    onOrderedPathsCommitted: saveToCloset
                )
                .id(prefilledCapturedInCanonicalOrder?.count.description ?? "private")
            }
            .navigationTitle(isPrivateFlow ? "Zapatos — solo tus fotos" : "Zapatos — 360°")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { dismiss() }
                        .foregroundStyle(Color.black)
                }
            }
        }
        .preferredColorScheme(.light)
        .background(Color.white)
    }

    private func saveToCloset(paths: [String]) {
        guard paths.count == ShoeAngle.allCases.count else { return }
        let leftIdx = ShoeAngle.left.rawValue
        let imageFile = paths.indices.contains(leftIdx) ? paths[leftIdx] : paths[0]

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
            category: .shoes,
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
            await enrichSavedShoeMetadata(row: row, coverPath: imageFile)
        }
        ClosetAnalytics.named(
            isPrivateFlow ? "closet_shoe360_private_saved" : "closet_shoe360_gallery_saved")
    }

    @MainActor
    private func enrichSavedShoeMetadata(row: ClosetItem, coverPath: String) async {
        guard GeminiService.apiKeyConfigured else { return }
        do {
            let meta = try await GeminiService.shared.enrichGarmentMetadata(
                cropRelativePath: coverPath,
                category: .shoes,
                provisionalName: row.name
            )
            if !meta.brand.isEmpty { row.brand = meta.brand }
            if !meta.sku.isEmpty {
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
            // Metadatos opcionales al guardar zapatos directos.
        }
    }
}

// MARK: - Ropa / complementos · lookbook (entradas paralelas sin outfit)

private struct ClosetGarmentLookbookStandaloneFlowView: View {
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
        NavigationStack {
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
        NavigationStack {
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
                        flow.pieces.first(where: { $0.id == token.pieceID })?.name ?? "Zapatos"
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
            if let ui = ImageStore.load(path) {
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
            .overlay(alignment: .bottom) {
                if let msg = message {
                    Text(msg)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.black.opacity(0.9)))
                        .padding(.bottom, 48)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.85), value: message)
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
        case "STOCKX":      return Color(red: 0.00, green: 0.60, blue: 0.30)
        case "GOAT":        return Color(red: 0.10, green: 0.10, blue: 0.10)
        case "FLIGHT CLUB": return Color(red: 0.85, green: 0.10, blue: 0.15)
        default:            return Color.gray
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

    /// Tries KicksDB (StockX + GOAT), then GOAT account, then OpenAI web search.
    @MainActor
    static func lookupForItem(
        _ item: ClosetItem,
        goatVM: GoatAccountViewModel,
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

        if goatVM.hasProviderToken {
            for query in queries {
                if let est = await goatVM.fetchMarketPriceEstimate(query: query) {
                    return est
                }
            }
        }

        guard useWebSearch else {
            throw NSError(domain: "PieceMarketPrice", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No market price found. Add KICKSDB_API_KEY in DeveloperSettings.local.xcconfig."
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
    private static let baseURL = "https://api.kicks.dev/v3"

    /// Plataformas soportadas en el plan free (mapeo a path de KicksDB).
    enum Platform: String, CaseIterable {
        case stockx
        case goat
        case flightclub
    }

    /// Lee la key del Info.plist (inyectada por xcconfig).
    static var apiKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "KICKSDB_API_KEY") as? String else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static var isConfigured: Bool { apiKey != nil }

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
            image = try? c.decode(String.self, forKey: .image)
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

    /// Busca el primer hit en una plataforma concreta.
    static func search(platform: Platform, query: String) async throws -> ProductHit? {
        let path = "/\(platform.rawValue)/products?query="
        return try await getFirst(at: path + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
    }

    /// Para GOAT necesitamos llamar al endpoint de detalle (`/products/{slug}`)
    /// porque el search no incluye `variants[].lowest_ask`. Para StockX, las variants
    /// requieren `?display[variants]=true`.
    static func detail(platform: Platform, slugOrID: String) async throws -> ProductHit? {
        let needsVariantsParam = (platform == .stockx)
        let path = "/\(platform.rawValue)/products/\(slugOrID)" + (needsVariantsParam ? "?display[variants]=true" : "")
        struct DetailEnvelope: Decodable { let data: ProductHit? }
        guard let key = apiKey else {
            throw NSError(domain: "KicksDB", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Falta KICKSDB_API_KEY"
            ])
        }
        guard let url = URL(string: "\(baseURL)\(path)") else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        let envelope = try JSONDecoder().decode(DetailEnvelope.self, from: data)
        return envelope.data
    }

    private static func getFirst(at path: String) async throws -> ProductHit? {
        guard let key = apiKey else {
            throw NSError(domain: "KicksDB", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Falta KICKSDB_API_KEY"
            ])
        }
        guard let url = URL(string: "\(baseURL)\(path)") else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[KicksDB] HTTP \(http.statusCode) en \(path) · body: \(body.prefix(200))")
            throw NSError(domain: "KicksDB", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "KicksDB HTTP \(http.statusCode) · \(body.prefix(120))"
            ])
        }

        let envelope = try JSONDecoder().decode(SearchEnvelope.self, from: data)
        let result = envelope.data?.first
        if result == nil {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[KicksDB] 200 OK pero sin data en \(path) · body: \(body.prefix(240))")
        }
        return result
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
        var t3 = t2.replacingOccurrences(of: " Boost", with: "", options: .caseInsensitive)
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
                NSLocalizedDescriptionKey: "Falta KICKSDB_API_KEY"
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

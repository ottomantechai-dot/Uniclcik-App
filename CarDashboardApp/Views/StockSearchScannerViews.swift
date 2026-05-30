import AVFoundation
import SwiftUI
import UIKit

// MARK: - Stock image cache (scroll fluido, sin recargas)

enum StockImageLoader {
    private actor InflightCoordinator {
        static let shared = InflightCoordinator()
        var tasks: [String: Task<UIImage?, Never>] = [:]

        func existing(for key: String) -> Task<UIImage?, Never>? { tasks[key] }
        func register(_ task: Task<UIImage?, Never>, for key: String) { tasks[key] = task }
        func remove(for key: String) { tasks.removeValue(forKey: key) }
    }

    static func localCacheKey(_ path: String) -> String { "stock:local:\(path)" }
    static func urlCacheKey(_ url: URL) -> String { "stock:url:\(url.absoluteString)" }

    static func cachedLocalImage(relativePath: String) -> UIImage? {
        guard !relativePath.isEmpty else { return nil }
        let key = localCacheKey(relativePath)
        if let mem = ImageCacheService.shared.image(forKey: key) { return mem }
        // Decodifica directamente a tamaño de miniatura desde disco (sin cargar el bitmap
        // completo en memoria). Evita guardar fotos a resolución completa en la caché y
        // elimina los tirones por evicción/re-decodificación durante el scroll.
        guard let ui = downsampledLocalImage(relativePath: relativePath, maxSide: 400)
            ?? ImageStore.load(relativePath) else { return nil }
        ImageCacheService.shared.store(ui, forKey: key)
        return ui
    }

    /// Carga + downsample desde disco usando `CGImageSource` (no decodifica la imagen completa).
    static func downsampledLocalImage(relativePath: String, maxSide: CGFloat) -> UIImage? {
        let url = ImageStore.url(forRelativePath: relativePath)
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxSide * 3),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Versión asíncrona: hace el decode/downsample fuera del hilo principal.
    static func cachedLocalImageAsync(relativePath: String) async -> UIImage? {
        guard !relativePath.isEmpty else { return nil }
        let key = localCacheKey(relativePath)
        if let mem = ImageCacheService.shared.image(forKey: key) { return mem }
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            downsampledLocalImage(relativePath: relativePath, maxSide: 400)
                ?? ImageStore.load(relativePath)
        }.value
        if let image { ImageCacheService.shared.store(image, forKey: key) }
        return image
    }

    static func memoryCachedURLImage(for url: URL) -> UIImage? {
        ImageCacheService.shared.image(forKey: urlCacheKey(url))
    }

    static func cachedURLImage(for url: URL) async -> UIImage? {
        let key = urlCacheKey(url)
        if let mem = ImageCacheService.shared.image(forKey: key) { return mem }

        if let existing = await InflightCoordinator.shared.existing(for: key) {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            defer { Task { await InflightCoordinator.shared.remove(for: key) } }
            do {
                let (data, _) = try await CarUIImageLoader.imageSession.data(from: url)
                guard let raw = UIImage(data: data) else { return nil }
                let img = downsampleIfNeeded(raw, maxSide: 176)
                ImageCacheService.shared.store(img, forKey: key)
                return img
            } catch {
                return nil
            }
        }
        await InflightCoordinator.shared.register(task, for: key)
        return await task.value
    }

    private static func downsampleIfNeeded(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let maxDim = max(image.size.width, image.size.height)
        guard maxDim > maxSide else { return image }
        let scale = maxSide / maxDim
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

struct StockCachedRemoteImage: View {
    let url: URL?

    @State private var image: UIImage?

    init(url: URL?) {
        self.url = url
        if let url {
            _image = State(initialValue: StockImageLoader.memoryCachedURLImage(for: url))
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if url != nil {
                Color.white
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.black.opacity(0.22))
            }
        }
        .task(id: url?.absoluteString) {
            guard let url, image == nil else { return }
            if let loaded = await StockImageLoader.cachedURLImage(for: url) {
                image = loaded
            }
        }
    }
}

// MARK: - Layout mode

enum StockLayoutMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .grid: return L10n.tr("closet.layoutGrid")
        case .list: return L10n.tr("closet.layoutList")
        }
    }
}

// MARK: - Profit badge (grid cards)

struct StockProfitCornerBadge: View {
    let usdLabel: String?
    let pctLabel: String?
    let isLoss: Bool

    var body: some View {
        let tint = isLoss
            ? Color(red: 0.92, green: 0.30, blue: 0.30)
            : Color(red: 0.20, green: 0.70, blue: 0.45)

        VStack(alignment: .trailing, spacing: 2) {
            if let usd = usdLabel {
                Text(usd)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            if let pct = pctLabel {
                Text(pct)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint)
                .shadow(color: tint.opacity(0.35), radius: 6, y: 2)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Marketplace list row (StockX-style)

struct StockMarketplaceListRow<ImageContent: View>: View {
    let seriesLine: String
    let nameLine: String
    var price: String? = nil
    var size: String? = nil
    var profitUSD: String? = nil
    var profitPct: String? = nil
    var isLoss: Bool = false
    var showProfitBadge: Bool = false
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var onTap: () -> Void
    @ViewBuilder var image: () -> ImageContent

    private let rowHeight: CGFloat = 108
    private let thumbSide: CGFloat = 88
    private let priceColumnWidth: CGFloat = 76
    private let textBlockHeight: CGFloat = 68

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Color.white
                        .frame(width: thumbSide, height: thumbSide)
                        .overlay {
                            image()
                                .frame(width: thumbSide - 10, height: thumbSide - 10)
                        }

                    if showProfitBadge, !selectionMode {
                        StockProfitCornerBadge(
                            usdLabel: profitUSD,
                            pctLabel: profitPct,
                            isLoss: isLoss
                        )
                        .scaleEffect(0.78)
                        .offset(x: 4, y: -6)
                    }
                }
                .frame(width: thumbSide, height: thumbSide)

                VStack(alignment: .leading, spacing: 2) {
                    Text(seriesLine)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.62))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .topLeading)

                    Text(nameLine)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: textBlockHeight)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(price ?? " ")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(price == nil ? Color.clear : Color.black.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(height: 22, alignment: .trailing)

                    Text(size ?? " ")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(size == nil ? Color.clear : Color.black.opacity(0.45))
                        .lineLimit(1)
                        .frame(height: 18, alignment: .trailing)

                    Group {
                        if selectionMode {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(isSelected ? Color.black : Color.black.opacity(0.22))
                                .contentTransition(.symbolEffect(.replace))
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .frame(width: priceColumnWidth)
            }
            .frame(height: rowHeight)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(selectionMode && isSelected ? Color.black.opacity(0.05) : Color.clear)
            }
            .animation(.easeInOut(duration: 0.18), value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StockMarketplaceListDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.black.opacity(0.08))
            .padding(.leading, 116)
    }
}

// MARK: - Search bar (reference: pill + barcode inside)

struct StockBrowseSearchBar: View {
    @Binding var searchText: String
    @Binding var layoutMode: StockLayoutMode
    var onScan: () -> Void
    @FocusState.Binding var searchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))

                TextField("", text: $searchText, prompt: Text(L10n.tr("closet.searchPrompt")).foregroundStyle(Color.black.opacity(0.38)))
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.black.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onScan) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.72))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("closet.scanBarcode"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                LiquidGlassSearchPillBackground()
            }

            HStack(spacing: 4) {
                ForEach(StockLayoutMode.allCases) { mode in
                    Button {
                        layoutMode = mode
                    } label: {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(layoutMode == mode ? Color.white : Color.black.opacity(0.55))
                            .frame(width: 36, height: 36)
                            .background {
                                Circle()
                                    .fill(layoutMode == mode ? Color.black : Color.black.opacity(0.06))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.accessibilityLabel)
                }
            }
        }
    }
}

// MARK: - Stock browse filters

enum StockSortOrder: String, CaseIterable, Identifiable {
    case newest
    case priceLowHigh
    case priceHighLow
    case sizeLowHigh
    case sizeHighLow
    case brandAZ

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Newest"
        case .priceLowHigh: return "Price: low → high"
        case .priceHighLow: return "Price: high → low"
        case .sizeLowHigh: return "Size: low → high"
        case .sizeHighLow: return "Size: high → low"
        case .brandAZ: return "Brand A → Z"
        }
    }

    var menuLabel: String {
        switch self {
        case .newest: return "Destacado"
        case .priceLowHigh: return "Precio ↑"
        case .priceHighLow: return "Precio ↓"
        case .sizeLowHigh: return "Talla ↑"
        case .sizeHighLow: return "Talla ↓"
        case .brandAZ: return "Marca A-Z"
        }
    }
}

enum StockQuickCategory: String, CaseIterable, Identifiable {
    case all
    case shoes
    case clothing
    case accessories
    case bags

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .shoes: return "Shoes"
        case .clothing: return "Clothing"
        case .accessories: return "Accessories"
        case .bags: return "Bags"
        }
    }

    var emoji: String {
        switch self {
        case .all: return "✨"
        case .shoes: return "👞"
        case .clothing: return "👔"
        case .accessories: return "⌚"
        case .bags: return "👜"
        }
    }

    var categoryKeys: Set<String> {
        switch self {
        case .all: return []
        case .shoes: return ["shoes"]
        case .clothing: return [
            "clothing", "tops", "dresses_jumpsuits", "pants_skirts", "coats", "underwear",
            "vintage", "new-drops", "new_drops",
        ]
        case .accessories: return ["accessories"]
        case .bags: return ["bags"]
        }
    }
}

struct StockBrowseFilters: Equatable {
    var sort: StockSortOrder = .newest
    var categoryKeys: Set<String> = []
    var brands: Set<String> = []
    var sizes: Set<String> = []

    var quickCategory: StockQuickCategory {
        get {
            if categoryKeys.isEmpty { return .all }
            for quick in StockQuickCategory.allCases where quick != .all {
                if categoryKeys == quick.categoryKeys { return quick }
            }
            return .all
        }
        set {
            categoryKeys = newValue.categoryKeys
        }
    }

    var isActive: Bool {
        !categoryKeys.isEmpty || !brands.isEmpty || !sizes.isEmpty || sort != .newest
    }

    mutating func reset() {
        sort = .newest
        categoryKeys = []
        brands = []
        sizes = []
    }
}

enum StockFilterEngine {
    static func closetCategoryKey(_ item: ClosetItem) -> String {
        item.category.rawValue
    }

    static func catalogCategoryKey(_ product: UpsoledProduct) -> String {
        let raw = (product.category ?? "other").lowercased()
        if ClothingCategory(rawValue: raw) != nil { return raw }
        switch raw {
        case "clothing": return "clothing"
        case "new-drops", "new_drops": return "new-drops"
        default: return raw
        }
    }

    static func brandKey(_ raw: String?) -> String? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !t.isEmpty, t.lowercased() != "unknown brand" else { return nil }
        return t
    }

    static func matches(_ filters: StockBrowseFilters, closetItem item: ClosetItem) -> Bool {
        if !filters.categoryKeys.isEmpty,
           !filters.categoryKeys.contains(closetCategoryKey(item)) {
            return false
        }
        if !filters.brands.isEmpty {
            guard let b = brandKey(item.brand), filters.brands.contains(b) else { return false }
        }
        if !filters.sizes.isEmpty {
            guard let s = StockSizeDisplay.normalizedStorage(from: item.sizeText),
                  filters.sizes.contains(s) else { return false }
        }
        return true
    }

    static func matches(_ filters: StockBrowseFilters, catalogProduct product: UpsoledProduct) -> Bool {
        if !filters.categoryKeys.isEmpty,
           !filters.categoryKeys.contains(catalogCategoryKey(product)) {
            return false
        }
        if !filters.brands.isEmpty {
            guard let b = brandKey(product.brand), filters.brands.contains(b) else { return false }
        }
        if !filters.sizes.isEmpty {
            let productSizes = product.sizes.compactMap { StockSizeDisplay.normalizedStorage(from: $0) }
            guard productSizes.contains(where: { filters.sizes.contains($0) }) else { return false }
        }
        return true
    }

    static func sortClosetItems(_ items: [ClosetItem], by order: StockSortOrder) -> [ClosetItem] {
        switch order {
        case .newest:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .priceLowHigh:
            return items.sorted { $0.stockValueUSD < $1.stockValueUSD }
        case .priceHighLow:
            return items.sorted { $0.stockValueUSD > $1.stockValueUSD }
        case .sizeLowHigh:
            return items.sorted {
                StockSizeDisplay.sortValue(from: $0.sizeText) < StockSizeDisplay.sortValue(from: $1.sizeText)
            }
        case .sizeHighLow:
            return items.sorted {
                StockSizeDisplay.sortValue(from: $0.sizeText) > StockSizeDisplay.sortValue(from: $1.sizeText)
            }
        case .brandAZ:
            return items.sorted {
                ($0.brand ?? "").localizedCaseInsensitiveCompare($1.brand ?? "") == .orderedAscending
            }
        }
    }

    static func sortCatalogProducts(_ products: [UpsoledProduct], by order: StockSortOrder) -> [UpsoledProduct] {
        switch order {
        case .newest:
            return products.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .priceLowHigh:
            return products.sorted { $0.stockValueUSD < $1.stockValueUSD }
        case .priceHighLow:
            return products.sorted { $0.stockValueUSD > $1.stockValueUSD }
        case .sizeLowHigh:
            return products.sorted {
                let a = productSizeSortValue($0)
                let b = productSizeSortValue($1)
                return a < b
            }
        case .sizeHighLow:
            return products.sorted {
                productSizeSortValue($0) > productSizeSortValue($1)
            }
        case .brandAZ:
            return products.sorted {
                ($0.brand ?? "").localizedCaseInsensitiveCompare($1.brand ?? "") == .orderedAscending
            }
        }
    }

    private static func productSizeSortValue(_ product: UpsoledProduct) -> Double {
        let cores = product.sizes.compactMap { StockSizeDisplay.normalizedStorage(from: $0) }
        guard let first = cores.first else { return 9999 }
        return StockSizeDisplay.sortValue(from: first)
    }

    static func availableBrands(closet: [ClosetItem], catalog: [UpsoledProduct]) -> [String] {
        var set = Set<String>()
        for item in closet {
            if let b = brandKey(item.brand) { set.insert(b) }
        }
        for p in catalog {
            if let b = brandKey(p.brand) { set.insert(b) }
        }
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func availableSizes(closet: [ClosetItem], catalog: [UpsoledProduct]) -> [String] {
        var set = Set<String>()
        for item in closet {
            if let s = StockSizeDisplay.normalizedStorage(from: item.sizeText) { set.insert(s) }
        }
        for p in catalog {
            for raw in p.sizes {
                if let s = StockSizeDisplay.normalizedStorage(from: raw) { set.insert(s) }
            }
        }
        return set.sorted {
            StockSizeDisplay.sortValue(from: $0) < StockSizeDisplay.sortValue(from: $1)
        }
    }

    static func availableCategoryOptions(closet: [ClosetItem], catalog: [UpsoledProduct]) -> [(key: String, emoji: String, title: String)] {
        var keys = Set<String>()
        for item in closet { keys.insert(closetCategoryKey(item)) }
        for p in catalog { keys.insert(catalogCategoryKey(p)) }

        let meta: (String) -> (String, String) = { key in
            if let cat = ClothingCategory(rawValue: key) {
                return (cat.emoji, cat.displayName)
            }
            switch key {
            case "clothing": return ("👔", "Clothing")
            case "shoes": return ("👞", "Shoes")
            case "accessories": return ("⌚", "Accessories")
            case "vintage": return ("🕰️", "Vintage")
            case "new-drops": return ("✨", "New drops")
            default: return ("📦", key.replacingOccurrences(of: "_", with: " ").capitalized)
            }
        }

        return keys.sorted().map { key in
            let m = meta(key)
            return (key, m.0, m.1)
        }
    }
}

// MARK: - Filter strip + sheet UI

struct StockBrowseFilterStrip: View {
    @Binding var filters: StockBrowseFilters
    var onOpenSheet: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StockQuickCategory.allCases) { quick in
                    let active = filters.quickCategory == quick
                    Button {
                        filters.quickCategory = quick
                    } label: {
                        HStack(spacing: 4) {
                            Text(quick.emoji)
                            Text(quick.label)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(active ? Color.white : Color.black.opacity(0.72))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            Capsule().fill(active ? Color.black : Color.black.opacity(0.06))
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onOpenSheet) {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Filters")
                            .font(.system(size: 12, weight: .semibold))
                        if filters.isActive {
                            Circle()
                                .fill(Color(red: 0.20, green: 0.45, blue: 0.85))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .foregroundStyle(Color.black.opacity(0.82))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }
}

struct StockBrowseFilterSortBar: View {
    @Binding var filters: StockBrowseFilters
    var onFilter: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onFilter) {
                HStack(spacing: 6) {
                    Text("Filtrar por")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                }
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(StockSortOrder.allCases) { order in
                    Button {
                        filters.sort = order
                    } label: {
                        if filters.sort == order {
                            Label(order.menuLabel, systemImage: "checkmark")
                        } else {
                            Text(order.menuLabel)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Ordenar por: \(filters.sort.menuLabel)")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

struct StockBrowseFiltersSheet: View {
    @Binding var filters: StockBrowseFilters
    let closetItems: [ClosetItem]
    let catalogProducts: [UpsoledProduct]
    @Environment(\.dismiss) private var dismiss

    private var brands: [String] {
        StockFilterEngine.availableBrands(closet: closetItems, catalog: catalogProducts)
    }

    private var sizes: [String] {
        StockFilterEngine.availableSizes(closet: closetItems, catalog: catalogProducts)
    }

    private var categories: [(key: String, emoji: String, title: String)] {
        StockFilterEngine.availableCategoryOptions(closet: closetItems, catalog: catalogProducts)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Sort by") {
                    Picker("Sort", selection: $filters.sort) {
                        ForEach(StockSortOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if !categories.isEmpty {
                    Section("Category") {
                        ForEach(categories, id: \.key) { cat in
                            filterToggleRow(
                                title: "\(cat.emoji) \(cat.title)",
                                isOn: filters.categoryKeys.isEmpty || filters.categoryKeys.contains(cat.key)
                            ) {
                                toggleCategory(cat.key)
                            }
                        }
                    }
                }

                if !brands.isEmpty {
                    Section("Brand") {
                        ForEach(brands, id: \.self) { brand in
                            filterToggleRow(
                                title: brand,
                                isOn: filters.brands.isEmpty || filters.brands.contains(brand)
                            ) {
                                toggleBrand(brand)
                            }
                        }
                    }
                }

                if !sizes.isEmpty {
                    Section("Size") {
                        ForEach(sizes, id: \.self) { size in
                            filterToggleRow(
                                title: StockSizeDisplay.cardLabel(from: size) ?? size,
                                isOn: filters.sizes.isEmpty || filters.sizes.contains(size)
                            ) {
                                toggleSize(size)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { filters.reset() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func filterToggleRow(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(Color.black)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.black : Color.black.opacity(0.25))
            }
        }
    }

    private func toggleCategory(_ key: String) {
        if filters.categoryKeys.isEmpty {
            filters.categoryKeys = Set(categories.map(\.key).filter { $0 != key })
        } else if filters.categoryKeys.contains(key) {
            filters.categoryKeys.remove(key)
            if filters.categoryKeys.count == categories.count - 1 {
                filters.categoryKeys = []
            }
        } else {
            filters.categoryKeys.insert(key)
            if filters.categoryKeys.count == categories.count {
                filters.categoryKeys = []
            }
        }
    }

    private func toggleBrand(_ brand: String) {
        if filters.brands.isEmpty {
            filters.brands = Set(brands.filter { $0 != brand })
        } else if filters.brands.contains(brand) {
            filters.brands.remove(brand)
            if filters.brands.count == brands.count - 1 { filters.brands = [] }
        } else {
            filters.brands.insert(brand)
            if filters.brands.count == brands.count { filters.brands = [] }
        }
    }

    private func toggleSize(_ size: String) {
        if filters.sizes.isEmpty {
            filters.sizes = Set(sizes.filter { $0 != size })
        } else if filters.sizes.contains(size) {
            filters.sizes.remove(size)
            if filters.sizes.count == sizes.count - 1 { filters.sizes = [] }
        } else {
            filters.sizes.insert(size)
            if filters.sizes.count == sizes.count { filters.sizes = [] }
        }
    }
}

// MARK: - Scan lookup payload

struct StockScanLookupPayload: Identifiable {
    let id = UUID()
    let scannedCode: String
    let productTitle: String
    let brand: String
    let sku: String
    let imageURL: String?
    let buyPriceUSD: Int?
    let sellPriceUSD: Int?
    let marketEstimate: PieceMarketPrice?
    let matchingStockItemID: UUID?
}

enum StockScanLookupService {
    @MainActor
    static func lookup(
        code rawCode: String,
        stock: [ClosetItem],
        goatVM: GoatAccountViewModel
    ) async -> StockScanLookupPayload {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = code.uppercased()
        let local = stock.first { item in
            let sku = (item.resolvedSKU ?? "").uppercased()
            if !sku.isEmpty, sku == normalized { return true }
            if let stored = item.skuText?.uppercased(), stored == normalized { return true }
            return item.name.uppercased().contains(normalized)
        }

        if goatVM.hasProviderToken {
            do {
                let pair = try await GoatAliasAPIService.searchAndPrice(keyword: code)
                let product = pair.product
                let prices = pair.prices
                return StockScanLookupPayload(
                    scannedCode: code,
                    productTitle: product.displayTitle,
                    brand: product.brand,
                    sku: product.sku.isEmpty ? normalized : product.sku,
                    imageURL: product.imageURL,
                    buyPriceUSD: prices.lowestUSD,
                    sellPriceUSD: prices.highestOfferUSD,
                    marketEstimate: prices.asPieceMarketPrice(),
                    matchingStockItemID: local?.id
                )
            } catch {
                // Fall through to OpenAI / local-only payload.
            }
        }

        do {
            let est = try await PieceMarketPrice.fetchStyleFromInternet(
                styleCode: SneakerSKU.extract(from: code) ?? normalized,
                brand: local?.brand,
                category: local?.category.displayName ?? "Shoes",
                sizeText: local?.sizeText,
                useWebSearch: true
            )
            return StockScanLookupPayload(
                scannedCode: code,
                productTitle: local?.catalogDisplayName ?? "Style \(normalized)",
                brand: local?.brand ?? "",
                sku: SneakerSKU.extract(from: code) ?? normalized,
                imageURL: nil,
                buyPriceUSD: est.avg,
                sellPriceUSD: est.max,
                marketEstimate: est,
                matchingStockItemID: local?.id
            )
        } catch {
            let style = SneakerSKU.extract(from: code) ?? normalized
            return StockScanLookupPayload(
                scannedCode: code,
                productTitle: local?.catalogDisplayName ?? "Style \(style)",
                brand: local?.brand ?? "",
                sku: style,
                imageURL: nil,
                buyPriceUSD: nil,
                sellPriceUSD: nil,
                marketEstimate: nil,
                matchingStockItemID: local?.id
            )
        }
    }
}

// MARK: - Barcode scanner (full screen)

struct StockBarcodeScannerScreen: View {
    var onCode: (String) -> Void
    var onCancel: () -> Void

    @State private var torchOn = false
    @State private var didScan = false

    var body: some View {
        ZStack {
            StockBarcodeCameraView(isTorchOn: torchOn) { code in
                guard !didScan else { return }
                didScan = true
                onCode(code)
            }
            .ignoresSafeArea()

            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .mask {
                    Rectangle()
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .frame(width: 280, height: 170)
                                .blendMode(.destinationOut)
                        }
                }
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        torchOn.toggle()
                    } label: {
                        Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Spacer()

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: 280, height: 170)
                    .overlay(alignment: .topLeading) {
                        scanCorner(rotation: 0)
                    }
                    .overlay(alignment: .topTrailing) {
                        scanCorner(rotation: 90)
                    }
                    .overlay(alignment: .bottomLeading) {
                        scanCorner(rotation: 270)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        scanCorner(rotation: 180)
                    }

                Spacer()

                Text(L10n.tr("closet.scanHint"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 40)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func scanCorner(rotation: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 18))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 18, y: 0))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .frame(width: 18, height: 18)
        .rotationEffect(.degrees(rotation))
        .padding(6)
    }
}

private struct StockBarcodeCameraView: UIViewControllerRepresentable {
    var isTorchOn: Bool
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> StockBarcodeScannerViewController {
        let vc = StockBarcodeScannerViewController()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ uiViewController: StockBarcodeScannerViewController, context: Context) {
        uiViewController.setTorch(isTorchOn)
    }
}

final class StockBarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureDevice: AVCaptureDevice?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
        setTorch(false)
    }

    func setTorch(_ on: Bool) {
        guard let device = captureDevice, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    private func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupCapture() }
                }
            }
        default:
            break
        }
    }

    private func setupCapture() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        captureDevice = device
        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.ean8, .ean13, .code128, .code39, .qr, .upce, .pdf417, .code93]
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(value)
    }
}

// MARK: - Scan result sheet

struct StockScanResultSheet: View {
    let payload: StockScanLookupPayload
    var onViewStockItem: (UUID) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("closet.scanSuccess"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            HStack(alignment: .top, spacing: 14) {
                productThumb
                VStack(alignment: .leading, spacing: 6) {
                    Text(payload.productTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black)
                        .lineLimit(3)
                    if !payload.sku.isEmpty {
                        Text("SKU \(payload.sku)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.55))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            HStack(spacing: 10) {
                priceActionCard(
                    title: L10n.tr("closet.scanBuyLabel"),
                    value: payload.buyPriceUSD,
                    background: Color(red: 0.20, green: 0.70, blue: 0.45)
                )
                priceActionCard(
                    title: L10n.tr("closet.scanSellLabel"),
                    value: payload.sellPriceUSD,
                    background: Color.black
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            if let itemID = payload.matchingStockItemID {
                Button {
                    onViewStockItem(itemID)
                } label: {
                    Text(L10n.tr("closet.scanViewInStock"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }

            Spacer(minLength: 12)
        }
        .background(Color.white)
    }

    @ViewBuilder
    private var productThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 72, height: 72)
            if let urlStr = payload.imageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        Image(systemName: "shoeprints.fill")
                            .foregroundStyle(Color.black.opacity(0.25))
                    }
                }
                .frame(width: 64, height: 64)
            } else {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.black.opacity(0.25))
            }
        }
    }

    private func priceActionCard(title: String, value: Int?, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
            Text(value.map { PieceMarketPrice.formatUSD($0) } ?? "—")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(background)
        }
    }
}

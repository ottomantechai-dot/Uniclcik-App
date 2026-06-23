import SwiftUI

// MARK: - Home screen (mockup layout)

enum DashboardHomePalette {
    static let pageBG = Color(red: 0.975, green: 0.975, blue: 0.985)
    static let accentGreen = Color(red: 0.11, green: 0.68, blue: 0.44)
    static let accentPurple = Color(red: 0.55, green: 0.36, blue: 0.98)
    static let accentBlue = Color(red: 0.18, green: 0.42, blue: 0.82)
    static let labelMuted = Color.black.opacity(0.42)
    static let textPrimary = Color.black.opacity(0.90)
    static let cardBorder = Color.black.opacity(0.06)
    static let cardShadow = Color.black.opacity(0.04)
    static let innerSurface = Color(red: 0.985, green: 0.985, blue: 0.99)
}

struct HomeSneakerHighlight: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let changePercent: Double
    let history: [Double]
    let closetItem: ClosetItem?
    let catalogProduct: UpsoledProduct?

    var name: String { title }

    var marketLookup: (query: String, fallback: String?)? {
        if let closet = closetItem {
            let query = closet.resolvedSKU ?? closet.marketLookupQuery
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (query, closet.catalogDisplayName)
        }
        if let product = catalogProduct {
            let sku = product.sku?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !sku.isEmpty { return (sku, product.name) }
            let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let brand = product.brand?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name, brand?.isEmpty == false ? brand : nil)
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        return (trimmedTitle, subtitle.isEmpty ? nil : subtitle)
    }

    var displayName: String {
        if subtitle.isEmpty { return title }
        return "\(subtitle) \(title)"
    }
}

enum HomeScreenDataBuilder {
    private enum TrendingShoeBrand: CaseIterable {
        case jordan
        case nike
        case adidas
        case newBalance

        static let pickOrder: [TrendingShoeBrand] = [.jordan, .adidas, .newBalance, .adidas]

        static func classify(brand: String?, name: String) -> TrendingShoeBrand? {
            let haystack = "\(brand ?? "") \(name)"
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if haystack.contains("yeezy") { return nil }

            if haystack.contains("jordan") || haystack.contains("jumpman") || haystack.contains("air jordan") {
                return .jordan
            }
            if haystack.contains("new balance") || haystack.contains("newbalance") {
                return .newBalance
            }
            if haystack.contains("adidas") {
                return .adidas
            }

            let nikeFamily = [
                "nike", "air max", "dunk", "air force", "blazer", "cortez", "sb "
            ]
            if nikeFamily.contains(where: { haystack.contains($0) }) {
                return .nike
            }
            return nil
        }
    }

    static func trendingHighlights(
        closet: [ClosetItem],
        catalog: [UpsoledProduct],
        limit: Int = 4
    ) -> [HomeSneakerHighlight] {
        var highlights: [HomeSneakerHighlight] = []

        for item in closet where item.category == .shoes && isTrendingShoe(brand: item.brand, name: item.catalogDisplayName) {
            let change = item.marketPrice?.changePercent ?? syntheticChange(from: item.marketPrice?.history)
            let lines = displayLines(title: item.catalogDisplayName, brand: item.brand)
            highlights.append(
                HomeSneakerHighlight(
                    id: item.id.uuidString,
                    title: lines.title,
                    subtitle: lines.subtitle,
                    changePercent: change,
                    history: item.marketPrice?.history ?? syntheticHistory(base: item.stockValueUSD),
                    closetItem: item,
                    catalogProduct: nil
                )
            )
        }

        for product in catalog {
            let units = max(1, product.quantity ?? 1)
            guard units > 0, isTrendingShoe(brand: product.brand, name: product.name) else { continue }
            let lines = displayLines(title: product.name, brand: product.brand)
            highlights.append(
                HomeSneakerHighlight(
                    id: product.id.uuidString,
                    title: lines.title,
                    subtitle: lines.subtitle,
                    changePercent: syntheticChange(from: syntheticHistory(base: product.stockValueUSD)),
                    history: syntheticHistory(base: product.stockValueUSD),
                    closetItem: nil,
                    catalogProduct: product
                )
            )
        }

        return pickTrending(highlights: highlights, limit: limit)
    }

    private static func pickTrending(highlights: [HomeSneakerHighlight], limit: Int) -> [HomeSneakerHighlight] {
        guard !highlights.isEmpty else { return [] }

        let sorted = highlights.sorted { $0.changePercent > $1.changePercent }
        var picked: [HomeSneakerHighlight] = []
        var usedIDs = Set<String>()

        func brand(of item: HomeSneakerHighlight) -> TrendingShoeBrand? {
            if let product = item.catalogProduct {
                return TrendingShoeBrand.classify(brand: product.brand, name: product.name)
            }
            if let closet = item.closetItem {
                return TrendingShoeBrand.classify(brand: closet.brand, name: closet.catalogDisplayName)
            }
            return TrendingShoeBrand.classify(
                brand: item.subtitle.isEmpty ? nil : item.subtitle,
                name: item.title
            )
        }

        for targetBrand in TrendingShoeBrand.pickOrder {
            guard picked.count < limit else { break }
            let candidates = sorted.filter { brand(of: $0) == targetBrand && !usedIDs.contains($0.id) }
            guard !candidates.isEmpty else { continue }

            let best: HomeSneakerHighlight
            if targetBrand == .jordan {
                best = candidates.max { jordanTrendingRank($0) < jordanTrendingRank($1) } ?? candidates[0]
            } else {
                best = candidates[0]
            }

            picked.append(best)
            usedIDs.insert(best.id)
        }

        let adidasRemainder = sorted.filter { brand(of: $0) == .adidas && !usedIDs.contains($0.id) }
        for item in adidasRemainder where picked.count < limit {
            picked.append(item)
            usedIDs.insert(item.id)
        }

        for item in sorted where picked.count < limit && !usedIDs.contains(item.id) && brand(of: item) != .nike {
            picked.append(item)
            usedIDs.insert(item.id)
        }

        return picked
    }

    /// Prioriza Jordan 3 frente a Jordan 5 (y similares) en la fila Trending.
    private static func jordanTrendingRank(_ item: HomeSneakerHighlight) -> Int {
        let haystack = "\(item.subtitle) \(item.title)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if haystack.contains("jordan 3")
            || haystack.contains("air jordan 3")
            || haystack.contains(" iii")
            || haystack.range(of: #"\b3 retro\b"#, options: .regularExpression) != nil {
            return 1_000 + Int(item.changePercent.rounded())
        }

        if haystack.contains("jordan 5")
            || haystack.contains("air jordan 5")
            || haystack.range(of: #"\b5 retro\b"#, options: .regularExpression) != nil {
            return 100 + Int(item.changePercent.rounded())
        }

        return 500 + Int(item.changePercent.rounded())
    }

    private static func isTrendingShoe(brand: String?, name: String) -> Bool {
        TrendingShoeBrand.classify(brand: brand, name: name) != nil
    }

    private static func syntheticChange(from history: [Double]?) -> Double {
        guard let history, history.count >= 2, let first = history.first, first > 0, let last = history.last else {
            return 8
        }
        return ((last - first) / first) * 100
    }

    private static func syntheticHistory(base: Double) -> [Double] {
        guard base > 0 else { return [1, 1.04, 1.08, 1.12] }
        return [base * 0.88, base * 0.94, base * 0.98, base]
    }

    private static func displayLines(title: String, brand: String?) -> (title: String, subtitle: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let brand, !brand.isEmpty {
            let b = brand.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix(b.lowercased()) {
                let rest = trimmed.dropFirst(b.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !rest.isEmpty { return (String(rest), b) }
            }
            if b.lowercased() != trimmed.lowercased() {
                return (trimmed, b)
            }
        }
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        if parts.count >= 3 {
            return (parts.prefix(2).joined(separator: " "), parts.dropFirst(2).joined(separator: " "))
        }
        return (trimmed, "")
    }
}

struct DashboardHomeScreen: View {
    let closetItems: [ClosetItem]
    let catalogProducts: [UpsoledProduct]
    let marketComparison: MarketComparison?
    var isLoadingMarketPrices: Bool = false
    @Binding var selectedTrendingID: String?
    var onViewStock: () -> Void = {}

    @State private var showMarketComparator = false

    private var trending: [HomeSneakerHighlight] {
        HomeScreenDataBuilder.trendingHighlights(closet: closetItems, catalog: catalogProducts, limit: 4)
    }

    private var selectedTrendingItem: HomeSneakerHighlight? {
        guard let selectedTrendingID else { return trending.first }
        return trending.first(where: { $0.id == selectedTrendingID }) ?? trending.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !trending.isEmpty {
                DashboardTrendingSneakersSection(
                    items: trending,
                    selectedID: selectedTrendingID,
                    onSelect: { item in selectedTrendingID = item.id },
                    onViewAll: onViewStock
                )
            }

            DashboardMarketPricesSection(
                comparison: marketComparison,
                isLoading: isLoadingMarketPrices,
                selectedProductName: selectedTrendingItem?.displayName,
                onViewFullTable: { showMarketComparator = true }
            )

            DashboardHomeBottomGrid(
                closetItems: closetItems,
                catalogProducts: catalogProducts,
                onViewStock: onViewStock
            )
        }
        .sheet(isPresented: $showMarketComparator) {
            MarketComparatorView()
        }
        .onAppear {
            if selectedTrendingID == nil, let first = trending.first {
                selectedTrendingID = first.id
            }
        }
        .onChange(of: trending.map(\.id)) { _, ids in
            guard !ids.isEmpty else { return }
            if let selectedTrendingID, ids.contains(selectedTrendingID) { return }
            self.selectedTrendingID = ids.first
        }
    }
}

// MARK: - Featured category cards (Pokémon · Streetwear)

struct HomeFeaturedPlatformQuote: Identifiable {
    let id = UUID()
    let name: String
    let price: Double
    var logoAsset: String?
}

struct HomeFeaturedProduct {
    let name: String
    let subtitle: String
    let badge: String?
    let badgeColor: Color
    let marketPrice: Double
    let changePercent: Double
    let platforms: [HomeFeaturedPlatformQuote]
    let closetItem: ClosetItem?
    let catalogProduct: UpsoledProduct?
}

enum HomeFeaturedDataBuilder {
    static func streetwearFeature(from closet: [ClosetItem], catalog: [UpsoledProduct]) -> HomeFeaturedProduct {
        if let item = bestApparelFromCloset(closet) {
            return productFromCloset(item)
        }
        if let product = bestApparelFromCatalog(catalog) {
            return productFromCatalog(product)
        }
        return HomeFeaturedProduct(
            name: "Classic Cotton Hoodie",
            subtitle: "Black",
            badge: "Size L",
            badgeColor: DashboardHomePalette.accentGreen,
            marketPrice: 89,
            changePercent: 6.2,
            platforms: streetwearPlatforms(base: 89),
            closetItem: nil,
            catalogProduct: nil
        )
    }

    private static func bestApparelFromCloset(_ closet: [ClosetItem]) -> ClosetItem? {
        let apparel = closet
            .filter { $0.isActiveInStock && $0.category != .shoes && $0.category != .underwear }
            .sorted { $0.createdAt > $1.createdAt }

        return apparel.first { !ImageStore.displayRelativePath(for: $0).isEmpty } ?? apparel.first
    }

    private static func bestApparelFromCatalog(_ catalog: [UpsoledProduct]) -> UpsoledProduct? {
        catalog
            .filter { product in
                let cat = product.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                let isApparel = cat == "clothing" || cat == "apparel" || cat == "streetwear" || cat.contains("ropa")
                let units = max(1, product.quantity ?? 1)
                return isApparel && units > 0 && product.primaryImageURL != nil
            }
            .sorted { ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast) }
            .first
    }

    private static func productFromCloset(_ item: ClosetItem) -> HomeFeaturedProduct {
        let change = item.marketPrice?.changePercent ?? 6.2
        let price = item.stockValueUSD > 0 ? item.stockValueUSD : 89
        let sizeBadge = item.sizeText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? "Size \(item.sizeText!)"
            : "Size M"
        let colorLine = item.colorLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? item.colorLabel!
            : (item.brand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? item.brand! : "Black")
        let lines = displayLines(title: item.catalogDisplayName, brand: item.brand)

        return HomeFeaturedProduct(
            name: lines.title.isEmpty ? item.catalogDisplayName : lines.title,
            subtitle: colorLine,
            badge: sizeBadge,
            badgeColor: DashboardHomePalette.accentGreen,
            marketPrice: price,
            changePercent: change,
            platforms: streetwearPlatforms(base: price),
            closetItem: item,
            catalogProduct: nil
        )
    }

    private static func productFromCatalog(_ product: UpsoledProduct) -> HomeFeaturedProduct {
        let price = product.price > 0 ? product.price : 89
        let sizeBadge = product.sizes.first.map { "Size \($0)" } ?? "Size M"
        let subtitle = product.brand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? product.brand!
            : "Black"

        return HomeFeaturedProduct(
            name: product.name,
            subtitle: subtitle,
            badge: sizeBadge,
            badgeColor: DashboardHomePalette.accentGreen,
            marketPrice: price,
            changePercent: 6.2,
            platforms: streetwearPlatforms(base: price),
            closetItem: nil,
            catalogProduct: product
        )
    }

    static var pokemonFeature: HomeFeaturedProduct {
        HomeFeaturedProduct(
            name: "Oddish Holo",
            subtitle: "Jungle • PSA 10",
            badge: nil,
            badgeColor: DashboardHomePalette.accentPurple,
            marketPrice: 1250,
            changePercent: 12.4,
            platforms: pokemonPlatforms(base: 1250),
            closetItem: nil,
            catalogProduct: nil
        )
    }

    private static func displayLines(title: String, brand: String?) -> (title: String, subtitle: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let brand, !brand.isEmpty {
            let b = brand.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix(b.lowercased()) {
                let rest = trimmed.dropFirst(b.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !rest.isEmpty { return (String(rest), b) }
            }
            if b.lowercased() != trimmed.lowercased() {
                return (trimmed, b)
            }
        }
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        if parts.count >= 3 {
            return (parts.prefix(2).joined(separator: " "), parts.dropFirst(2).joined(separator: " "))
        }
        return (trimmed, "")
    }

    private static func streetwearPlatforms(base: Double) -> [HomeFeaturedPlatformQuote] {
        [
            HomeFeaturedPlatformQuote(name: "StockX", price: base * 1.02, logoAsset: "stockx"),
            HomeFeaturedPlatformQuote(name: "ebay", price: base * 0.98, logoAsset: "ebay"),
            HomeFeaturedPlatformQuote(name: "Grailed", price: base * 0.92),
            HomeFeaturedPlatformQuote(name: "Depop", price: base * 0.96)
        ]
    }

    private static func pokemonPlatforms(base: Double) -> [HomeFeaturedPlatformQuote] {
        [
            HomeFeaturedPlatformQuote(name: "ebay", price: base * 0.94, logoAsset: "ebay"),
            HomeFeaturedPlatformQuote(name: "TCGplayer", price: base * 0.97),
            HomeFeaturedPlatformQuote(name: "Cardmarket", price: base * 1.05)
        ]
    }
}

private enum AccarLogoAssets {
    static let oddishGIFName = "3d-pokemon-card-oddish"
    static let imagesetFolder = "AccarLogo.imageset"
}

private enum HomeBottomGridMetrics {
    static let imageSide: CGFloat = 78
    static let badgeRowHeight: CGFloat = 18
    static let platformRowHeight: CGFloat = 38
}

private struct DashboardHomeBottomGrid: View {
    let closetItems: [ClosetItem]
    let catalogProducts: [UpsoledProduct]
    var onViewStock: () -> Void = {}

    private var streetwear: HomeFeaturedProduct {
        HomeFeaturedDataBuilder.streetwearFeature(from: closetItems, catalog: catalogProducts)
    }

    private var pokemon: HomeFeaturedProduct {
        HomeFeaturedDataBuilder.pokemonFeature
    }

    var body: some View {
        Grid(horizontalSpacing: 10) {
            GridRow(alignment: .top) {
                DashboardHomeCategoryCard(
                    icon: "bolt.fill",
                    iconColor: Color(red: 0.95, green: 0.78, blue: 0.12),
                    title: "POKÉMON",
                    product: pokemon,
                    actionColor: DashboardHomePalette.accentPurple,
                    onViewAll: onViewStock
                ) {
                    GIFAnimatedView(
                        resourceName: AccarLogoAssets.oddishGIFName,
                        subdirectory: AccarLogoAssets.imagesetFolder,
                        contentMode: .scaleAspectFit
                    )
                }

                DashboardHomeCategoryCard(
                    icon: "tshirt.fill",
                    iconColor: DashboardHomePalette.accentGreen,
                    title: "STREETWEAR & APPAREL",
                    product: streetwear,
                    actionColor: DashboardHomePalette.accentGreen,
                    onViewAll: onViewStock
                ) {
                    streetwearImage(streetwear)
                }
            }
        }
    }

    @ViewBuilder
    private func streetwearImage(_ product: HomeFeaturedProduct) -> some View {
        if let item = product.closetItem {
            HomeClosetThumbnail(relativePath: ImageStore.displayRelativePath(for: item))
        } else if let url = product.catalogProduct?.primaryImageURL {
            StockCachedRemoteImage(url: url)
        } else {
            ZStack {
                Color(red: 0.96, green: 0.96, blue: 0.97)
                Image(systemName: "tshirt.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.black.opacity(0.18))
            }
        }
    }
}

private struct DashboardHomeCategoryCard<ImageContent: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let product: HomeFeaturedProduct
    let actionColor: Color
    var onViewAll: () -> Void = {}
    @ViewBuilder let imageContent: () -> ImageContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                icon: icon,
                iconColor: iconColor,
                title: title,
                actionTitle: "View all",
                actionColor: actionColor,
                action: onViewAll
            )

            HStack(alignment: .top, spacing: 8) {
                imageContent()
                    .frame(width: HomeBottomGridMetrics.imageSide, height: HomeBottomGridMetrics.imageSide)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DashboardHomePalette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Text(product.subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DashboardHomePalette.labelMuted)
                        .lineLimit(1)

                    Group {
                        if let badge = product.badge, !badge.isEmpty {
                            Text(badge)
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(product.badgeColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background {
                                    Capsule()
                                        .fill(product.badgeColor.opacity(0.14))
                                }
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: HomeBottomGridMetrics.badgeRowHeight, alignment: .leading)

                    Text("Market Price")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(DashboardHomePalette.labelMuted)
                        .padding(.top, 2)

                    Text(DealershipStatsViewModel.formatUSD(product.marketPrice))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(DashboardHomePalette.textPrimary)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)

                    HStack(spacing: 2) {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 6, weight: .bold))
                        Text(String(format: "%.1f%% (7D)", abs(product.changePercent)))
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(DashboardHomePalette.accentGreen)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                ForEach(product.platforms) { quote in
                    HomeFeaturedPlatformChip(quote: quote)
                }
            }
            .frame(height: HomeBottomGridMetrics.platformRowHeight, alignment: .top)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(homeCardBackground)
    }
}

private struct HomeFeaturedPlatformChip: View {
    let quote: HomeFeaturedPlatformQuote

    var body: some View {
        VStack(spacing: 3) {
            if let asset = quote.logoAsset {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 11)
            } else {
                Text(quote.name)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(DashboardHomePalette.labelMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(DealershipStatsViewModel.formatUSD(quote.price))
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(DashboardHomePalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .padding(.horizontal, 3)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.04))
        }
    }
}

// MARK: - Trending sneakers

private struct DashboardTrendingSneakersSection: View {
    let items: [HomeSneakerHighlight]
    var selectedID: String?
    var onSelect: (HomeSneakerHighlight) -> Void = { _ in }
    var onViewAll: () -> Void = {}

    private let columnCount = 4
    private let columnSpacing: CGFloat = 8

    private var visibleItems: [HomeSneakerHighlight] {
        Array(items.prefix(columnCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                icon: "flame.fill",
                iconColor: DashboardHomePalette.accentPurple,
                title: "TRENDING SNEAKERS",
                actionTitle: "View all",
                actionColor: DashboardHomePalette.accentPurple,
                action: onViewAll
            )

            HStack(alignment: .top, spacing: columnSpacing) {
                ForEach(visibleItems) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        trendingCard(item, isSelected: selectedID == item.id)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func trendingCard(_ item: HomeSneakerHighlight, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            highlightImage(item)
                .frame(maxWidth: .infinity)
                .frame(height: 78)
                .padding(.top, 8)
                .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DashboardHomePalette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DashboardHomePalette.labelMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? DashboardHomePalette.accentPurple : DashboardHomePalette.cardBorder,
                            lineWidth: isSelected ? 2 : 1
                        )
                }
        }
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }

    @ViewBuilder
    private func highlightImage(_ item: HomeSneakerHighlight) -> some View {
        if let closet = item.closetItem {
            HomeClosetThumbnail(relativePath: ImageStore.displayRelativePath(for: closet))
        } else if let url = item.catalogProduct?.primaryImageURL {
            StockCachedRemoteImage(url: url)
        } else {
            Image("AuthSneakerHero")
                .resizable()
                .scaledToFit()
                .padding(6)
        }
    }
}

// MARK: - Market prices

enum HomeMarketTableBuilder {
    static let standardSizes = ["7", "7.5", "8"]
    static let homePlatforms = ["StockX", "GOAT", "eBay", "Flight Club"]

    static func displayRows(from comparison: MarketComparison?, maxRows: Int = 5) -> [MarketSizeRow] {
        Array(buildHomeRows(from: comparison).prefix(maxRows))
    }

    /// Construye filas del Home: precios reales cuando existen y estimados para plataformas/tallas faltantes.
    static func buildHomeRows(from comparison: MarketComparison?) -> [MarketSizeRow] {
        let liveRows = comparison?.rows ?? []
        let hasLive = liveRows.contains { !$0.asks.isEmpty }

        if !hasLive {
            return standardSizes.map { MarketSizeRow(size: $0, asks: completeAsks(demoAsks(for: $0))) }
        }

        return standardSizes.map { size in
            let normalized = normalizeSizeKey(size)
            let exact = liveRows.first { normalizeSizeKey($0.size) == normalized }
            var asks = canonicalizeAsks(exact?.asks ?? [:])

            if asks.isEmpty, let nearest = nearestRow(to: size, in: liveRows) {
                let delta = (numericSize(size) ?? 0) - (numericSize(nearest.size) ?? 0)
                asks = extrapolatedAsks(from: canonicalizeAsks(nearest.asks), halfSizeSteps: delta * 2)
            } else if asks.isEmpty, let anchor = liveRows.max(by: { $0.asks.count < $1.asks.count }) {
                let delta = (numericSize(size) ?? 0) - (numericSize(anchor.size) ?? 0)
                asks = extrapolatedAsks(from: canonicalizeAsks(anchor.asks), halfSizeSteps: delta * 2)
            }

            return MarketSizeRow(size: size, asks: completeAsks(asks))
        }
    }

    /// Enriquece la comparación con eBay por talla y deja filas listas para el Home.
    static func prepareHomeComparison(from raw: MarketComparison, query: String) async -> MarketComparison {
        let enriched = await enrichWithEbay(comparison: raw, query: query)
        let rows = buildHomeRows(from: enriched)
        return MarketComparison(
            query: enriched.query,
            platforms: enriched.platforms,
            sizes: rows.map(\.size),
            rows: rows,
            fetchedAt: enriched.fetchedAt,
            skuAligned: enriched.skuAligned
        )
    }

    static func enrichWithEbay(comparison: MarketComparison, query: String) async -> MarketComparison {
        guard EbayPriceService.isConfigured else { return comparison }

        var rowsBySize = Dictionary(uniqueKeysWithValues: comparison.rows.map {
            (normalizeSizeKey($0.size), $0)
        })

        let ebaySizes = Set(standardSizes + comparison.rows.map { normalizeSizeKey($0.size) })

        await withTaskGroup(of: (String, Double?).self) { group in
            for size in ebaySizes {
                group.addTask {
                    let listing = try? await EbayPriceService.lowestListing(query: query, size: size)
                    return (size, listing?.price)
                }
            }

            for await (size, price) in group {
                guard let price, price > 0 else { continue }
                if let row = rowsBySize[size] {
                    var asks = row.asks
                    asks["eBay"] = price
                    rowsBySize[size] = MarketSizeRow(size: row.size, asks: asks)
                } else {
                    rowsBySize[size] = MarketSizeRow(size: size, asks: ["eBay": price])
                }
            }
        }

        let rows = rowsBySize.values.sorted {
            (numericSize($0.size) ?? 0) < (numericSize($1.size) ?? 0)
        }

        return MarketComparison(
            query: comparison.query,
            platforms: comparison.platforms,
            sizes: rows.map(\.size),
            rows: Array(rows),
            fetchedAt: comparison.fetchedAt,
            skuAligned: comparison.skuAligned
        )
    }

    /// Garantiza las 4 plataformas del Home en cada celda (real o estimado).
    static func completeAsks(_ asks: [String: Double]) -> [String: Double] {
        var result = fillMissingPlatforms(in: canonicalizeAsks(asks))
        for platform in homePlatforms where result[platform] == nil || result[platform]! <= 0 {
            result = fillMissingPlatforms(in: result)
        }
        return result
    }

    private static func nearestRow(to size: String, in rows: [MarketSizeRow]) -> MarketSizeRow? {
        guard let target = numericSize(size) else { return rows.first }
        return rows
            .filter { numericSize($0.size) != nil && !$0.asks.isEmpty }
            .min {
                abs((numericSize($0.size) ?? 0) - target) < abs((numericSize($1.size) ?? 0) - target)
            }
    }

    static func normalizeSizeKey(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "US", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "Avg" { return trimmed }
        if let value = Double(trimmed) {
            return value == value.rounded() ? String(Int(value)) : String(value)
        }
        return trimmed
    }

    static func canonicalizeAsks(_ asks: [String: Double]) -> [String: Double] {
        var result: [String: Double] = [:]
        for (key, value) in asks where value > 0 {
            if let name = matchPlatform(key) {
                result[name] = min(result[name] ?? value, value)
            }
        }
        return result
    }

    static func fillMissingPlatforms(in asks: [String: Double]) -> [String: Double] {
        var result = asks
        guard !result.isEmpty else { return demoAsks(for: "8.5") }

        let low = result.values.min() ?? 300
        let high = result.values.max() ?? low
        let mid = (low + high) / 2

        if result["StockX"] == nil { result["StockX"] = high * 1.02 }
        if result["GOAT"] == nil { result["GOAT"] = low * 0.98 }
        if result["eBay"] == nil { result["eBay"] = low * 0.96 }
        if result["Flight Club"] == nil { result["Flight Club"] = mid * 1.04 }
        return result
    }

    static func extrapolatedAsks(from anchor: [String: Double], halfSizeSteps: Double) -> [String: Double] {
        let stepUSD = 14.0 * halfSizeSteps
        var result: [String: Double] = [:]
        for (platform, price) in completeAsks(anchor) {
            result[platform] = max(50, price + stepUSD)
        }
        return result
    }

    static func demoAsks(for size: String) -> [String: Double] {
        let index = standardSizes.firstIndex(of: normalizeSizeKey(size)) ?? 2
        let base = 420.0 + Double(index) * 18
        return [
            "StockX": base,
            "GOAT": base * 0.96,
            "eBay": base * 0.93,
            "Flight Club": base * 1.05
        ]
    }

    private static func numericSize(_ raw: String) -> Double? {
        Double(normalizeSizeKey(raw))
    }

    private static func matchPlatform(_ raw: String) -> String? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("stockx") { return "StockX" }
        if lower == "goat" { return "GOAT" }
        if lower.contains("ebay") { return "eBay" }
        if lower.contains("flight") { return "Flight Club" }
        return homePlatforms.first { $0.lowercased() == lower }
    }
}

struct DashboardMarketPricesSection: View {
    let comparison: MarketComparison?
    var isLoading: Bool = false
    var selectedProductName: String? = nil
    var onViewFullTable: () -> Void = {}

    private let platforms = HomeMarketTableBuilder.homePlatforms
    private let rowHeight: CGFloat = 52
    private let maxVisibleRows = 3

    private var tableRows: [MarketSizeRow] {
        HomeMarketTableBuilder.displayRows(from: comparison, maxRows: maxVisibleRows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tableHeader

            if let selectedProductName, !selectedProductName.isEmpty {
                Text(selectedProductName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DashboardHomePalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            HomeMarketPriceGridTable(
                platforms: platforms,
                rows: tableRows,
                rowHeight: rowHeight
            )
            .redacted(reason: isLoading ? .placeholder : [])

            Button(action: onViewFullTable) {
                Text("View full price table  ›")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(homeCardBackground)
    }

    private var tableHeader: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DashboardHomePalette.accentBlue)
                Text("MARKET PRICES")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.9)
                    .foregroundStyle(Color.black.opacity(0.88))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text("Live prices")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.42))
                Circle()
                    .fill(DashboardHomePalette.accentGreen)
                    .frame(width: 7, height: 7)
            }
        }
    }
}

private struct HomeMarketPriceGridTable: View {
    let platforms: [String]
    let rows: [MarketSizeRow]
    let rowHeight: CGFloat

    private let gridLine = Color.black.opacity(0.07)
    private let cellHorizontalPadding: CGFloat = 8
    private let cellVerticalPadding: CGFloat = 12
    private let headerLogoMaxHeight: CGFloat = 20
    private let sizeColumnWidth: CGFloat = 74

    var body: some View {
        GeometryReader { geo in
            let sizeWidth = sizeColumnWidth
            let platformWidth = max(48, (geo.size.width - sizeWidth) / CGFloat(platforms.count))
            let columnWidths = [sizeWidth] + Array(repeating: platformWidth, count: platforms.count)

            VStack(spacing: 0) {
                tableRow(
                    columnWidths: columnWidths,
                    isHeader: true,
                    sizeLabel: "Size",
                    asks: [:]
                )
                ForEach(rows) { row in
                    tableRow(
                        columnWidths: columnWidths,
                        isHeader: false,
                        sizeLabel: sizeLabel(row.size),
                        asks: row.asks
                    )
                }
            }
            .overlay {
                HomeMarketGridLines(
                    columnWidths: columnWidths,
                    rowHeight: rowHeight,
                    lineColor: gridLine
                )
            }
            .overlay(alignment: .top) {
                Rectangle().fill(gridLine).frame(height: 1)
            }
        }
        .frame(height: rowHeight * CGFloat(rows.count + 1))
    }

    private func tableRow(
        columnWidths: [CGFloat],
        isHeader: Bool,
        sizeLabel: String,
        asks: [String: Double]
    ) -> some View {
        HStack(spacing: 0) {
            sizeCell(
                width: columnWidths[0],
                isHeader: isHeader,
                label: sizeLabel
            )

            ForEach(Array(platforms.enumerated()), id: \.offset) { index, platform in
                if isHeader {
                    headerPlatformCell(
                        width: columnWidths[index + 1],
                        platform: platform
                    )
                } else {
                    pricePlatformCell(
                        width: columnWidths[index + 1],
                        price: asks[platform]
                    )
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(gridLine).frame(height: 1)
        }
    }

    private func sizeCell(width: CGFloat, isHeader: Bool, label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: isHeader ? .bold : .semibold))
            .foregroundStyle(Color.black.opacity(isHeader ? 0.82 : 0.72))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, cellVerticalPadding)
            .frame(width: width, height: rowHeight, alignment: .leading)
    }

    private func headerPlatformCell(width: CGFloat, platform: String) -> some View {
        StylizedMarketplaceLogo(brand: platform)
            .frame(maxWidth: .infinity, maxHeight: headerLogoMaxHeight, alignment: .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, cellHorizontalPadding)
            .padding(.vertical, cellVerticalPadding)
            .frame(width: width, height: rowHeight, alignment: .center)
    }

    private func pricePlatformCell(width: CGFloat, price: Double?) -> some View {
        priceCell(price: price)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, cellHorizontalPadding)
            .padding(.vertical, cellVerticalPadding)
            .frame(width: width, height: rowHeight, alignment: .center)
    }

    private func priceCell(price: Double?) -> some View {
        Group {
            if let price {
                HStack(spacing: 4) {
                    Text(DealershipStatsViewModel.formatUSD(price))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DashboardHomePalette.accentGreen)
                }
            } else {
                Text("—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.20))
            }
        }
    }

    private func sizeLabel(_ size: String) -> String {
        let normalized = HomeMarketTableBuilder.normalizeSizeKey(size)
        if normalized == "Avg" { return "Avg" }
        return "US \(normalized)"
    }
}

private struct HomeMarketGridLines: View {
    let columnWidths: [CGFloat]
    let rowHeight: CGFloat
    let lineColor: Color

    var body: some View {
        GeometryReader { geo in
            let totalWidth = columnWidths.reduce(0, +)
            let scale = geo.size.width / max(totalWidth, 1)
            let scaled = columnWidths.map { $0 * scale }

            Path { path in
                var x = scaled[0]
                for index in 1..<scaled.count {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    x += scaled[index]
                }
            }
            .stroke(lineColor, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Shared helpers

private struct HomeClosetThumbnail: View {
    let relativePath: String

    @State private var image: UIImage?

    init(relativePath: String) {
        self.relativePath = relativePath
        let key = StockImageLoader.localCacheKey(relativePath)
        _image = State(initialValue: ImageCacheService.shared.image(forKey: key))
    }

    var body: some View {
        Group {
            if let ui = image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.white
            }
        }
        .background(Color.white)
        .task(id: relativePath) {
            guard image == nil else { return }
            if let loaded = await StockImageLoader.cachedLocalImageAsync(relativePath: relativePath) {
                image = loaded
            }
        }
    }
}

private func sectionHeader(
    icon: String,
    iconColor: Color,
    title: String,
    actionTitle: String,
    actionColor: Color = DashboardHomePalette.accentBlue,
    action: @escaping () -> Void
) -> some View {
    HStack {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(DashboardHomePalette.labelMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        Spacer(minLength: 0)
        Button(action: action) {
            HStack(spacing: 3) {
                Text(actionTitle)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(actionColor)
        }
        .buttonStyle(.plain)
    }
}

private var homeCardBackground: some View {
    RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.white)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(DashboardHomePalette.cardBorder, lineWidth: 1)
        }
        .shadow(color: DashboardHomePalette.cardShadow, radius: 14, x: 0, y: 4)
}

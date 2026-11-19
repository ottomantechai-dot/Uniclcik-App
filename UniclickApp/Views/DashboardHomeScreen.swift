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

    /// Un style code REAL de fábrica tiene un bloque de 3+ dígitos seguidos (CT8532-012, 136064-004,
    /// DZ5485-100). Los códigos internos de tienda (JACK-LWR, SPL-OHR, LUC-OXR, SPL-HE-1) no → se ignoran
    /// y se busca por nombre del modelo, que sí es real.
    static func isRealStyleCode(_ sku: String) -> Bool {
        sku.range(of: "[0-9]{3,}", options: .regularExpression) != nil
    }

    var marketLookup: (query: String, fallback: String?)? {
        if let closet = closetItem {
            let sku = closet.resolvedSKU?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = closet.marketLookupQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = closet.catalogDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sku.isEmpty, Self.isRealStyleCode(sku) {
                return (sku, name.isEmpty ? (displayName.isEmpty ? nil : displayName) : name)
            }
            // SKU no real (código interno tipo "SPL-HE-1"): buscamos por el NOMBRE del modelo,
            // nunca por ese código falso (que confunde a KicksDB y trae el zapato equivocado).
            let q = displayName.isEmpty ? name : displayName
            guard !q.isEmpty else { return nil }
            return (q, displayName.isEmpty ? nil : (name.isEmpty || name == q ? nil : name))
        }
        if let product = catalogProduct {
            let sku = product.sku?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sku.isEmpty, Self.isRealStyleCode(sku) {
                return (sku, name.isEmpty ? nil : name)
            }
            guard !name.isEmpty else { return nil }
            return (name, nil)
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
    @Binding var selectedTrendingID: String?
    var onViewStock: () -> Void = {}

    @State private var showMarketComparator = false
    @State private var showWatchlist = false
    @State private var showSearch = false
    /// En Inicio, la fila de tendencias enseña zapatos o cartas según el acceso elegido.
    @State private var homeShowsCards = false
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var showOpportunities = false
    @ObservedObject private var watchlist = WatchlistStore.shared

    private var trending: [HomeSneakerHighlight] {
        HomeScreenDataBuilder.trendingHighlights(closet: closetItems, catalog: catalogProducts, limit: 4)
    }

    private var selectedTrendingItem: HomeSneakerHighlight? {
        guard let selectedTrendingID else { return trending.first }
        return trending.first(where: { $0.id == selectedTrendingID }) ?? trending.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HomeBentoGrid(closetItems: closetItems, catalogProducts: catalogProducts,
                          showsCards: $homeShowsCards,
                          onSneakers: onViewStock,
                          onScan: { tabRouter.scanRequested = true; tabRouter.selected = .closet },
                          onCards: { tabRouter.selected = .cards })

            CardsShowcase(onViewAll: { tabRouter.selected = .cards })

            if homeShowsCards {
                HomeTrendingCardsRow(onViewAll: { tabRouter.selected = .cards })
            } else {
                HomeTrendingRow(products: Array(catalogProducts.prefix(12)), onViewAll: onViewStock)
            }

            if !watchlist.items.isEmpty {
                HStack(spacing: 10) {
                    Button { showWatchlist = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill").font(.system(size: 13)).foregroundStyle(.yellow)
                            Text("Watchlist").font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DashboardHomePalette.textPrimary)
                            Spacer(minLength: 2)
                            Text("\(watchlist.items.count)").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DashboardHomePalette.labelMuted)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(homeCardBackground)
                    }
                    .buttonStyle(.plain)

                    Button { showOpportunities = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "target").font(.system(size: 13)).foregroundStyle(DashboardHomePalette.accentGreen)
                            Text("Opportunities").font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DashboardHomePalette.textPrimary)
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DashboardHomePalette.labelMuted)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(homeCardBackground)
                    }
                    .buttonStyle(.plain)
                }
            }

            DashboardMarketPricesSection(
                comparison: marketComparison,
                featured: marketComparison == nil ? catalogProducts.first : nil
            )

            DashboardHomeBottomGrid(
                closetItems: closetItems,
                catalogProducts: catalogProducts,
                onViewStock: onViewStock
            )
        }
        .onChange(of: tabRouter.homeSearchTick) { _, _ in showSearch = true }
        .onReceive(NotificationCenter.default.publisher(for: .homeOpenCards)) { _ in tabRouter.selected = .cards }
        .fullScreenCover(isPresented: $showMarketComparator) {
            if let item = selectedTrendingItem {
                ShoeMarketDetailView(item: item)
            } else {
                MarketComparatorView()
            }
        }
        .sheet(isPresented: $showWatchlist) {
            WatchlistView()
        }
        .fullScreenCover(isPresented: $showSearch) {
            MarketComparatorView()
        }
        .sheet(isPresented: $showOpportunities) {
            OpportunitiesView()
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

// MARK: - Comisiones de venta por plataforma (aproximadas, ajustables)

enum PlatformFees {
    /// (comisión %, fijo $). Valores aproximados — ajusta aquí si cambian.
    static func params(_ platform: String) -> (rate: Double, fixed: Double) {
        switch platform.lowercased() {
        case let p where p.contains("stockx"):     return (0.12, 0)
        case let p where p.contains("goat"):       return (0.095, 5)
        case let p where p.contains("ebay"):       return (0.13, 0)
        case let p where p.contains("flight"):     return (0.20, 0)
        default:                                    return (0.12, 0)
        }
    }
    /// Lo que el vendedor cobra tras comisión por vender a `price` en `platform`.
    static func net(price: Double, platform: String) -> Double {
        let p = params(platform)
        return max(0, price * (1 - p.rate) - p.fixed)
    }
    static func ratePercent(_ platform: String) -> Int { Int((params(platform).rate * 100).rounded()) }
}

// MARK: - Ficha de mercado del zapato (compra, última venta, mejor oferta, historial)

struct ShoeMarketDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: HomeSneakerHighlight

    @State private var comparison: MarketComparison?
    @State private var sales: [DailySalePoint] = []
    @State private var loading = true
    @State private var costText = ""
    @FocusState private var costFocused: Bool
    @ObservedObject private var watchlist = WatchlistStore.shared

    private static let green = Color(red: 0.13, green: 0.55, blue: 0.30)
    private static let red = Color(red: 0.85, green: 0.25, blue: 0.25)
    private static let blue = Color(red: 0.20, green: 0.45, blue: 0.85)
    private static func usd(_ v: Double) -> String { DealershipStatsViewModel.formatUSD(v) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Shoe360View(titles: (comparison?.spinTitles ?? []) + [item.displayName], fallbackURL: comparison?.imageURL, queries: [item.marketLookup?.query].compactMap { $0 })
                        .frame(height: 220)
                        .padding(.vertical, 6)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    if loading {
                        loadingSkeleton
                    } else if let comp = comparison, !comp.rows.isEmpty {
                        bestOfferCard(comp)
                        sellerCard(comp)
                        sellSuggestionCard(comp)
                        calculatorCard(comp)
                        if !sales.isEmpty { salesCard }
                        DashboardMarketPricesSection(
                            comparison: comp,
                            maxVisibleRows: nil
                        )
                    } else {
                        emptyState
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.96, blue: 1.0), Color(red: 0.99, green: 0.99, blue: 1.0)],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()
            )
            .navigationTitle("Price details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let q = item.marketLookup?.query {
                        Button {
                            watchlist.toggle(query: q, displayName: item.displayName)
                        } label: {
                            Image(systemName: watchlist.contains(q) ? "star.fill" : "star")
                                .foregroundStyle(watchlist.contains(q) ? Color.yellow : Color.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") { costFocused = false }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .task { await load() }
        }
        .preferredColorScheme(.light)
    }

    // Hero premium: degradado oscuro + glow verde + valor de mercado grande.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Self.green).frame(width: 7, height: 7)
                Text("LIVE").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(.white.opacity(0.9))
                Spacer()
            }
            Text(item.displayName)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let sku = comparison?.matchedSKU {
                Text("SKU \(sku)").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
            }
            // Los DOS precios reales que de verdad importan, lado a lado (sin promedios que confunden).
            HStack(alignment: .top, spacing: 28) {
                if let ask = comparison?.bestBuyOverall {
                    headerPrice(label: "ASK MÁS BAJO", value: Self.usd(ask.price), sub: "comprar ya · \(ask.platform)")
                }
                if let last = sales.last {
                    headerPrice(label: "ÚLTIMA VENTA", value: Self.usd(last.avg), sub: "venta real")
                }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.07, green: 0.09, blue: 0.15), Color(red: 0.13, green: 0.20, blue: 0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Circle().fill(Self.green.opacity(0.30)).frame(width: 220, height: 220).blur(radius: 70).offset(x: 110, y: -30)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
    }

    /// Columna de precio del header (texto claro sobre fondo oscuro).
    private func headerPrice(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(.white.opacity(0.55))
            Text(value).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text(sub).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder
    private func bestOfferCard(_ comp: MarketComparison) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LA MEJOR OFERTA").font(.system(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(.secondary)
            if let buy = comp.bestBuyOverall {
                offerRow(icon: "cart.fill", tint: Self.green, label: "Mejor para COMPRAR",
                         value: Self.usd(buy.price), detail: "\(buy.platform) · talla \(buy.size)")
            }
            if let last = sales.last {
                offerRow(icon: "dollarsign.circle.fill", tint: Self.blue, label: "Última venta (mercado)",
                         value: Self.usd(last.avg), detail: "\(sales.count) días de historial real")
            }
            // Margen REALISTA: comprar al precio más bajo vs vender al valor de mercado REAL
            // (la última venta), no al "ask" más alto que pide alguien y nadie compra.
            if let buy = comp.bestBuyOverall, let market = sales.last?.avg {
                let margin = market - buy.price
                let roi = buy.price > 0 ? margin / buy.price * 100 : 0
                offerRow(icon: "arrow.up.right.circle.fill", tint: margin >= 0 ? Self.green : Self.red,
                         label: "Margen estimado (vs valor de mercado)",
                         value: "\(margin >= 0 ? "+" : "")\(Self.usd(margin)) · \(Int(roi))% ROI",
                         detail: "Compra \(Self.usd(buy.price)) (\(buy.platform), talla \(buy.size)) → mercado \(Self.usd(market))")
            } else if let arb = comp.bestArbitrage {
                offerRow(icon: "arrow.up.right.circle.fill", tint: Self.green, label: "Spread entre plataformas",
                         value: "\(Self.usd(arb.margin)) · \(Int(arb.roi))% ROI",
                         detail: "Compra en \(arb.buyPlatform) (\(Self.usd(arb.buy))) → vende en \(arb.sellPlatform) (\(Self.usd(arb.sell)))")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(premiumCardBG)
    }

    private func offerRow(icon: String, tint: Color, label: String, value: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(detail).font(.system(size: 11)).foregroundStyle(Color.black.opacity(0.45)).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(value).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Color.black)
        }
    }

    /// Precio de venta REAL del zapato: la última venta real (KicksDB). Si no hay historial,
    /// usa el ask más bajo del mercado (lo más cercano a una venta real), NUNCA el avg inflado
    /// de una sola plataforma (p.ej. Flight Club pidiendo $299 cuando el mercado es $140).
    private func realSellPrice(_ comp: MarketComparison) -> Double? {
        if let s = sales.last?.avg, s > 0 { return s }
        if let b = comp.bestBuyOverall?.price, b > 0 { return b }
        let asks = comp.platforms.compactMap { $0.lowestAsk ?? $0.avg }.filter { $0 > 0 }
        return asks.min()
    }

    @ViewBuilder
    private func sellerCard(_ comp: MarketComparison) -> some View {
        // Todas las plataformas venden al MISMO precio real de mercado; solo cambia la comisión.
        let market = realSellPrice(comp) ?? 0
        let rows: [(name: String, color: Color, price: Double, net: Double)] = comp.platforms
            .compactMap { p in
                guard market > 0 else { return nil }
                return (p.platform, p.color, market, PlatformFees.net(price: market, platform: p.platform))
            }
            .sorted { $0.net > $1.net }
        let bestName = rows.first?.name
        let last30 = sales.suffix(30).reduce(0) { $0 + $1.orders }

        VStack(alignment: .leading, spacing: 12) {
            Text("PARA VENDER · lo que cobras tras comisiones")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(.secondary)

            let maxNet = rows.first?.net ?? 1
            ForEach(rows.indices, id: \.self) { i in
                let r = rows[i]
                let frac = maxNet > 0 ? CGFloat(r.net / maxNet) : 0
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Circle().fill(r.color).frame(width: 9, height: 9)
                        Text(r.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.black)
                        if r.name == bestName {
                            Text("MÁS PAGA").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Self.green.opacity(0.15))).foregroundStyle(Self.green)
                        }
                        Spacer(minLength: 6)
                        Text("Cobras \(Self.usd(r.net))")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(r.name == bestName ? Self.green : Color.black)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.05)).frame(height: 11)
                            Capsule()
                                .fill(LinearGradient(colors: [r.color, r.color.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(10, g.size.width * frac), height: 11)
                                .shadow(color: r.color.opacity(0.45), radius: 3, x: 0, y: 2)
                        }
                    }
                    .frame(height: 11)
                    Text("venta real \(Self.usd(r.price)) · −\(PlatformFees.ratePercent(r.name))% comisión")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            if last30 > 0 {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: last30 >= 30 ? "flame.fill" : "tortoise.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(last30 >= 30 ? Color.orange : .secondary)
                    Text(last30 >= 30 ? "Se vende rápido" : "Se vende lento")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.black)
                    Spacer()
                    Text("~\(last30) ventas/mes (StockX)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Text("Comisiones aproximadas; ajustables.")
                .font(.system(size: 9)).foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(premiumCardBG)
    }

    /// Plataforma donde el vendedor cobra más (mayor neto tras comisiones) a un precio dado.
    private func bestPayout(_ price: Double, _ comp: MarketComparison) -> (platform: String, net: Double) {
        let names = comp.platforms.map(\.platform)
        let options = (names.isEmpty ? ["StockX", "GOAT"] : names)
            .map { (p: $0, n: PlatformFees.net(price: price, platform: $0)) }
        let best = options.max { $0.n < $1.n } ?? (p: "StockX", n: PlatformFees.net(price: price, platform: "StockX"))
        return (best.p, best.n)
    }

    /// Sugerencia accionable de a qué precio LISTAR para vender — rápido (siendo el más barato)
    /// o al valor de mercado real — con el neto que cobrarías en la mejor plataforma.
    @ViewBuilder
    private func sellSuggestionCard(_ comp: MarketComparison) -> some View {
        let market = realSellPrice(comp) ?? 0
        if market > 0 {
            let lowestAsk = comp.bestBuyOverall?.price
            let fastPrice = ((lowestAsk.map { $0 * 0.98 } ?? market * 0.97)).rounded()
            let fast = bestPayout(fastPrice, comp)
            let fair = bestPayout(market, comp)

            VStack(alignment: .leading, spacing: 12) {
                Text("SUGERENCIA DE PRECIO · PARA VENDER")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(.secondary)

                suggestionRow(
                    icon: "bolt.fill", tint: Color.orange,
                    title: "Vender rápido", listPrice: fastPrice,
                    detail: "sé el más barato · cobras \(Self.usd(fast.net)) en \(fast.platform)"
                )
                Divider().opacity(0.5)
                suggestionRow(
                    icon: "checkmark.seal.fill", tint: Self.green,
                    title: "Precio de mercado", listPrice: market,
                    detail: "valor real · cobras \(Self.usd(fair.net)) en \(fair.platform)"
                )

                Text("Listar por debajo del ask más bajo te pone primero en la búsqueda y vende antes.")
                    .font(.system(size: 9)).foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(premiumCardBG)
        }
    }

    private func suggestionRow(icon: String, tint: Color, title: String, listPrice: Double, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.black)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text("Lista").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(Self.usd(listPrice)).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Color.black)
            }
        }
    }

    @ViewBuilder
    private func calculatorCard(_ comp: MarketComparison) -> some View {
        let cost = Double(costText.replacingOccurrences(of: ",", with: "."))
        let market = realSellPrice(comp)
        let rows: [(name: String, color: Color, profit: Double, roi: Double)] = comp.platforms
            .compactMap { p in
                guard let m = market, m > 0, let c = cost, c > 0 else { return nil }
                let net = PlatformFees.net(price: m, platform: p.platform)
                return (p.platform, p.color, net - c, (net - c) / c * 100)
            }
            .sorted { $0.profit > $1.profit }

        VStack(alignment: .leading, spacing: 12) {
            Text("CALCULADORA DE GANANCIA")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(.secondary)

            HStack {
                Text("Tu coste de compra").font(.system(size: 13)).foregroundStyle(Color.black.opacity(0.7))
                Spacer()
                HStack(spacing: 4) {
                    Text("$").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
                    TextField("0", text: $costText)
                        .keyboardType(.decimalPad)
                        .focused($costFocused)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .font(.system(size: 17, weight: .bold))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(costFocused ? Self.green : Color.clear, lineWidth: 1.5)
                )
            }

            if rows.isEmpty {
                Text("Escribe lo que pagaste para ver tu beneficio neto por plataforma.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(rows.indices, id: \.self) { i in
                    let r = rows[i]
                    HStack(spacing: 10) {
                        Circle().fill(r.color).frame(width: 9, height: 9)
                        Text(r.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.black)
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(r.profit >= 0 ? "+" : "")\(Self.usd(r.profit))")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(r.profit >= 0 ? Self.green : Self.red)
                            Text("\(r.roi >= 0 ? "+" : "")\(String(format: "%.0f", r.roi))% ROI")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(premiumCardBG)
    }

    private var salesCard: some View {
        let vals = sales.map(\.avg)
        // Tendencia: compara la media de la primera mitad con la de la segunda mitad del periodo.
        let trendPct: Double = {
            guard vals.count >= 4 else { return 0 }
            let half = vals.count / 2
            let firstAvg = vals.prefix(half).reduce(0, +) / Double(half)
            let lastAvg = vals.suffix(half).reduce(0, +) / Double(vals.count - half)
            return firstAvg > 0 ? (lastAvg - firstAvg) / firstAvg * 100 : 0
        }()
        let up = trendPct >= 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Historial de ventas", systemImage: "chart.line.uptrend.xyaxis").font(.system(size: 13, weight: .bold))
                Spacer()
                if let last = sales.last { Text(Self.usd(last.avg)).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Self.green) }
            }
            if abs(trendPct) >= 1 {
                HStack(spacing: 6) {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(up ? "Tiende a subir" : "Tiende a bajar") · \(up ? "+" : "")\(String(format: "%.0f", trendPct))%")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(up ? "buen momento para vender" : "buen momento para comprar")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .foregroundStyle(up ? Self.green : Self.red)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill((up ? Self.green : Self.red).opacity(0.10)))
            }
            areaChart(vals).frame(height: 90)
            HStack {
                Text("mín \(Self.usd(vals.min() ?? 0))").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("\(sales.count) días · ventas reales (KicksDB)").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("máx \(Self.usd(vals.max() ?? 0))").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(premiumCardBG)
    }

    /// Gráfica de área premium: degradado bajo la línea + trazo con gradiente + punto final luminoso.
    private func areaChart(_ values: [Double]) -> some View {
        GeometryReader { geo in
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 1)
            let pts: [CGPoint] = values.enumerated().map { i, v in
                CGPoint(
                    x: values.count > 1 ? geo.size.width * CGFloat(i) / CGFloat(values.count - 1) : 0,
                    y: geo.size.height * (1 - CGFloat((v - minV) / range))
                )
            }
            ZStack {
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: geo.size.height))
                    p.addLine(to: f)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    if let l = pts.last { p.addLine(to: CGPoint(x: l.x, y: geo.size.height)) }
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Self.green.opacity(0.32), Self.green.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(LinearGradient(colors: [Self.green, Self.green.opacity(0.6)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let l = pts.last {
                    Circle().fill(Self.green).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: Self.green.opacity(0.7), radius: 6)
                        .position(l)
                }
            }
        }
    }

    /// Skeleton de carga: tarjetas grises difuminadas mientras se consulta el mercado.
    private var loadingSkeleton: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    Text("Cargando modelo del mercado").font(.system(size: 14, weight: .bold))
                    Text("$000 · consultando precios reales").font(.system(size: 12))
                    Text("$000 · $000 · $000 · $000").font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(premiumCardBG)
            }
        }
        .redacted(reason: .placeholder)
    }

    /// Fondo de tarjeta premium reutilizable (blanco + borde sutil + sombra con profundidad).
    private var premiumCardBG: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.black.opacity(0.04), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 28, weight: .semibold)).foregroundStyle(Color.black.opacity(0.25))
            Text("No market prices yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        guard let lookup = item.marketLookup,
              let raw = try? await KicksDBClient.fetchComparison(query: lookup.query, fallbackQuery: lookup.fallback) else {
            comparison = nil
            return
        }
        comparison = await HomeMarketTableBuilder.prepareDetailComparison(from: raw, query: lookup.query)
        if let q = comparison?.platforms.first(where: { $0.platformKey == "stockx" && $0.productID != nil })
            ?? comparison?.platforms.first(where: { $0.productID != nil }),
           let pid = q.productID {
            sales = await KicksDBClient.dailySales(platformKey: q.platformKey, productID: pid)
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

// MARK: - Precios reales de cartas Pokémon (pokemontcg.io: TCGplayer + Cardmarket)

struct PokemonSetData: Identifiable, Hashable {
    let id: String
    let name: String
    let series: String
    let total: Int
    let year: String
    let logoURL: URL?
}

struct PokemonCardData: Identifiable {
    let id: String
    let name: String
    let setName: String
    let rarity: String
    let tcgMarketUSD: Double?      // precio de mercado real TCGplayer
    let cardmarketEUR: Double?     // tendencia real Cardmarket (EUR)
    let changePercent: Double      // tendencia real (avg7 vs avg30 de Cardmarket)
    let imageURL: URL?

    /// Versión pequeña de la imagen, para rejillas: pesa mucho menos y carga al instante.
    var thumbURL: URL? {
        guard let imageURL else { return nil }
        return URL(string: imageURL.absoluteString.replacingOccurrences(of: "_hires.png", with: ".png"))
    }
}

enum PokemonTCGClient {
    private struct Env: Decodable { let data: [Card] }
    private struct Card: Decodable {
        let id: String?
        let name: String
        let rarity: String?
        let set: CardSet
        let images: Imgs?
        let tcgplayer: Tcg?
        let cardmarket: Cm?
    }
    private struct CardSet: Decodable { let name: String }
    private struct Imgs: Decodable { let small: String?; let large: String? }
    private struct Tcg: Decodable { let prices: [String: Block]? }
    private struct Block: Decodable { let market: Double? }
    private struct Cm: Decodable { let prices: CmPrices? }
    private struct CmPrices: Decodable {
        let trendPrice: Double?; let averageSellPrice: Double?
        let avg7: Double?; let avg30: Double?
    }

    /// Busca una carta y devuelve sus precios REALES (TCGplayer market + Cardmarket trend).
    static func fetchCard(query: String) async -> PokemonCardData? {
        guard var comps = URLComponents(string: "https://api.pokemontcg.io/v2/cards") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "pageSize", value: "1"),
        ]
        guard let url = comps.url else { print("[Pokemon] URL inválida"); return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let data: Data
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { print("[Pokemon] sin HTTPURLResponse"); return nil }
            guard (200..<300).contains(http.statusCode) else {
                print("[Pokemon] HTTP \(http.statusCode) · \(String(data: d, encoding: .utf8)?.prefix(160) ?? "")")
                return nil
            }
            data = d
        } catch {
            print("[Pokemon] error de red: \(error.localizedDescription)")
            return nil
        }
        guard let env = try? JSONDecoder().decode(Env.self, from: data) else {
            print("[Pokemon] fallo al decodificar JSON")
            return nil
        }
        guard let c = env.data.first else { print("[Pokemon] sin resultados para: \(query)"); return nil }
        print("[Pokemon] OK \(c.name)")
        return map(c)
    }

    /// Trae VARIAS cartas reales (con precio de TCGplayer), ordenadas por precio descendente.
    static func fetchCards(query: String, limit: Int = 16) async -> [PokemonCardData] {
        guard var comps = URLComponents(string: "https://api.pokemontcg.io/v2/cards") else { return [] }
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "pageSize", value: String(limit)),
        ]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let env = try? JSONDecoder().decode(Env.self, from: data) else {
            print("[Pokemon] fetchCards falló")
            return []
        }
        let cards = env.data.map(map)
            .filter { ($0.tcgMarketUSD ?? 0) > 0 }
            .sorted { ($0.tcgMarketUSD ?? 0) > ($1.tcgMarketUSD ?? 0) }
        print("[Pokemon] fetchCards: \(cards.count) cartas con precio")
        return cards
    }

    // MARK: Catálogo completo (colecciones y páginas de cartas)

    private struct SetEnv: Decodable { let data: [SetRow] }
    private struct SetRow: Decodable {
        let id: String; let name: String; let series: String?
        let total: Int?; let releaseDate: String?
        let images: SetImgs?
    }
    private struct SetImgs: Decodable { let logo: String?; let symbol: String? }

    private struct SeedSet: Codable { let id: String; let name: String; let series: String; let total: Int; let year: String; let logo: String }
    private static let cacheFolder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("cards", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private static func sets(from data: Data?) -> [PokemonSetData] {
        guard let data, let rows = try? JSONDecoder().decode([SeedSet].self, from: data) else { return [] }
        return rows.map { PokemonSetData(id: $0.id, name: $0.name, series: $0.series, total: $0.total, year: $0.year, logoURL: URL(string: $0.logo)) }
    }

    /// Colecciones disponibles al instante: las últimas guardadas en el teléfono o las incluidas en la app.
    static func storedSets() -> [PokemonSetData] {
        let saved = sets(from: try? Data(contentsOf: cacheFolder.appendingPathComponent("sets.json")))
        return saved.isEmpty ? sets(from: CardSetsSeed.json.data(using: .utf8)) : saved
    }

    /// Todas las colecciones, de la más nueva a la más antigua. Si el catálogo falla, las guardadas.
    static func fetchSets() async -> [PokemonSetData] {
        guard let url = URL(string: "https://api.pokemontcg.io/v2/sets?orderBy=-releaseDate&pageSize=250") else { return storedSets() }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        guard let data = await dataWithRetry(req), let env = try? JSONDecoder().decode(SetEnv.self, from: data), !env.data.isEmpty else { return storedSets() }
        let rows = env.data.map { SeedSet(id: $0.id, name: $0.name, series: $0.series ?? "", total: $0.total ?? 0, year: String(($0.releaseDate ?? "").prefix(4)), logo: $0.images?.logo ?? "") }
        if let encoded = try? JSONEncoder().encode(rows) {
            try? encoded.write(to: cacheFolder.appendingPathComponent("sets.json"), options: .atomic)
            return sets(from: encoded)
        }
        return storedSets()
    }

    /// El catálogo a veces responde con error; se reintenta un par de veces antes de rendirse.
    private static func dataWithRetry(_ request: URLRequest, attempts: Int = 3) async -> Data? {
        for attempt in 0..<attempts {
            if let (data, resp) = try? await URLSession.shared.data(for: request),
               let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) { return data }
            try? await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
        }
        return nil
    }

    /// Devuelve `nil` si el catálogo no respondió (para ofrecer reintentar), y `[]` si no hay más cartas.
    static func fetchPage(query: String, page: Int, pageSize: Int = 30) async -> [PokemonCardData]? {
        guard var comps = URLComponents(string: "https://api.pokemontcg.io/v2/cards") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "orderBy", value: "-set.releaseDate,number"),
            URLQueryItem(name: "select", value: "id,name,rarity,set,images,tcgplayer,cardmarket"),
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.timeoutInterval = 12
        let key = Data((query + "|\(page)|\(pageSize)").utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").prefix(120)
        let file = cacheFolder.appendingPathComponent("page-\(key).json")
        if let data = await dataWithRetry(req, attempts: 4), let env = try? JSONDecoder().decode(Env.self, from: data) {
            try? data.write(to: file, options: .atomic)
            return env.data.map(map)
        }
        // El catálogo no respondió: se enseña lo último que se guardó de esta misma página.
        if let data = try? Data(contentsOf: file), let env = try? JSONDecoder().decode(Env.self, from: data) { return env.data.map(map) }
        return nil
    }

    private static func map(_ c: Card) -> PokemonCardData {
        let market = (c.tcgplayer?.prices ?? [:]).values.compactMap(\.market).max()
        let cm = c.cardmarket?.prices?.trendPrice ?? c.cardmarket?.prices?.averageSellPrice
        var change = 0.0
        if let a7 = c.cardmarket?.prices?.avg7, let a30 = c.cardmarket?.prices?.avg30, a30 > 0 {
            change = (a7 - a30) / a30 * 100
        }
        return PokemonCardData(
            id: c.id ?? UUID().uuidString,
            name: c.name,
            setName: c.set.name,
            rarity: c.rarity ?? "",
            tcgMarketUSD: market,
            cardmarketEUR: cm,
            changePercent: change,
            imageURL: (c.images?.large ?? c.images?.small).flatMap { URL(string: $0) }
        )
    }
}

// MARK: - Carrusel de cartas Pokémon reales (precios TCGplayer en vivo)

struct PokemonCardsStrip: View {
    @State private var cards: [PokemonCardData] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.12))
                Text("POKÉMON · CARDS")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DashboardHomePalette.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(DashboardHomePalette.accentGreen).frame(width: 6, height: 6)
                    Text("real prices").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }

            if cards.isEmpty {
                Text(loaded ? "No disponible ahora" : "Cargando cartas…")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(cards) { card in cardCell(card) }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(16)
        .background(homeCardBackground)
        .task {
            guard cards.isEmpty else { return }
            cards = await PokemonTCGClient.fetchCards(query: "set.id:base1 rarity:\"Rare Holo\"", limit: 16)
            loaded = true
        }
    }

    private func cardCell(_ card: PokemonCardData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = card.imageURL {
                StockCachedRemoteImage(url: url)
                    .frame(width: 96, height: 134)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground))
                    .frame(width: 96, height: 134)
            }
            Text(card.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DashboardHomePalette.textPrimary)
                .lineLimit(1).frame(width: 96, alignment: .leading)
            Text(PieceMarketPrice.formatUSD(Int((card.tcgMarketUSD ?? 0).rounded())))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(DashboardHomePalette.textPrimary)
        }
    }
}

private enum AccarLogoAssets {
    static let oddishGIFName = "3d-pokemon-card-oddish"
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

    var body: some View {
        VStack(spacing: 16) {
            HomeTrendingCardsRow(title: "Card Catalog", icon: "rectangle.portrait.on.rectangle.portrait.fill", onViewAll: { NotificationCenter.default.post(name: .homeOpenCards, object: nil) })
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

            // Dos zapatos por fila, en fichas de cristal, solo con el nombre.
            GlassEffectContainer(spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(visibleItems) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            trendingCard(item, isSelected: selectedID == item.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func trendingCard(_ item: HomeSneakerHighlight, isSelected: Bool) -> some View {
        VStack(spacing: 8) {
            highlightImage(item)
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .blendMode(.multiply)   // el fondo blanco de la foto se funde con el cristal

            Text(item.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(DashboardHomePalette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isSelected ? Color.black : .clear, lineWidth: 2)
        }
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
    static let standardSizes = ["8", "9", "10"]
    /// Tallas "normales" de adulto que priorizamos en el Home (evita tallas de niño tipo US 3-4).
    static let preferredSizes = ["8", "9", "10", "11", "8.5", "9.5", "10.5", "12", "7", "7.5", "11.5", "13"]
    static let allShoeSizes: [String] = [
        "4", "4.5", "5", "5.5", "6", "6.5", "7", "7.5", "8", "8.5",
        "9", "9.5", "10", "10.5", "11", "11.5", "12", "13", "14", "15",
    ]
    static let homePlatforms = ["StockX", "GOAT", "eBay", "Flight Club"]

    static func displayRows(from comparison: MarketComparison?, maxRows: Int = 5) -> [MarketSizeRow] {
        Array(buildHomeRows(from: comparison).prefix(maxRows))
    }

    /// Tallas con precio REAL (no rellenamos toda la escala con estimaciones).
    static func resolvedAllSizes(from comparison: MarketComparison?) -> [String] {
        (comparison?.rows ?? [])
            .filter { !canonicalizeAsks($0.asks).isEmpty }
            .map { normalizeSizeKey($0.size) }
            .sorted { (numericSize($0) ?? 0) < (numericSize($1) ?? 0) }
    }

    /// Ficha de zapato: TODAS las tallas con precio real, sin inventar ni extrapolar.
    static func buildAllSizeRows(from comparison: MarketComparison?) -> [MarketSizeRow] {
        (comparison?.rows ?? [])
            .map { MarketSizeRow(size: normalizeSizeKey($0.size), asks: canonicalizeAsks($0.asks)) }
            .filter { !$0.asks.isEmpty }
            .sorted { (numericSize($0.size) ?? 0) < (numericSize($1.size) ?? 0) }
    }

    /// Enriquece con eBay y devuelve todas las tallas (ficha de zapato).
    static func prepareDetailComparison(from raw: MarketComparison, query: String) async -> MarketComparison {
        let enriched = await enrichWithEbay(comparison: raw, query: query, includeStandardSizes: false)
        let rows = buildAllSizeRows(from: enriched)
        return MarketComparison(
            query: enriched.query,
            platforms: enriched.platforms,
            sizes: rows.map(\.size),
            rows: rows,
            fetchedAt: enriched.fetchedAt,
            skuAligned: enriched.skuAligned
        )
    }

    /// SOLO precios reales de la API (StockX/GOAT/eBay). No se inventan precios ni se extrapolan
    /// tallas: si la API no trae ese modelo/talla, la celda queda vacía → la tabla muestra "—".
    /// Se devuelven únicamente las tallas que tienen al menos un precio real, ordenadas.
    static func buildHomeRows(from comparison: MarketComparison?) -> [MarketSizeRow] {
        let real = (comparison?.rows ?? [])
            .map { MarketSizeRow(size: normalizeSizeKey($0.size), asks: canonicalizeAsks($0.asks)) }
            .filter { !$0.asks.isEmpty }
        guard !real.isEmpty else { return [] }

        let bySize = Dictionary(real.map { ($0.size, $0) }, uniquingKeysWith: { a, _ in a })
        let cap = 6
        var chosen: [MarketSizeRow] = []
        var used = Set<String>()

        // 1) Tallas normales de adulto primero (8, 9, 10, 11…).
        for s in preferredSizes where chosen.count < cap {
            if let r = bySize[s] { chosen.append(r); used.insert(s) }
        }
        // 2) Si faltan, completa con otras tallas >= 7 (evita tallas de niño).
        if chosen.count < cap {
            for r in real
                .filter({ !used.contains($0.size) && (numericSize($0.size) ?? 0) >= 7 })
                .sorted(by: { (numericSize($0.size) ?? 0) < (numericSize($1.size) ?? 0) })
            where chosen.count < cap {
                chosen.append(r); used.insert(r.size)
            }
        }
        // 3) Último recurso: si el producto SOLO tiene tallas pequeñas, muestra esas.
        if chosen.isEmpty {
            chosen = real.sorted { (numericSize($0.size) ?? 0) < (numericSize($1.size) ?? 0) }
        }

        return chosen.sorted { (numericSize($0.size) ?? 0) < (numericSize($1.size) ?? 0) }
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

    static func enrichWithEbay(
        comparison: MarketComparison,
        query: String,
        includeStandardSizes: Bool = true
    ) async -> MarketComparison {
        guard EbayPriceService.isConfigured else { return comparison }

        // eBay (Browse) encuentra muchos más listados buscando por NOMBRE del producto que por SKU.
        // Usamos el título emparejado en StockX/GOAT; si no, la query original.
        let matched = comparison.matchedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ebayQuery = (matched?.isEmpty == false) ? matched! : query

        // Una sola consulta a eBay (ya filtrada de basura: zapatos sueltos, tallas de niño…).
        let listings = (try? await EbayPriceService.lowestListings(query: ebayQuery, limit: 50)) ?? []
        guard !listings.isEmpty else { return comparison }

        var rowsBySize = Dictionary(uniqueKeysWithValues: comparison.rows.map {
            (normalizeSizeKey($0.size), $0)
        })

        _ = includeStandardSizes
        for (sizeKey, row) in rowsBySize {
            // Listados de eBay cuya talla detectada coincide con esta fila.
            let sized = listings.filter {
                guard let asp = $0.sizeAspect else { return false }
                return normalizeSizeKey(asp) == sizeKey
            }
            guard !sized.isEmpty else { continue }

            // Ancla de precio: el real de StockX/GOAT para esa talla. eBay solo se acepta dentro de
            // una banda razonable → rechaza precios absurdos (modelo distinto, condición rara, etc.).
            let anchor = [row.asks["StockX"], row.asks["GOAT"]].compactMap { $0 }.min()
            let valid = anchor.map { a in sized.filter { $0.price >= a * 0.6 && $0.price <= a * 2.2 } } ?? sized
            guard let best = valid.min(by: { $0.price < $1.price }) else { continue }

            var asks = row.asks
            asks["eBay"] = best.price
            rowsBySize[sizeKey] = MarketSizeRow(size: row.size, asks: asks)
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

    /// Real-only: NO rellena plataformas faltantes. Solo deja los precios reales (StockX/GOAT/eBay);
    /// lo que no exista se queda fuera y la tabla lo pinta como "—".
    static func completeAsks(_ asks: [String: Double]) -> [String: Double] {
        canonicalizeAsks(asks)
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
        return dropPriceOutliers(result)
    }

    /// Descarta precios claramente irreales — p.ej. un emparejado erróneo a $1,772 cuando el resto
    /// de plataformas están en ~$140. Solo actúa con 3+ precios para no eliminar datos válidos.
    static func dropPriceOutliers(_ asks: [String: Double]) -> [String: Double] {
        let values = asks.values.sorted()
        guard values.count >= 3 else { return asks }
        let median = values[values.count / 2]
        guard median > 0 else { return asks }
        return asks.filter { _, v in v <= median * 3.5 && v >= median / 3.5 }
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
        let base = 320.0 + (numericSize(size) ?? 8) * 16
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
    var maxVisibleRows: Int? = 3
    /// Zapato del que se enseñan los precios (en Inicio): su foto, su marca y su nombre encabezan la tabla.
    var featured: UpsoledProduct?

    private let platforms = HomeMarketTableBuilder.homePlatforms
    private let rowHeight: CGFloat = 52
    @State private var lastSale: Double?

    private var tableRows: [MarketSizeRow] {
        if let maxVisibleRows {
            return HomeMarketTableBuilder.displayRows(from: comparison, maxRows: maxVisibleRows)
        }
        return HomeMarketTableBuilder.buildAllSizeRows(from: comparison)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tableHeader

            if let featured {
                HStack(spacing: 12) {
                    StockCachedRemoteImage(url: featured.primaryImageURL, maxPixelSide: 320, fillFrame: false)
                        .frame(width: 96, height: 70).blendMode(.multiply)
                    VStack(alignment: .leading, spacing: 6) {
                        BrandLogoLabel(brand: featured.brand ?? "", compact: true)
                            .frame(width: 30, height: 30).glassEffect(.regular, in: .circle)
                        Text(featured.name).font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
            }

            if comparison?.bestBuyOverall != nil || lastSale != nil {
                priceSummary
            }

            if tableRows.isEmpty {
                // Sin precios todavía: la tabla sale montada, con cada plataforma y cada talla en su casilla.
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "ruler").font(.system(size: 11, weight: .bold))
                            Text("US").font(.system(size: 11, weight: .heavy))
                        }
                        .foregroundStyle(Color.black.opacity(0.55))
                        .frame(width: 52, height: 38)
                        .background(Color.black.opacity(0.05), in: .rect(cornerRadius: 11))
                        ForEach(["StockX", "GOAT", "eBay", "Flight Club"], id: \.self) { brand in
                            StylizedMarketplaceLogo(brand: brand).frame(height: 13).padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(Color.black.opacity(0.05), in: .rect(cornerRadius: 11))
                        }
                    }
                    ForEach(featured == nil ? ["8", "9", "10", "11"] : ["7", "8", "9", "10", "11", "12"], id: \.self) { size in
                        HStack(spacing: 8) {
                            DotMatrixText(text: size)
                                .frame(width: 52, height: 40)
                                .background(Color.black, in: .rect(cornerRadius: 11))
                            ForEach(0..<4, id: \.self) { _ in
                                Text("—").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.black.opacity(0.25))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background { RoundedRectangle(cornerRadius: 11).strokeBorder(Color.black.opacity(0.08)) }
                            }
                        }
                    }
                    Text("Prices appear here as soon as the market responds")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.black.opacity(0.45))
                        .frame(maxWidth: .infinity).padding(.top, 4)
                }
            } else {
                HomeMarketPriceGridTable(
                    platforms: platforms,
                    rows: tableRows,
                    rowHeight: rowHeight
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(.white, in: .rect(cornerRadius: 26))
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .task(id: comparison?.matchedSKU ?? comparison?.query ?? "") { await loadLastSale() }
    }

    /// Los dos precios reales que importan, lado a lado (sin promedios que confunden).
    private var priceSummary: some View {
        HStack(spacing: 0) {
            if let ask = comparison?.bestBuyOverall {
                summaryCol(label: "ASK MÁS BAJO",
                           value: PieceMarketPrice.formatUSD(Int(ask.price.rounded())),
                           sub: "comprar ya · \(ask.platform)",
                           color: DashboardHomePalette.accentGreen)
            }
            if let ls = lastSale {
                Divider().frame(height: 36)
                summaryCol(label: "ÚLTIMA VENTA",
                           value: PieceMarketPrice.formatUSD(Int(ls.rounded())),
                           sub: "venta real",
                           color: DashboardHomePalette.accentBlue)
            }
        }
        .padding(.vertical, 4)
    }

    private func summaryCol(label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(DashboardHomePalette.labelMuted)
            Text(value).font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text(sub).font(.system(size: 9)).foregroundStyle(DashboardHomePalette.labelMuted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Trae la última venta real (KicksDB) usando el productID del producto emparejado.
    private func loadLastSale() async {
        guard let comp = comparison,
              let q = comp.platforms.first(where: { $0.platformKey == "stockx" && $0.productID != nil })
                ?? comp.platforms.first(where: { $0.productID != nil }),
              let pid = q.productID else { lastSale = nil; return }
        let sales = await KicksDBClient.dailySales(platformKey: q.platformKey, productID: pid)
        lastSale = sales.last?.avg
    }

    private var tableHeader: some View {
        HStack {
            HStack(spacing: 7) {
                Image("IconMercado").resizable().scaledToFit().frame(width: 20, height: 20).foregroundStyle(.black)
                Text("MARKET PRICES")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.9)
                    .foregroundStyle(Color.black.opacity(0.88))
            }
            Spacer(minLength: 0)
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

    /// Mediana de los precios reales de esa talla (misma fila) para marcar ↑ verde / ↓ rojo.
    private func rowPriceMedian(_ asks: [String: Double]) -> Double? {
        let prices = platforms.compactMap { asks[$0] }.filter { $0 > 0 }
        guard !prices.isEmpty else { return nil }
        let sorted = prices.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

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
        let rowMedian = isHeader ? nil : rowPriceMedian(asks)
        return HStack(spacing: 0) {
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
                        price: asks[platform],
                        rowMedian: rowMedian
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

    private func pricePlatformCell(width: CGFloat, price: Double?, rowMedian: Double?) -> some View {
        priceCell(price: price, rowMedian: rowMedian)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, cellHorizontalPadding)
            .padding(.vertical, cellVerticalPadding)
            .frame(width: width, height: rowHeight, alignment: .center)
    }

    private func priceCell(price: Double?, rowMedian: Double?) -> some View {
        Group {
            if let price {
                let isHigher = rowMedian.map { price >= $0 } ?? true
                HStack(spacing: 4) {
                    Text(DealershipStatsViewModel.formatUSD(price))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: isHigher ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(
                            isHigher
                                ? DashboardHomePalette.accentGreen
                                : Color(red: 0.92, green: 0.34, blue: 0.34)
                        )
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
        // Tallas ≥ 27 no existen en US (la US llega ~18): son europeas → etiquetar EU.
        if let n = Double(normalized.replacingOccurrences(of: ",", with: ".")), n >= 27 {
            return "US \(normalized)"
        }
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

// MARK: - Watchlist (favoritos)

struct WatchlistView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WatchlistStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView(
                        "Sin favoritos",
                        systemImage: "star",
                        description: Text("Añade modelos con la estrella ★ en la ficha de precios para seguir su precio aquí.")
                    )
                } else {
                    List {
                        ForEach(store.items) { WatchRow(item: $0) }
                            .onDelete { idx in idx.map { store.items[$0] }.forEach(store.remove) }
                    }
                }
            }
            .navigationTitle("Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
        }
        .preferredColorScheme(.light)
    }
}

struct WatchRow: View {
    let item: WatchItem
    @State private var price: Double?
    @State private var loading = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(item.query).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if loading {
                ProgressView()
            } else if let p = price {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(PieceMarketPrice.formatUSD(Int(p.rounded())))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text("mejor compra").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if let comp = (try? await KicksDBClient.fetchComparison(query: item.query)) ?? nil,
           let v = comp.bestBuyOverall?.price {
            price = v
        }
    }
}


// MARK: - Inicio en mosaico de cristal

/// Inicio: banner, cifras reales del negocio, accesos por categoría.
struct HomeBentoGrid: View {
    let closetItems: [ClosetItem]
    let catalogProducts: [UpsoledProduct]
    @Binding var showsCards: Bool
    var onSneakers: () -> Void
    var onScan: () -> Void
    var onCards: () -> Void
    @ObservedObject private var reports = SaleReportStore.shared
    @ObservedObject private var listings = ListingStore.shared
    @State private var showReports = false

    private var stock: [ClosetItem] { closetItems.filter(\.isActiveInStock) }
    private var sold: [ClosetItem] { closetItems.filter(\.isSold) }
    private var stockValue: Double { stock.reduce(0) { $0 + $1.stockValueUSD } }
    private var earnings: Double { sold.reduce(0) { $0 + $1.stockValueUSD } }
    private let purple = Color.black

    private func money(_ value: Double) -> String { value > 0 ? SaleReport.usd(value.rounded()) : "$0" }

    var body: some View {
        VStack(spacing: 14) {
            // Banner de cartas
            Button(action: onCards) {
                ZStack(alignment: .leading) {
                    // Tres cartas gradadas en abanico, a la derecha, que se difuminan hacia el texto y hacia abajo.
                    HStack(spacing: -30) {
                        bannerCard("BannerCard1", angle: -7, y: 8)
                        bannerCard("BannerCard2", angle: 7, y: 8).zIndex(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 0)
                    .offset(x: 6, y: 34)
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0.40), .init(color: .black, location: 0.54)], startPoint: .leading, endPoint: .trailing)
                    }
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0.78), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Trading Cards").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        Text("Buy · Sell · Track value").font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                        HStack(spacing: 6) {
                            Text("Explore").font(.system(size: 14, weight: .bold))
                            Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.black).padding(.horizontal, 16).frame(height: 36)
                        .background(.white, in: .capsule).padding(.top, 6)
                    }
                    .padding(.leading, 18)
                }
                .frame(maxWidth: .infinity, minHeight: Self.bigScreen ? 176 : 150, maxHeight: Self.bigScreen ? 176 : 150)
                // Rojo sólido de fondo y, encima, el cristal teñido: se nota el color sin perder el brillo.
                .background(Color(red: 0.93, green: 0.05, blue: 0.05))
                .clipShape(.rect(cornerRadius: 26))
                .glassEffect(.clear.tint(Color(red: 0.93, green: 0.05, blue: 0.05).opacity(0.35)).interactive(), in: .rect(cornerRadius: 26))
            }
            .buttonStyle(.plain)

            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        bigStat(icon: "wallet.bifold", title: "Total Earnings", value: money(earnings))
                            .frame(maxWidth: .infinity)
                        bigStat(icon: "shippingbox", title: "Pairs Sold", value: "\(sold.count)")
                            .frame(width: 130)
                    }
                    HStack(spacing: 10) {
                        Button(action: onSneakers) { smallStat(icon: "shoe.2", title: "Inventory", value: "\(stock.count)") }.buttonStyle(.plain)
                        Button(action: onSneakers) { smallStat(icon: "chart.bar", title: "Stock Value", value: money(stockValue)) }.buttonStyle(.plain)
                        Button { showReports = true } label: { smallStat(icon: "tag", title: "Listings", value: "\(listings.listings.count)") }.buttonStyle(.plain)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showReports) {
            NavigationStack {
                SaleReportsHistoryView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button { showReports = false } label: { Image(systemName: "xmark") } } }
            }
        }
    }

    /// iPhone grande (Pro Max / Plus): el banner y sus cartas crecen.
    private static var bigScreen: Bool { UIScreen.main.bounds.width >= 428 }

    private func bannerCard(_ name: String, angle: Double, y: CGFloat) -> some View {
        Image(name).resizable().scaledToFit()
            .frame(width: Self.bigScreen ? 132 : 106)
            .clipShape(.rect(cornerRadius: 8))
            .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
            .rotationEffect(.degrees(angle))
            .offset(y: y)
    }

    private func bigStat(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.black)
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.black.opacity(0.7)).lineLimit(1)
            }
            Text(value).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.black).minimumScaleFactor(0.5).lineLimit(1)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: 22))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func smallStat(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.black.opacity(0.7))
            HStack {
                Text(value).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.black).minimumScaleFactor(0.6).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.black.opacity(0.4))
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: 18))
        .background(.white, in: .rect(cornerRadius: 18))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private func category(_ icon: String, _ title: String, highlighted: Bool = false) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22, weight: .medium)).foregroundStyle(highlighted ? purple : .black).frame(height: 26)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .contentShape(.rect(cornerRadius: 18))
        .background(highlighted ? Color(white: 0.90) : .white, in: .rect(cornerRadius: 18))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }
}

/// «Trending Now»: fila de zapatos del catálogo que se desliza hacia la derecha.
struct HomeTrendingRow: View {
    let products: [UpsoledProduct]
    var onViewAll: () -> Void

    var body: some View {
        if !products.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AnimatedFlame()
                    Text("Trending Now").font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                    Spacer()
                    Button(action: onViewAll) {
                        HStack(spacing: 4) { Text("View all"); Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)) }
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(products) { product in
                            NavigationLink { CatalogShoePreview(product: product) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    StockCachedRemoteImage(url: product.primaryImageURL, maxPixelSide: 320, fillFrame: false)
                                        .frame(width: 118, height: 90).blendMode(.multiply)
                                    Text(product.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                                        .lineLimit(2).multilineTextAlignment(.leading).frame(width: 118, height: 34, alignment: .topLeading)
                                }
                                .padding(12).padding(.top, 14)
                                .background(.white, in: .rect(cornerRadius: 20))
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                                .overlay(alignment: .topLeading) {
                                    // La marca, en un círculo de cristal en la esquina.
                                    BrandLogoLabel(brand: product.brand ?? "", compact: true)
                                        .frame(width: 30, height: 30)
                                        .glassEffect(.regular, in: .circle)
                                        .padding(8)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }
}


/// «Trending Now» con cartas: las mismas fichas que los zapatos, con cartas reales del catálogo.
extension Notification.Name { static let homeOpenCards = Notification.Name("Uniclick.homeOpenCards") }

struct HomeTrendingCardsRow: View {
    var title = "Trending Now"
    var icon = "flame.fill"
    var onViewAll: () -> Void
    @State private var cards: [PokemonCardData] = []
    @State private var report: SaleReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if icon == "flame.fill" { AnimatedFlame() } else { Image("IconSlab").resizable().scaledToFit().frame(width: 22, height: 22).foregroundStyle(.black) }
                Text(title).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                Spacer()
                Button(action: onViewAll) {
                    HStack(spacing: 4) { Text("View all"); Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)) }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    if cards.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.04)).frame(width: 142, height: 200)
                        }
                    }
                    ForEach(cards) { card in
                        Button { report = SaleReport.from(card: card) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncImage(url: card.thumbURL) { phase in
                                    if let image = phase.image { image.resizable().scaledToFit() } else { Color.black.opacity(0.05) }
                                }
                                .frame(width: 118, height: 150)
                                Text(card.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black).lineLimit(1).frame(width: 118, alignment: .leading)
                                Text(card.tcgMarketUSD.map(SaleReport.usd) ?? card.setName)
                                    .font(.system(size: 12, weight: card.tcgMarketUSD == nil ? .medium : .heavy, design: .rounded))
                                    .foregroundStyle(card.tcgMarketUSD == nil ? Color.black.opacity(0.5) : .black).lineLimit(1).frame(width: 118, alignment: .leading)
                            }
                            .padding(12)
                            .background(.white, in: .rect(cornerRadius: 20))
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                            .overlay(alignment: .topTrailing) { CardEditionBadge(card: card).padding(6) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .task {
            guard cards.isEmpty else { return }
            // Surtido: cartas conocidas de muchas ediciones, y solo una por edición.
            let query = "(name:charizard OR name:pikachu OR name:mewtwo OR name:umbreon OR name:gengar OR name:rayquaza OR name:lugia OR name:eevee)"
            let found = await PokemonTCGClient.fetchPage(query: query, page: 1, pageSize: 80) ?? []
            var seenSets = Set<String>(), seenNames = [String: Int](), picked: [PokemonCardData] = []
            for card in found where !seenSets.contains(card.setName) {
                let base = card.name.split(separator: " ").first.map(String.init) ?? card.name
                guard seenNames[base, default: 0] < 2 else { continue }
                seenSets.insert(card.setName); seenNames[base, default: 0] += 1
                picked.append(card)
                if picked.count == 12 { break }
            }
            cards = picked.isEmpty ? Array(found.prefix(12)) : picked
        }
        .fullScreenCover(item: $report) { SaleReportView(report: $0) }
    }
}

/// Difuminado en la parte de abajo, como el de la cabecera: el contenido se pierde bajo la barra.
struct BottomFade: ViewModifier {
    var color: Color = .white
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            LinearGradient(colors: [color.opacity(0), color.opacity(0.9), color], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}


/// Etiqueta de cristal en la esquina de una carta: el logo de su edición (colección).
struct CardEditionBadge: View {
    let card: PokemonCardData
    private static let logos: [String: URL] = {
        var map: [String: URL] = [:]
        for set in PokemonTCGClient.storedSets() { if let url = set.logoURL { map[set.name] = url } }
        return map
    }()

    var body: some View {
        if let url = Self.logos[card.setName] {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFit() } else { Color.clear }
            }
            .frame(width: 44, height: 18)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
        }
    }
}


/// Llama animada: el icono de fuego con contorno negro, centrado, que arde a saltos como un GIF
/// (crece y encoge desde la base y cambia un poco de brillo).
struct AnimatedFlame: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 10)) { context in
            let t = (context.date.timeIntervalSinceReferenceDate * 10).rounded() / 10
            let flicker = sin(t * 11) * 0.6 + sin(t * 17.3) * 0.4
            let glow = (sin(t * 2.4) + 1) / 2
            Image("FlameIcon")
                .resizable().scaledToFit()
                .frame(width: 17, height: 22)
                .scaleEffect(x: 1 - flicker * 0.04, y: 1 + flicker * 0.08, anchor: .bottom)
                .brightness(-0.10 + glow * 0.14)
                .saturation(0.9 + glow * 0.3)
        }
        .frame(width: 19, height: 24, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Número en matriz de puntos, como un marcador luminoso.
struct DotMatrixText: View {
    let text: String
    var dot: CGFloat = 2.1
    var color: Color = .white

    private static let glyphs: [Character: [String]] = [
        "0": ["01110","10001","10011","10101","11001","10001","01110"],
        "1": ["00100","01100","00100","00100","00100","00100","01110"],
        "2": ["01110","10001","00001","00010","00100","01000","11111"],
        "3": ["11110","00001","00001","01110","00001","00001","11110"],
        "4": ["00010","00110","01010","10010","11111","00010","00010"],
        "5": ["11111","10000","11110","00001","00001","10001","01110"],
        "6": ["00110","01000","10000","11110","10001","10001","01110"],
        "7": ["11111","00001","00010","00100","01000","01000","01000"],
        "8": ["01110","10001","10001","01110","10001","10001","01110"],
        "9": ["01110","10001","10001","01111","00001","00010","01100"],
        ".": ["0","0","0","0","0","0","1"],
    ]

    var body: some View {
        let chars = text.compactMap { Self.glyphs[$0] }
        let step = dot * 1.45
        let width = chars.reduce(CGFloat(0)) { $0 + CGFloat($1[0].count) * step } + CGFloat(max(0, chars.count - 1)) * step
        Canvas { context, _ in
            var x: CGFloat = 0
            for glyph in chars {
                for (row, line) in glyph.enumerated() {
                    for (col, bit) in line.enumerated() where bit == "1" {
                        let rect = CGRect(x: x + CGFloat(col) * step, y: CGFloat(row) * step, width: dot, height: dot)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                x += CGFloat(glyph[0].count + 1) * step
            }
        }
        .frame(width: width, height: 7 * step)
        .accessibilityLabel(text)
    }
}


// MARK: - Escaparate giratorio de cartas

/// Cartas gradadas en un carrusel que gira: la del centro va grande y de frente; las demás se
/// alejan hacia los lados. Se arrastra para girar y, si no se toca, avanza solo.
struct CardsShowcase: View {
    var onViewAll: () -> Void
    private let cards = ["ShowCard1", "ShowCard2", "ShowCard3", "ShowCard4", "ShowCard5"]
    private let red = Color(red: 0.93, green: 0.05, blue: 0.05)

    @State private var position: Double = 0      // carta que está en el centro (puede ser fraccionaria)
    @State private var dragStart: Double?
    @State private var lastTouch = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Logo de PSA (el archivo original), recortado a su recuadro rojo, sin sombra.
                Image("LogoPSA").resizable().scaledToFill()
                    .frame(width: 54, height: 34)
                    .clipShape(.rect(cornerRadius: 9))
                    .accessibilityLabel("PSA")
                Text("Trading Cards").font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                Spacer()
                Button(action: onViewAll) {
                    HStack(spacing: 4) { Text("View all"); Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)) }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }

            ZStack(alignment: .bottom) {
                // Plataforma luminosa bajo las cartas.
                Ellipse().fill(RadialGradient(colors: [red.opacity(0.35), red.opacity(0)], center: .center, startRadius: 4, endRadius: 170))
                    .frame(width: 340, height: 70)
                Ellipse().strokeBorder(LinearGradient(colors: [.white, red.opacity(0.7)], startPoint: .top, endPoint: .bottom), lineWidth: 3)
                    .frame(width: 250, height: 38).blur(radius: 0.6)
                    .shadow(color: red.opacity(0.8), radius: 10)
                    .padding(.bottom, 10)

                ZStack {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, name in
                        let d = offset(of: index)
                        let depth = min(abs(d), 2.5)
                        Image(name).resizable().scaledToFit()
                            .frame(height: 250)
                            .clipShape(.rect(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.22 - depth * 0.05), radius: 10, y: 6)
                            .scaleEffect(1 - depth * 0.19)
                            .rotation3DEffect(.degrees(-d * 16), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                            .offset(x: sin(d * 0.62) * 150, y: depth * 4)
                            .opacity(depth > 2.2 ? 0 : 1 - depth * 0.16)
                            .zIndex(10 - depth)
                    }
                }
                .padding(.bottom, 26)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        if dragStart == nil { dragStart = position }
                        position = (dragStart ?? 0) - value.translation.width / 110
                        lastTouch = Date()
                    }
                    .onEnded { value in
                        let target = ((dragStart ?? position) - value.predictedEndTranslation.width / 110).rounded()
                        dragStart = nil
                        lastTouch = Date()
                        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { position = target }
                    }
            )
            .onTapGesture { onViewAll() }
        }
        .task {
            // Si nadie lo toca, gira solo a la siguiente carta cada pocos segundos.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard dragStart == nil, Date().timeIntervalSince(lastTouch) > 4 else { continue }
                withAnimation(.spring(duration: 0.8, bounce: 0.15)) { position = position.rounded() + 1 }
            }
        }
    }

    /// Distancia de la carta al centro, dando la vuelta (de −2,5 a 2,5 con cinco cartas).
    private func offset(of index: Int) -> Double {
        let count = Double(cards.count)
        var d = (Double(index) - position).truncatingRemainder(dividingBy: count)
        if d > count / 2 { d -= count }
        if d < -count / 2 { d += count }
        return d
    }
}

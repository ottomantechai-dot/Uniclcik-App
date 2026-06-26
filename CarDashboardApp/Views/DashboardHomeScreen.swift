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
            let q = name.isEmpty ? displayName : name
            guard !q.isEmpty else { return nil }
            return (q, nil)
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
    @State private var showPortfolio = false

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

            DashboardPortfolioSection(
                items: closetItems,
                onOpen: { showPortfolio = true }
            )

            DashboardMarketPricesSection(
                comparison: marketComparison,
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
            if let item = selectedTrendingItem {
                ShoeMarketDetailView(item: item)
            } else {
                MarketComparatorView()
            }
        }
        .sheet(isPresented: $showPortfolio) {
            PortfolioDetailView(items: closetItems)
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

    private static let green = Color(red: 0.13, green: 0.55, blue: 0.30)
    private static let red = Color(red: 0.85, green: 0.25, blue: 0.25)
    private static let blue = Color(red: 0.20, green: 0.45, blue: 0.85)
    private static func usd(_ v: Double) -> String { DealershipStatsViewModel.formatUSD(v) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if loading {
                        ProgressView("Consultando el mercado…")
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else if let comp = comparison, !comp.rows.isEmpty {
                        bestOfferCard(comp)
                        sellerCard(comp)
                        calculatorCard(comp)
                        if !sales.isEmpty { salesCard }
                        DashboardMarketPricesSection(
                            comparison: comp,
                            selectedProductName: nil,
                            maxVisibleRows: nil,
                            showsViewFullTable: false
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
            .navigationTitle("Detalle de precios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } }
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
            if let last = sales.last {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.usd(last.avg)).font(.system(size: 32, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Text("valor de mercado").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                }
                .padding(.top, 2)
            }
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Historial de ventas", systemImage: "chart.line.uptrend.xyaxis").font(.system(size: 13, weight: .bold))
                Spacer()
                if let last = sales.last { Text(Self.usd(last.avg)).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Self.green) }
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

    /// Fondo de tarjeta premium reutilizable (blanco + borde sutil + sombra con profundidad).
    private var premiumCardBG: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.black.opacity(0.04), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 24)).foregroundStyle(.secondary)
            Text("Sin precios reales para este modelo").font(.system(size: 14, weight: .semibold))
            Text("No se encontró en StockX, GOAT ni eBay.").font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
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
    var selectedProductName: String? = nil
    var maxVisibleRows: Int? = 3
    var showsViewFullTable: Bool = true
    var onViewFullTable: () -> Void = {}

    private let platforms = HomeMarketTableBuilder.homePlatforms
    private let rowHeight: CGFloat = 52

    private var tableRows: [MarketSizeRow] {
        if let maxVisibleRows {
            return HomeMarketTableBuilder.displayRows(from: comparison, maxRows: maxVisibleRows)
        }
        return HomeMarketTableBuilder.buildAllSizeRows(from: comparison)
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

            if tableRows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.black.opacity(0.25))
                    Text("Sin precios reales para este modelo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.6))
                    Text("No se encontró en StockX, GOAT ni eBay con su SKU/nombre.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.black.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                HomeMarketPriceGridTable(
                    platforms: platforms,
                    rows: tableRows,
                    rowHeight: rowHeight
                )
            }

            if showsViewFullTable {
                Button(action: onViewFullTable) {
                    Text("View full price table  ›")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
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

// MARK: - Portfolio P&L (coste vs valor de mercado real)

/// Resumen financiero del inventario activo: cuánto invertiste, cuánto vale hoy y tu ganancia/pérdida.
struct PortfolioStats {
    var count: Int = 0
    var pairsWithCost: Int = 0
    var totalCost: Double = 0          // invertido (solo pares con coste)
    var valueOfCosted: Double = 0      // valor mercado de esos mismos pares
    var totalMarketValue: Double = 0   // valor mercado de TODO el stock activo
    var estNetPayout: Double = 0       // payout estimado tras comisiones (~12%)
    var realizedPL: Double = 0         // ganancia ya materializada (vendidos)
    var soldCount: Int = 0

    var unrealizedPL: Double { valueOfCosted - totalCost }
    var unrealizedPct: Double? { totalCost > 0 ? (unrealizedPL / totalCost) * 100 : nil }

    static func compute(_ items: [ClosetItem]) -> PortfolioStats {
        var s = PortfolioStats()
        for item in items where item.isActiveInStock {
            s.count += 1
            let value = item.stockValueUSD
            s.totalMarketValue += value
            s.estNetPayout += PlatformFees.net(price: value, platform: "stockx")
            let cost = item.purchaseValueUSD
            if cost > 0 {
                s.pairsWithCost += 1
                s.totalCost += cost
                s.valueOfCosted += value
            }
        }
        for item in items where item.isExplicitlySold {
            let cost = item.purchaseValueUSD
            let sell = item.effectiveSellValueUSD
            if cost > 0, sell > 0 {
                s.soldCount += 1
                s.realizedPL += (sell - cost)
            }
        }
        return s
    }
}

enum PortfolioPalette {
    static let green = Color(red: 0.11, green: 0.68, blue: 0.44)
    static let red = Color(red: 0.86, green: 0.27, blue: 0.24)
    static func money(_ v: Double) -> String { PieceMarketPrice.formatUSD(Int(v.rounded())) }
    static func signed(_ v: Double) -> String {
        let m = money(abs(v))
        return v >= 0 ? "+\(m)" : "−\(m)"
    }
}

struct DashboardPortfolioSection: View {
    let items: [ClosetItem]
    var onOpen: () -> Void = {}

    private var stats: PortfolioStats { PortfolioStats.compute(items) }

    var body: some View {
        let s = stats
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Mi portfolio", systemImage: "chart.pie.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DashboardHomePalette.textPrimary)
                    Spacer()
                    Text("\(s.count) en stock")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DashboardHomePalette.labelMuted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DashboardHomePalette.labelMuted)
                }

                // Valor de mercado total
                VStack(alignment: .leading, spacing: 2) {
                    Text("Valor de mercado")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DashboardHomePalette.labelMuted)
                    Text(PortfolioPalette.money(s.totalMarketValue))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(DashboardHomePalette.textPrimary)
                }

                // Fila de métricas
                HStack(spacing: 10) {
                    metric("Invertido", PortfolioPalette.money(s.totalCost), DashboardHomePalette.textPrimary)
                    metric(
                        "Ganancia no realizada",
                        s.pairsWithCost > 0 ? PortfolioPalette.signed(s.unrealizedPL) : "—",
                        s.unrealizedPL >= 0 ? PortfolioPalette.green : PortfolioPalette.red,
                        badge: s.unrealizedPct.map { String(format: "%+.0f%%", $0) }
                    )
                }

                Divider().opacity(0.5)

                HStack {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DashboardHomePalette.labelMuted)
                    Text("Payout neto estimado (tras comisiones)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DashboardHomePalette.labelMuted)
                    Spacer()
                    Text(PortfolioPalette.money(s.estNetPayout))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DashboardHomePalette.textPrimary)
                }
            }
            .padding(18)
            .background(homeCardBackground)
        }
        .buttonStyle(.plain)
    }

    private func metric(_ title: String, _ value: String, _ color: Color, badge: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DashboardHomePalette.labelMuted)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 5) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.12)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PortfolioDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [ClosetItem]

    private var active: [ClosetItem] {
        items.filter { $0.isActiveInStock }
            .sorted { $0.projectedProfitUSD > $1.projectedProfitUSD }
    }

    var body: some View {
        let s = PortfolioStats.compute(items)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard(s)
                    if active.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Por par")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DashboardHomePalette.textPrimary)
                            ForEach(active, id: \.id) { row($0) }
                        }
                    }
                }
                .padding(16)
            }
            .background(DashboardHomePalette.pageBG.ignoresSafeArea())
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } }
            }
        }
        .preferredColorScheme(.light)
    }

    private func summaryCard(_ s: PortfolioStats) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("Valor de mercado del inventario")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DashboardHomePalette.labelMuted)
                Text(PortfolioPalette.money(s.totalMarketValue))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(DashboardHomePalette.textPrimary)
                if s.pairsWithCost > 0 {
                    HStack(spacing: 6) {
                        Text(PortfolioPalette.signed(s.unrealizedPL))
                        if let pct = s.unrealizedPct { Text(String(format: "(%+.0f%%)", pct)) }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(s.unrealizedPL >= 0 ? PortfolioPalette.green : PortfolioPalette.red)
                }
            }
            Divider()
            HStack {
                summaryStat("Invertido", PortfolioPalette.money(s.totalCost))
                Divider().frame(height: 34)
                summaryStat("Payout neto", PortfolioPalette.money(s.estNetPayout))
                Divider().frame(height: 34)
                summaryStat("Realizado", s.soldCount > 0 ? PortfolioPalette.signed(s.realizedPL) : "—",
                            color: s.realizedPL >= 0 ? PortfolioPalette.green : PortfolioPalette.red)
            }
        }
        .padding(18)
        .background(homeCardBackground)
    }

    private func summaryStat(_ title: String, _ value: String, color: Color = DashboardHomePalette.textPrimary) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(DashboardHomePalette.labelMuted)
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 30)).foregroundStyle(DashboardHomePalette.labelMuted)
            Text("Sin pares en stock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DashboardHomePalette.textPrimary)
            Text("Añade el coste de compra a tus pares para ver tu ganancia.")
                .font(.system(size: 12))
                .foregroundStyle(DashboardHomePalette.labelMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func row(_ item: ClosetItem) -> some View {
        let cost = item.purchaseValueUSD
        let value = item.stockValueUSD
        let hasPL = item.hasPricingForProfit
        let pl = item.projectedProfitUSD
        let color = pl >= 0 ? PortfolioPalette.green : PortfolioPalette.red
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.catalogDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DashboardHomePalette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let size = item.cardSizeLabel {
                        Text(size).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DashboardHomePalette.labelMuted)
                    }
                    Text(cost > 0 ? "Coste \(PortfolioPalette.money(cost))" : "Sin coste")
                        .font(.system(size: 10))
                        .foregroundStyle(DashboardHomePalette.labelMuted)
                    Text("· Vale \(PortfolioPalette.money(value))")
                        .font(.system(size: 10))
                        .foregroundStyle(DashboardHomePalette.labelMuted)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(hasPL ? PortfolioPalette.signed(pl) : "—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(hasPL ? color : DashboardHomePalette.labelMuted)
                if hasPL, let pct = item.projectedProfitPercent {
                    Text(String(format: "%+.0f%%", pct))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                }
            }
        }
        .padding(14)
        .background(homeCardBackground)
    }
}

import Foundation
import SwiftUI

enum DealershipPeriodScope: String, CaseIterable, Identifiable {
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"

    var id: String { rawValue }
}

enum DashboardStockSegment: String, CaseIterable, Identifiable {
    case footwear
    case apparel
    case accessories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .footwear: return "Footwear"
        case .apparel: return "Apparel"
        case .accessories: return "Accessories"
        }
    }

    var icon: String {
        switch self {
        case .footwear: return "shoeprints.fill"
        case .apparel: return "tshirt.fill"
        case .accessories: return "bag.fill"
        }
    }
}

struct DashboardCategorySnapshot: Identifiable {
    let id: String
    let segment: DashboardStockSegment
    let valueUSD: Double
    let itemCount: Int
    let changePercent: Double?
    let isUp: Bool

    var valueLabel: String { DealershipStatsViewModel.formatUSD(valueUSD) }
}

struct DashboardMetricTile: Identifiable {
    let id: String
    let title: String
    let icon: String
    let value: String
    let changePercent: Double?
    let isUp: Bool
    let subtitle: String?
}

@MainActor
final class DealershipStatsViewModel: ObservableObject {
    @Published var periodScope: DealershipPeriodScope = .month
    @Published var periodDisplayLabel: String = ""

    @Published var vehiclesInStock: Int = 0
    @Published var vehiclesStockBadge: String = ""
    @Published var totalStockValue: String = "$0"
    @Published var totalStockBadge: String = ""
    @Published var carsSold: Int = 0
    @Published var salesProfit: String = "$0"
    @Published var commercialCommissions: String = "$0"
    @Published var commissionsSubtitle: String = "No recorded sales"
    @Published var totalDealershipEarnings: String = "$0"
    @Published var totalEarningsSubtitle: String = "Sales profit + added earnings"
    @Published var totalInvested: String = "$0"
    @Published var potentialProfit: String = "$0"
    @Published var potentialProfitSubtitle: String = "Based on market / asking price"

    // Extended inventory KPIs
    @Published var stockValueHistory: [Double] = []
    @Published var stockValueChangePercent: Double = 0
    @Published var stockValueIsUp: Bool = true
    @Published var investedChangePercent: Double = 0
    @Published var investedIsUp: Bool = true
    @Published var categorySnapshots: [DashboardCategorySnapshot] = []
    @Published var metricTiles: [DashboardMetricTile] = []
    @Published var grossMarginLabel: String = "—"
    @Published var unrealizedGainLabel: String = "$0"
    @Published var marketCoverageLabel: String = "0 items"
    @Published var comparisonDateLabel: String = ""

    private static let locale = Locale(identifier: "en_US")

    init() {
        periodDisplayLabel = Self.monthLabel(for: Date())
        comparisonDateLabel = Self.yearAgoLabel()
    }

    func refreshFromInventory(
        cars: [Car],
        closetItems: [ClosetItem] = [],
        catalogProducts: [UpsoledProduct] = [],
        asOf date: Date = Date()
    ) {
        periodDisplayLabel = Self.monthLabel(for: date)
        comparisonDateLabel = Self.yearAgoLabel(from: date)

        let activeStock = closetItems.filter(\.isActiveInStock)
        let sold = closetItems.filter(\.isExplicitlySold)

        if !activeStock.isEmpty || !catalogProducts.isEmpty {
            let closetValue = activeStock.reduce(0.0) { $0 + $1.stockValueUSD }
            let catalogValue = catalogProducts.reduce(0.0) { $0 + $1.stockValueUSD }
            let total = closetValue + catalogValue
            totalStockValue = Self.formatUSD(total)

            vehiclesInStock = activeStock.count
                + catalogProducts.reduce(0) { $0 + max(1, $1.quantity ?? 1) }
            let shoesCount = activeStock.filter { $0.category == .shoes }.count
                + catalogProducts.filter { Self.catalogSegment(for: $0.category) == .footwear }.count
            vehiclesStockBadge = shoesCount > 0 ? "\(shoesCount) sneakers" : "\(vehiclesInStock) items"
            totalStockBadge = "\(vehiclesInStock) items"

            let closetInvested = activeStock.reduce(0.0) { $0 + $1.purchaseValueUSD }
            let catalogInvested = catalogProducts.reduce(0.0) { $0 + $1.purchaseValueUSD }
            let investedTotal = closetInvested + catalogInvested
            totalInvested = Self.formatUSD(investedTotal)

            let closetProfit = activeStock.reduce(0.0) { $0 + $1.projectedProfitUSD }
            let catalogProfit = catalogProducts.reduce(0.0) { $0 + $1.projectedProfitUSD }
            let profitTotal = closetProfit + catalogProfit
            potentialProfit = Self.formatSignedUSD(profitTotal)

            let pricedCount = activeStock.filter(\.hasPricingForProfit).count
                + catalogProducts.filter { $0.purchaseCostUSD > 0 && $0.price > 0 }.count
            potentialProfitSubtitle = pricedCount == 0
                ? "Add purchase + asking prices"
                : "\(pricedCount) items with cost basis"

            carsSold = sold.count
            let salesTotal = sold.reduce(0.0) { $0 + $1.projectedProfitUSD }
            salesProfit = Self.formatSignedUSD(salesTotal)
            commissionsSubtitle = sold.isEmpty ? Self.emptySalesSubtitle : "\(sold.count) sold items"
            totalDealershipEarnings = Self.formatSignedUSD(salesTotal)

            refreshExtendedKPIs(
                activeStock: activeStock,
                catalogProducts: catalogProducts,
                sold: sold,
                totalValue: total,
                investedTotal: investedTotal,
                profitTotal: profitTotal
            )
        } else if !cars.isEmpty {
            vehiclesInStock = cars.count
            vehiclesStockBadge = ""
            totalStockBadge = ""
            let total = cars.reduce(0.0) { acc, car in
                acc + (car.listPriceUSD ?? 0)
            }
            totalStockValue = Self.formatUSD(total)
            carsSold = 0
            salesProfit = Self.formatUSD(0)
            commissionsSubtitle = Self.emptySalesSubtitle
            totalDealershipEarnings = Self.formatUSD(0)
            totalInvested = Self.formatUSD(0)
            potentialProfit = Self.formatUSD(0)
            potentialProfitSubtitle = Self.emptySalesSubtitle
            resetExtendedKPIs()
        } else {
            vehiclesInStock = 0
            vehiclesStockBadge = ""
            totalStockBadge = ""
            totalStockValue = Self.formatUSD(0)
            carsSold = 0
            salesProfit = Self.formatUSD(0)
            commissionsSubtitle = Self.emptySalesSubtitle
            totalDealershipEarnings = Self.formatUSD(0)
            totalInvested = Self.formatUSD(0)
            potentialProfit = Self.formatUSD(0)
            potentialProfitSubtitle = Self.emptySalesSubtitle
            resetExtendedKPIs()
        }

        commercialCommissions = Self.formatUSD(0)
    }

    private func resetExtendedKPIs() {
        stockValueHistory = []
        stockValueChangePercent = 0
        stockValueIsUp = true
        investedChangePercent = 0
        investedIsUp = true
        categorySnapshots = []
        metricTiles = []
        grossMarginLabel = "—"
        unrealizedGainLabel = "$0"
        marketCoverageLabel = "0 items"
    }

    private func refreshExtendedKPIs(
        activeStock: [ClosetItem],
        catalogProducts: [UpsoledProduct],
        sold: [ClosetItem],
        totalValue: Double,
        investedTotal: Double,
        profitTotal: Double
    ) {
        stockValueHistory = Self.aggregatePortfolioHistory(
            closetItems: activeStock,
            baselineValue: totalValue
        )
        stockValueChangePercent = Self.historyChangePercent(stockValueHistory)
        stockValueIsUp = stockValueChangePercent >= 0

        if investedTotal > 0 {
            let roi = ((totalValue - investedTotal) / investedTotal) * 100
            investedChangePercent = roi
            investedIsUp = roi >= 0
            unrealizedGainLabel = Self.formatSignedUSD(totalValue - investedTotal)
        } else {
            investedChangePercent = 0
            investedIsUp = true
            unrealizedGainLabel = Self.formatUSD(0)
        }

        if totalValue > 0, investedTotal > 0 {
            let margin = (profitTotal / totalValue) * 100
            grossMarginLabel = String(format: "%.1f%%", margin)
        } else {
            grossMarginLabel = "—"
        }

        let marketTracked = activeStock.filter { ($0.marketPrice?.avg ?? 0) > 0 }.count
        marketCoverageLabel = marketTracked == 1 ? "1 item tracked" : "\(marketTracked) items tracked"

        categorySnapshots = Self.buildCategorySnapshots(
            activeStock: activeStock,
            catalogProducts: catalogProducts
        )

        metricTiles = Self.buildMetricTiles(
            activeStock: activeStock,
            catalogProducts: catalogProducts,
            sold: sold,
            totalValue: totalValue,
            investedTotal: investedTotal,
            profitTotal: profitTotal,
            marketTracked: marketTracked
        )
    }

    // MARK: - Analytics helpers

    nonisolated static func formatUSD(_ amount: Double) -> String {
        let n = NSNumber(value: amount.rounded())
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.maximumFractionDigits = 0
        f.locale = locale
        return f.string(from: n) ?? "$\(Int(amount.rounded()))"
    }

    nonisolated private static func formatSignedUSD(_ amount: Double) -> String {
        if amount == 0 { return formatUSD(0) }
        let absFormatted = formatUSD(abs(amount))
        return amount >= 0 ? "+\(absFormatted)" : "−\(absFormatted)"
    }

    private static let emptySalesSubtitle = "No recorded sales"

    private static func monthLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "LLLL yyyy"
        let raw = f.string(from: date)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private static func yearAgoLabel(from date: Date = Date()) -> String {
        let past = Calendar.current.date(byAdding: .year, value: -1, to: date) ?? date
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: past)
    }

    nonisolated static func formatChangePercent(_ value: Double) -> String {
        String(format: "%@%.1f%%", value >= 0 ? "+" : "", value)
    }

    nonisolated static func historyChangePercent(_ history: [Double]) -> Double {
        guard history.count >= 2, let first = history.first, first > 0, let last = history.last else { return 0 }
        return ((last - first) / first) * 100
    }

    /// Portfolio trend from cached market histories (oldest → newest).
    static func aggregatePortfolioHistory(
        closetItems: [ClosetItem],
        baselineValue: Double
    ) -> [Double] {
        let histories = closetItems.compactMap { item -> [Double]? in
            guard let h = item.marketPrice?.history, h.count >= 2 else { return nil }
            return h
        }
        guard !histories.isEmpty else {
            guard baselineValue > 0 else { return [] }
            return [baselineValue, baselineValue]
        }

        let length = histories.map(\.count).max() ?? 0
        var points: [Double] = []
        for index in 0..<length {
            var sum = 0.0
            for history in histories where index < history.count {
                sum += history[index]
            }
            let untracked = closetItems
                .filter { ($0.marketPrice?.history.count ?? 0) < 2 }
                .reduce(0.0) { $0 + $1.stockValueUSD }
            points.append(sum + untracked)
        }
        return points
    }

    static func closetSegment(for category: ClothingCategory) -> DashboardStockSegment {
        switch category {
        case .shoes: return .footwear
        case .accessories, .bags: return .accessories
        case .tops, .dressesJumpsuits, .pantsSkirts, .coats, .underwear: return .apparel
        }
    }

    static func catalogSegment(for raw: String?) -> DashboardStockSegment {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" {
        case "shoes", "sneakers", "footwear": return .footwear
        case "accessories", "bags": return .accessories
        case "clothing", "vintage", "new-drops", "apparel": return .apparel
        default: return .apparel
        }
    }

    static func averageMarketChange(for items: [ClosetItem]) -> Double? {
        let changes = items.compactMap { item -> Double? in
            guard let mp = item.marketPrice, mp.history.count >= 2 else { return nil }
            return mp.changePercent
        }
        guard !changes.isEmpty else { return nil }
        return changes.reduce(0, +) / Double(changes.count)
    }

    static func buildCategorySnapshots(
        activeStock: [ClosetItem],
        catalogProducts: [UpsoledProduct]
    ) -> [DashboardCategorySnapshot] {
        var values: [DashboardStockSegment: Double] = [:]
        var counts: [DashboardStockSegment: Int] = [:]
        var changeBuckets: [DashboardStockSegment: [Double]] = [:]

        for item in activeStock {
            let seg = closetSegment(for: item.category)
            values[seg, default: 0] += item.stockValueUSD
            counts[seg, default: 0] += 1
            if let change = item.marketPrice?.changePercent, item.marketPrice?.history.count ?? 0 >= 2 {
                changeBuckets[seg, default: []].append(change)
            }
        }

        for product in catalogProducts {
            let seg = catalogSegment(for: product.category)
            let units = max(1, product.quantity ?? 1)
            values[seg, default: 0] += product.stockValueUSD
            counts[seg, default: 0] += units
        }

        return DashboardStockSegment.allCases.map { segment in
            let avgChange = changeBuckets[segment].map { values in
                values.reduce(0, +) / Double(values.count)
            }
            return DashboardCategorySnapshot(
                id: segment.rawValue,
                segment: segment,
                valueUSD: values[segment] ?? 0,
                itemCount: counts[segment] ?? 0,
                changePercent: avgChange,
                isUp: (avgChange ?? 0) >= 0
            )
        }
    }

    static func buildMetricTiles(
        activeStock: [ClosetItem],
        catalogProducts: [UpsoledProduct],
        sold: [ClosetItem],
        totalValue: Double,
        investedTotal: Double,
        profitTotal: Double,
        marketTracked: Int
    ) -> [DashboardMetricTile] {
        let units = activeStock.count + catalogProducts.reduce(0) { $0 + max(1, $1.quantity ?? 1) }
        let avgValue = units > 0 ? totalValue / Double(units) : 0
        let trendingUp = activeStock.filter { $0.marketPrice?.isUp == true }.count
        let trendingDown = activeStock.filter {
            guard let mp = $0.marketPrice, mp.history.count >= 2 else { return false }
            return !mp.isUp
        }.count
        let totalEver = units + sold.count
        let sellThrough = totalEver > 0 ? (Double(sold.count) / Double(totalEver)) * 100 : 0
        let realizedProfit = sold.reduce(0.0) { $0 + $1.projectedProfitUSD }
        let portfolioHistory = aggregatePortfolioHistory(closetItems: activeStock, baselineValue: totalValue)
        let portfolioChange = historyChangePercent(portfolioHistory)
        let avgMarketChange = averageMarketChange(for: activeStock)
        let topCategory = buildCategorySnapshots(activeStock: activeStock, catalogProducts: catalogProducts)
            .max(by: { $0.valueUSD < $1.valueUSD })

        return [
            DashboardMetricTile(
                id: "units",
                title: "Units in stock",
                icon: "shippingbox.fill",
                value: "\(units)",
                changePercent: nil,
                isUp: true,
                subtitle: "\(marketTracked) with live market price"
            ),
            DashboardMetricTile(
                id: "market_trend",
                title: "Market trend",
                icon: "chart.line.uptrend.xyaxis",
                value: formatChangePercent(portfolioChange),
                changePercent: portfolioChange,
                isUp: portfolioChange >= 0,
                subtitle: "Portfolio vs last year"
            ),
            DashboardMetricTile(
                id: "gross_profit",
                title: "Unrealized profit",
                icon: "dollarsign.circle.fill",
                value: formatSignedUSD(profitTotal),
                changePercent: investedTotal > 0 ? (profitTotal / investedTotal) * 100 : nil,
                isUp: profitTotal >= 0,
                subtitle: "Market / asking minus cost"
            ),
            DashboardMetricTile(
                id: "gross_margin",
                title: "Gross margin",
                icon: "chart.pie.fill",
                value: totalValue > 0 && investedTotal > 0
                    ? String(format: "%.1f%%", (profitTotal / totalValue) * 100)
                    : "—",
                changePercent: nil,
                isUp: profitTotal >= 0,
                subtitle: "On current stock value"
            ),
            DashboardMetricTile(
                id: "realized",
                title: "Realized profit",
                icon: "checkmark.seal.fill",
                value: formatSignedUSD(realizedProfit),
                changePercent: nil,
                isUp: realizedProfit >= 0,
                subtitle: sold.isEmpty ? "No sales yet" : "\(sold.count) sold items"
            ),
            DashboardMetricTile(
                id: "avg_value",
                title: "Avg. item value",
                icon: "tag.fill",
                value: formatUSD(avgValue),
                changePercent: avgMarketChange,
                isUp: (avgMarketChange ?? 0) >= 0,
                subtitle: "Current market / asking"
            ),
            DashboardMetricTile(
                id: "top_category",
                title: "Top category",
                icon: "star.fill",
                value: topCategory?.segment.title ?? "—",
                changePercent: topCategory?.changePercent,
                isUp: topCategory?.isUp ?? true,
                subtitle: topCategory.map { formatUSD($0.valueUSD) }
            ),
            DashboardMetricTile(
                id: "trending",
                title: "Price movers",
                icon: "arrow.up.arrow.down",
                value: "\(trendingUp) up · \(trendingDown) down",
                changePercent: nil,
                isUp: trendingUp >= trendingDown,
                subtitle: "Based on market history"
            ),
            DashboardMetricTile(
                id: "sell_through",
                title: "Sell-through",
                icon: "arrow.triangle.2.circlepath",
                value: String(format: "%.0f%%", sellThrough),
                changePercent: nil,
                isUp: sellThrough >= 50,
                subtitle: "\(sold.count) sold of \(totalEver) total"
            ),
        ]
    }
}

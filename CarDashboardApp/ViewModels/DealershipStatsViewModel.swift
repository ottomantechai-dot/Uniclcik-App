import Foundation
import SwiftUI

enum DealershipPeriodScope: String, CaseIterable, Identifiable {
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"

    var id: String { rawValue }
}

@MainActor
final class DealershipStatsViewModel: ObservableObject {
    @Published var periodScope: DealershipPeriodScope = .month
    /// Visible period label (e.g. month and year).
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

    private static let locale = Locale(identifier: "en_US")

    init() {
        periodDisplayLabel = Self.monthLabel(for: Date())
    }

    func refreshFromInventory(cars: [Car], closetItems: [ClosetItem] = [], asOf date: Date = Date()) {
        periodDisplayLabel = Self.monthLabel(for: date)

        if !closetItems.isEmpty {
            let activeStock = closetItems.filter { !$0.isExplicitlySold }
            let sold = closetItems.filter(\.isExplicitlySold)
            vehiclesInStock = activeStock.count
            let shoes = activeStock.filter { $0.category == .shoes }
            vehiclesStockBadge = shoes.isEmpty
                ? ""
                : "\(shoes.count) sneakers"
            let total = activeStock.reduce(0.0) { $0 + $1.stockValueUSD }
            totalStockValue = Self.formatUSD(total)
            let invested = activeStock.reduce(0.0) { $0 + $1.purchaseValueUSD }
            totalInvested = Self.formatUSD(invested)
            let profit = activeStock.reduce(0.0) { $0 + $1.projectedProfitUSD }
            potentialProfit = Self.formatSignedUSD(profit)
            let pricedCount = activeStock.filter(\.hasPricingForProfit).count
            potentialProfitSubtitle = pricedCount == 0
                ? "Add purchase + asking prices"
                : "\(pricedCount) items with cost basis"
            carsSold = sold.count
            let salesTotal = sold.reduce(0.0) { $0 + $1.projectedProfitUSD }
            salesProfit = Self.formatSignedUSD(salesTotal)
            commissionsSubtitle = sold.isEmpty ? Self.emptySalesSubtitle : "\(sold.count) sold items"
            totalDealershipEarnings = Self.formatSignedUSD(salesTotal)
        } else {
            vehiclesInStock = cars.count
            vehiclesStockBadge = ""
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
        }

        commercialCommissions = Self.formatUSD(0)
    }

    private static func formatSignedUSD(_ amount: Double) -> String {
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

    private static func formatUSD(_ amount: Double) -> String {
        let n = NSNumber(value: amount.rounded())
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.maximumFractionDigits = 0
        f.locale = locale
        return f.string(from: n) ?? "$\(Int(amount.rounded()))"
    }
}

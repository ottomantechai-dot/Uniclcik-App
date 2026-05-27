import Foundation
import SwiftUI

enum DealershipPeriodScope: String, CaseIterable, Identifiable {
    case month = "Mes"
    case quarter = "Trimestre"
    case year = "Año"

    var id: String { rawValue }
}

@MainActor
final class DealershipStatsViewModel: ObservableObject {
    @Published var periodScope: DealershipPeriodScope = .month
    /// Etiqueta visible del período (ej. mes y año).
    @Published var periodDisplayLabel: String = ""

    @Published var vehiclesInStock: Int = 0
    @Published var vehiclesStockBadge: String = ""
    @Published var totalStockValue: String = "$0"
    @Published var totalStockBadge: String = ""
    @Published var carsSold: Int = 0
    @Published var salesProfit: String = "$0"
    @Published var commercialCommissions: String = "$0"
    @Published var commissionsSubtitle: String = "Sin ventas registradas"
    @Published var totalDealershipEarnings: String = "$0"
    @Published var totalEarningsSubtitle: String = "Beneficio ventas + beneficios agregados"

    init() {
        periodDisplayLabel = Self.monthLabel(for: Date())
    }

    func refreshFromInventory(cars: [Car], asOf date: Date = Date()) {
        periodDisplayLabel = Self.monthLabel(for: date)
        vehiclesInStock = cars.count

        let total = cars.reduce(0.0) { acc, car in
            acc + (car.listPriceUSD ?? 0)
        }
        totalStockValue = Self.formatUSD(total)

        // Sin fuente de ventas en vivo: mantenemos KPIs de ventas en cero al refrescar inventario.
        carsSold = 0
        salesProfit = Self.formatUSD(0)
        commercialCommissions = Self.formatUSD(0)
        commissionsSubtitle = Self.emptySalesSubtitle
        totalDealershipEarnings = Self.formatUSD(0)
    }

    private static var currentLanguage: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.spanish.rawValue
        return AppLanguage(rawValue: raw) ?? .spanish
    }

    private static var emptySalesSubtitle: String {
        currentLanguage == .english ? "No recorded sales" : "Sin ventas registradas"
    }

    private static func monthLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = currentLanguage.locale
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
        f.locale = currentLanguage.locale
        return f.string(from: n) ?? "$\(Int(amount.rounded()))"
    }
}

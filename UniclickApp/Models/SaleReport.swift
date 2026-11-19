import Foundation
import SwiftUI

// MARK: - Informe de venta
// Lo que sale al escanear una caja (o al elegir una carta): cuánto se paga en cada plataforma,
// cuánto se queda la plataforma y cuánto le llega de verdad al vendedor. Los informes se guardan
// en el teléfono para poder volver a verlos o compartirlos.

struct SaleReport: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case shoe, card }

    struct Line: Identifiable, Codable, Equatable {
        var platform: String
        var priceUSD: Double
        var feePercent: Int
        var feeFixedUSD: Double
        var netUSD: Double
        var id: String { platform }
        var feeUSD: Double { max(0, priceUSD - netUSD) }
    }

    var id = UUID()
    var kind: Kind = .shoe
    var title: String
    var sku: String
    var scannedCode: String
    var imageURL: String?
    var size: String?
    /// Lo que costó la pieza, si se sabe (para sacar la ganancia).
    var costUSD: Double?
    var lines: [Line]
    /// `true` cuando el precio es una estimación de mercado y no el precio de cada plataforma.
    var priceIsEstimate: Bool
    var createdAt = Date()

    /// La plataforma donde más dinero le queda al vendedor.
    var best: Line? { lines.max { $0.netUSD < $1.netUSD } }
    var worst: Line? { lines.min { $0.netUSD < $1.netUSD } }

    func profit(_ line: Line) -> Double? { costUSD.map { line.netUSD - $0 } }
    func roiPercent(_ line: Line) -> Double? {
        guard let cost = costUSD, cost > 0 else { return nil }
        return (line.netUSD - cost) / cost * 100
    }

    /// Diferencia entre vender en la mejor y en la peor plataforma.
    var spreadUSD: Double? {
        guard let hi = best, let lo = worst, hi.platform != lo.platform else { return nil }
        return hi.netUSD - lo.netUSD
    }

    var recommendation: String {
        guard let best else { return "Todavía no hay precios de mercado para este producto." }
        var text = "Publica en \(best.platform): a \(Self.usd(best.priceUSD)) te quedan \(Self.usd(best.netUSD)) después de comisiones."
        if let gain = profit(best) {
            text += gain >= 0 ? " Ganas \(Self.usd(gain)) sobre lo que te costó." : " Pierdes \(Self.usd(-gain)) sobre lo que te costó."
        }
        if let spread = spreadUSD, spread >= 1, let worst {
            text += " Son \(Self.usd(spread)) más que en \(worst.platform)."
        }
        return text
    }

    /// Texto del informe para mandarlo por WhatsApp, correo, etc.
    var shareText: String {
        var out: [String] = ["INFORME DE VENTA · Uniclick", title]
        if !sku.isEmpty { out.append("SKU: \(sku)") }
        if let size, !size.isEmpty { out.append("Talla: \(size)") }
        if let costUSD { out.append("Coste: \(Self.usd(costUSD))") }
        out.append("")
        for line in lines.sorted(by: { $0.netUSD > $1.netUSD }) {
            var row = "\(line.platform): precio \(Self.usd(line.priceUSD)) · comisión \(Self.usd(line.feeUSD)) · te quedan \(Self.usd(line.netUSD))"
            if let gain = profit(line) { row += " · ganancia \(Self.usd(gain))" }
            out.append(row)
        }
        out.append("")
        out.append(recommendation)
        if priceIsEstimate { out.append("Precio estimado de mercado; las comisiones son aproximadas.") }
        out.append(createdAt.formatted(date: .abbreviated, time: .shortened))
        return out.joined(separator: "\n")
    }

    static func usd(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? "$\(Int(rounded))" : String(format: "$%.2f", rounded)
    }

    private static func line(_ platform: String, price: Double) -> Line {
        let fee = PlatformFees.params(platform)
        return Line(platform: platform, priceUSD: price, feePercent: PlatformFees.ratePercent(platform),
                    feeFixedUSD: fee.fixed, netUSD: PlatformFees.net(price: price, platform: platform))
    }

    static let shoePlatforms = ["StockX", "GOAT", "eBay"]
    static let cardPlatforms = ["eBay", "StockX"]

    // MARK: Constructores

    /// Informe a partir del escaneo de una caja (código de barras).
    static func from(payload: StockScanLookupPayload, costUSD: Double? = nil, size: String? = nil) -> SaleReport {
        // Solo precios confirmados por cada plataforma: sin ellos, el informe no inventa cifras.
        let estimate = false
        let lines = (payload.marketEstimate?.platforms ?? []).filter { $0.avg > 0 }.map { line($0.name, price: Double($0.avg)) }
        return SaleReport(title: payload.productTitle, sku: payload.sku, scannedCode: payload.scannedCode,
                          imageURL: payload.imageURL, size: size, costUSD: costUSD ?? payload.buyPriceUSD.map(Double.init),
                          lines: lines, priceIsEstimate: estimate)
    }

    /// Informe a partir del comparador (foto de la caja o búsqueda), para una talla concreta si se da.
    static func from(comparison: MarketComparison, size: String? = nil, costUSD: Double? = nil) -> SaleReport {
        let wanted = size.flatMap(MarketComparison.normalizeSize)
        let lines: [Line] = comparison.platforms.compactMap { quote in
            let price = wanted.flatMap { quote.asksBySize[$0] } ?? quote.lowestAsk ?? quote.avg
            guard let price, price > 0 else { return nil }
            return line(quote.platform, price: price)
        }
        return SaleReport(title: comparison.matchedTitle ?? comparison.query, sku: comparison.matchedSKU ?? "",
                          scannedCode: comparison.query, imageURL: comparison.imageURL?.absoluteString, size: size,
                          costUSD: costUSD, lines: lines, priceIsEstimate: false)
    }

    /// Informe de una carta coleccionable, con su precio de mercado real.
    static func from(card: PokemonCardData) -> SaleReport {
        let price = card.tcgMarketUSD ?? 0
        return SaleReport(kind: .card, title: card.name, sku: card.setName, scannedCode: card.id,
                          imageURL: card.imageURL?.absoluteString, size: card.rarity, costUSD: nil,
                          lines: price > 0 ? cardPlatforms.map { line($0, price: price) } : [], priceIsEstimate: true)
    }
}

// MARK: - Historial de informes

@MainActor
final class SaleReportStore: ObservableObject {
    static let shared = SaleReportStore()
    @Published private(set) var reports: [SaleReport] = []

    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sale-reports.json")

    private init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([SaleReport].self, from: data) {
            reports = saved
        }
    }

    /// Guarda el informe (el más nuevo primero). Devuelve `true` si es nuevo.
    @discardableResult
    func save(_ report: SaleReport) -> Bool {
        let isNew = !reports.contains { $0.id == report.id }
        reports.removeAll { $0.id == report.id }
        reports.insert(report, at: 0)
        reports = Array(reports.prefix(200))
        persist()
        return isNew
    }

    func delete(_ report: SaleReport) {
        reports.removeAll { $0.id == report.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(reports) { try? data.write(to: url, options: .atomic) }
    }
}

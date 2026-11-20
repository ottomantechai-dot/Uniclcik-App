import Foundation

/// Producto del catálogo Upsoled (tabla `public.upsoled_products` en Supabase).
/// Compartido con la web Sneak Peek Miami: lo que la app iOS inserta aquí aparece
/// inmediatamente en la web (lectura RLS pública).
struct UpsoledProduct: Codable, Identifiable, Hashable {
    let id: UUID
    var slug: String
    var name: String
    var brand: String?
    var sku: String?
    var description: String?

    var price: Double
    var compareAtPrice: Double?
    var currency: String

    var image: String?
    var images: [String]
    var mainImageUrl: String?

    var category: String?    // "shoes" | "clothing" | "accessories" | "vintage" | "new-drops"
    var tags: [String]
    var condition: String     // "new" | "used" | "vintage" | "rare"
    var collection: String?

    var sizes: [String]
    var inStock: Bool
    var quantity: Int?

    var userId: UUID?
    var organizationId: UUID?

    var createdAt: Date?
    var updatedAt: Date?

    /// Datos extra del catálogo; aquí llegan los precios de mercado por plataforma.
    var metadata: UpsoledProductMetadata? = nil
    var marketPrices: UpsoledMarketPrices? { metadata?.marketPrices }

    private enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case brand
        case sku
        case description
        case price
        case compareAtPrice = "compare_at_price"
        case currency
        case image
        case images
        case mainImageUrl = "main_image_url"
        case category
        case tags
        case condition
        case collection
        case sizes
        case inStock = "in_stock"
        case quantity
        case userId = "user_id"
        case organizationId = "organization_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case metadata
    }

    /// Imagen "segura" — devuelve la primera URL válida o nil si no hay ninguna.
    var primaryImageURL: URL? {
        let candidates = [image, mainImageUrl] + images
        for raw in candidates {
            guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty,
                  let url = URL(string: s) else { continue }
            return url
        }
        return nil
    }
}

/// Payload de inserción. Se usa para crear productos nuevos. `id`, `created_at`,
/// `updated_at` los genera Postgres.
struct UpsoledProductInsert: Encodable {
    var slug: String
    var name: String
    var brand: String?
    var sku: String?
    var description: String?

    var price: Double
    var compareAtPrice: Double?
    var currency: String = "USD"

    var image: String?
    var images: [String]
    var mainImageUrl: String?

    var category: String?
    var tags: [String]
    var condition: String = "new"
    var collection: String?

    var sizes: [String]
    var inStock: Bool = true
    var quantity: Int?

    var userId: UUID?
    var organizationId: UUID?

    private enum CodingKeys: String, CodingKey {
        case slug, name, brand, sku, description
        case price
        case compareAtPrice = "compare_at_price"
        case currency
        case image, images
        case mainImageUrl = "main_image_url"
        case category, tags, condition, collection
        case sizes
        case inStock = "in_stock"
        case quantity
        case userId = "user_id"
        case organizationId = "organization_id"
    }
}

extension UpsoledProduct {
    /// Cost basis stored in `compare_at_price` when set from the app.
    var purchaseCostUSD: Double { compareAtPrice ?? 0 }

    private var unitCount: Int { max(1, quantity ?? 1) }

    var stockValueUSD: Double { price * Double(unitCount) }

    var purchaseValueUSD: Double { purchaseCostUSD * Double(unitCount) }

    var projectedProfitUSD: Double {
        let cost = purchaseCostUSD
        guard cost > 0, price > 0 else { return 0 }
        return (price - cost) * Double(unitCount)
    }

    var effectiveSellValueUSD: Double { price }

    var hasPricingForProfit: Bool {
        purchaseCostUSD > 0 && price > 0
    }

    var projectedProfitPercent: Double? {
        guard hasPricingForProfit else { return nil }
        let cost = purchaseCostUSD
        guard cost > 0 else { return nil }
        return ((price - cost) / cost) * 100
    }

    var isProjectedLoss: Bool {
        hasPricingForProfit && projectedProfitUSD < 0
    }

    var cardPriceLabel: String? {
        let value = stockValueUSD
        guard value > 0 else { return nil }
        return PieceMarketPrice.formatUSD(Int(value.rounded()))
    }

    var cardProfitUSDLabel: String? {
        guard hasPricingForProfit else { return nil }
        let amount = Int(abs(projectedProfitUSD).rounded())
        let formatted = PieceMarketPrice.formatUSD(amount)
        return projectedProfitUSD >= 0 ? "+\(formatted)" : "−\(formatted)"
    }

    var cardProfitPercentLabel: String? {
        guard let pct = projectedProfitPercent else { return nil }
        return String(format: "%+.0f%%", pct)
    }

    var cardSizeLabel: String? {
        if let first = sizes.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            return StockSizeDisplay.cardLabel(from: first)
        }
        return nil
    }

    var cardSKULabel: String? {
        let t = sku?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    /// URL-friendly slug from the product name.
    static func generateSlug(from name: String) -> String {
        let lowered = name.lowercased()
            .folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US"))
        let cleaned = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(cleaned).replacingOccurrences(
            of: "-+",
            with: "-",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}


/// `metadata` de un producto. Se lee con tolerancia: si algo no tiene la forma esperada, se ignora
/// en lugar de tirar el producto entero.
struct UpsoledProductMetadata: Codable, Hashable {
    var marketPrices: UpsoledMarketPrices?

    private enum CodingKeys: String, CodingKey { case marketPrices = "market_prices" }

    init(from decoder: Decoder) throws {
        let box = try? decoder.container(keyedBy: CodingKeys.self)
        marketPrices = try? box?.decodeIfPresent(UpsoledMarketPrices.self, forKey: .marketPrices)
    }
}

/// Precios de mercado consultados en cada plataforma (USD).
struct UpsoledMarketPrices: Codable, Hashable {
    struct StockX: Codable, Hashable {
        var lowestAsk: Double?
        var highestBid: Double?
        private enum CodingKeys: String, CodingKey { case lowestAsk = "lowest_ask", highestBid = "highest_bid" }
    }
    struct Goat: Codable, Hashable { var lowest: Double? }
    struct EBay: Codable, Hashable {
        /// Mediana de los cinco anuncios más baratos.
        var typicalLow: Double?
        var listings: Int?
        private enum CodingKeys: String, CodingKey { case typicalLow = "median_5_cheapest", listings }
    }

    var asof: String?
    var stockx: StockX?
    var goat: Goat?
    var ebay: EBay?

    /// Precio por plataforma, en el orden en que se enseñan.
    var quotes: [(platform: String, price: Double)] {
        var list: [(String, Double)] = []
        if let value = stockx?.lowestAsk { list.append(("StockX", value)) }
        if let value = goat?.lowest { list.append(("GOAT", value)) }
        if let value = ebay?.typicalLow { list.append(("eBay", value)) }
        return list.map { (platform: $0.0, price: $0.1) }
    }

    /// El más bajo entre StockX y GOAT; eBay solo si es la única fuente (misma regla que el catálogo).
    var best: (platform: String, price: Double)? {
        let main = quotes.filter { $0.platform != "eBay" }
        return (main.isEmpty ? quotes : main).min { $0.price < $1.price }
    }
}

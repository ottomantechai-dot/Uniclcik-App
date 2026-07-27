import Foundation

/// Segmento de inventario que determina qué marketplaces se muestran en cada fila.
enum StockMarketplaceSegment: String, CaseIterable, Identifiable, Sendable {
    case shoes
    case cards
    case clothing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shoes: return "Zapatos"
        case .cards: return "Tarjetas"
        case .clothing: return "Ropa"
        }
    }

    var subtitle: String {
        switch self {
        case .shoes: return "Sneakers & footwear"
        case .cards: return "TCG & graded collectibles"
        case .clothing: return "Apparel & streetwear"
        }
    }

    var emoji: String {
        switch self {
        case .shoes: return "👟"
        case .cards: return "🃏"
        case .clothing: return "👕"
        }
    }

    /// Marketplaces conectados por categoría (demo).
    var platforms: [String] {
        switch self {
        case .shoes:
            return ["StockX", "GOAT", "eBay", "Flight Club"]
        case .cards:
            return ["TCG Collector", "StockX", "eBay"]
        case .clothing:
            return ["StockX", "GOAT", "Grailed", "eBay"]
        }
    }

    /// Nota demo sobre integraciones relacionadas.
    var connectionNote: String? {
        switch self {
        case .shoes:
            return "Alias comparte el backend de precios con GOAT; Flight Club es la vitrina retail."
        default:
            return nil
        }
    }
}

enum StockCategoryMarketplaceCatalog {
    private static let cardKeywords = [
        "pokemon", "pokémon", "charizard", "pikachu", "tcg", "psa", "bgs", "cgc",
        "trading card", "yugioh", "yu-gi-oh", "magic:", "mtg", "panini", "topps",
        "booster", "graded", "holo", "lorcana", "one piece card", "sports card"
    ]

    private static let shoeKeywords = [
        "jordan", "dunk", "yeezy", "air max", "samba", "new balance", "sneaker", "air force"
    ]

    static func segment(for category: ClothingCategory) -> StockMarketplaceSegment {
        switch category {
        case .shoes:
            return .shoes
        case .tops, .dressesJumpsuits, .pantsSkirts, .coats, .underwear, .accessories, .bags:
            return .clothing
        }
    }

    static func segment(for item: ClosetItem) -> StockMarketplaceSegment {
        let haystack = [
            item.name,
            item.brand ?? "",
            item.skuText ?? "",
            item.productDescription ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        if cardKeywords.contains(where: { haystack.contains($0) }) {
            return .cards
        }
        if item.category == .shoes {
            return .shoes
        }
        if item.category == .tops || item.category == .dressesJumpsuits ||
            item.category == .pantsSkirts || item.category == .coats || item.category == .underwear {
            return .clothing
        }
        if shoeKeywords.contains(where: { haystack.contains($0) }) {
            return .shoes
        }
        return segment(for: item.category)
    }

    static func segment(for product: UpsoledProduct) -> StockMarketplaceSegment {
        let category = product.category?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let haystack = [product.name, product.brand ?? "", category]
            .joined(separator: " ")
            .lowercased()

        if category == "cards" || category.contains("tcg") ||
            cardKeywords.contains(where: { haystack.contains($0) }) {
            return .cards
        }
        if category == "shoes" || category == "sneakers" {
            return .shoes
        }
        if category == "clothing" || category == "vintage" || category == "apparel" {
            return .clothing
        }
        if shoeKeywords.contains(where: { haystack.contains($0) }) {
            return .shoes
        }
        return .shoes
    }

    static func synthesizedPlatformPrice(platform name: String, base: Int) -> Int {
        switch name.uppercased() {
        case "STOCKX":
            return base
        case "GOAT", "ALIAS":
            return max(1, Int((Double(base) * 0.988).rounded()))
        case "EBAY":
            return max(1, Int((Double(base) * 0.921).rounded()))
        case "FLIGHT CLUB":
            return max(1, Int((Double(base) * 1.04).rounded()))
        case "TCG COLLECTOR":
            return max(1, Int((Double(base) * 0.952).rounded()))
        case "GRAILED":
            return max(1, Int((Double(base) * 0.938).rounded()))
        case "POSHMARK":
            return max(1, Int((Double(base) * 0.875).rounded()))
        default:
            return base
        }
    }
}

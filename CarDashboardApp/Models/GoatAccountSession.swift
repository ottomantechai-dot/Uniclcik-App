import Foundation

struct GoatAccountSession: Codable, Equatable {
    var auth: String
    var accessToken: String
    var refreshToken: String
    var accountEmail: String
    var displayName: String?
    var connectedAt: Date

    var connectedLabel: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return accountEmail
    }
}

enum GoatAccountStore {
    private static let key = "goatAccountSession.v1"

    static func load() -> GoatAccountSession? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GoatAccountSession.self, from: data)
    }

    static func save(_ session: GoatAccountSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - GOAT catalog models (CommercialGoatAPI)

struct GoatProductSummary: Identifiable, Equatable {
    let id: String
    let slug: String
    let sku: String
    let name: String
    let brand: String
    let imageURL: String?
    let sizeLabel: String?
    let listPriceUSD: Int?

    var displayTitle: String {
        let b = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { return name }
        if name.lowercased().contains(b.lowercased()) { return name }
        return "\(b) \(name)"
    }
}

struct GoatProductPriceDetail {
    let slug: String
    let lowestUSD: Int?
    let highestOfferUSD: Int?
    let currency: String
    let rawDetail: [String: Any]

    var averageUSD: Int? {
        switch (lowestUSD, highestOfferUSD) {
        case let (l?, h?): return (l + h) / 2
        case let (l?, nil): return l
        case let (nil, h?): return h
        default: return nil
        }
    }

    func asPieceMarketPrice() -> PieceMarketPrice? {
        guard let avg = averageUSD else { return nil }
        let minV = lowestUSD ?? avg
        let maxV = highestOfferUSD ?? avg
        let hist = (0..<6).map { i -> Double in
            let t = Double(i) / 5.0
            return Double(minV) + (Double(maxV - minV) * t)
        }
        return PieceMarketPrice(avg: avg, min: minV, max: maxV, history: hist)
    }
}

struct GoatSellerListing: Identifiable, Equatable {
    let id: String
    let name: String
    let sku: String
    let slug: String
    let sizeLabel: String?
    let priceUSD: Int?
    let status: String?
}

enum GoatCatalogParser {
    static func products(from root: [String: Any]) -> [GoatProductSummary] {
        let arrays = candidateArrays(in: root)
        var out: [GoatProductSummary] = []
        var seen = Set<String>()
        for arr in arrays {
            for obj in arr {
                guard let dict = obj as? [String: Any],
                      let parsed = product(from: dict)
                else { continue }
                if seen.insert(parsed.id).inserted {
                    out.append(parsed)
                }
            }
        }
        return out
    }

    static func listings(from root: [String: Any]) -> [GoatSellerListing] {
        let arrays = candidateArrays(in: root)
        var out: [GoatSellerListing] = []
        var seen = Set<String>()
        for arr in arrays {
            for obj in arr {
                guard let dict = obj as? [String: Any],
                      let parsed = listing(from: dict)
                else { continue }
                if seen.insert(parsed.id).inserted {
                    out.append(parsed)
                }
            }
        }
        return out
    }

    static func priceDetail(
        slug: String,
        lowestJSON: [String: Any],
        offersJSON: [String: Any],
        detailJSON: [String: Any],
        currency: String = "USD"
    ) -> GoatProductPriceDetail {
        let lowest = extractUSD(from: lowestJSON)
        let highest = extractUSD(from: offersJSON, preferKeys: ["highest_offer", "highest", "max", "offer"])
            ?? extractUSD(from: offersJSON)
        return GoatProductPriceDetail(
            slug: slug,
            lowestUSD: lowest,
            highestOfferUSD: highest,
            currency: currency,
            rawDetail: detailJSON
        )
    }

    private static func candidateArrays(in root: [String: Any]) -> [[Any]] {
        var found: [[Any]] = []
        func walk(_ value: Any, depth: Int) {
            guard depth < 4 else { return }
            if let arr = value as? [[String: Any]] {
                found.append(arr)
                return
            }
            if let arr = value as? [Any], arr.first is [String: Any] {
                found.append(arr)
                return
            }
            if let dict = value as? [String: Any] {
                for key in ["products", "items", "hits", "results", "list", "data", "records"] {
                    if let v = dict[key] { walk(v, depth: depth + 1) }
                }
            }
        }
        walk(root, depth: 0)
        if let data = root["data"] { walk(data, depth: 0) }
        if found.isEmpty, let data = root["data"] as? [String: Any] {
            for (_, v) in data { walk(v, depth: 1) }
        }
        return found
    }

    private static func product(from dict: [String: Any]) -> GoatProductSummary? {
        let slug = string(dict, keys: ["slug", "product_slug", "productSlug", "url_slug"]) ?? ""
        let sku = string(dict, keys: ["sku", "style_id", "styleId", "style_code"]) ?? ""
        let name = string(dict, keys: ["name", "title", "product_name", "productName", "shoe_name"]) ?? ""
        let brand = string(dict, keys: ["brand", "brand_name", "brandName"]) ?? ""
        guard !slug.isEmpty || !sku.isEmpty || !name.isEmpty else { return nil }

        let id = slug.isEmpty ? (sku.isEmpty ? name : sku) : slug
        let image = string(dict, keys: ["image_url", "imageUrl", "picture_url", "main_picture_url", "thumbnail_url"])
        let size = string(dict, keys: ["size", "size_us", "sizeUs", "size_label"])
        let price = extractUSD(from: dict)

        return GoatProductSummary(
            id: id,
            slug: slug,
            sku: sku,
            name: name.isEmpty ? sku : name,
            brand: brand,
            imageURL: image,
            sizeLabel: size,
            listPriceUSD: price
        )
    }

    private static func listing(from dict: [String: Any]) -> GoatSellerListing? {
        let id = string(dict, keys: ["product_id", "id", "listing_id", "order_number"]) ?? UUID().uuidString
        let name = string(dict, keys: ["name", "title", "product_name"]) ?? "Listing"
        let sku = string(dict, keys: ["sku", "style_id"]) ?? ""
        let slug = string(dict, keys: ["slug", "product_slug"]) ?? ""
        let size = string(dict, keys: ["size", "size_us", "size_label"])
        let price = extractUSD(from: dict)
        let status = string(dict, keys: ["status", "state", "condition"])
        return GoatSellerListing(id: id, name: name, sku: sku, slug: slug, sizeLabel: size, priceUSD: price, status: status)
    }

    static func extractUSD(from root: [String: Any], preferKeys: [String] = []) -> Int? {
        let keys = preferKeys + [
            "lowest_price", "lowestPrice", "price", "price_cents", "amount",
            "lowest_price_cents", "offer_amount", "value", "usd", "retail_price",
        ]
        if let v = int(from: root, keys: keys) {
            return normalizeCents(v, dict: root)
        }
        if let data = root["data"] as? [String: Any], let v = int(from: data, keys: keys) {
            return normalizeCents(v, dict: data)
        }
        for (_, val) in root {
            if let nested = val as? [String: Any], let v = int(from: nested, keys: keys) {
                return normalizeCents(v, dict: nested)
            }
        }
        return nil
    }

    private static func normalizeCents(_ value: Int, dict: [String: Any]) -> Int {
        let hasCentsKey = dict.keys.contains { $0.lowercased().contains("cent") }
        if hasCentsKey && value > 999 { return max(1, value / 100) }
        if value > 50_000 { return max(1, value / 100) }
        return value
    }

    private static func string(_ dict: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = dict[k] as? String, !s.isEmpty { return s }
            if let n = dict[k] as? Int { return String(n) }
            if let d = dict[k] as? Double { return String(Int(d)) }
        }
        return nil
    }

    private static func int(from dict: [String: Any], keys: [String]) -> Int? {
        for k in keys {
            if let n = dict[k] as? Int { return n }
            if let d = dict[k] as? Double { return Int(d.rounded()) }
            if let s = dict[k] as? String, let n = Int(s.filter { $0.isNumber || $0 == "-" }) { return n }
        }
        return nil
    }
}

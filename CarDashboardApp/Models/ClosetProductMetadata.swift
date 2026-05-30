import Foundation

// MARK: - Size display (🇺🇸U.S + size)

enum StockSizeDisplay {
    private static let flag = "🇺🇸"
    private static let usTag = "U.S"

    /// Display label for cards and summaries: `🇺🇸U.S 11`
    static func cardLabel(from raw: String?) -> String? {
        guard let core = coreSize(from: raw) else { return nil }
        return "\(flag)\(usTag) \(core)"
    }

    /// Stores only the size value (e.g. `11`, `M`, `10.5`) without the prefix.
    static func normalizedStorage(from raw: String?) -> String? {
        coreSize(from: raw)
    }

    private static func coreSize(from raw: String?) -> String? {
        guard var t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return nil
        }
        t = t.replacingOccurrences(of: flag, with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        let stripPrefixes = [
            "U.S.", "U.S", "US.", "US",
            "EU", "UK", "MX",
        ]
        var changed = true
        while changed {
            changed = false
            for prefix in stripPrefixes {
                let upper = t.uppercased()
                let p = prefix.uppercased()
                if upper.hasPrefix(p) {
                    t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                    break
                }
            }
        }

        return t.isEmpty ? nil : t
    }

    /// Numeric sort key for size filters (lower = smaller).
    static func sortValue(from raw: String?) -> Double {
        guard let core = coreSize(from: raw) else { return 9999 }
        let normalized = core.replacingOccurrences(of: ",", with: ".")
        if let n = Double(normalized) { return n }
        switch core.uppercased() {
        case "XXS": return 0
        case "XS": return 1
        case "S": return 2
        case "M": return 3
        case "L": return 4
        case "XL": return 5
        case "XXL": return 6
        case "XXXL": return 7
        default: return 500 + Double(core.unicodeScalars.first?.value ?? 0)
        }
    }
}

/// Metadatos enriquecidos por Gemini al detectar / revisar una prenda.
struct GarmentEnrichment: Codable, Equatable {
    var brand: String
    var sku: String
    var sizeText: String
    var colorLabel: String
    var productDescription: String
    var priceText: String
    /// Plataformas sugeridas (StockX, Wallapop, …).
    var listingPlatforms: [String]

    static let empty = GarmentEnrichment(
        brand: "",
        sku: "",
        sizeText: "",
        colorLabel: "",
        productDescription: "",
        priceText: "",
        listingPlatforms: []
    )
}

// MARK: - SKU / style code

enum SneakerSKU {
    /// Common sneaker style codes: DD1391-101, FW2499, DV1749-601, etc.
    static func extract(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            #"\b[A-Z0-9]{2,6}-[A-Z0-9]{2,4}\b"#,
            #"\b[A-Z]{2}\d{4}-\d{3}\b"#,
            #"\b[A-Z]{2}\d{4}\b"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range, in: trimmed) {
                return String(trimmed[range]).uppercased()
            }
        }
        return nil
    }

    static func splitNameAndSKU(from text: String) -> (name: String, sku: String?) {
        guard let sku = extract(from: text) else { return (text, nil) }
        var name = trimmedName(
            text.replacingOccurrences(of: sku, with: "", options: .caseInsensitive)
        )
        name = trimmedName(name.replacingOccurrences(of: sku.replacingOccurrences(of: "-", with: " "), with: ""))
        if name.isEmpty { return (text, sku) }
        return (name, sku)
    }

    private static func trimmedName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-·|/"))
    }
}

extension ClosetItem {
    /// Stored SKU or one parsed from the legacy combined name field.
    var resolvedSKU: String? {
        let stored = skuText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty { return stored.uppercased() }
        return SneakerSKU.extract(from: name)
    }

    var cardSKULabel: String? {
        resolvedSKU
    }

    /// Product title without embedded style code when SKU is known.
    var catalogDisplayName: String {
        guard let sku = resolvedSKU else { return name }
        let cleaned = SneakerSKU.splitNameAndSKU(from: name).name
        return cleaned.isEmpty ? name : cleaned
    }

    /// GOAT / OpenAI lookup: SKU first, then brand + name.
    var marketLookupQuery: String {
        if let sku = resolvedSKU { return sku }
        return [brand ?? "", catalogDisplayName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Ordered queries for market lookup — Style/SKU first.
    var marketLookupQueries: [String] {
        var seen = Set<String>()
        var out: [String] = []

        func add(_ raw: String) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            let key = t.lowercased()
            guard seen.insert(key).inserted else { return }
            out.append(t)
        }

        if let sku = resolvedSKU {
            add(sku)
            let brandLine = brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !brandLine.isEmpty { add("\(brandLine) \(sku)") }
        }

        let fallback = marketLookupQuery
        if !fallback.isEmpty { add(fallback) }

        return out
    }

    var hasStyleForMarketLookup: Bool {
        !(resolvedSKU ?? "").isEmpty || !marketLookupQuery.isEmpty
    }

    /// True when cached market price is missing or older than 24 hours.
    var marketPriceNeedsRefresh: Bool {
        guard hasStyleForMarketLookup else { return false }
        guard marketPrice != nil else { return true }
        guard let fetched = marketPriceFetchedAt else { return true }
        return Date().timeIntervalSince(fetched) >= 86_400
    }

    func applyMarketPrice(_ estimate: PieceMarketPrice, fetchedAt: Date = .now) {
        marketPrice = estimate
        marketPriceFetchedAt = fetchedAt
    }
}

enum StockRemovalReason: String, CaseIterable {
    case sold
    case discontinued

    var dialogLabel: String {
        switch self {
        case .sold: return "I sold it"
        case .discontinued: return "Discontinuing — remove from stock"
        }
    }
}

extension ClosetItem {
    /// Only items explicitly marked sold (with a date) leave active stock.
    var isExplicitlySold: Bool {
        isSold && soldAt != nil && !isArchivedRemoved
    }

    var isArchivedRemoved: Bool {
        deletedAt != nil
    }

    /// Active inventory in Tu stock (not sold, not archived).
    var isActiveInStock: Bool {
        !isExplicitlySold && !isArchivedRemoved
    }

    var removalReason: StockRemovalReason? {
        guard let raw = deletionReasonRaw else { return nil }
        return StockRemovalReason(rawValue: raw)
    }

    var marketPrice: PieceMarketPrice? {
        get {
            guard let s = marketPriceJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty,
                  let data = s.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(PieceMarketPrice.self, from: data)
            else { return nil }
            return decoded
        }
        set {
            if let v = newValue,
               let data = try? JSONEncoder().encode(v),
               let str = String(data: data, encoding: .utf8) {
                marketPriceJSON = str
            } else {
                marketPriceJSON = nil
            }
        }
    }

    var listingPlatforms: [String] {
        get {
            (listingPlatformsRaw ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set {
            listingPlatformsRaw = newValue.isEmpty ? nil : newValue.joined(separator: ",")
        }
    }

    /// Card shows listing price when set; otherwise market avg, then cost.
    var cardPriceLabel: String? {
        let asking = ClosetItem.parsePriceUSD(from: priceText)
        if asking > 0 {
            return PieceMarketPrice.formatUSD(Int(asking.rounded()))
        }
        if let mp = marketPrice, mp.avg > 0 {
            return PieceMarketPrice.formatUSD(mp.avg)
        }
        let cost = purchaseValueUSD
        guard cost > 0 else { return nil }
        return PieceMarketPrice.formatUSD(Int(cost.rounded()))
    }

    var purchaseValueUSD: Double {
        ClosetItem.parsePriceUSD(from: purchasePriceText)
    }

    /// Listing price if set, otherwise market average.
    var effectiveSellValueUSD: Double {
        let asking = ClosetItem.parsePriceUSD(from: priceText)
        if asking > 0 { return asking }
        if let mp = marketPrice, mp.avg > 0 { return Double(mp.avg) }
        return 0
    }

    /// Projected gain: sell value minus what you paid.
    var projectedProfitUSD: Double {
        let cost = purchaseValueUSD
        let sell = effectiveSellValueUSD
        guard cost > 0, sell > 0 else { return 0 }
        return sell - cost
    }

    var hasPricingForProfit: Bool {
        purchaseValueUSD > 0 && effectiveSellValueUSD > 0
    }

    var projectedProfitPercent: Double? {
        guard hasPricingForProfit else { return nil }
        let cost = purchaseValueUSD
        guard cost > 0 else { return nil }
        return (projectedProfitUSD / cost) * 100
    }

    var isProjectedLoss: Bool {
        hasPricingForProfit && projectedProfitUSD < 0
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

    /// KPI stock value (USD): market avg → asking → purchase cost.
    var stockValueUSD: Double {
        if let mp = marketPrice, mp.avg > 0 { return Double(mp.avg) }
        let asking = ClosetItem.parsePriceUSD(from: priceText)
        if asking > 0 { return asking }
        return purchaseValueUSD
    }

    var cardSizeLabel: String? {
        StockSizeDisplay.cardLabel(from: sizeText)
    }

    var soldOnDate: Date { soldAt ?? createdAt }

    var soldDaysAgo: Int {
        Calendar.current.dateComponents([.day], from: soldOnDate, to: Date()).day ?? 0
    }

    func soldDateLabel() -> String {
        let daysAgo = soldDaysAgo
        switch daysAgo {
        case 0:
            return L10n.tr("sold.today")
        case 1:
            return L10n.tr("sold.yesterday")
        case 2...6:
            return String(format: L10n.tr("sold.daysAgo"), String(daysAgo))
        case 7...13:
            return L10n.tr("sold.oneWeekAgo")
        case 14...29:
            return String(format: L10n.tr("sold.weeksAgo"), String(daysAgo / 7))
        default:
            return String(format: L10n.tr("sold.monthsAgo"), String(max(1, daysAgo / 30)))
        }
    }

    var removedOnDate: Date { deletedAt ?? createdAt }

    var removedDaysAgo: Int {
        Calendar.current.dateComponents([.day], from: removedOnDate, to: Date()).day ?? 0
    }

    func removedDateLabel() -> String {
        let daysAgo = removedDaysAgo
        switch daysAgo {
        case 0:
            return L10n.tr("sold.today")
        case 1:
            return L10n.tr("sold.yesterday")
        case 2...6:
            return String(format: L10n.tr("sold.daysAgo"), String(daysAgo))
        case 7...13:
            return L10n.tr("sold.oneWeekAgo")
        case 14...29:
            return String(format: L10n.tr("sold.weeksAgo"), String(daysAgo / 7))
        default:
            return String(format: L10n.tr("sold.monthsAgo"), String(max(1, daysAgo / 30)))
        }
    }
}

extension PieceMarketPrice {
    static func formatUSD(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: amount)) ?? "\(amount)")
    }

    static func formatUSD(_ amount: Double) -> String {
        formatUSD(Int(amount.rounded()))
    }
}

extension ClosetItem {
    /// Parses user-entered or stored price text (`$1,234`, `1234`, etc.).
    static func parsePriceUSD(from text: String?) -> Double {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return 0 }
        let cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "USD", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) ?? 0
    }

    /// Canonical display + storage format: `$1,234`.
    static func normalizedPriceText(from text: String?) -> String? {
        let value = parsePriceUSD(from: text)
        guard value > 0 else { return nil }
        return PieceMarketPrice.formatUSD(value)
    }

    static func displayPriceDraft(from text: String?) -> String {
        normalizedPriceText(from: text) ?? (text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}

extension ClosetItem {
    /// Every on-disk image for this item, deduped in a stable browse order.
    var allSelectableImagePaths: [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        func append(_ raw: String?) {
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return
            }
            guard !seen.contains(trimmed) else { return }
            guard ImageStore.exists(trimmed) else { return }
            seen.insert(trimmed)
            ordered.append(trimmed)
        }

        append(imageFilename)
        append(originalCropFilename)
        multiAngleFilenames.forEach { append($0) }
        spin360Filenames.forEach { append($0) }
        lookbookAllFilenamesInOrder.forEach { append($0) }
        append(galleryCoverRelativePath)

        if let cover = galleryCoverRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cover.isEmpty,
           let idx = ordered.firstIndex(of: cover),
           idx > 0 {
            ordered.remove(at: idx)
            ordered.insert(cover, at: 0)
        }

        return ordered
    }
}

extension ImageStore {
    /// Portada de zapatos: lateral izquierdo cuando exista en el set 360°.
    static func shoeLeftLateralPath(for item: ClosetItem) -> String? {
        guard item.category == .shoes else { return nil }
        let paths = item.multiAngleFilenames
        let idx = ShoeAngle.left.rawValue
        guard paths.indices.contains(idx) else { return nil }
        let path = paths[idx]
        return load(path) != nil ? path : nil
    }

    static func preferredCatalogCoverPath(for item: ClosetItem) -> String {
        let manual = item.galleryCoverRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !manual.isEmpty, load(manual) != nil { return manual }
        if let left = shoeLeftLateralPath(for: item) { return left }
        return item.imageFilename
    }
}

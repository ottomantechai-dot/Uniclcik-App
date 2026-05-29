import Foundation
import SwiftData
import UIKit

/// Normalizes legacy SwiftData rows after schema changes (e.g. `isSold` migration).
enum ClosetInventoryRepair {
    @MainActor
    static func normalizeSoldFlags(in context: ModelContext) {
        let descriptor = FetchDescriptor<ClosetItem>()
        guard let items = try? context.fetch(descriptor) else { return }

        var changed = false
        for item in items {
            if item.isSold, item.soldAt == nil {
                item.isSold = false
                changed = true
            }
        }

        if changed {
            try? context.save()
        }
    }

    @MainActor
    static func backfillSKUFromNames(in context: ModelContext) {
        let descriptor = FetchDescriptor<ClosetItem>()
        guard let items = try? context.fetch(descriptor) else { return }

        var changed = false
        for item in items {
            let stored = item.skuText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stored.isEmpty { continue }

            let split = SneakerSKU.splitNameAndSKU(from: item.name)
            guard let sku = split.sku else { continue }

            item.skuText = sku
            if split.name != item.name, !split.name.isEmpty {
                item.name = split.name
            }
            changed = true
        }

        if changed {
            try? context.save()
        }
    }

    /// Moves every item in Sold back to active Your stock.
    @MainActor
    static func restoreAllSoldToStock(in context: ModelContext) {
        var descriptor = FetchDescriptor<ClosetItem>(
            predicate: #Predicate { $0.isSold == true }
        )
        guard let sold = try? context.fetch(descriptor), !sold.isEmpty else { return }

        for item in sold {
            item.isSold = false
            item.soldAt = nil
        }
        try? context.save()
    }

    /// Sets listing price to the same stock value used on Home (market avg, else asking).
    @MainActor
    static func alignAskingPricesToStockValue(in context: ModelContext) {
        let descriptor = FetchDescriptor<ClosetItem>()
        guard let items = try? context.fetch(descriptor) else { return }

        var changed = false
        for item in items {
            let stock = item.stockValueUSD
            guard stock > 0 else { continue }
            let formatted = PieceMarketPrice.formatUSD(Int(stock.rounded()))
            let current = item.priceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if current != formatted {
                item.priceText = formatted
                changed = true
            }
        }

        if changed {
            try? context.save()
        }
    }

    /// One-time launch hygiene only — does not overwrite prices or restore sold items.
    @MainActor
    static func syncInventoryOnLaunch(in context: ModelContext) {
        // Intentionally empty: restoreAllSoldToStock / alignAskingPricesToStockValue
        // were resetting user edits every time the closet tab loaded.
    }

    @MainActor
    static func permanentlyDeleteClosetItem(_ item: ClosetItem, in context: ModelContext) {
        let closetId = item.id
        purgeClosetItemFiles(item)
        CatalogClosetBridge.unlink(closetId: closetId)
        context.delete(item)
        try? context.save()
        NotificationCenter.default.post(name: .closetInventoryDidChange, object: closetId)
        NotificationCenter.default.post(name: .upsoledCatalogDidChange, object: nil)
    }

    @MainActor
    static func restoreArchivedItemToStock(_ item: ClosetItem, in context: ModelContext) {
        item.deletedAt = nil
        item.deletionReasonRaw = nil
        item.isSold = false
        item.soldAt = nil
        try? context.save()
    }

    static func purgeClosetItemFiles(_ item: ClosetItem) {
        ImageStore.deleteIfExists(item.imageFilename)
        if let path = item.originalCropFilename { ImageStore.deleteIfExists(path) }
        if let path = item.sourceOutfitFilename { ImageStore.deleteIfExists(path) }
        for path in item.multiAngleFilenames { ImageStore.deleteIfExists(path) }
        for path in item.lookbookStudio { ImageStore.deleteIfExists(path) }
        for path in item.lookbookLifestyle { ImageStore.deleteIfExists(path) }
        for path in item.spin360Filenames { ImageStore.deleteIfExists(path) }
    }
}

// MARK: - Catalog ↔ local closet bridge

enum CatalogClosetBridge {
    private static let linksKey = "Upsoled.catalogClosetLinks.v1"

    static func catalogProductId(forClosetItem closetId: UUID) -> UUID? {
        let map = loadLinks()
        return map.first(where: { $0.value == closetId })?.key
    }

    static func closetItemId(forCatalogProduct catalogId: UUID) -> UUID? {
        loadLinks()[catalogId]
    }

    @MainActor
    static func ensureClosetItem(for product: UpsoledProduct, in context: ModelContext) async -> ClosetItem {
        let merged = product.applyingStoredOverrides()
        if let linkedId = closetItemId(forCatalogProduct: merged.id),
           let existing = fetchClosetItem(id: linkedId, in: context) {
            applyCatalogFields(merged, to: existing, preserveLocalEdits: true)
            try? context.save()
            return existing
        }

        let imagePath = await downloadCatalogImage(from: merged.primaryImageURL)
            ?? (try? saveWhitePlaceholder())
            ?? "catalog_import/\(UUID().uuidString).jpg"

        let item = ClosetItem(
            name: merged.name,
            brand: merged.brand,
            skuText: merged.sku,
            purchasePriceText: merged.purchaseCostUSD > 0
                ? PieceMarketPrice.formatUSD(Int(merged.purchaseCostUSD.rounded())) : nil,
            priceText: merged.price > 0
                ? PieceMarketPrice.formatUSD(Int(merged.price.rounded())) : nil,
            sizeText: StockSizeDisplay.normalizedStorage(from: merged.sizes.first),
            productDescription: merged.description,
            category: clothingCategory(from: merged.category),
            imageFilename: imagePath,
            isDraft: false
        )
        context.insert(item)
        link(catalogId: merged.id, closetId: item.id)
        try? context.save()
        return item
    }

    @MainActor
    static func syncClosetItemEditsToCatalog(_ item: ClosetItem) {
        guard let catalogId = catalogProductId(forClosetItem: item.id) else { return }
        let draft = ProductDraft(
            name: item.name,
            brand: item.brand ?? "",
            sku: item.skuText ?? "",
            description: item.productDescription ?? "",
            price: ClosetItem.parsePriceUSD(from: item.priceText),
            purchasePrice: ClosetItem.parsePriceUSD(from: item.purchasePriceText),
            category: catalogCategoryString(from: item.category),
            condition: "new",
            sizes: item.sizeText ?? "",
            quantity: 1,
            imageURL: ""
        )
        CatalogProductOverridesStore.set(from: draft, for: catalogId)
        NotificationCenter.default.post(name: .closetInventoryDidChange, object: item.id)
        NotificationCenter.default.post(name: .upsoledCatalogDidChange, object: nil)
    }

    private static func loadLinks() -> [UUID: UUID] {
        guard let raw = UserDefaults.standard.dictionary(forKey: linksKey) as? [String: String] else {
            return [:]
        }
        var map: [UUID: UUID] = [:]
        for (k, v) in raw {
            guard let cid = UUID(uuidString: k), let lid = UUID(uuidString: v) else { continue }
            map[cid] = lid
        }
        return map
    }

    private static func link(catalogId: UUID, closetId: UUID) {
        var map = loadLinks()
        map[catalogId] = closetId
        persistLinks(map)
    }

    static func unlink(catalogId: UUID) {
        var map = loadLinks()
        map.removeValue(forKey: catalogId)
        persistLinks(map)
    }

    static func unlink(closetId: UUID) {
        var map = loadLinks()
        map = map.filter { $0.value != closetId }
        persistLinks(map)
    }

    /// Deletes the linked Supabase row and clears local overrides + link map entry.
    @MainActor
    static func deleteLinkedCatalogProduct(forClosetItem closetId: UUID) async {
        guard let catalogId = catalogProductId(forClosetItem: closetId) else { return }
        CatalogProductOverridesStore.remove(productID: catalogId)
        unlink(catalogId: catalogId)
        try? await UpsoledProductsService.delete(id: catalogId)
    }

    /// Deletes a catalog row and any closet link (does not delete the closet row itself).
    @MainActor
    static func deleteCatalogProduct(_ catalogId: UUID) async {
        CatalogProductOverridesStore.remove(productID: catalogId)
        unlink(catalogId: catalogId)
        try? await UpsoledProductsService.delete(id: catalogId)
    }

    private static func persistLinks(_ map: [UUID: UUID]) {
        let raw = Dictionary(uniqueKeysWithValues: map.map { ($0.key.uuidString, $0.value.uuidString) })
        UserDefaults.standard.set(raw, forKey: linksKey)
    }

    @MainActor
    private static func fetchClosetItem(id: UUID, in context: ModelContext) -> ClosetItem? {
        var descriptor = FetchDescriptor<ClosetItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func applyCatalogFields(
        _ product: UpsoledProduct,
        to item: ClosetItem,
        preserveLocalEdits: Bool = false
    ) {
        item.name = product.name
        item.brand = product.brand
        if !preserveLocalEdits || (item.skuText ?? "").isEmpty {
            item.skuText = product.sku
        }
        if product.purchaseCostUSD > 0,
           !preserveLocalEdits || ClosetItem.parsePriceUSD(from: item.purchasePriceText) <= 0 {
            item.purchasePriceText = PieceMarketPrice.formatUSD(Int(product.purchaseCostUSD.rounded()))
        }
        if product.price > 0,
           !preserveLocalEdits || ClosetItem.parsePriceUSD(from: item.priceText) <= 0 {
            item.priceText = PieceMarketPrice.formatUSD(Int(product.price.rounded()))
        }
        if let size = StockSizeDisplay.normalizedStorage(from: product.sizes.first),
           !preserveLocalEdits || (item.sizeText ?? "").isEmpty {
            item.sizeText = size
        }
        if !preserveLocalEdits || (item.productDescription ?? "").isEmpty {
            item.productDescription = product.description
        }
        if !preserveLocalEdits {
            item.categoryRaw = clothingCategory(from: product.category).rawValue
        }
    }

    static func catalogCategoryString(from category: ClothingCategory) -> String {
        switch category {
        case .shoes: return "shoes"
        case .bags: return "accessories"
        case .accessories: return "accessories"
        case .tops, .dressesJumpsuits, .pantsSkirts, .coats, .underwear: return "clothing"
        }
    }

    private static func clothingCategory(from catalogCategory: String?) -> ClothingCategory {
        let key = (catalogCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "shoes": return .shoes
        case "clothing", "tops": return .tops
        case "bags": return .bags
        case "accessories": return .accessories
        case "vintage", "new-drops", "new_drops": return .accessories
        default:
            if let cat = ClothingCategory(rawValue: key) { return cat }
            return .shoes
        }
    }

    private static func downloadCatalogImage(from url: URL?) async -> String? {
        guard let url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let ui = UIImage(data: data) else { return nil }
            let normalized = ClosetPhotoExports.normalizedClosetProductImage(ui)
            guard let jpeg = normalized.jpegData(compressionQuality: 0.92) else { return nil }
            let name = "\(UUID().uuidString).jpg"
            return try ImageStore.save(jpeg, inFolder: "catalog_import", filename: name)
        } catch {
            return nil
        }
    }

    private static func saveWhitePlaceholder() throws -> String {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        }
        guard let jpeg = img.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "CatalogClosetBridge", code: 1)
        }
        return try ImageStore.save(jpeg, inFolder: "catalog_import", filename: "\(UUID().uuidString).jpg")
    }
}

import Foundation
import SwiftData

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
}

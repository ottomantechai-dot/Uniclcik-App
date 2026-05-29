import Foundation
import SwiftUI

/// ViewModel para la pestaña de productos: lista, refresca y crea contra
/// `public.upsoled_products` en Supabase.
@MainActor
final class UpsoledProductsViewModel: ObservableObject {
    @Published var products: [UpsoledProduct] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    /// Filtros UI
    @Published var selectedCategory: String? = nil
    @Published var searchText: String = ""
    @Published var onlyInStock: Bool = false

    /// `true` mientras se hace un INSERT en background. La UI lo usa para
    /// deshabilitar el botón "Guardar".
    @Published var isCreating: Bool = false

    /// Categorías que el filtro UI permite (mismas que la web).
    let availableCategories: [(label: String, value: String)] = [
        ("Todos", ""),
        ("Shoes", "shoes"),
        ("Clothing", "clothing"),
        ("Accessories", "accessories"),
        ("Vintage", "vintage"),
        ("New Drops", "new-drops"),
    ]

    /// Productos filtrados por texto (la búsqueda se hace cliente; el filtro de
    /// categoría se hace en el server vía `selectedCategory`).
    var filtered: [UpsoledProduct] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return products }
        return products.filter { p in
            p.name.lowercased().contains(needle)
                || (p.brand ?? "").lowercased().contains(needle)
                || (p.sku ?? "").lowercased().contains(needle)
        }
    }

    /// Si no es `nil`, filtra por `app_listing_section` (`user_stock`, `marketplace`, …).
    var listingSectionFilter: String?
    /// Límite de filas al listar (Tu stock usa el catálogo completo ~732 ítems).
    var fetchLimit: Int = 250

    /// Refresca la lista desde Supabase.
    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await UpsoledProductsService.list(
                category: selectedCategory,
                onlyInStock: onlyInStock,
                listingSection: listingSectionFilter,
                limit: fetchLimit
            )
            products = rows.map { $0.applyingStoredOverrides() }
            errorMessage = nil
        } catch {
            errorMessage = "No se pudieron cargar los productos: \(error.localizedDescription)"
        }
    }

    /// Crea un producto nuevo a partir de un draft de UI.
    /// Devuelve `true` si OK.
    func create(_ draft: ProductDraft, ownerUserID: UUID?) async -> Bool {
        isCreating = true
        defer { isCreating = false }
        do {
            let slug = try await UpsoledProductsService.ensureUniqueSlug(base: draft.name)
            let saved = try await UpsoledProductsService.create(
                draft.insertPayload(slug: slug, ownerUserID: ownerUserID)
            )
            products.insert(saved, at: 0)
            errorMessage = nil
            NotificationCenter.default.post(name: .upsoledCatalogDidChange, object: nil)
            return true
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
            return false
        }
    }

    /// Guarda en el dispositivo y actualiza la lista al instante.
    func persistEditLocally(_ product: UpsoledProduct, draft: ProductDraft) {
        CatalogProductOverridesStore.set(from: draft, for: product.id)
        let merged = product.applyingStoredOverrides()
        if let idx = products.firstIndex(where: { $0.id == product.id }) {
            products[idx] = merged
        }
        NotificationCenter.default.post(name: .upsoledCatalogDidChange, object: nil)
    }

    /// Actualiza un producto existente (mismos campos que al crear).
    func update(_ product: UpsoledProduct, draft: ProductDraft) async -> Bool {
        persistEditLocally(product, draft: draft)

        isCreating = true
        defer { isCreating = false }
        do {
            let saved = try await UpsoledProductsService.update(
                id: product.id,
                draft.insertPayload(slug: product.slug, ownerUserID: product.userId)
            )
            if let idx = products.firstIndex(where: { $0.id == product.id }) {
                products[idx] = saved.applyingStoredOverrides()
            }
            errorMessage = nil
            return true
        } catch {
            // Local overrides already saved — imported catalog rows often lack owner RLS.
            errorMessage = nil
            return true
        }
    }

    /// Auto-save while editing (local + best-effort remote, no blocking UI).
    func autosaveEdit(_ product: UpsoledProduct, draft: ProductDraft) async {
        guard draft.isValid else { return }
        persistEditLocally(product, draft: draft)
        _ = try? await UpsoledProductsService.update(
            id: product.id,
            draft.insertPayload(slug: product.slug, ownerUserID: product.userId)
        )
    }

    /// Removes a catalog row from Supabase and local list/overrides.
    func deleteProduct(id: UUID) async {
        await CatalogClosetBridge.deleteCatalogProduct(id)
        products.removeAll { $0.id == id }
        NotificationCenter.default.post(name: .upsoledCatalogDidChange, object: nil)
    }
}

/// Draft simple para el formulario de creación/edición.
struct ProductDraft: Equatable {
    var name: String = ""
    var brand: String = ""
    var sku: String = ""
    var description: String = ""
    var price: Double = 0
    var purchasePrice: Double = 0
    var category: String = "shoes"
    var condition: String = "new"
    /// CSV separadas por coma (ej. "8, 9, 10, 11").
    var sizes: String = ""
    var quantity: Int = 1
    var imageURL: String = ""

    var isValid: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanName.isEmpty && price > 0
    }

    static func from(_ product: UpsoledProduct) -> ProductDraft {
        ProductDraft(
            name: product.name,
            brand: product.brand ?? "",
            sku: product.sku ?? "",
            description: product.description ?? "",
            price: product.price,
            purchasePrice: product.purchaseCostUSD,
            category: product.category ?? "shoes",
            condition: product.condition,
            sizes: product.sizes.joined(separator: ", "),
            quantity: max(1, product.quantity ?? 1),
            imageURL: product.image ?? product.mainImageUrl ?? ""
        )
    }

    fileprivate func insertPayload(slug: String, ownerUserID: UUID?) -> UpsoledProductInsert {
        let sizeList = sizes
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let images = [imageURL]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return UpsoledProductInsert(
            slug: slug,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand.trimmedNilIfEmpty,
            sku: sku.trimmedNilIfEmpty,
            description: description.trimmedNilIfEmpty,
            price: price,
            compareAtPrice: purchasePrice > 0 ? purchasePrice : nil,
            currency: "USD",
            image: images.first,
            images: images,
            mainImageUrl: images.first,
            category: category,
            tags: [],
            condition: condition,
            collection: nil,
            sizes: sizeList,
            inStock: true,
            quantity: max(1, quantity),
            userId: ownerUserID,
            organizationId: nil
        )
    }
}

private extension String {
    /// Devuelve nil si tras trim queda vacío. Cómodo para campos opcionales del insert.
    var trimmedNilIfEmpty: String? {
        let t = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Local catalog overrides (device persistence)

struct CatalogProductOverride: Codable, Equatable {
    var name: String?
    var brand: String?
    var sku: String?
    var description: String?
    var price: Double?
    var compareAtPrice: Double?
    var category: String?
    var condition: String?
    var sizes: [String]?
    var quantity: Int?
    var imageURL: String?
    var updatedAt: Date

    static func from(_ draft: ProductDraft) -> CatalogProductOverride {
        let sizeList = draft.sizes
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let image = draft.imageURL.trimmingCharacters(in: .whitespacesAndNewlines)

        return CatalogProductOverride(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            brand: draft.brand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            sku: draft.sku.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            price: draft.price > 0 ? draft.price : nil,
            compareAtPrice: draft.purchasePrice > 0 ? draft.purchasePrice : nil,
            category: draft.category.nilIfEmpty,
            condition: draft.condition.nilIfEmpty,
            sizes: sizeList.isEmpty ? nil : sizeList,
            quantity: max(1, draft.quantity),
            imageURL: image.isEmpty ? nil : image,
            updatedAt: Date()
        )
    }
}

enum CatalogProductOverridesStore {
    private static let storageKey = "Upsoled.catalogProductOverrides.v1"

    static func all() -> [UUID: CatalogProductOverride] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([UUID: CatalogProductOverride].self, from: data)
        else { return [:] }
        return decoded
    }

    static func override(for productID: UUID) -> CatalogProductOverride? {
        all()[productID]
    }

    static func set(_ override: CatalogProductOverride, for productID: UUID) {
        var map = all()
        map[productID] = override
        persist(map)
    }

    static func set(from draft: ProductDraft, for productID: UUID) {
        set(CatalogProductOverride.from(draft), for: productID)
    }

    static func remove(productID: UUID) {
        var map = all()
        map.removeValue(forKey: productID)
        persist(map)
    }

    private static func persist(_ map: [UUID: CatalogProductOverride]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

extension UpsoledProduct {
    /// Applies on-device edits for this catalog row.
    func applyingStoredOverrides() -> UpsoledProduct {
        guard let o = CatalogProductOverridesStore.override(for: id) else { return self }
        var p = self
        if let v = o.name { p.name = v }
        if let v = o.brand { p.brand = v }
        if let v = o.sku { p.sku = v }
        if let v = o.description { p.description = v }
        if let v = o.price { p.price = v }
        if let v = o.compareAtPrice { p.compareAtPrice = v }
        if let v = o.category { p.category = v }
        if let v = o.condition { p.condition = v }
        if let v = o.sizes { p.sizes = v }
        if let v = o.quantity { p.quantity = v }
        if let v = o.imageURL {
            p.image = v
            p.mainImageUrl = v
            if p.images.isEmpty { p.images = [v] }
        }
        return p
    }
}

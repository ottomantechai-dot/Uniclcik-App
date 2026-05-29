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

    /// Refresca la lista desde Supabase.
    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await UpsoledProductsService.list(
                category: selectedCategory,
                onlyInStock: onlyInStock,
                limit: 250
            )
            products = rows
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
            let sizes = draft.sizes
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let images = [draft.imageURL]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let payload = UpsoledProductInsert(
                slug: slug,
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                brand: draft.brand.trimmedNilIfEmpty,
                sku: draft.sku.trimmedNilIfEmpty,
                description: draft.description.trimmedNilIfEmpty,
                price: draft.price,
                compareAtPrice: nil,
                currency: "USD",
                image: images.first,
                images: images,
                mainImageUrl: images.first,
                category: draft.category,
                tags: [],
                condition: draft.condition,
                collection: nil,
                sizes: sizes,
                inStock: true,
                quantity: nil,
                userId: ownerUserID,
                organizationId: nil
            )

            let saved = try await UpsoledProductsService.create(payload)
            // Insertamos al principio en la lista local sin recargar entera
            products.insert(saved, at: 0)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Error al guardar: \(error.localizedDescription)"
            return false
        }
    }
}

/// Draft simple para el formulario de creación.
struct ProductDraft {
    var name: String = ""
    var brand: String = ""
    var sku: String = ""
    var description: String = ""
    var price: Double = 0
    var category: String = "shoes"
    var condition: String = "new"
    /// CSV separadas por coma (ej. "8, 9, 10, 11").
    var sizes: String = ""
    var imageURL: String = ""

    var isValid: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanName.isEmpty && price > 0
    }
}

private extension String {
    /// Devuelve nil si tras trim queda vacío. Cómodo para campos opcionales del insert.
    var trimmedNilIfEmpty: String? {
        let t = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

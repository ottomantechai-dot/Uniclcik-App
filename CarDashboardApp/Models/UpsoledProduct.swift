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
    /// Genera un slug URL-friendly a partir del nombre. Si quedan colisiones,
    /// el caller debe añadir un sufijo (UUID corto) antes de insertar.
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

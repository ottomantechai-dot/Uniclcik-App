import Foundation
import Supabase

/// CRUD sobre la tabla `public.upsoled_products` (compartida con la web Sneak Peek Miami).
/// Misma instancia Supabase que el resto del app — usa `SupabaseClientProvider.shared`.
enum UpsoledProductsService {
    private static let tableName = "upsoled_products"

    /// Lista paginada y filtrable.
    static func list(
        category: String? = nil,
        brand: String? = nil,
        onlyInStock: Bool = false,
        listingSection: String? = nil,
        limit: Int = 100
    ) async throws -> [UpsoledProduct] {
        let client = SupabaseClientProvider.shared
        var query = client.from(tableName)
            .select()

        if let category = category, !category.isEmpty {
            query = query.eq("category", value: category)
        }
        if let brand = brand, !brand.isEmpty {
            query = query.ilike("brand", pattern: brand)
        }
        if onlyInStock {
            query = query.eq("in_stock", value: true)
        }
        if let listingSection = listingSection, !listingSection.isEmpty {
            query = query.eq("app_listing_section", value: listingSection)
        }

        let response: [UpsoledProduct] = try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return response
    }

    /// Devuelve UN producto por slug.
    static func get(slug: String) async throws -> UpsoledProduct? {
        let client = SupabaseClientProvider.shared
        let response: [UpsoledProduct] = try await client
            .from(tableName)
            .select()
            .eq("slug", value: slug)
            .limit(1)
            .execute()
            .value
        return response.first
    }

    /// Sube una foto de producto al bucket `product-media` y devuelve la URL
    /// pública absoluta (lista para guardar en image/main_image_url/images).
    ///
    /// Ruta: `{user_id}/{uuid}.jpg` — la primera carpeta debe ser el dueño para
    /// cumplir la policy de Storage (ver migración product-media).
    static func uploadProductImage(jpegData: Data, ownerUserID: UUID) async throws -> String {
        let client = SupabaseClientProvider.shared
        _ = try await client.auth.session // garantiza sesión válida (RLS authenticated)

        let bucket = SupabaseClientProvider.productMediaBucket
        let path = "\(ownerUserID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"

        _ = try await client.storage
            .from(bucket)
            .upload(
                path,
                data: jpegData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

        return SupabaseClientProvider.publicStorageObjectURL(bucket: bucket, path: path)
    }

    /// Inserta un producto. Requiere usuario autenticado (RLS owner_insert).
    @discardableResult
    static func create(_ payload: UpsoledProductInsert) async throws -> UpsoledProduct {
        let client = SupabaseClientProvider.shared
        let response: UpsoledProduct = try await client
            .from(tableName)
            .insert(payload, returning: .representation)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    /// Actualiza un producto (solo el dueño, vía RLS owner_update).
    @discardableResult
    static func update(id: UUID, _ payload: UpsoledProductInsert) async throws -> UpsoledProduct {
        let client = SupabaseClientProvider.shared
        let response: UpsoledProduct = try await client
            .from(tableName)
            .update(payload, returning: .representation)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    /// Elimina un producto (solo el dueño, vía RLS owner_delete).
    static func delete(id: UUID) async throws {
        let client = SupabaseClientProvider.shared
        _ = try await client
            .from(tableName)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Genera un slug único añadiendo sufijo si ya existe.
    static func ensureUniqueSlug(base name: String) async throws -> String {
        let base = UpsoledProduct.generateSlug(from: name)
        // Si el slug está libre lo usamos. Si no, añadimos sufijo corto.
        if try await get(slug: base) == nil {
            return base
        }
        let suffix = String(UUID().uuidString.prefix(6)).lowercased()
        return "\(base)-\(suffix)"
    }
}

enum ShoeCatalogService {
    private static let projection = "slug,title,brand,style_code,image_url,size_system"

    static func variant(gtin: String) async throws -> ShoeCatalogVariant? {
        let rows: [ShoeCatalogVariant] = try await SupabaseClientProvider.shared
            .from("shoe_catalog_variants")
            .select("us_size,model:shoe_catalog_models(\(projection))")
            .eq("gtin", value: gtin)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    static func model(slug: String) async -> ShoeCatalogModel? {
        let rows: [ShoeCatalogModel]? = try? await SupabaseClientProvider.shared
            .from("shoe_catalog_models")
            .select(projection)
            .eq("slug", value: slug)
            .limit(1)
            .execute()
            .value
        if let model = rows?.first, model.styleCode != nil { return model }
        let reference = ShoeCatalogVariant.lostAndFound.model
        return slug == reference.slug ? reference : rows?.first
    }
}

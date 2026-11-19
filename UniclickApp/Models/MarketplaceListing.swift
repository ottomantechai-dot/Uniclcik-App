import Foundation

// MARK: - Anuncios para vender
// Un anuncio preparado para una plataforma (StockX, eBay, GOAT). La app todavía no tiene cuentas
// de vendedor conectadas: el anuncio queda «listo para publicar» y, en cuanto exista la conexión
// de vendedor de esa plataforma, `ListingPublisher.publish` es el único sitio que hay que completar.

struct MarketplaceListing: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case ready       // preparado; falta la cuenta de vendedor
        case published   // publicado de verdad en la plataforma
    }
    enum Condition: String, Codable, CaseIterable, Identifiable {
        case new = "Nuevo, con caja"
        case newNoBox = "Nuevo, sin caja"
        case used = "Usado"
        var id: String { rawValue }
    }

    var id = UUID()
    var platform: String
    var title: String
    var sku: String
    var size: String
    var priceUSD: Double
    var condition: Condition
    var imageURL: String?
    var status: Status = .ready
    var createdAt = Date()
    /// Dirección del anuncio en la plataforma, cuando se publica de verdad.
    var externalURL: String?

    var netUSD: Double { PlatformFees.net(price: priceUSD, platform: platform) }
}

enum ListingPublisher {
    enum Outcome: Equatable {
        case published
        case needsSellerAccount(String)
    }

    /// Plataformas con cuenta de vendedor conectada. Hoy ninguna: las claves que hay solo leen precios.
    static func sellerAccountConnected(_ platform: String) -> Bool { false }

    /// Publica el anuncio si la plataforma tiene cuenta de vendedor; si no, lo deja preparado.
    @MainActor
    static func publish(_ listing: MarketplaceListing) async -> Outcome {
        var saved = listing
        guard sellerAccountConnected(listing.platform) else {
            saved.status = .ready
            ListingStore.shared.save(saved)
            return .needsSellerAccount("Falta conectar la cuenta de vendedor de \(listing.platform). El anuncio queda guardado y listo para publicar.")
        }
        // Aquí va la llamada real a la plataforma (por la pasarela segura de Supabase) cuando exista.
        saved.status = .published
        ListingStore.shared.save(saved)
        return .published
    }
}

@MainActor
final class ListingStore: ObservableObject {
    static let shared = ListingStore()
    @Published private(set) var listings: [MarketplaceListing] = []

    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("marketplace-listings.json")

    private init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([MarketplaceListing].self, from: data) {
            listings = saved
        }
    }

    func save(_ listing: MarketplaceListing) {
        // Un solo anuncio por producto, talla y plataforma: el nuevo sustituye al anterior.
        listings.removeAll { $0.id == listing.id || ($0.platform == listing.platform && $0.sku == listing.sku && $0.title == listing.title && $0.size == listing.size) }
        listings.insert(listing, at: 0)
        persist()
    }

    func delete(_ listing: MarketplaceListing) {
        listings.removeAll { $0.id == listing.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(listings) { try? data.write(to: url, options: .atomic) }
    }
}

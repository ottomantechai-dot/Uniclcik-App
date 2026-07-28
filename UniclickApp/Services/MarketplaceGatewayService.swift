import Foundation
import Supabase

/// Read-only marketplace transport. Provider credentials live in the
/// `marketplace-gateway` Supabase Edge Function, never in the iOS bundle.
enum MarketplaceGatewayService {
    static let functionName = "marketplace-gateway"

    /// The gateway itself is part of the app backend. Individual provider
    /// availability is returned by `fetchStatus()`.
    static var isAvailable: Bool { true }

    struct Status: Decodable, Equatable {
        let kicksdb: Bool
        let ebay: Bool
        let stockx: Bool
        let goat: Bool
        let flightclub: Bool

        static let unavailable = Status(
            kicksdb: false,
            ebay: false,
            stockx: false,
            goat: false,
            flightclub: false
        )

        func isConnected(_ platform: String) -> Bool {
            switch platform.lowercased() {
            case "stockx": return stockx
            case "goat", "alias": return goat
            case "flight club", "flightclub": return flightclub
            case "ebay": return ebay
            default: return false
            }
        }
    }

    struct DailySaleRow: Decodable {
        let avgAmount: Double?
        let orders: Int?
        let date: String?

        private enum CodingKeys: String, CodingKey {
            case avgAmount = "avg_amount"
            case orders, date
        }
    }

    struct EbaySearchItem: Decodable {
        struct Aspect: Decodable {
            let name: String
            let value: String
        }

        let id: String
        let title: String
        let price: Double
        let currency: String
        let url: String?
        let aspects: [Aspect]
    }

    private struct Request: Encodable {
        let operation: String
        var platform: String?
        var query: String?
        var limit: Int?
        var productKey: String?
        var slug: String?
        var shop: String?
        var productID: String?
        var profile: String?

        private enum CodingKeys: String, CodingKey {
            case operation, platform, query, limit, slug, shop, profile
            case productKey = "product_key"
            case productID = "product_id"
        }
    }

    private struct ResponseEnvelope<T: Decodable>: Decodable {
        let ok: Bool?
        let data: T?
        let error: String?
    }

    private struct ErrorEnvelope: Decodable {
        let error: String?
    }

    enum GatewayError: LocalizedError {
        case missingData
        case backend(String)

        var errorDescription: String? {
            switch self {
            case .missingData:
                return "El gateway de marketplaces devolvió una respuesta incompleta."
            case .backend(let message):
                return message
            }
        }
    }

    static func fetchStatus() async throws -> Status {
        try await invoke(Request(operation: "status"))
    }

    static func kicksSearch(
        platform: KicksDBClient.Platform,
        query: String,
        limit: Int
    ) async throws -> [KicksDBClient.ProductHit] {
        try await invoke(Request(
            operation: "kicks_search",
            platform: platform.rawValue,
            query: query,
            limit: limit
        ))
    }

    static func kicksDetail(
        platform: KicksDBClient.Platform,
        productKey: String
    ) async throws -> KicksDBClient.ProductHit? {
        try await invokeOptional(Request(
            operation: "kicks_detail",
            platform: platform.rawValue,
            productKey: productKey
        ))
    }

    static func kicksUnifiedPrices(
        slug: String,
        shop: String
    ) async throws -> [String: Double] {
        try await invoke(Request(
            operation: "kicks_unified",
            slug: slug,
            shop: shop
        ))
    }

    static func kicksDailySales(
        platform: String,
        productID: String
    ) async throws -> [DailySaleRow] {
        try await invoke(Request(
            operation: "kicks_daily_sales",
            platform: platform,
            productID: productID
        ))
    }

    static func ebaySearch(
        query: String,
        limit: Int,
        profile: String
    ) async throws -> [EbaySearchItem] {
        try await invoke(Request(
            operation: "ebay_search",
            query: query,
            limit: limit,
            profile: profile
        ))
    }

    private static func invoke<T: Decodable>(_ request: Request) async throws -> T {
        let envelope: ResponseEnvelope<T> = try await perform(request)
        if let error = envelope.error, !error.isEmpty {
            throw GatewayError.backend(error)
        }
        guard let data = envelope.data else {
            throw GatewayError.missingData
        }
        return data
    }

    private static func invokeOptional<T: Decodable>(_ request: Request) async throws -> T? {
        let envelope: ResponseEnvelope<T> = try await perform(request)
        if let error = envelope.error, !error.isEmpty {
            throw GatewayError.backend(error)
        }
        return envelope.data
    }

    private static func perform<T: Decodable>(
        _ request: Request
    ) async throws -> ResponseEnvelope<T> {
        let client = SupabaseClientProvider.shared
        let token = try await client.auth.session.accessToken
        client.functions.setAuth(token: token)

        do {
            return try await client.functions.invoke(
                functionName,
                options: FunctionInvokeOptions(body: request)
            )
        } catch FunctionsError.httpError(_, let data) {
            if let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
               let message = decoded.error,
               !message.isEmpty {
                throw GatewayError.backend(message)
            }
            throw GatewayError.backend("No se pudo consultar el marketplace.")
        }
    }
}

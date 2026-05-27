import Foundation

/// Client for the Commercial GOAT / Alias proxy API (CommercialGoatAPI).
/// Docs: https://goatapi.dataspiderhub.com/docs
enum GoatAliasAPIService {
    static let defaultBaseURL = "https://goatapi.dataspiderhub.com"

    enum ServiceError: LocalizedError {
        case missingProviderToken
        case invalidURL
        case invalidResponse
        case httpStatus(Int, String)
        case apiMessage(String)
        case missingAuth
        case missingAccessToken
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .missingProviderToken:
                return "Missing GOAT API token. Add GOAT_API_TOKEN in DeveloperSettings.local.xcconfig."
            case .invalidURL:
                return "Invalid GOAT API URL."
            case .invalidResponse:
                return "Unexpected response from GOAT API."
            case .httpStatus(let code, let body):
                return "GOAT API HTTP \(code): \(body)"
            case .apiMessage(let msg):
                return msg
            case .missingAuth:
                return "GOAT API did not return an auth handle."
            case .missingAccessToken:
                return "GOAT login did not return an access token."
            case .notSignedIn:
                return "Sign in to your GOAT seller account first."
            }
        }
    }

    struct LoginResult {
        let auth: String
        let accessToken: String
        let refreshToken: String
        let displayName: String?
        let accountEmail: String
    }

    struct SessionContext {
        let auth: String
        let accessToken: String?
    }

    private static let catalogAuthKey = "goatCatalogAuth.v1"

    /// Commercial API token (not the Alias seller password).
    static var providerToken: String? {
        let fromPlist = (Bundle.main.object(forInfoDictionaryKey: "GoatAPIToken") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromPlist, !fromPlist.isEmpty, !fromPlist.hasPrefix("$(") { return fromPlist }

        let stored = UserDefaults.standard.string(forKey: "goatAPIToken")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.flatMap { $0.isEmpty ? nil : $0 }
    }

    static var baseURL: URL {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "GoatAPIBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = (raw?.isEmpty == false && raw?.hasPrefix("$(") == false) ? raw! : defaultBaseURL
        return URL(string: candidate) ?? URL(string: defaultBaseURL)!
    }

    static func ping() async throws -> [String: Any] {
        try await get(path: "/ping", query: [:], requiresProviderToken: false)
    }

    static func initAuth() async throws -> String {
        let json = try await get(path: "/api/alias/init_auth", query: [:], requiresProviderToken: true)
        if let auth = JSONHelper.string(in: json, keys: ["auth", "result"]) {
            UserDefaults.standard.set(auth, forKey: catalogAuthKey)
            return auth
        }
        if let data = json["data"] as? String, !data.isEmpty {
            UserDefaults.standard.set(data, forKey: catalogAuthKey)
            return data
        }
        if let data = json["data"] as? [String: Any],
           let auth = JSONHelper.string(in: data, keys: ["auth", "token", "result"]) {
            UserDefaults.standard.set(auth, forKey: catalogAuthKey)
            return auth
        }
        throw ServiceError.missingAuth
    }

    static func catalogAuth(preferred: String? = nil) async throws -> String {
        if let preferred, !preferred.isEmpty { return preferred }
        if let cached = UserDefaults.standard.string(forKey: catalogAuthKey), !cached.isEmpty {
            return cached
        }
        return try await initAuth()
    }

    static func login(account: String, password: String) async throws -> LoginResult {
        let auth = try await initAuth()
        let loginJSON = try await get(
            path: "/api/alias/login",
            query: [
                "auth": auth,
                "account": account,
                "password": password,
            ],
            requiresProviderToken: true
        )

        guard let accessToken = JSONHelper.string(in: loginJSON, keys: ["access_token", "accessToken", "token"]) else {
            throw ServiceError.missingAccessToken
        }
        let refreshToken = JSONHelper.string(in: loginJSON, keys: ["refresh_token", "refreshToken"]) ?? ""

        var profileName: String?
        do {
            let info = try await selfInfo(auth: auth, accessToken: accessToken)
            profileName = JSONHelper.string(in: info, keys: ["username", "name", "seller_name", "email"])
                ?? JSONHelper.deepString(in: info, paths: [
                    ["data", "username"],
                    ["data", "name"],
                    ["data", "seller", "username"],
                    ["data", "user", "username"],
                ])
        } catch {
            profileName = nil
        }

        return LoginResult(
            auth: auth,
            accessToken: accessToken,
            refreshToken: refreshToken,
            displayName: profileName,
            accountEmail: account
        )
    }

    static func selfInfo(auth: String, accessToken: String) async throws -> [String: Any] {
        try await get(
            path: "/api/alias/self_info",
            query: ["auth": auth, "access_token": accessToken],
            requiresProviderToken: true
        )
    }

    static func sellerInfo(auth: String, accessToken: String) async throws -> [String: Any] {
        try await get(
            path: "/api/alias/seller_info",
            query: ["auth": auth, "access_token": accessToken],
            requiresProviderToken: true
        )
    }

    static func refreshAccessToken(auth: String, refreshToken: String) async throws -> String {
        let json = try await get(
            path: "/api/alias/update_access_token",
            query: ["auth": auth, "refresh_token": refreshToken],
            requiresProviderToken: true
        )
        guard let token = JSONHelper.string(in: json, keys: ["access_token", "accessToken", "token"]) else {
            throw ServiceError.missingAccessToken
        }
        return token
    }

    // MARK: - Catalog & prices (provider token + auth handle)

    static func queryBySKU(keyword: String, page: Int = 0) async throws -> [GoatProductSummary] {
        let json = try await get(
            path: "/api/alias/query_by_sku",
            query: ["keyword": keyword, "page": String(page)],
            requiresProviderToken: true
        )
        return GoatCatalogParser.products(from: json)
    }

    static func queryByCondition(_ condition: String = "popular", page: Int = 0) async throws -> [GoatProductSummary] {
        let json = try await get(
            path: "/api/alias/query_by_condition",
            query: ["condition": condition, "page": String(page)],
            requiresProviderToken: true
        )
        return GoatCatalogParser.products(from: json)
    }

    static func goatProductDetail(slug: String, auth: String? = nil, currency: String = "USD") async throws -> [String: Any] {
        let a = try await catalogAuth(preferred: auth)
        return try await get(
            path: "/api/alias/goat_product_detail",
            query: ["auth": a, "slug": slug, "currency": currency],
            requiresProviderToken: true
        )
    }

    static func goatLowestPrice(
        slug: String,
        countryCode: String = "US",
        auth: String? = nil,
        currency: String = "USD"
    ) async throws -> [String: Any] {
        let a = try await catalogAuth(preferred: auth)
        return try await get(
            path: "/api/alias/goat_lowest_price",
            query: ["auth": a, "slug": slug, "country_code": countryCode, "currency": currency],
            requiresProviderToken: true
        )
    }

    static func goatHighestOffers(
        slug: String,
        countryCode: String = "US",
        auth: String? = nil,
        currency: String = "USD"
    ) async throws -> [String: Any] {
        let a = try await catalogAuth(preferred: auth)
        return try await get(
            path: "/api/alias/goat_highest_offers",
            query: ["auth": a, "slug": slug, "country_code": countryCode, "currency": currency],
            requiresProviderToken: true
        )
    }

    static func fetchPriceDetail(for product: GoatProductSummary, auth: String? = nil) async throws -> GoatProductPriceDetail {
        let slug = product.slug
        guard !slug.isEmpty else {
            throw ServiceError.apiMessage("Product has no GOAT slug for price lookup.")
        }
        async let lowest = goatLowestPrice(slug: slug, auth: auth)
        async let offers = goatHighestOffers(slug: slug, auth: auth)
        async let detail = goatProductDetail(slug: slug, auth: auth)
        return GoatCatalogParser.priceDetail(
            slug: slug,
            lowestJSON: try await lowest,
            offersJSON: try await offers,
            detailJSON: try await detail
        )
    }

    /// Search catalog then pick best match and load prices.
    static func searchAndPrice(keyword: String) async throws -> (product: GoatProductSummary, prices: GoatProductPriceDetail) {
        let hits = try await queryBySKU(keyword: keyword, page: 0)
        guard let best = bestMatch(for: keyword, in: hits) else {
            throw ServiceError.apiMessage("No GOAT products found for \"\(keyword)\".")
        }
        let slug = best.slug
        guard !slug.isEmpty else {
            throw ServiceError.apiMessage("Matched product is missing a slug.")
        }
        let prices = try await fetchPriceDetail(for: best)
        return (best, prices)
    }

    private static func bestMatch(for keyword: String, in products: [GoatProductSummary]) -> GoatProductSummary? {
        guard !products.isEmpty else { return nil }
        let q = keyword.lowercased()
        let scored = products.map { p -> (GoatProductSummary, Int) in
            var score = 0
            let blob = "\(p.brand) \(p.name) \(p.sku) \(p.slug)".lowercased()
            if blob.contains(q) { score += 10 }
            for token in q.split(separator: " ") where token.count > 2 {
                if blob.contains(token) { score += 3 }
            }
            if !p.slug.isEmpty { score += 1 }
            return (p, score)
        }
        return scored.max(by: { $0.1 < $1.1 })?.0 ?? products.first
    }

    // MARK: - Seller inventory (requires sign-in)

    static func getSellingProducts(session: GoatAccountSession, page: Int = 0, query: String = "") async throws -> [GoatSellerListing] {
        let json = try await get(
            path: "/api/alias/get_selling_products",
            query: [
                "auth": session.auth,
                "access_token": session.accessToken,
                "page": String(page),
                "query": query,
            ],
            requiresProviderToken: true
        )
        return GoatCatalogParser.listings(from: json)
    }

    static func getSoldProducts(session: GoatAccountSession, page: Int = 0) async throws -> [GoatSellerListing] {
        let json = try await get(
            path: "/api/alias/get_sold_products",
            query: [
                "auth": session.auth,
                "access_token": session.accessToken,
                "page": String(page),
            ],
            requiresProviderToken: true
        )
        return GoatCatalogParser.listings(from: json)
    }

    static func getSellingInfo(session: GoatAccountSession) async throws -> [String: Any] {
        try await get(
            path: "/api/alias/get_selling_info",
            query: ["auth": session.auth, "access_token": session.accessToken],
            requiresProviderToken: true
        )
    }

    // MARK: - HTTP

    private static func get(
        path: String,
        query: [String: String],
        requiresProviderToken: Bool
    ) async throws -> [String: Any] {
        var items = query
        if requiresProviderToken {
            guard let token = providerToken else { throw ServiceError.missingProviderToken }
            items["token"] = token
        }

        guard let url = URL(string: path.hasPrefix("/") ? path : "/\(path)", relativeTo: baseURL)?.absoluteURL else {
            throw ServiceError.invalidURL
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ServiceError.invalidURL
        }
        components.queryItems = items.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw ServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }

        let bodyText = String(data: data, encoding: .utf8) ?? ""
        if !(200...299).contains(http.statusCode) {
            throw ServiceError.httpStatus(http.statusCode, bodyText.prefix(280).description)
        }

        let object = try JSONHelper.parseObject(data)
        if let message = JSONHelper.errorMessage(in: object) {
            throw ServiceError.apiMessage(message)
        }
        return object
    }
}

// MARK: - JSON helpers

private enum JSONHelper {
    static func parseObject(_ data: Data) throws -> [String: Any] {
        let raw = try JSONSerialization.jsonObject(with: data)
        if let dict = raw as? [String: Any] { return dict }
        if let text = raw as? String { return ["result": text] }
        if let arr = raw as? [Any] { return ["data": arr] }
        throw GoatAliasAPIService.ServiceError.invalidResponse
    }

    static func errorMessage(in root: [String: Any]) -> String? {
        let code = deepValue(in: root, path: ["code"]) ?? deepValue(in: root, path: ["status"])
        let msg = string(in: root, keys: ["msg", "message", "error", "detail"])
            ?? deepString(in: root, paths: [["data", "msg"], ["data", "message"]])

        if let code {
            let numeric = (code as? NSNumber)?.intValue ?? Int("\(code)")
            if numeric == 0 || numeric == 200 { return nil }
        }
        if let msg, !msg.isEmpty, !isSuccessMessage(msg) { return msg }
        if let success = root["success"] as? Bool, success == false {
            return msg ?? "GOAT API request failed."
        }
        return nil
    }

    private static func isSuccessMessage(_ msg: String) -> Bool {
        let lower = msg.lowercased()
        return lower == "success" || lower == "ok" || lower.contains("success")
    }

    static func string(in root: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let v = root[key] as? String, !v.isEmpty { return v }
            if let v = root[key] as? Int { return String(v) }
        }
        if let data = root["data"] {
            if let s = data as? String, !s.isEmpty { return s }
            if let dict = data as? [String: Any] {
                for key in keys {
                    if let v = dict[key] as? String, !v.isEmpty { return v }
                }
            }
        }
        return nil
    }

    static func deepString(in root: [String: Any], paths: [[String]]) -> String? {
        for path in paths {
            if let v = deepValue(in: root, path: path) as? String, !v.isEmpty { return v }
        }
        return nil
    }

    static func deepValue(in root: [String: Any], path: [String]) -> Any? {
        var current: Any = root
        for segment in path {
            guard let dict = current as? [String: Any], let next = dict[segment] else { return nil }
            current = next
        }
        return current
    }
}

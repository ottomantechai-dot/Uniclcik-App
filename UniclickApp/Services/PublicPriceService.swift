import Foundation
import Supabase

struct MarketReferenceQuote: Decodable, Sendable, Identifiable {
    enum Kind: String, Decodable, Sendable {
        case snapshot, market, estimate, listing

        var label: String {
            switch self {
            case .snapshot: "Marketplace snapshot"
            case .market: "Market reference"
            case .estimate: "Comparable estimate"
            case .listing: "Catalog asking price"
            }
        }
    }

    let source: String
    let quoteKind: Kind
    let amount: Double
    let observedOn: String
    let basis: String?
    let sourceURL: URL?
    var id: String { "\(source)-\(quoteKind.rawValue)" }

    private enum CodingKeys: String, CodingKey {
        case source, amount, basis
        case quoteKind = "quote_kind"
        case observedOn = "observed_on"
        case sourceURL = "source_url"
    }
}

enum MarketReferenceStore {
    private static let bundled: [String: [MarketReferenceQuote]] = {
        guard let url = Bundle.main.url(forResource: "MarketReferences", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([String: [MarketReferenceQuote]].self, from: data)
        else { return [:] }
        return records
    }()

    static func saved(_ key: String) -> [MarketReferenceQuote] {
        bundled[key] ?? []
    }

    static func load(_ key: String) async -> [MarketReferenceQuote] {
        let local = saved(key)
        let remote: [MarketReferenceQuote]? = try? await SupabaseClientProvider.catalogAnon
            .from("market_references")
            .select("source,quote_kind,amount,observed_on,basis,source_url")
            .eq("item_key", value: key)
            .execute().value
        guard let remote, !remote.isEmpty else { return local }
        return remote.sorted { $0.source.localizedStandardCompare($1.source) == .orderedAscending }
    }
}

struct PublicProductOffer: Sendable {
    let source: String
    let title: String
    let sku: String?
    let url: URL
    let imageURL: URL?
    let pricesBySize: [String: Double]
    var sizeSystem: ShoeSizeSystem? = nil
}

struct PublicCardSale: Sendable {
    let source: String
    let grade: String
    let amount: Double
    let date: Date
    let url: URL?
}

struct PublicCardPrices: Sendable {
    let url: URL
    let checkedAt: Date
    let estimates: [String: Double]
    let sales: [PublicCardSale]

    func latestSale(source: String, grade: String) -> PublicCardSale? {
        sales.first { $0.source == source && $0.grade == grade }
    }
}

enum PublicPriceService {
    struct ProductQuery: Hashable, Sendable {
        let query: String
        var fallback: String?
    }

    struct CardQuery: Hashable, Sendable {
        let name: String
        let set: String
        let number: String
    }

    struct ProductPrices: Sendable {
        let checkedAt: Date
        let offers: [PublicProductOffer]
    }

    static let refreshInterval: Duration = .seconds(90)

    private static let stadium = URL(string: "https://www.stadiumgoods.com")!
    private static let snkrdunk = URL(string: "https://snkrdunk.com")!
    private static let priceCharting = URL(string: "https://www.pricecharting.com")!
    private static let productCache = QueryCache<ProductQuery, ProductPrices>()
    private static let cardCache = QueryCache<CardQuery, PublicCardPrices?>()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 18
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: PublicPageRedirects(), delegateQueue: nil)
    }()

    static func product(_ input: ProductQuery) async -> ProductPrices {
        let key = ProductQuery(query: clean(input.query), fallback: input.fallback.map(clean))
        return await productCache.value(for: key) {
            guard !key.query.isEmpty else { return ProductPrices(checkedAt: Date(), offers: []) }
            async let stadium = stadiumOffer(key)
            async let snkr = snkrOffer(key)
            var (stadiumPrice, snkrPrice) = await (stadium, snkr)
            if URL(string: key.query)?.scheme == "https" {
                if let stadiumPrice, snkrPrice == nil {
                    snkrPrice = await snkrOffer(ProductQuery(query: stadiumPrice.sku ?? stadiumPrice.title, fallback: stadiumPrice.title))
                } else if let snkrPrice, stadiumPrice == nil {
                    stadiumPrice = await stadiumOffer(ProductQuery(query: snkrPrice.sku ?? snkrPrice.title, fallback: snkrPrice.title))
                }
            }
            if let stadiumSystem = stadiumPrice?.sizeSystem, let snkrSystem = snkrPrice?.sizeSystem,
               stadiumSystem != snkrSystem { snkrPrice = nil }
            return ProductPrices(checkedAt: Date(), offers: [stadiumPrice, snkrPrice].compactMap { $0 })
        }
    }

    @MainActor
    static func poll(_ refresh: @MainActor () async -> Void) async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: refreshInterval) }
            catch { return }
        }
    }

    static func card(_ key: CardQuery) async -> PublicCardPrices? {
        await cardCache.value(for: key) {
            guard !key.name.isEmpty, !key.set.isEmpty,
                  capture(#"^[A-Za-z]*[0-9]+[A-Za-z]*$"#, in: key.number) != nil else { return nil }
            let query = [key.name, key.number, "Pokemon", key.set].joined(separator: " ")
            let url = searchURL(priceCharting, path: "/search-products", params: [("type", "prices"), ("q", clean(query))])
            guard let page = await page(at: url) else { return nil }
            if let prices = cardPrices(in: page.html, url: page.url, matching: key) { return prices }
            guard page.url.path == "/search-products",
                  let candidate = cardResult(in: page.html, matching: key),
                  let detail = await Self.page(at: candidate) else { return nil }
            return cardPrices(in: detail.html, url: detail.url, matching: key)
        }
    }

    // MARK: - Products

    private static func stadiumOffer(_ input: ProductQuery) async -> PublicProductOffer? {
        if let url = productURL(input.query, base: stadium, prefix: "/products/"),
           let page = await page(at: url) {
            return stadiumProduct(in: page.html, url: page.url)
        }
        guard URL(string: input.query)?.scheme == nil else { return nil }
        let sku = styleCode(input.query)
        let search = searchURL(stadium, path: "/search", params: [("q", input.query)])
        var candidates = await page(at: search).map { stadiumHandles(in: $0.html) } ?? []
        let name = sku == nil ? input.query : input.fallback
        if candidates.isEmpty, let name, name != input.query {
            let fallbackSearch = searchURL(stadium, path: "/search", params: [("q", name)])
            candidates = await page(at: fallbackSearch).map { stadiumHandles(in: $0.html) } ?? []
        }
        if let name {
            let tokens = words(productName(name))
            candidates = candidates.sorted {
                tokens.intersection(words($0)).count > tokens.intersection(words($1)).count
            }
        }
        for handle in candidates.prefix(4) {
            guard let detail = await page(at: stadium.appendingPathComponent("products").appendingPathComponent(handle)),
                  let offer = stadiumProduct(in: detail.html, url: detail.url) else { continue }
            if let sku {
                if offer.sku.map(Self.skuKey) == skuKey(sku) { return offer }
            } else if productMatches(offer.title, query: input.query) {
                return offer
            }
        }
        return nil
    }

    private static func stadiumHandles(in html: String) -> [String] {
        guard let data = capture(#"\bGSC_COUNTDOWN_COLLECTION_DATA\s*=\s*\[(.*?)</script>"#, in: html, group: 1) else { return [] }
        var seen = Set<String>()
        return captures(#"\bhandle:\s*"([a-z0-9-]+)""#, in: data, group: 1).filter { seen.insert($0).inserted }
    }

    static func stadiumProduct(in html: String, url: URL) -> PublicProductOffer? {
        guard url.host == stadium.host, url.path.hasPrefix("/products/") else { return nil }
        var prices: [String: Double] = [:]
        var title: String?
        var sku: String?
        var thumbnail: URL?
        for item in productMetadata(in: html) {
            guard let variant = item["sku"] as? String, let name = item["name"] as? String,
                  let offer = item["offers"] as? [String: Any], offer["priceCurrency"] as? String == "USD",
                  let status = offer["availability"] as? String, status.hasSuffix("/InStock"),
                  let amount = amount(offer["price"]) else { continue }
            let parts = variant.components(separatedBy: "|")
            let nameParts = name.components(separatedBy: " — ")
            guard parts.count == 3, nameParts.count >= 2, !parts[2].isEmpty else { continue }
            let size = normalizeSize(parts[2])
            guard !size.isEmpty else { continue }
            let style = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if let sku, sku != style { continue }
            if title == nil {
                var base = nameParts.dropLast().joined(separator: " — ")
                if !style.isEmpty, base.hasSuffix(" " + style) { base.removeLast(style.count + 1) }
                let brand = (item["brand"] as? [String: Any])?["name"] as? String ?? ""
                let formatted = words(base).isSuperset(of: words(brand)) ? base : "\(brand) \(base)"
                title = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
                sku = style.isEmpty ? nil : style
                thumbnail = httpsURL(item["image"] as? String)
            }
            prices[size] = min(prices[size] ?? amount, amount)
        }
        guard let title, !prices.isEmpty else { return nil }
        let gender = capture(#">GENDER</h3>\s*<p[^>]*>([^<]+)</p>"#, in: html, group: 1)
        return PublicProductOffer(source: "Stadium Goods", title: title, sku: sku, url: url, imageURL: thumbnail,
                                  pricesBySize: prices, sizeSystem: shoeSizeSystem(gender))
    }

    private static func snkrOffer(_ input: ProductQuery) async -> PublicProductOffer? {
        for prefix in ["/en/sneakers/", "/en/streetwears/"] {
            if let url = productURL(input.query, base: snkrdunk, prefix: prefix) {
                return await page(at: url).flatMap { snkrProduct(in: $0.html, url: $0.url) }
            }
        }
        guard URL(string: input.query)?.scheme == nil else { return nil }
        let sku = styleCode(input.query)
        if let sku {
            let url = snkrdunk.appendingPathComponent("en/sneakers").appendingPathComponent(sku)
            if let detail = await page(at: url), let offer = snkrProduct(in: detail.html, url: detail.url),
               offer.sku.map(skuKey) == skuKey(sku) { return offer }
        }
        guard let name = sku == nil ? input.query : input.fallback else { return nil }
        let search = searchURL(snkrdunk, path: "/search", params: [("keywords", name)])
        guard let result = await page(at: search) else { return nil }
        let pattern = #"<a\b[^>]*href="https://snkrdunk\.com/(products|apparels)/([A-Za-z0-9-]+)"[^>]*aria-label="([^"]+)"[^>]*>"#
        var seen = Set<String>()
        for link in captures(pattern, in: result.html, group: 0) {
            guard let label = capture(pattern, in: link, group: 3),
                  let priceRange = label.range(of: " - ¥", options: .backwards),
                  productMatches(plain(String(label[..<priceRange.lowerBound])), query: name),
                  let section = capture(pattern, in: link, group: 1),
                  let id = capture(pattern, in: link, group: 2), seen.insert(id).inserted else { continue }
            let path = section == "products" ? "en/sneakers" : "en/streetwears"
            let url = snkrdunk.appendingPathComponent(path).appendingPathComponent(id)
            guard let detail = await page(at: url), let offer = snkrProduct(in: detail.html, url: detail.url),
                  productMatches(offer.title, query: name) else { continue }
            if let sku, let matchedSKU = offer.sku, skuKey(sku) != skuKey(matchedSKU) { continue }
            return offer
        }
        return nil
    }

    static func snkrProduct(in html: String, url: URL) -> PublicProductOffer? {
        guard url.host == snkrdunk.host,
              let item = productMetadata(in: html).first(where: { $0["offers"] != nil }),
              let title = item["name"] as? String, let groups = item["offers"] as? [[String: Any]] else { return nil }
        let isShoe = url.path.hasPrefix("/en/sneakers/")
        var prices: [String: Double] = [:]
        var explicitSystems = Set<ShoeSizeSystem>()
        for offer in groups.flatMap({ $0["offers"] as? [[String: Any]] ?? [] }) {
            guard offer["priceCurrency"] as? String == "USD",
                  (offer["availability"] as? String)?.hasSuffix("/InStock") == true,
                  (offer["itemCondition"] as? String)?.hasSuffix("/NewCondition") == true,
                  let label = offer["description"] as? String,
                  let amount = amount(offer["price"]) else { continue }
            let size = isShoe ? capture(#"^US\s+(?:[MWY]\s+)?(\d+(?:\.5)?Y?)$"#, in: label, group: 1) : label
            guard let size, !size.isEmpty else { continue }
            if isShoe {
                if let marker = capture(#"^US\s+([MWY])\s+"#, in: label, group: 1) {
                    if let system = shoeSizeSystem(marker) { explicitSystems.insert(system) }
                } else if size.uppercased().hasSuffix("Y") {
                    explicitSystems.insert(.usYouth)
                }
            }
            let normalized = normalizeSize(size)
            prices[normalized] = min(prices[normalized] ?? amount, amount)
        }
        guard !prices.isEmpty, explicitSystems.count <= 1 else { return nil }
        return PublicProductOffer(source: "SNKRDUNK", title: title, sku: isShoe ? item["mpn"] as? String : nil,
                                  url: url, imageURL: httpsURL(item["image"] as? String), pricesBySize: prices,
                                  sizeSystem: explicitSystems.first)
    }

    private static func shoeSizeSystem(_ label: String?) -> ShoeSizeSystem? {
        switch label?.uppercased().filter(\.isLetter) {
        case "M", "MEN", "MENS", "UNISEX": .usMen
        case "W", "WOMEN", "WOMENS": .usWomen
        case "Y", "YOUTH", "KIDS", "GS", "GRADESCHOOL": .usYouth
        default: nil
        }
    }

    // MARK: - Cards

    private static func cardResult(in html: String, matching key: CardQuery) -> URL? {
        let cells = captures(#"<td\s+class="title"[^>]*>(.*?)</td>"#, in: html, group: 1)
        for cell in cells {
            guard let name = capture(#"<a\b[^>]*>(.*?)</a>"#, in: cell, group: 1),
                  let set = capture(#"<div\s+class="console-in-title"[^>]*>(.*?)</div>"#, in: cell, group: 1),
                  matchesCard(name: plain(name), set: plain(set), key: key),
                  let href = capture(#"<a\b[^>]*href="([^"]+)""#, in: cell, group: 1),
                  let url = URL(string: plain(href), relativeTo: priceCharting)?.absoluteURL,
                  permits(url), url.path.hasPrefix("/game/pokemon") else { continue }
            return url
        }
        return nil
    }

    static func cardPrices(in html: String, url: URL, matching key: CardQuery) -> PublicCardPrices? {
        guard url.host == priceCharting.host, url.path.hasPrefix("/game/pokemon"),
              let heading = capture(#"<h1\b[^>]*id="product_name"[^>]*>(.*?)</h1>"#, in: html, group: 1),
              let name = capture(#"^\s*([^<]+)"#, in: heading, group: 1),
              let set = capture(#"<a\b[^>]*>(.*?)</a>"#, in: heading, group: 1),
              matchesCard(name: plain(name), set: plain(set), key: key) else { return nil }

        var estimates: [String: Double] = [:]
        if let guide = capture(#"<div\s+id="full-prices"[^>]*>(.*?)</table>"#, in: html, group: 1) {
            for (label, grade) in [("Ungraded", "Raw"), ("PSA 10", "10")] {
                let pattern = "<td>\(label)</td>\\s*<td[^>]*>([^<]+)</td>"
                estimates[grade] = capture(pattern, in: guide, group: 1).flatMap(usd)
            }
        }

        let rows = captures(#"<tr\s+id="(?:ebay|tcgplayer)-[^"]+"[^>]*>.*?</tr>"#, in: html, group: 0)
        let dateFormat = DateFormatter()
        dateFormat.locale = Locale(identifier: "en_US_POSIX")
        dateFormat.calendar = Calendar(identifier: .gregorian)
        dateFormat.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormat.dateFormat = "yyyy-MM-dd"
        let sales = rows.compactMap { row -> PublicCardSale? in
            guard let sourceKey = capture(#"<tr\s+id="(ebay|tcgplayer)-"#, in: row, group: 1),
                  let day = capture(#"<td\s+class="date"[^>]*>\s*(\d{4}-\d{2}-\d{2})\s*</td>"#, in: row, group: 1),
                  let date = dateFormat.date(from: day), date <= Date(),
                  let title = capture(#"<a\b[^>]*class="js-(?:ebay|tcgplayer)-completed-sale"[^>]*>(.*?)</a>"#, in: row, group: 1).map(plain),
                  let grade = saleGrade(title: title, key: key),
                  let value = capture(#"<td\s+class="numeric"[^>]*>\s*<span[^>]*>([^<]+)</span>"#, in: row, group: 1).flatMap(usd)
            else { return nil }
            let itemID = capture(#"<tr\s+id="ebay-(\d+)""#, in: row, group: 1)
            let link = itemID.flatMap { URL(string: "https://www.ebay.com/itm/\($0)") }
            return PublicCardSale(source: sourceKey == "ebay" ? "eBay" : "TCGplayer", grade: grade, amount: value, date: date, url: link)
        }.sorted { $0.date > $1.date }

        guard !estimates.isEmpty || !sales.isEmpty else { return nil }
        var canonical = URLComponents(url: url, resolvingAgainstBaseURL: false)
        canonical?.query = nil
        canonical?.fragment = nil
        return PublicCardPrices(url: canonical?.url ?? url, checkedAt: Date(), estimates: estimates, sales: sales)
    }

    private static func matchesCard(name: String, set: String, key: CardQuery) -> Bool {
        let parts = name.split(separator: "#", maxSplits: 1)
        guard parts.count == 2,
              comparableCardNumber(String(parts[1])) == comparableCardNumber(key.number),
              normalized(String(parts[0])) == normalized(key.name) else { return false }
        return normalizedSet(set) == normalizedSet(key.set)
    }

    private static func saleGrade(title: String, key: CardQuery) -> String? {
        let text = normalized(title)
        let quoted = NSRegularExpression.escapedPattern(for: comparableCardNumber(key.number).lowercased())
        let numberPattern = #"(?i)(?<![a-z0-9])0*"# + quoted + #"(?=\s*/\s*\d|\b)"#
        guard text.contains(normalized(key.name)), capture(numberPattern, in: title) != nil,
              capture(#"\b(?:proxy|replica|reprint|custom|lot|japanese|korean|chinese|metal|jumbo|digital)\b"#, in: text) == nil else { return nil }
        if let grade = capture(#"\bpsa\s+(8|9|10)\b(?![.\d])"#, in: title, group: 1) { return grade }
        guard capture(#"\b(?:psa|bgs|cgc|sgc|ace|beckett|graded|slab|tag)\b"#, in: text) == nil else { return nil }
        return "Raw"
    }

    // MARK: - Public HTML

    private struct Page {
        let url: URL
        let html: String
    }

    private static func page(at url: URL) async -> Page? {
        guard permits(url) else { return nil }
        let (data, response): (Data, URLResponse)
        do {
            var request = URLRequest(url: url)
            request.setValue("text/html, application/xhtml+xml", forHTTPHeaderField: "Accept")
            (data, response) = try await session.data(for: request)
        } catch { return nil }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let finalURL = response.url, permits(finalURL),
              response.mimeType == "text/html", data.count <= 8_000_000,
              let html = String(data: data, encoding: .utf8) else { return nil }
        return Page(url: finalURL, html: html)
    }

    fileprivate static func permits(_ url: URL) -> Bool {
        guard url.scheme == "https", url.port == nil, url.user == nil, url.password == nil else { return false }
        let path = url.path
        switch url.host {
        case stadium.host: return path == "/search" || validProductPath(path, prefix: "/products/")
        case snkrdunk.host: return path == "/search" || validProductPath(path, prefix: "/en/sneakers/") || validProductPath(path, prefix: "/en/streetwears/")
        case priceCharting.host: return path == "/search-products" || (path.hasPrefix("/game/pokemon") && path.split(separator: "/").count == 3)
        default: return false
        }
    }

    private static func validProductPath(_ path: String, prefix: String) -> Bool {
        path.hasPrefix(prefix) && capture(#"^[a-zA-Z0-9-]+/?$"#, in: String(path.dropFirst(prefix.count))) != nil
    }

    private static func productURL(_ raw: String, base: URL, prefix: String) -> URL? {
        guard let url = httpsURL(raw), url.host == base.host, permits(url),
              validProductPath(url.path, prefix: prefix) else { return nil }
        var canonical = URLComponents(url: url, resolvingAgainstBaseURL: false)
        canonical?.query = nil
        canonical?.fragment = nil
        return canonical?.url
    }

    private static func searchURL(_ base: URL, path: String, params: [(String, String)]) -> URL {
        var url = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        url.path = path
        url.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return url.url!
    }

    private static func productMetadata(in html: String) -> [[String: Any]] {
        captures(#"<script\b[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#, in: html, group: 1)
            .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            .filter { $0["@type"] as? String == "Product" }
    }

    private static func captures(_ pattern: String, in value: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            Range(match.range(at: group), in: value).map { String(value[$0]) }
        }
    }

    private static func capture(_ pattern: String, in value: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: group), in: value) else { return nil }
        return String(value[range])
    }

    private static func clean(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }

    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    private static func words(_ text: String) -> Set<Substring> { Set(normalized(text).split(separator: " ")) }

    private static func productName(_ text: String) -> String {
        normalized(text).split(separator: " ").filter {
            capture(#"^(?:fw|ss)\d\d$"#, in: String($0)) == nil
        }.joined(separator: " ")
    }

    private static func productMatches(_ title: String, query: String) -> Bool {
        guard productName(title) == productName(query) else { return false }
        let requestedSeason = capture(#"\b(?:fw|ss)\d\d\b"#, in: normalized(query))
        return requestedSeason == nil || capture(#"\b(?:fw|ss)\d\d\b"#, in: normalized(title)) == requestedSeason
    }

    private static func normalizedSet(_ text: String) -> String {
        normalized(text).replacingOccurrences(of: " trainer gallery", with: "").split(separator: " ").filter {
            $0 != "pokemon" && $0 != "and" && capture(#"^(?:swsh|sv|sm)\d*$"#, in: String($0)) == nil
        }.joined(separator: " ")
    }

    private static func comparableCardNumber(_ number: String) -> String {
        let key = skuKey(number)
        if let numeric = Int(key) { return String(numeric) }
        return key
    }

    private static func styleCode(_ query: String) -> String? {
        guard capture(#"^(?=[a-z0-9 -]*\d)[a-z0-9]{3,12}[- ]?[0-9]{2,4}$"#, in: query) != nil else { return nil }
        return query.uppercased().replacingOccurrences(of: " ", with: "-")
    }

    private static func skuKey(_ text: String) -> String { String(text.uppercased().filter { $0.isLetter || $0.isNumber }) }

    static func normalizeSize(_ text: String) -> String {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let size = capture(#"^US\s*(?:[MW]\s*)?(\d+(?:\.5)?)$"#, in: clean, group: 1) { clean = size }
        if let value = Double(clean), value.isFinite, value >= 0, value < 100 {
            return value.rounded() == value ? String(Int(value)) : String(value)
        }
        return clean
    }

    static func sizeOrder(_ a: String, _ b: String) -> Bool {
        let apparel = ["XXXS", "XXS", "XS", "S", "M", "L", "XL", "XXL", "XXXL", "XXXXL"]
        if let first = apparel.firstIndex(of: a), let second = apparel.firstIndex(of: b) { return first < second }
        return a.localizedStandardCompare(b) == .orderedAscending
    }

    private static func httpsURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    private static func amount(_ raw: Any?) -> Double? {
        let value = (raw as? String).flatMap(Double.init) ?? (raw as? NSNumber)?.doubleValue
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func usd(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard capture(#"^\$\d[\d,]*(?:\.\d\d)?$"#, in: text) != nil else { return nil }
        return amount(String(text.dropFirst()).replacingOccurrences(of: ",", with: ""))
    }
}

private final class PublicPageRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let next = request.url, next.host == response.url?.host, PublicPriceService.permits(next) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private actor QueryCache<Key: Hashable & Sendable, Value: Sendable> {
    private var entries: [Key: (Date, Value)] = [:]
    private var inFlight: [Key: Task<Value, Never>] = [:]

    func value(for key: Key, load: @escaping @Sendable () async -> Value) async -> Value {
        let now = Date()
        if let (expiry, value) = entries[key], now < expiry { return value }
        if let existing = inFlight[key] { return await existing.value }
        let task = Task { await load() }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        entries = entries.filter { $0.value.0 > now }
        if entries.count >= 64, let oldest = entries.min(by: { $0.value.0 < $1.value.0 })?.key {
            entries.removeValue(forKey: oldest)
        }
        entries[key] = (Date().addingTimeInterval(45), result)
        return result
    }
}

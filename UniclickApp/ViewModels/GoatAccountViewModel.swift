import Foundation

@MainActor
final class GoatAccountViewModel: ObservableObject {
    @Published private(set) var session: GoatAccountSession?
    @Published private(set) var isValidating = false
    @Published private(set) var isSigningIn = false
    @Published var lastError: String?

    @Published var searchQuery = ""
    @Published private(set) var searchResults: [GoatProductSummary] = []
    @Published private(set) var selectedProduct: GoatProductSummary?
    @Published private(set) var selectedPriceDetail: GoatProductPriceDetail?
    @Published private(set) var sellingListings: [GoatSellerListing] = []
    @Published private(set) var soldListings: [GoatSellerListing] = []

    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingPrices = false
    @Published private(set) var isLoadingInventory = false
    @Published private(set) var apiReachable: Bool?

    var isConnected: Bool { session != nil }
    var hasProviderToken: Bool { GoatAliasAPIService.providerToken != nil }

    init() {
        session = GoatAccountStore.load()
    }

    func validateStoredSession() async {
        guard var current = session else { return }
        isValidating = true
        lastError = nil
        defer { isValidating = false }

        do {
            _ = try await GoatAliasAPIService.selfInfo(auth: current.auth, accessToken: current.accessToken)
        } catch {
            if !current.refreshToken.isEmpty {
                do {
                    let newToken = try await GoatAliasAPIService.refreshAccessToken(
                        auth: current.auth,
                        refreshToken: current.refreshToken
                    )
                    current.accessToken = newToken
                    GoatAccountStore.save(current)
                    session = current
                    return
                } catch {
                    disconnect()
                    lastError = error.localizedDescription
                    return
                }
            }
            disconnect()
            lastError = error.localizedDescription
        }
    }

    func signIn(account: String, password: String) async -> Bool {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty, !password.isEmpty else {
            lastError = "Enter your Alias email and password."
            return false
        }

        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }

        do {
            let result = try await GoatAliasAPIService.login(account: trimmedAccount, password: password)
            let saved = GoatAccountSession(
                auth: result.auth,
                accessToken: result.accessToken,
                refreshToken: result.refreshToken,
                accountEmail: result.accountEmail,
                displayName: result.displayName,
                connectedAt: Date()
            )
            GoatAccountStore.save(saved)
            session = saved
            await loadSellerInventory()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func disconnect() {
        GoatAccountStore.clear()
        session = nil
        sellingListings = []
        soldListings = []
        lastError = nil
    }

    func pingAPI() async {
        do {
            _ = try await GoatAliasAPIService.ping()
            apiReachable = true
        } catch {
            apiReachable = false
            lastError = error.localizedDescription
        }
    }

    func searchCatalog() async {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            lastError = "Enter a SKU or product name."
            return
        }
        isSearching = true
        lastError = nil
        selectedProduct = nil
        selectedPriceDetail = nil
        defer { isSearching = false }

        do {
            searchResults = try await GoatAliasAPIService.queryBySKU(keyword: q, page: 0)
            if searchResults.isEmpty {
                lastError = "No products found on GOAT."
            }
        } catch {
            searchResults = []
            lastError = error.localizedDescription
        }
    }

    func loadPrices(for product: GoatProductSummary) async {
        isLoadingPrices = true
        lastError = nil
        selectedProduct = product
        defer { isLoadingPrices = false }

        do {
            selectedPriceDetail = try await GoatAliasAPIService.fetchPriceDetail(
                for: product,
                auth: session?.auth
            )
        } catch {
            selectedPriceDetail = nil
            lastError = error.localizedDescription
        }
    }

    func loadSellerInventory() async {
        guard let session else {
            sellingListings = []
            soldListings = []
            return
        }
        isLoadingInventory = true
        lastError = nil
        defer { isLoadingInventory = false }

        do {
            async let selling = GoatAliasAPIService.getSellingProducts(session: session, page: 0)
            async let sold = GoatAliasAPIService.getSoldProducts(session: session, page: 0)
            sellingListings = try await selling
            soldListings = try await sold
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Used from closet item detail — returns market price estimate from GOAT.
    func fetchMarketPriceEstimate(query: String) async -> PieceMarketPrice? {
        guard hasProviderToken else { return nil }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        do {
            let pair = try await GoatAliasAPIService.searchAndPrice(keyword: q)
            return pair.prices.asPieceMarketPrice()
        } catch {
            return nil
        }
    }
}

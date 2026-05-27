import SwiftUI
import UIKit

// MARK: - Enrutador de pestañas (mismo módulo que `CarsView` / `DashboardView`)

enum UpsoledMainTab: Hashable {
    case home
    case closet
    case cars
    case chat
    case ai
    case settings
}

@MainActor
final class MainTabRouter: ObservableObject {
    @Published var selected: UpsoledMainTab = .home
}

/// Abre un hilo concreto al cambiar a la pestaña Chat (p. ej. grupo «Mi equipo» desde Inicio).
@MainActor
final class ChatNavigationCoordinator: ObservableObject {
    @Published var threadToOpen: ChatThread?
}

// MARK: - Pestañas (TabView nativo iOS 26 + Liquid Glass del sistema)

struct MainTabView: View {
    @StateObject private var tabRouter = MainTabRouter()
    @StateObject private var invoiceHistory = InvoiceHistoryStore()
    @StateObject private var chatInbox = ChatInboxStore()
    @StateObject private var communityVM = DashboardCommunityViewModel()
    @StateObject private var chatNav = ChatNavigationCoordinator()
    @State private var chatSearchText = ""
    @StateObject private var addClosetFlowVM = AddToClosetFlowViewModel()

    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel

    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue
    private var appLanguage: AppLanguage { AppLanguage(rawValue: appLanguageRaw) ?? .spanish }

    /// Solo tareas coordinator pendientes; sin esto habría badge por mensajes de chat (incorrecto para la pestaña Soled).
    private var soledTabRequestBadgeCount: Int {
        guard let uid = auth.session?.user.id else { return 0 }
        return chatInbox.openCoordinatorRequestsAssigned(toRecipient: uid)
    }

    var body: some View {
        mainTabChrome
    }

    /// Cuerpo partido para el type-check del compilador (`TabView` + muchos modificadores).
    private var mainTabChrome: some View {
        bareTabView
        .environmentObject(chatInbox)
        .environmentObject(tabRouter)
        .environmentObject(chatNav)
        .environmentObject(communityVM)
        .environmentObject(invoiceHistory)
            .environmentObject(addClosetFlowVM)
            /// Ítem seleccionado: azul marca; ítems no seleccionados: negro (`MainTabBarAppearance`).
            .accentColor(PremiumAccent.tabActive)
            .tint(PremiumAccent.tabActive)
        .onAppear {
                MainTabBarAppearance.applyBlackInactiveBlueSelected()
            communityVM.attach(auth: auth)
            communityVM.startPeriodicRefresh()
            Task { await communityVM.refresh() }
        }
        .onDisappear {
            communityVM.stopPeriodicRefresh()
        }
        .onChange(of: auth.session?.user.id) { _, _ in
            communityVM.attach(auth: auth)
            Task { await communityVM.refresh() }
        }
        .onChange(of: auth.organizationId) { _, _ in
            if !auth.canAccessIASection, tabRouter.selected == .ai {
                tabRouter.selected = .home
            }
        }
        .toolbarBackground(PremiumAccent.tabBarDockBackgroundGradient, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.light, for: .tabBar)
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            await carsVM.loadVehicles(companyId: auth.companyId)
        }
            .task(id: auth.session?.user.id) {
                guard let uid = auth.session?.user.id else { return }
                await chatInbox.refreshCoordinatorTasksFromServer(currentUserId: uid)
            }
        .onReceive(NotificationCenter.default.publisher(for: .coordinatorTaskAcceptedFromPush)) { _ in
            guard let uid = auth.session?.user.id else { return }
            Task {
                await chatInbox.refreshCoordinatorTasksFromServer(currentUserId: uid)
                }
            }
    }

    /// Solo el `TabView` con sus ítems; los `.environmentObject`/`task`/`onReceive` van en `mainTabChrome`.
    private var bareTabView: some View {
        TabView(selection: $tabRouter.selected) {
            Tab(L10n.tr("tab.dashboard", lang: appLanguage), systemImage: "square.grid.2x2.fill", value: UpsoledMainTab.home) {
                NavigationStack {
                    DashboardView()
                }
            }

            Tab(L10n.tr("tab.closet", lang: appLanguage), systemImage: "tshirt.fill", value: UpsoledMainTab.closet) {
                NavigationStack {
                    ClosetView()
                }
            }

            Tab(L10n.tr("tab.collection", lang: appLanguage), systemImage: "shoe.fill", value: UpsoledMainTab.cars) {
                NavigationStack {
                    CarsView()
                }
            }

            if soledTabRequestBadgeCount > 0 {
                Tab(L10n.tr("tab.soled", lang: appLanguage), systemImage: "shippingbox.fill", value: UpsoledMainTab.chat) {
                    NavigationStack {
                        SoldView()
                    }
                }
                .badge(soledTabRequestBadgeCount)
        } else {
                Tab(L10n.tr("tab.soled", lang: appLanguage), systemImage: "shippingbox.fill", value: UpsoledMainTab.chat) {
                    NavigationStack {
                        SoldView()
                    }
                }
            }

            if auth.canAccessIASection {
                Tab(L10n.tr("tab.pricing", lang: appLanguage), systemImage: "dollarsign.circle.fill", value: UpsoledMainTab.ai) {
                    TeamAITabView()
                        .toolbar(.hidden, for: .tabBar)
                        .toolbarBackground(.hidden, for: .tabBar)
                }
            }

            Tab(L10n.tr("tab.settings", lang: appLanguage), systemImage: "gearshape.fill", value: UpsoledMainTab.settings) {
        NavigationStack {
                    SettingsView()
                }
            }
        }
    }
}

// MARK: - Pricing Tier (sin UI tipo chat IA)

/// Pestaña sin conversación tipo chat: sin burbujas, streaming ni micrófono Viera (eliminado a petición).
struct TeamAITabView: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .spanish
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            ContentUnavailableView(
                L10n.tr("pricing.title", lang: appLanguage),
                systemImage: "dollarsign.circle",
                description: Text(
                    L10n.tr("pricing.placeholder", lang: appLanguage)
                )
            )
            .foregroundStyle(Color.black.opacity(0.78))
            .symbolRenderingMode(.hierarchical)
            .tint(Color(red: 0.20, green: 0.45, blue: 0.85))
        }
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - UITabBar (inactivos negro, seleccionados azul Upsoled)

private enum MainTabBarAppearance {
    static func applyBlackInactiveBlueSelected() {
        let inactive = UIColor.black
        let selected = UIColor(red: 0.16, green: 0.44, blue: 0.98, alpha: 1.0)

        let item = UITabBarItemAppearance()
        item.normal.iconColor = inactive
        item.normal.titleTextAttributes = [.foregroundColor: inactive]
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [.foregroundColor: selected]

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowImage = UIImage()
        appearance.shadowColor = .clear

        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        let bar = UITabBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.isTranslucent = true
        bar.tintColor = selected
        bar.unselectedItemTintColor = inactive
        bar.barTintColor = nil
        bar.backgroundColor = .clear
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
        .environmentObject(CarsViewModel())
        .environmentObject(SettingsViewModel())
}

// MARK: - Vendido (sales history)

struct SoldView: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue
    @State private var searchText = ""
    @State private var filter: SoldFilter = .all
    @State private var didAppear = false
    @FocusState private var searchFocused: Bool

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .spanish
    }

    private var filteredSales: [SoldSneakerMock] {
        let base = SoldSneakerMock.catalog.filter { sale in
            switch filter {
            case .all: return true
            case .thisMonth: return sale.daysAgo <= 30
            case .topProfit: return sale.profitUSD >= 200
            }
        }
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
        return base.filter { sale in
            "\(sale.brand) \(sale.model) \(sale.colorway) \(sale.buyer)"
                .lowercased()
                .contains(searchText.lowercased())
        }
    }

    private var totalRevenue: Int {
        filteredSales.reduce(0) { $0 + $1.salePriceUSD }
    }

    private var totalProfit: Int {
        filteredSales.reduce(0) { $0 + $1.profitUSD }
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                soldTopBar
                    .appChromeHeaderOuterPadding()
                    .environment(\.dashboardLightSurface, true)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        soldSummaryCard
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .modifier(SoldEntranceAnimation(didAppear: didAppear, delay: 0.05))

                        filterPicker
                            .padding(.horizontal, 16)
                            .modifier(SoldEntranceAnimation(didAppear: didAppear, delay: 0.15))

                        LazyVStack(spacing: 12) {
                            if filteredSales.isEmpty {
                                ContentUnavailableView(
                                    L10n.tr("sold.emptyTitle", lang: appLanguage),
                                    systemImage: "checkmark.seal",
                                    description: Text(L10n.tr("sold.emptyDesc", lang: appLanguage))
                                )
                                .padding(.vertical, 40)
                            } else {
                            ForEach(filteredSales) { sale in
                                SoldSneakerRow(sale: sale)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .modifier(SoldEntranceAnimation(didAppear: didAppear, delay: 0.25))
                    }
                    .padding(.bottom, 36)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .environment(\.dashboardLightSurface, true)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                didAppear = true
            }
        }
    }

    private var soldTopBar: some View {
        ChromeSearchTrailingHeaderRow(
            searchText: $searchText,
            prompt: Text(L10n.tr("sold.searchPrompt", lang: appLanguage))
                .foregroundStyle(Color.black.opacity(0.42)),
            showsSearchClearButton: true,
            searchFieldFocused: $searchFocused
        ) {
            HStack(spacing: AppChromeHeaderMetrics.hStackSpacing) {
                AppChromeHeaderCircleIconButton(
                    systemName: "arrow.up.arrow.down",
                    accessibilityLabel: LocalizedStringKey(L10n.tr("common.sort", lang: appLanguage)),
                    action: {}
                )
                AppChromeHeaderCircleIconButton(
                    systemName: "line.3.horizontal.decrease",
                    accessibilityLabel: LocalizedStringKey(L10n.tr("common.filters", lang: appLanguage)),
                    action: {}
                )
            }
        }
    }

    private var soldSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
                Text(L10n.tr("sold.thisPeriod", lang: appLanguage))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(formatUSD(totalRevenue))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            HStack(spacing: 14) {
                summaryStat(label: L10n.tr("sold.sales", lang: appLanguage), value: "\(filteredSales.count)", tint: Color(red: 0.20, green: 0.45, blue: 0.85))
                Divider().frame(height: 28)
                summaryStat(label: L10n.tr("sold.profit", lang: appLanguage), value: formatUSD(totalProfit), tint: Color(red: 0.20, green: 0.70, blue: 0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 5)
        }
    }

    private func summaryStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.50))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
    }

    private var filterPicker: some View {
        HStack(spacing: 8) {
            ForEach(SoldFilter.allCases, id: \.self) { f in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        filter = f
                    }
                } label: {
                    Text(f.label(lang: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(filter == f ? .white : Color.black.opacity(0.60))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            Capsule(style: .continuous)
                                .fill(
                                    filter == f
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.20, green: 0.50, blue: 0.95),
                                                    Color(red: 0.14, green: 0.36, blue: 0.85),
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        : AnyShapeStyle(Color(red: 0.95, green: 0.96, blue: 0.99))
                                )
                                .shadow(color: filter == f ? Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.40) : .clear, radius: 8, y: 4)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func formatUSD(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.maximumFractionDigits = 0
        f.locale = appLanguage.locale
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

private enum SoldFilter: CaseIterable {
    case all, thisMonth, topProfit

    func label(lang: AppLanguage) -> String {
        switch self {
        case .all: return L10n.tr("sold.filterAll", lang: lang)
        case .thisMonth: return L10n.tr("sold.filterMonth", lang: lang)
        case .topProfit: return L10n.tr("sold.filterTop", lang: lang)
        }
    }
}

struct SoldSneakerRow: View {
    let sale: SoldSneakerMock
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .spanish
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [sale.tint.opacity(0.55), sale.tint.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.50), .clear], startPoint: .top, endPoint: .center))
                    .frame(width: 92, height: 92)

                Image("AuthSneakerHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(-18))
                    .shadow(color: sale.tint.opacity(0.45), radius: 10, y: 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(sale.brand.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.black.opacity(0.55))

                Text("\(sale.model) · \(sale.colorway)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.40))
                    Text(sale.buyer)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                    Text("·")
                        .foregroundStyle(Color.black.opacity(0.30))
                    Text(sale.dateLabel(lang: appLanguage))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatUSD(sale.salePriceUSD))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.88))

                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("+\(formatUSD(sale.profitUSD))")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(Color(red: 0.20, green: 0.70, blue: 0.45).opacity(0.12))
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.6)
                }
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
        }
    }

    private func formatUSD(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.maximumFractionDigits = 0
        f.locale = appLanguage.locale
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

struct SoldSneakerMock: Identifiable {
    let id = UUID()
    let brand: String
    let model: String
    let colorway: String
    let buyer: String
    let salePriceUSD: Int
    let profitUSD: Int
    let daysAgo: Int
    let tint: Color

    func dateLabel(lang: AppLanguage) -> String {
        switch daysAgo {
        case 0:
            return L10n.tr("sold.today", lang: lang)
        case 1:
            return L10n.tr("sold.yesterday", lang: lang)
        case 2...6:
            return String(format: L10n.tr("sold.daysAgo", lang: lang), String(daysAgo))
        case 7...13:
            return L10n.tr("sold.oneWeekAgo", lang: lang)
        case 14...29:
            return String(format: L10n.tr("sold.weeksAgo", lang: lang), String(daysAgo / 7))
        default:
            return String(format: L10n.tr("sold.monthsAgo", lang: lang), String(daysAgo / 30))
        }
    }

    static let catalog: [SoldSneakerMock] = []
}

private struct SoldEntranceAnimation: ViewModifier {
    let didAppear: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(didAppear ? 1 : 0)
            .offset(y: didAppear ? 0 : 16)
            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay), value: didAppear)
    }
}

// MARK: - Comparativa de precio de mercado (Market price lookup)

struct PriceSourceQuote: Identifiable {
    let id = UUID()
    let source: String
    let sourceColor: Color
    let sourceLetter: String
    let avgPriceEUR: Int
    let lastSaleEUR: Int
    let hoursAgo: Int
}

struct RecentSaleEntry: Identifiable {
    let id = UUID()
    let priceEUR: Int
    let size: String
    let source: String
    let daysAgo: Int
}

struct MarketPriceSummary {
    let query: String
    let avg: Int
    let min: Int
    let max: Int
    let sources: [PriceSourceQuote]
    let recentSales: [RecentSaleEntry]
}

/// Servicio que consulta precios de mercado. Usa Chat Completions de OpenAI
/// con JSON mode para estimar el precio medio de un sneaker basándose en su
/// conocimiento de StockX/GOAT/eBay. Si no hay API key configurada o la
/// llamada falla, cae al mock local.
@MainActor
final class SneakerPriceLookupService: ObservableObject {
    @Published var isSearching = false
    @Published var summary: MarketPriceSummary?
    @Published var errorMessage: String?

    /// Lee la API key desde el mismo sitio que el resto del proyecto:
    /// `OPENAI_API_KEY` del Info.plist (inyectado por xcconfig). Cae a
    /// @AppStorage("openaiAPIKey") como respaldo.
    private var apiKey: String {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return UserDefaults.standard.string(forKey: "openaiAPIKey") ?? ""
    }

    private var modelName: String {
        if let m = Bundle.main.object(forInfoDictionaryKey: "OPENAI_MODEL") as? String {
            let t = m.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return "gpt-4o-mini"
    }

    func lookup(_ name: String) async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        // Si no hay key, usa mock local
        guard !apiKey.isEmpty else {
            try? await Task.sleep(nanoseconds: 600_000_000)
            summary = Self.simulateLookup(for: name)
            errorMessage = "Sin API key de OpenAI · usando datos simulados. Configúrala en Ajustes."
            return
        }

        do {
            summary = try await fetchFromOpenAI(name: name)
        } catch {
            // Fallback: mock + mensaje de error visible
            summary = Self.simulateLookup(for: name)
            errorMessage = "Error OpenAI: \(error.localizedDescription) · usando estimación local."
        }
    }

    // MARK: - OpenAI Chat Completions con JSON mode

    private struct OAResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct OAJSON: Decodable {
        let avg_eur: Double
        let min_eur: Double
        let max_eur: Double
        let sources: [OASource]
        let recent_sales: [OASale]
    }
    private struct OASource: Decodable {
        let name: String
        let avg_price_eur: Double
        let last_sale_eur: Double
        let hours_ago: Int
    }
    private struct OASale: Decodable {
        let price_eur: Double
        let size: String
        let source: String
        let days_ago: Int
    }

    /// Envoltura del endpoint /v1/responses con `output_text` agregado.
    private struct ResponsesEnvelope: Decodable {
        let output_text: String?
        struct OutputItem: Decodable {
            let type: String?
            let content: [ContentBlock]?
        }
        struct ContentBlock: Decodable {
            let type: String?
            let text: String?
        }
        let output: [OutputItem]?

        var finalText: String? {
            if let t = output_text, !t.isEmpty { return t }
            let joined = (output ?? [])
                .flatMap { $0.content ?? [] }
                .compactMap { $0.text }
                .joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
    }

    private func fetchFromOpenAI(name: String) async throws -> MarketPriceSummary {
        // Endpoint Responses con web_search → busca StockX/GOAT/eBay en internet
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let instructions = """
        You are a sneaker resale market analyst. Use web search on StockX, \
        GOAT, eBay and Grailed to find the current US resale market for the \
        sneaker provided. Return ONLY a valid JSON object (no prose, no \
        markdown) with this exact shape:
        {
          "avg_eur": number,
          "min_eur": number,
          "max_eur": number,
          "sources": [
            {"name": "StockX|GOAT|eBay|Grailed", "avg_price_eur": number, "last_sale_eur": number, "hours_ago": number}
          ],
          "recent_sales": [
            {"price_eur": number, "size": "US 9", "source": "StockX|GOAT|eBay|Grailed", "days_ago": number}
          ]
        }
        IMPORTANT: although fields are named `_eur`, VALUES must be in USD. \
        Return exactly 4 sources (StockX, GOAT, eBay, Grailed) and 6 \
        recent_sales. Use actual data found via search.
        """

        let body: [String: Any] = [
            "model": modelName,
            "input": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": "Sneaker: \(name)"]
            ],
            "tools": [
                ["type": "web_search"]
            ],
            "tool_choice": "auto",
            "temperature": 0.3
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "OpenAI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) · \(errBody.prefix(160))"]
            )
        }

        let envelope = try JSONDecoder().decode(ResponsesEnvelope.self, from: data)
        guard let rawText = envelope.finalText else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Respuesta vacía"])
        }
        guard let jsonRange = Self.extractFirstJSONObject(in: rawText),
              let jsonData = String(rawText[jsonRange]).data(using: .utf8) else {
            throw NSError(domain: "OpenAI", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "No se pudo extraer JSON · \(rawText.prefix(120))"
            ])
        }

        let parsed = try JSONDecoder().decode(OAJSON.self, from: jsonData)

        let sources = parsed.sources.map { s -> PriceSourceQuote in
            let (color, letter) = Self.brandPalette(for: s.name)
            return PriceSourceQuote(
                source: s.name,
                sourceColor: color,
                sourceLetter: letter,
                avgPriceEUR: Int(s.avg_price_eur.rounded()),
                lastSaleEUR: Int(s.last_sale_eur.rounded()),
                hoursAgo: max(0, s.hours_ago)
            )
        }
        let sales = parsed.recent_sales.map {
            RecentSaleEntry(
                priceEUR: Int($0.price_eur.rounded()),
                size: $0.size,
                source: $0.source,
                daysAgo: max(0, $0.days_ago)
            )
        }

        return MarketPriceSummary(
            query: name,
            avg: Int(parsed.avg_eur.rounded()),
            min: Int(parsed.min_eur.rounded()),
            max: Int(parsed.max_eur.rounded()),
            sources: sources,
            recentSales: sales
        )
    }

    /// Encuentra el primer objeto JSON balanceado dentro de un texto.
    private static func extractFirstJSONObject(in text: String) -> Range<String.Index>? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = start
        while index < text.endIndex {
            let c = text[index]
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 {
                    let end = text.index(after: index)
                    return start..<end
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Color y letra que se muestran para cada marketplace.
    private static func brandPalette(for name: String) -> (Color, String) {
        switch name.lowercased() {
        case "stockx":  return (Color(red: 0.00, green: 0.60, blue: 0.30), "X")
        case "goat":    return (Color.black, "g")
        case "ebay":    return (Color(red: 0.20, green: 0.50, blue: 0.95), "e")
        case "grailed": return (Color.black, "G")
        default:        return (Color.gray, String(name.prefix(1)).uppercased())
        }
    }

    // MARK: - Mock fallback

    private static func simulateLookup(for name: String) -> MarketPriceSummary {
        let lower = name.lowercased()
        let base: Int
        if lower.contains("jordan 1") && lower.contains("off") { base = 1_840 }
        else if lower.contains("travis") { base = 1_350 }
        else if lower.contains("jordan 1") { base = 420 }
        else if lower.contains("yeezy 350") { base = 320 }
        else if lower.contains("jordan 4") { base = 280 }
        else if lower.contains("dunk") { base = 180 }
        else if lower.contains("samba") { base = 130 }
        else if lower.contains("550") || lower.contains("new balance") { base = 190 }
        else if lower.contains("foam") { base = 140 }
        else { base = 250 }

        let sources: [PriceSourceQuote] = [
            PriceSourceQuote(source: "StockX", sourceColor: Color(red: 0.00, green: 0.60, blue: 0.30), sourceLetter: "X", avgPriceEUR: base + Int.random(in: 5...30), lastSaleEUR: base + Int.random(in: 0...20), hoursAgo: Int.random(in: 1...4)),
            PriceSourceQuote(source: "GOAT", sourceColor: Color.black, sourceLetter: "g", avgPriceEUR: base + Int.random(in: -15...15), lastSaleEUR: base + Int.random(in: -10...10), hoursAgo: Int.random(in: 2...8)),
            PriceSourceQuote(source: "eBay", sourceColor: Color(red: 0.20, green: 0.50, blue: 0.95), sourceLetter: "e", avgPriceEUR: base - Int.random(in: 10...40), lastSaleEUR: base - Int.random(in: 5...30), hoursAgo: Int.random(in: 6...24)),
            PriceSourceQuote(source: "Grailed", sourceColor: Color.black, sourceLetter: "G", avgPriceEUR: base - Int.random(in: 5...25), lastSaleEUR: base - Int.random(in: 0...15), hoursAgo: Int.random(in: 12...48)),
        ]

        let avg = sources.map(\.avgPriceEUR).reduce(0, +) / sources.count
        let prices = sources.flatMap { [$0.avgPriceEUR, $0.lastSaleEUR] }
        let minP = prices.min() ?? base
        let maxP = prices.max() ?? base

        let sizes = ["41", "41.5", "42", "42.5", "43", "44"]
        let sourceNames = ["StockX", "GOAT", "eBay", "Grailed"]
        let recents = (1...6).map { i in
            RecentSaleEntry(
                priceEUR: base + Int.random(in: -60...60),
                size: sizes.randomElement() ?? "42",
                source: sourceNames.randomElement() ?? "StockX",
                daysAgo: i + Int.random(in: 0...2)
            )
        }

        return MarketPriceSummary(
            query: name,
            avg: avg,
            min: minP,
            max: maxP,
            sources: sources,
            recentSales: recents
        )
    }
}

// MARK: - UI de la comparativa

struct PriceCompareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = SneakerPriceLookupService()
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue
    private var appLanguage: AppLanguage { AppLanguage(rawValue: appLanguageRaw) ?? .spanish }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerCard
                        searchField
                        if service.isSearching {
                            loadingView
                                .padding(.top, 30)
                        } else if let summary = service.summary {
                            summaryCard(summary)
                            sourcesCard(summary)
                            recentSalesCard(summary)
                        }
                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Color.black.opacity(0.65))
                            .frame(width: 32, height: 32)
                            .background {
                                Circle().fill(Color(red: 0.94, green: 0.96, blue: 0.99))
                            }
                    }
                }
            }
            .toolbarBackground(Color.white, for: .navigationBar)
            .navigationTitle(L10n.tr("price.compareTitle", lang: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.light)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.30, green: 0.55, blue: 0.95), Color(red: 0.14, green: 0.36, blue: 0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(L10n.tr("price.compareTitle", lang: appLanguage))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.92))
            }
            Text(L10n.tr("price.compareSubtitle", lang: appLanguage))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("Jordan 1, Yeezy 350, Dunk…")
                        .foregroundStyle(Color.black.opacity(0.42))
                )
                .focused($searchFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await service.lookup(searchText) } }
                .foregroundStyle(Color.black.opacity(0.88))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        service.summary = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.black.opacity(0.30))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                Capsule(style: .continuous)
                    .fill(Color(red: 0.95, green: 0.96, blue: 0.99))
            }

            Button {
                Task { await service.lookup(searchText) }
            } label: {
                Text(L10n.tr("price.lookup", lang: appLanguage))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color(red: 0.30, green: 0.55, blue: 0.95), Color(red: 0.14, green: 0.36, blue: 0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .shadow(color: Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(searchText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color(red: 0.20, green: 0.45, blue: 0.85))
                .scaleEffect(1.3)
            Text(L10n.tr("price.searching", lang: appLanguage))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryCard(_ s: MarketPriceSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(s.query)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(formatEUR(s.avg))
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.50, blue: 0.95), Color(red: 0.14, green: 0.36, blue: 0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            HStack(spacing: 14) {
                priceStat(label: L10n.tr("price.min", lang: appLanguage), value: formatEUR(s.min), color: Color(red: 0.20, green: 0.70, blue: 0.45))
                Divider().frame(height: 28)
                priceStat(label: L10n.tr("price.max", lang: appLanguage), value: formatEUR(s.max), color: Color(red: 0.92, green: 0.30, blue: 0.20))
                Divider().frame(height: 28)
                priceStat(label: L10n.tr("price.source", lang: appLanguage), value: "\(s.sources.count)", color: Color(red: 0.20, green: 0.45, blue: 0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 5)
        }
    }

    private func priceStat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.50))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func sourcesCard(_ s: MarketPriceSummary) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(s.sources.enumerated()), id: \.element.id) { idx, src in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(src.sourceColor)
                            .frame(width: 32, height: 32)
                        Text(src.sourceLetter)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(src.source)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.88))
                        Text("hace \(src.hoursAgo) h")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }

                    Spacer(minLength: 0)

                    Text(formatEUR(src.avgPriceEUR))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.88))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if idx < s.sources.count - 1 {
                    Divider().padding(.leading, 58)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
        }
    }

    private func recentSalesCard(_ s: MarketPriceSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("price.lastSales", lang: appLanguage).uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.black.opacity(0.48))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(s.recentSales.enumerated()), id: \.element.id) { idx, sale in
                    HStack(spacing: 10) {
                        Text(sale.source)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(Color.black.opacity(0.55))
                            .frame(width: 60, alignment: .leading)

                        Text("Talla \(sale.size)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.70))

                        Spacer(minLength: 0)

                        Text("hace \(sale.daysAgo) d")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.42))

                        Text(formatEUR(sale.priceEUR))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.88))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if idx < s.recentSales.count - 1 {
                        Divider().padding(.horizontal, 14)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
            }
        }
    }

    private func formatEUR(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: amount)) ?? "\(amount)")
    }
}

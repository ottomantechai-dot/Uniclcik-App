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
            Tab("Dashboard", systemImage: "square.grid.2x2.fill", value: UpsoledMainTab.home) {
                NavigationStack {
                    DashboardView()
                }
            }

            Tab("Closet", systemImage: "tshirt.fill", value: UpsoledMainTab.closet) {
                NavigationStack {
                    ClosetView()
                }
            }

            Tab("Collection", systemImage: "shoe.fill", value: UpsoledMainTab.cars) {
                NavigationStack {
                    CarsView()
                }
            }

            if soledTabRequestBadgeCount > 0 {
                Tab("Soled", systemImage: "shippingbox.fill", value: UpsoledMainTab.chat) {
                    NavigationStack {
                        SoldView()
                    }
                }
                .badge(soledTabRequestBadgeCount)
        } else {
                Tab("Soled", systemImage: "shippingbox.fill", value: UpsoledMainTab.chat) {
                    NavigationStack {
                        SoldView()
                    }
                }
            }

            if auth.canAccessIASection {
                Tab("Pricing Tier", systemImage: "dollarsign.circle.fill", value: UpsoledMainTab.ai) {
                    TeamAITabView()
                        .toolbar(.hidden, for: .tabBar)
                        .toolbarBackground(.hidden, for: .tabBar)
                }
            }

            Tab("Ajustes", systemImage: "gearshape.fill", value: UpsoledMainTab.settings) {
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
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            ContentUnavailableView(
                "Pricing Tier",
                systemImage: "dollarsign.circle",
                description: Text(
                    "El diseño de chat con IA ya no aparece aquí."
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
    @State private var searchText = ""
    @State private var filter: SoldFilter = .all
    @State private var didAppear = false
    @FocusState private var searchFocused: Bool

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
                                    "Sin ventas",
                                    systemImage: "checkmark.seal",
                                    description: Text("No hay ventas registradas en este periodo.")
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
            prompt: Text("Buscar venta")
                .foregroundStyle(Color.black.opacity(0.42)),
            showsSearchClearButton: true,
            searchFieldFocused: $searchFocused
        ) {
            HStack(spacing: AppChromeHeaderMetrics.hStackSpacing) {
                AppChromeHeaderCircleIconButton(
                    systemName: "arrow.up.arrow.down",
                    accessibilityLabel: "Ordenar",
                    action: {}
                )
                AppChromeHeaderCircleIconButton(
                    systemName: "line.3.horizontal.decrease",
                    accessibilityLabel: "Filtros",
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
                Text("Vendido este periodo")
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
                summaryStat(label: "Ventas", value: "\(filteredSales.count)", tint: Color(red: 0.20, green: 0.45, blue: 0.85))
                Divider().frame(height: 28)
                summaryStat(label: "Beneficio", value: formatUSD(totalProfit), tint: Color(red: 0.20, green: 0.70, blue: 0.45))
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
                    Text(f.label)
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
        f.locale = Locale(identifier: "es_ES")
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

private enum SoldFilter: CaseIterable {
    case all, thisMonth, topProfit

    var label: String {
        switch self {
        case .all: return "Todas"
        case .thisMonth: return "Este mes"
        case .topProfit: return "Top beneficio"
        }
    }
}

struct SoldSneakerRow: View {
    let sale: SoldSneakerMock

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
                    Text(sale.dateLabel)
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
        f.locale = Locale(identifier: "es_ES")
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

    var dateLabel: String {
        switch daysAgo {
        case 0: return "Hoy"
        case 1: return "Ayer"
        case 2...6: return "Hace \(daysAgo) días"
        case 7...13: return "Hace 1 semana"
        case 14...29: return "Hace \(daysAgo / 7) semanas"
        default: return "Hace \(daysAgo / 30) meses"
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

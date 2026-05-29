import SwiftUI
import SwiftData
import UIKit

// MARK: - Notificaciones entre pestañas (p. ej. abrir «Añadir» desde Inicio)

extension Notification.Name {
    /// Abre el mismo sheet de entrada que el botón + del stock (clóset).
    static let upsoledPresentAddToClosetMenu = Notification.Name("Upsoled.presentAddToClosetMenu")
}

enum UpsoledMainTab: Hashable {
    case home
    case closet
    case add
    case chat
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

    private func presentAddToClosetFlowFromTabBar() {
        ClosetAnalytics.named("add_to_closet_opened")
        tabRouter.selected = .closet
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .upsoledPresentAddToClosetMenu, object: nil)
        }
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
        .onChange(of: tabRouter.selected) { _, new in
            if new == .add {
                presentAddToClosetFlowFromTabBar()
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
            Tab(L10n.tr("tab.dashboard"), systemImage: "square.grid.2x2.fill", value: UpsoledMainTab.home) {
                NavigationStack {
                    DashboardView()
                }
            }

            Tab(L10n.tr("tab.closet"), systemImage: "archivebox.fill", value: UpsoledMainTab.closet) {
                NavigationStack {
                    ClosetView()
                }
            }

            Tab(value: UpsoledMainTab.add) {
                NavigationStack {
                    UpsoledAddTabPlaceholderView()
                }
            } label: {
                Label {
                    Text(L10n.tr("dashboard.quickAdd"))
                } icon: {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black)
                }
            }

            // Pestaña Marketplace: lista los productos `upsoled_products` de Supabase,
            // compartidos con la web Sneak Peek Miami. El usuario puede crear nuevos
            // productos desde aquí (botón `+` arriba a la derecha del view).
            if soledTabRequestBadgeCount > 0 {
                Tab(L10n.tr("tab.soled"), systemImage: "bag.fill", value: UpsoledMainTab.chat) {
                    UpsoledProductsView()
                }
                .badge(soledTabRequestBadgeCount)
            } else {
                Tab(L10n.tr("tab.soled"), systemImage: "bag.fill", value: UpsoledMainTab.chat) {
                    UpsoledProductsView()
                }
            }

            Tab(L10n.tr("tab.settings"), systemImage: "gearshape.fill", value: UpsoledMainTab.settings) {
        NavigationStack {
                    SettingsView()
                }
            }
        }
    }
}

/// Contenido mínimo de la pestaña «Añadir»; al pulsarla `onChange` en `MainTabView` cambia ya a Tu stock y abre el sheet.
private struct UpsoledAddTabPlaceholderView: View {
    var body: some View {
        Color.white
            .ignoresSafeArea()
            .accessibilityHidden(true)
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
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<ClosetItem> { $0.isSold == true && $0.soldAt != nil },
        sort: \ClosetItem.soldAt,
        order: .reverse
    )
    private var soldItems: [ClosetItem]

    @State private var searchText = ""
    @State private var filter: SoldFilter = .all
    @State private var didAppear = false
    @FocusState private var searchFocused: Bool

    private var filteredSales: [ClosetItem] {
        let base = soldItems.filter { item in
            switch filter {
            case .all: return true
            case .thisMonth: return item.soldDaysAgo <= 30
            case .topProfit: return item.stockValueUSD >= 200
            }
        }
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter { item in
            let brand = item.brand ?? ""
            let color = item.colorLabel ?? ""
            return "\(brand) \(item.name) \(color)".lowercased().contains(q)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    soldTopBar
                        .appChromeHeaderOuterPadding()
                        .environment(\.dashboardLightSurface, true)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 18) {
                            filterPicker
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .modifier(SoldEntranceAnimation(didAppear: didAppear, delay: 0.05))

                            if filteredSales.isEmpty {
                                soldEmptyIllustratedState
                                    .modifier(SoldEntranceAnimation(didAppear: didAppear, delay: 0.15))
                                    .frame(maxWidth: .infinity, minHeight: max(260, geo.size.height - 400))
                            } else {
                                LazyVStack(spacing: 12) {
                                    ForEach(filteredSales) { item in
                                        SoldClosetItemRow(item: item) {
                                            restoreItemToStock(item)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .modifier(SoldEntranceAnimation(didAppear: didAppear, delay: 0.15))
                            }
                        }
                        .padding(.bottom, 36)
                    }
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

    /// Ilustración de vacío (`caja`, mismo arte que App Icon) + copy localizada.
    private var soldEmptyIllustratedState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            Image("SoldEmptyCaja")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 240)
                .accessibilityHidden(true)

            Text(L10n.tr("sold.emptyTitle"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.92))

            Text(L10n.tr("sold.emptyDesc"))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.52))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private var soldTopBar: some View {
        ChromeSearchTrailingHeaderRow(
            searchText: $searchText,
            prompt: Text(L10n.tr("sold.searchPrompt"))
                .foregroundStyle(Color.black.opacity(0.42)),
            showsSearchClearButton: true,
            searchFieldFocused: $searchFocused
        ) {
            HStack(spacing: AppChromeHeaderMetrics.hStackSpacing) {
                AppChromeHeaderCircleIconButton(
                    systemName: "arrow.up.arrow.down",
                    accessibilityLabel: LocalizedStringKey(L10n.tr("common.sort")),
                    action: {}
                )
                AppChromeHeaderCircleIconButton(
                    systemName: "line.3.horizontal.decrease",
                    accessibilityLabel: LocalizedStringKey(L10n.tr("common.filters")),
                    action: {}
                )
            }
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
                    Text(f.label())
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

    private func restoreItemToStock(_ item: ClosetItem) {
        item.isSold = false
        item.soldAt = nil
        try? modelContext.save()
    }
}

private enum SoldFilter: CaseIterable {
    case all, thisMonth, topProfit

    func label() -> String {
        switch self {
        case .all: return L10n.tr("sold.filterAll")
        case .thisMonth: return L10n.tr("sold.filterMonth")
        case .topProfit: return L10n.tr("sold.filterTop")
        }
    }
}

struct SoldClosetItemRow: View {
    let item: ClosetItem
    var onRestoreToStock: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 92, height: 92)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    }

                if let ui = ImageStore.load(ImageStore.displayRelativePath(for: item)) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .frame(width: 92, height: 92)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.black.opacity(0.25))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text((item.brand ?? "Unknown Brand").uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.black.opacity(0.55))

                Text(item.catalogDisplayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let sku = item.cardSKULabel {
                    Text("SKU \(sku)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.55))
                }

                HStack(spacing: 6) {
                    if let size = item.cardSizeLabel {
                        Text(size)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.55))
                        Text("·")
                            .foregroundStyle(Color.black.opacity(0.30))
                    }
                    Text(item.soldDateLabel())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                if let price = item.cardPriceLabel {
                    Text(price)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.88))
                }

                if item.hasPricingForProfit {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let usd = item.cardProfitUSDLabel {
                            HStack(spacing: 3) {
                                Image(systemName: item.isProjectedLoss ? "arrow.down.right" : "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                                Text(usd)
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        if let pct = item.cardProfitPercentLabel {
                            Text(pct)
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .foregroundStyle(item.isProjectedLoss ? Color(red: 0.92, green: 0.30, blue: 0.30) : Color(red: 0.20, green: 0.70, blue: 0.45))
                }

                Button(action: onRestoreToStock) {
                    Text(L10n.tr("sold.undoSold"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                }
                .buttonStyle(.plain)
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
                    Text(sale.dateLabel())
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
        f.locale = Locale(identifier: "en_US")
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

    func dateLabel() -> String {
        switch daysAgo {
        case 0:
            return L10n.tr("sold.today")
        case 1:
            return L10n.tr("sold.yesterday")
        case 2...6:
            return String(format: L10n.tr("sold.daysAgo"), String(daysAgo))
        case 7...13:
            return L10n.tr("sold.oneWeekAgo")
        case 14...29:
            return String(format: L10n.tr("sold.weeksAgo"), String(daysAgo / 7))
        default:
            return String(format: L10n.tr("sold.monthsAgo"), String(daysAgo / 30))
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


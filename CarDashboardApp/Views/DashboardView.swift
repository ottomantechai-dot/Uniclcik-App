import SwiftUI
import SwiftData
import UIKit
import Combine

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var carsVM: CarsViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter
    @Query(sort: \ClosetItem.createdAt, order: .reverse) private var closetItems: [ClosetItem]
    @StateObject private var vm = DealershipStatsViewModel()
    @StateObject private var homeCatalogVM = UpsoledProductsViewModel()
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator
    @StateObject private var locationHub = DashboardLocationHub()
    @State private var didAppear = false
    @State private var homeStatsReady = false
    @State private var homeMarketComparison: MarketComparison?
    @State private var selectedTrendingID: String?
    @State private var homeStatsRefreshTask: Task<Void, Never>?

    private var trendingHighlights: [HomeSneakerHighlight] {
        HomeScreenDataBuilder.trendingHighlights(
            closet: closetItems,
            catalog: homeCatalogVM.products,
            limit: 4
        )
    }

    private var homeMarketLookupKey: String {
        resolvedMarketLookup().map { "\($0.sourceID ?? "legacy")|\($0.query)|\($0.fallback ?? "")" } ?? ""
    }

    private var closetInventoryFingerprint: String {
        closetItems.map { item in
            "\(item.id.uuidString):\(item.isSold):\(Int(item.stockValueUSD)):\(item.priceText ?? ""):\(item.marketPriceJSON ?? "")"
        }.joined(separator: "|")
    }

    var body: some View {
        dashboardContent
            .onAppear(perform: handleDashboardAppear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.dashboardLightSurface, true)
            .preferredColorScheme(.light)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: auth.session?.user.id) {
                if let uid = auth.session?.user.id {
                    await chatInbox.refreshCoordinatorTasksFromServer(currentUserId: uid)
                }
            }
            .onAppear {
                locationHub.onLocationForUpload = { coord in
                    Task { await communityVM.uploadMyCoordinate(coord) }
                }
                locationHub.requestWhenInUseAndStart()
            }
            .onDisappear { locationHub.stopUpdates() }
            .task { await performHomeStatsRefresh(replayAnimations: true) }
            .onChange(of: carsVM.cars) { _, _ in scheduleHomeStatsRefresh() }
            .onChange(of: closetItems.count) { _, _ in scheduleHomeStatsRefresh() }
            .onChange(of: closetInventoryFingerprint) { _, _ in scheduleHomeStatsRefresh() }
            .onReceive(inventoryRefreshPublisher) { _ in scheduleHomeStatsRefresh() }
            .task(id: "\(homeMarketLookupKey)|\(closetInventoryFingerprint)") {
                await loadHomeMarketTable()
            }
    }

    private func scheduleHomeStatsRefresh() {
        homeStatsRefreshTask?.cancel()
        homeStatsRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await performHomeStatsRefresh(replayAnimations: false)
        }
    }

    private var inventoryRefreshPublisher: AnyPublisher<Notification, Never> {
        NotificationCenter.default.publisher(for: .upsoledCatalogDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .closetInventoryDidChange))
            .eraseToAnyPublisher()
    }

    private var dashboardContent: some View {
        ZStack {
            DashboardHomePalette.pageBG.ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if homeStatsReady {
                        DashboardHomeScreen(
                            closetItems: closetItems,
                            catalogProducts: homeCatalogVM.products,
                            marketComparison: homeMarketComparison,
                            selectedTrendingID: $selectedTrendingID,
                            onViewStock: { tabRouter.selected = .closet }
                        )
                        .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.05))
                    } else {
                        homeStatsLoadingPlaceholder
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
    }

    private var homeStatsLoadingPlaceholder: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(height: 200)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(height: 140)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(height: 220)
        }
        .redacted(reason: .placeholder)
        .overlay {
            ProgressView()
                .controlSize(.regular)
        }
    }

    private func handleDashboardAppear() {
        didAppear = true
    }

    @MainActor
    private func performHomeStatsRefresh(replayAnimations: Bool) async {
        homeCatalogVM.fetchLimit = 750
        await homeCatalogVM.reload()
        vm.refreshFromInventory(
            cars: carsVM.cars,
            closetItems: closetItems,
            catalogProducts: homeCatalogVM.products,
            replayAnimations: replayAnimations
        )
        homeStatsReady = true
    }

    @MainActor
    private func loadHomeMarketTable() async {
        guard let lookup = resolvedMarketLookup() else {
            homeMarketComparison = nil
            return
        }

        if KicksDBClient.isConfigured {
            do {
                if let comparison = try await KicksDBClient.fetchComparison(
                    query: lookup.query,
                    fallbackQuery: lookup.fallback
                ) {
                    homeMarketComparison = await HomeMarketTableBuilder.prepareHomeComparison(
                        from: comparison,
                        query: lookup.query
                    )
                    return
                }
            } catch {
                #if DEBUG
                print("[Home] KicksDB market table: \(error.localizedDescription)")
                #endif
            }
        }

        if let sourceID = lookup.sourceID,
           let item = trendingHighlights.first(where: { $0.id == sourceID }),
           let cached = Self.cachedMarketComparison(for: item) {
            homeMarketComparison = Self.homeReadyComparison(from: cached)
            return
        }

        if let cached = Self.cachedMarketComparison(closetItems: closetItems) {
            homeMarketComparison = Self.homeReadyComparison(from: cached)
        } else {
            homeMarketComparison = nil
        }
    }

    private func resolvedMarketLookup() -> (query: String, fallback: String?, sourceID: String?)? {
        let trending = trendingHighlights

        if let selectedTrendingID,
           let item = trending.first(where: { $0.id == selectedTrendingID }),
           let lookup = item.marketLookup {
            return (lookup.query, lookup.fallback, item.id)
        }

        if let item = trending.first(where: { $0.marketLookup != nil }),
           let lookup = item.marketLookup {
            return (lookup.query, lookup.fallback, item.id)
        }

        if let legacy = Self.featuredMarketLookup(
            closetItems: closetItems,
            catalog: homeCatalogVM.products
        ) {
            return (legacy.query, legacy.fallback, nil)
        }

        return nil
    }

    private static func homeReadyComparison(from cached: MarketComparison) -> MarketComparison {
        let rows = HomeMarketTableBuilder.buildHomeRows(from: cached)
        return MarketComparison(
            query: cached.query,
            platforms: cached.platforms,
            sizes: rows.map(\.size),
            rows: rows,
            fetchedAt: cached.fetchedAt,
            skuAligned: cached.skuAligned
        )
    }

    /// Precios cacheados del inventario cuando KicksDB no está disponible.
    private static func cachedMarketComparison(for item: HomeSneakerHighlight) -> MarketComparison? {
        guard let closet = item.closetItem,
              let marketPrice = closet.marketPrice,
              !marketPrice.platforms.isEmpty else { return nil }

        let sizeRaw = marketPrice.sizeUsed?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? closet.sizeText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let size = sizeRaw.isEmpty ? "Avg" : sizeRaw

        var asks: [String: Double] = [:]
        for platform in marketPrice.platforms {
            asks[platform.name] = Double(platform.avg)
        }

        guard !asks.isEmpty else { return nil }

        return MarketComparison(
            query: closet.resolvedSKU ?? closet.marketLookupQuery,
            platforms: [],
            sizes: [size],
            rows: [MarketSizeRow(size: size, asks: asks)],
            fetchedAt: closet.marketPriceFetchedAt ?? Date(),
            skuAligned: true
        )
    }

    /// Precios cacheados del inventario cuando KicksDB no está disponible.
    private static func cachedMarketComparison(closetItems: [ClosetItem]) -> MarketComparison? {
        guard let item = closetItems.first(where: {
            $0.isActiveInStock && $0.category == .shoes && $0.marketPrice != nil && !($0.marketPrice?.platforms.isEmpty ?? true)
        }), let marketPrice = item.marketPrice else { return nil }

        let sizeRaw = marketPrice.sizeUsed?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? item.sizeText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let size = sizeRaw.isEmpty ? "Avg" : sizeRaw

        var asks: [String: Double] = [:]
        for platform in marketPrice.platforms {
            asks[platform.name] = Double(platform.avg)
        }

        guard !asks.isEmpty else { return nil }

        return MarketComparison(
            query: item.resolvedSKU ?? item.marketLookupQuery,
            platforms: [],
            sizes: [size],
            rows: [MarketSizeRow(size: size, asks: asks)],
            fetchedAt: item.marketPriceFetchedAt ?? Date(),
            skuAligned: true
        )
    }

    private static func featuredMarketLookup(
        closetItems: [ClosetItem],
        catalog: [UpsoledProduct]
    ) -> (query: String, fallback: String?)? {
        if let item = closetItems.first(where: {
            $0.isActiveInStock && $0.hasStyleForMarketLookup && $0.category == .shoes
        }) {
            let query = item.resolvedSKU ?? item.marketLookupQuery
            guard !query.isEmpty else { return nil }
            return (query, item.catalogDisplayName)
        }

        if let product = catalog.first(where: {
            let sku = $0.sku?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !sku.isEmpty
        }) {
            let sku = product.sku?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (sku, product.name)
        }

        if let item = closetItems.first(where: { $0.isActiveInStock && $0.hasStyleForMarketLookup }) {
            let query = item.resolvedSKU ?? item.marketLookupQuery
            guard !query.isEmpty else { return nil }
            return (query, item.catalogDisplayName)
        }

        return nil
    }
}

// MARK: - Animaciones reutilizables

/// Aplica fade + slide-up con delay para entrada escalonada de cada sección.
private struct EntranceAnimation: ViewModifier {
    let didAppear: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(didAppear ? 1 : 0.92)
            .offset(y: didAppear ? 0 : 6)
            .animation(.easeOut(duration: 0.35).delay(delay), value: didAppear)
    }
}

/// Count-up animado para montos en USD (hero KPIs).
struct DashboardCountUpCurrency: View {
    let target: Double
    let trigger: UUID
    var fontSize: CGFloat = 30

    @State private var animatedAmount: Double = 0

    var body: some View {
        CountUpCurrencyLabel(amount: animatedAmount, fontSize: fontSize)
            .onAppear { runCountUp(to: target) }
            .onChange(of: target) { _, newValue in runCountUp(to: newValue) }
            .onChange(of: trigger) { _, _ in runCountUp(to: target) }
    }

    private func runCountUp(to value: Double) {
        guard abs(animatedAmount - value) > 0.5 else { return }
        let duration = animatedAmount == 0 ? 0.85 : 0.35
        withAnimation(.easeOut(duration: duration)) {
            animatedAmount = value
        }
    }
}

private struct CountUpCurrencyLabel: View, Animatable {
    var amount: Double
    var fontSize: CGFloat

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    var body: some View {
        Text(DealershipStatsViewModel.formatUSD(amount))
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.92))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
    }
}

/// Sparkline con reveal horizontal al aparecer o al refrescar datos.
private struct DashboardAnimatedSparkline: View {
    let points: [Double]
    let isUp: Bool
    let trigger: UUID

    @State private var reveal: CGFloat = 0
    @State private var dotPulse = false

    var body: some View {
        PriceTrendSparkline(points: points, isUp: isUp)
            .mask(alignment: .leading) {
                Rectangle()
                    .scaleEffect(x: reveal, y: 1, anchor: .leading)
            }
            .overlay(alignment: .trailing) {
                if reveal > 0.95 {
                    Circle()
                        .fill(isUp
                            ? Color(red: 0.20, green: 0.70, blue: 0.45)
                            : Color(red: 0.92, green: 0.30, blue: 0.30))
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotPulse ? 1.25 : 0.85)
                        .opacity(dotPulse ? 0.85 : 1)
                        .animation(
                            .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                            value: dotPulse
                        )
                        .offset(x: -2)
                }
            }
            .onAppear { runReveal() }
            .onChange(of: trigger) { _, _ in runReveal() }
            .onChange(of: points.count) { _, _ in runReveal() }
    }

    private func runReveal() {
        reveal = 0
        dotPulse = false
        withAnimation(.easeOut(duration: 1.15)) {
            reveal = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dotPulse = true
        }
    }
}

/// Badge de tendencia con pop-in al cargar.
private struct DashboardAnimatedTrendBadge: View {
    let changePercent: Double
    let isUp: Bool
    var compact: Bool = false
    let trigger: UUID

    @State private var visible = false

    var body: some View {
        trendBadgeContent
            .scaleEffect(visible ? 1 : 0.6)
            .opacity(visible ? 1 : 0)
            .onAppear { animateIn() }
            .onChange(of: trigger) { _, _ in animateIn() }
    }

    private func animateIn() {
        visible = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72).delay(0.25)) {
            visible = true
        }
    }

    private var trendBadgeContent: some View {
        let tint = isUp
            ? Color(red: 0.20, green: 0.70, blue: 0.45)
            : Color(red: 0.92, green: 0.30, blue: 0.30)

        return HStack(spacing: 3) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: compact ? 8 : 9, weight: .heavy))
            Text(DealershipStatsViewModel.formatChangePercent(changePercent))
                .font(.system(size: compact ? 9 : 11, weight: .heavy, design: .rounded))
                .contentTransition(.numericText(value: changePercent))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

// MARK: - Backdrop claro (no usado actualmente — se mantiene por si se reactiva)

/// Fondo claro tipo UPSOLED. Sustituye `DashboardHomeBackdropImage` (video oscuro)
/// pero NO modifica ninguno de los modificadores `.ultraThinMaterial` / glass
/// presentes en la jerarquía superior, así que las tarjetas glass siguen
/// renderizándose como frosted glass sobre el fondo blanco.
struct DashboardHomeLightBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.99, blue: 1.00),
                Color(red: 0.93, green: 0.96, blue: 1.00),
                Color(red: 0.99, green: 0.99, blue: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Stats Overview (KPIs principales)

private struct DashboardStatsOverview: View {
    @ObservedObject var stats: DealershipStatsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            dashboardPeriodHeader

            VStack(spacing: 12) {
                heroKPICard(
                    title: L10n.tr("dashboard.totalStock"),
                    amount: stats.totalStockValueAmount,
                    subtitle: stats.totalStockBadge.isEmpty
                        ? nil
                        : "\(stats.totalStockBadge) · \(stats.marketCoverageLabel)",
                    changePercent: stats.stockValueChangePercent,
                    isUp: stats.stockValueIsUp,
                    chartIsUp: stats.stockValueIsUp,
                    history: stats.stockValueHistory,
                    icon: "chart.line.uptrend.xyaxis"
                )

                heroKPICard(
                    title: "Total invested",
                    amount: stats.totalInvestedAmount,
                    subtitle: "Unrealized \(stats.unrealizedGainLabel)",
                    subtitleTint: unrealizedSubtitleTint(stats.unrealizedGainAmount),
                    changePercent: stats.investedChangePercent,
                    isUp: stats.investedIsUp,
                    chartIsUp: stats.stockValueIsUp,
                    history: stats.stockValueHistory,
                    icon: "creditcard.fill"
                )
            }
        }
    }

    private var dashboardPeriodHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))
                Text("vs \(stats.comparisonDateLabel)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
            Spacer(minLength: 0)
            Text(stats.periodDisplayLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.06)))
        }
    }

    private func unrealizedSubtitleTint(_ amount: Double) -> Color {
        if amount == 0 { return Color.black.opacity(0.48) }
        return amount > 0
            ? Color(red: 0.20, green: 0.70, blue: 0.45)
            : Color(red: 0.92, green: 0.30, blue: 0.30)
    }

    private func heroKPICard(
        title: String,
        amount: Double,
        subtitle: String?,
        subtitleTint: Color? = nil,
        changePercent: Double,
        isUp: Bool,
        chartIsUp: Bool? = nil,
        history: [Double],
        icon: String
    ) -> some View {
        let sparkIsUp = chartIsUp ?? isUp
        let tint = sparkIsUp
            ? Color(red: 0.20, green: 0.70, blue: 0.45)
            : Color(red: 0.92, green: 0.30, blue: 0.30)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                Spacer(minLength: 0)
                if abs(changePercent) >= 0.5 {
                    DashboardAnimatedTrendBadge(
                        changePercent: changePercent,
                        isUp: isUp,
                        trigger: stats.statsAnimationToken
                    )
                }
            }

            DashboardCountUpCurrency(
                target: amount,
                trigger: stats.statsAnimationToken
            )

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(subtitleTint ?? Color.black.opacity(0.48))
            }

            if history.count >= 2 {
                DashboardAnimatedSparkline(
                    points: history,
                    isUp: sparkIsUp,
                    trigger: stats.statsAnimationToken
                )
                .frame(height: 44)
            } else if amount > 0 {
                DashboardAnimatedSparkline(
                    points: [amount * 0.8, amount * 0.9, amount],
                    isUp: true,
                    trigger: stats.statsAnimationToken
                )
                .frame(height: 44)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.08))
                    .frame(height: 44)
                    .overlay {
                        Text("Add items to track your portfolio")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.38))
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
            .environmentObject(AuthViewModel())
            .environmentObject(CarsViewModel())
            .environmentObject(MainTabRouter())
            .environmentObject(ChatNavigationCoordinator())
            .environmentObject(ChatInboxStore())
            .environmentObject(DashboardCommunityViewModel())
            .environmentObject(InvoiceHistoryStore())
    }
}

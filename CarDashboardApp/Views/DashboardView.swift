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
            .task { await refreshHomeStats() }
            .task(id: carsVM.cars.count) { await refreshHomeStats() }
            .onChange(of: carsVM.cars) { _, _ in Task { await refreshHomeStats() } }
            .onChange(of: closetItems.count) { _, _ in Task { await refreshHomeStats() } }
            .onChange(of: closetInventoryFingerprint) { _, _ in Task { await refreshHomeStats() } }
            .onChange(of: homeCatalogVM.products.count) { _, _ in
                vm.refreshFromInventory(
                    cars: carsVM.cars,
                    closetItems: closetItems,
                    catalogProducts: homeCatalogVM.products
                )
            }
            .onReceive(inventoryRefreshPublisher) { _ in
                Task { await refreshHomeStats() }
            }
    }

    private var inventoryRefreshPublisher: AnyPublisher<Notification, Never> {
        NotificationCenter.default.publisher(for: .upsoledCatalogDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .closetInventoryDidChange))
            .eraseToAnyPublisher()
    }

    private var dashboardContent: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    dashboardScreenHeader
                    DashboardStatsOverview(stats: vm, didAppear: didAppear)
                        .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.05))
                    DashboardLatestSaleSection(closetItems: closetItems, cars: carsVM.cars)
                        .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.15))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
    }

    private var dashboardScreenHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(L10n.tr("tab.dashboard"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                tabRouter.selected = .add
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black)
            }
            .accessibilityLabel(L10n.tr("dashboard.quickAdd"))
        }
        .padding(.bottom, 4)
    }

    private func handleDashboardAppear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            didAppear = true
        }
    }

    @MainActor
    private func refreshHomeStats() async {
        homeCatalogVM.fetchLimit = 750
        await homeCatalogVM.reload()
        vm.refreshFromInventory(
            cars: carsVM.cars,
            closetItems: closetItems,
            catalogProducts: homeCatalogVM.products
        )
    }
}

// MARK: - Animaciones reutilizables

/// Aplica fade + slide-up con delay para entrada escalonada de cada sección.
private struct EntranceAnimation: ViewModifier {
    let didAppear: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(didAppear ? 1 : 0)
            .offset(y: didAppear ? 0 : 18)
            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay), value: didAppear)
    }
}

/// Count-up animado para montos en USD (hero KPIs).
private struct DashboardCountUpCurrency: View {
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
        animatedAmount = 0
        withAnimation(.easeOut(duration: 1.05)) {
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

/// Entrada escalonada para tarjetas de categoría y métricas.
private struct StaggeredCardEntrance: ViewModifier {
    let index: Int
    let didAppear: Bool
    let trigger: UUID

    @State private var cardVisible = false

    private var delay: Double { Double(index) * 0.07 + 0.12 }

    func body(content: Content) -> some View {
        content
            .opacity(cardVisible ? 1 : 0)
            .offset(y: cardVisible ? 0 : 14)
            .scaleEffect(cardVisible ? 1 : 0.94)
            .onAppear { playEntrance() }
            .onChange(of: didAppear) { _, appeared in
                if appeared { playEntrance() }
            }
            .onChange(of: trigger) { _, _ in playEntrance() }
    }

    private func playEntrance() {
        cardVisible = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(delay)) {
            cardVisible = true
        }
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
    var didAppear: Bool = true

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

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
                    history: stats.stockValueHistory,
                    icon: "chart.line.uptrend.xyaxis"
                )

                heroKPICard(
                    title: "Total invested",
                    amount: stats.totalInvestedAmount,
                    subtitle: "Unrealized \(stats.unrealizedGainLabel)",
                    changePercent: stats.investedChangePercent,
                    isUp: stats.investedIsUp,
                    history: stats.stockValueHistory,
                    icon: "creditcard.fill"
                )
            }

            if let snapshot = stats.marketSnapshot {
                DashboardPortfolioMarketCard(
                    snapshot: snapshot,
                    animationToken: stats.statsAnimationToken
                )
                .modifier(StaggeredCardEntrance(
                    index: 0,
                    didAppear: didAppear,
                    trigger: stats.statsAnimationToken
                ))
            }

            if !stats.categorySnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("By category")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))

                    HStack(spacing: 10) {
                        ForEach(Array(stats.categorySnapshots.enumerated()), id: \.element.id) { index, row in
                            categoryMiniCard(row)
                                .modifier(StaggeredCardEntrance(
                                    index: index,
                                    didAppear: didAppear,
                                    trigger: stats.statsAnimationToken
                                ))
                        }
                    }
                }
            }

            if !stats.metricTiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Performance")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(stats.metricTiles.enumerated()), id: \.element.id) { index, tile in
                            metricTileCard(tile)
                                .modifier(StaggeredCardEntrance(
                                    index: index,
                                    didAppear: didAppear,
                                    trigger: stats.statsAnimationToken
                                ))
                        }
                    }
                }
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

    private func heroKPICard(
        title: String,
        amount: Double,
        subtitle: String?,
        changePercent: Double,
        isUp: Bool,
        history: [Double],
        icon: String
    ) -> some View {
        let tint = isUp
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
                DashboardAnimatedTrendBadge(
                    changePercent: changePercent,
                    isUp: isUp,
                    trigger: stats.statsAnimationToken
                )
            }

            DashboardCountUpCurrency(
                target: amount,
                trigger: stats.statsAnimationToken
            )

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.48))
            }

            if history.count >= 2 {
                DashboardAnimatedSparkline(
                    points: history,
                    isUp: isUp,
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

    private func categoryMiniCard(_ row: DashboardCategorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: row.segment.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))

            Text(row.segment.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.50))
                .lineLimit(1)

            DashboardCountUpCurrency(
                target: row.valueUSD,
                trigger: stats.statsAnimationToken,
                fontSize: 14
            )

            if let change = row.changePercent {
                DashboardAnimatedTrendBadge(
                    changePercent: change,
                    isUp: row.isUp,
                    compact: true,
                    trigger: stats.statsAnimationToken
                )
            } else {
                Text("\(row.itemCount) items")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.40))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
    }

    private func metricTileCard(_ tile: DashboardMetricTile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: tile.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                    .frame(width: 28, height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.10))
                    }
                Spacer(minLength: 0)
                if let change = tile.changePercent {
                    DashboardAnimatedTrendBadge(
                        changePercent: change,
                        isUp: tile.isUp,
                        compact: true,
                        trigger: stats.statsAnimationToken
                    )
                }
            }

            Text(tile.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.50))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(tile.value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.92))
                .minimumScaleFactor(0.75)
                .lineLimit(2)
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: tile.value)

            if let subtitle = tile.subtitle {
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
        }
    }
}

// MARK: - Portfolio market price (Home statistics)

private struct DashboardPortfolioMarketCard: View {
    let snapshot: DashboardMarketSnapshot
    let animationToken: UUID

    private var tint: Color {
        snapshot.isUp
            ? Color(red: 0.20, green: 0.70, blue: 0.45)
            : Color(red: 0.92, green: 0.30, blue: 0.30)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.30, green: 0.55, blue: 0.95),
                                Color(red: 0.14, green: 0.36, blue: 0.85),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("MARKET PRICE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.black.opacity(0.55))
                Spacer(minLength: 0)
                if snapshot.trackedCount > 0 {
                    Text("\(snapshot.trackedCount) tracked")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.38))
                }
            }

            HStack(spacing: 6) {
                Image(systemName: snapshot.hasPlatformBreakdown ? "checkmark.seal.fill" : "chart.bar.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.75))
                Text(snapshot.headline)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                Spacer(minLength: 0)
            }
            .padding(.top, -2)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        DashboardCountUpCurrency(
                            target: snapshot.totalLiveValueUSD,
                            trigger: animationToken
                        )
                        Text("average")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(Color.black.opacity(0.45))
                            .padding(.bottom, 4)
                    }
                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(red: 0.18, green: 0.65, blue: 0.40))
                            Text("From \(DealershipStatsViewModel.formatUSD(snapshot.minUSD))")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.70))
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.35))
                            Text("Up to \(DealershipStatsViewModel.formatUSD(snapshot.maxUSD))")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.45))
                        }
                    }
                }

                Spacer(minLength: 0)

                DashboardAnimatedTrendBadge(
                    changePercent: snapshot.changePercent,
                    isUp: snapshot.isUp,
                    trigger: animationToken
                )
            }

            if snapshot.history.count >= 2 {
                DashboardAnimatedSparkline(
                    points: snapshot.history,
                    isUp: snapshot.isUp,
                    trigger: animationToken
                )
                .frame(height: 48)
            }

            if snapshot.hasPlatformBreakdown {
                HStack(spacing: 8) {
                    ForEach(snapshot.platforms) { platform in
                        PlatformPriceTag(
                            platform: platform,
                            formatted: PieceMarketPrice.formatUSD(platform.avg)
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.08), .clear],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.35),
                                Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.15),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .shadow(color: tint.opacity(0.12), radius: 14, y: 5)
            .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
        }
    }
}

// MARK: - Última venta

private struct DashboardLatestSaleSection: View {
    let closetItems: [ClosetItem]
    let cars: [Car]

    private var latestSold: ClosetItem? {
        closetItems
            .filter(\.isExplicitlySold)
            .sorted { ($0.soldAt ?? $0.createdAt) > ($1.soldAt ?? $1.createdAt) }
            .first
    }

    private var featuredCar: Car? {
        cars
            .filter { ($0.listPriceUSD ?? 0) > 0 }
            .sorted { ($0.listPriceUSD ?? 0) > ($1.listPriceUSD ?? 0) }
            .first
            ?? cars.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("dashboard.lastSale"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                Spacer()
            }

            if let sold = latestSold {
                soldItemRow(sold)
            } else if let car = featuredCar {
                carRow(car)
            } else {
                emptyRow
            }
        }
    }

    private func soldItemRow(_ item: ClosetItem) -> some View {
        let profit = item.projectedProfitUSD
        let isUp = profit >= 0

        return HStack(alignment: .center, spacing: 16) {
            itemThumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(item.catalogDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineLimit(2)

                Text(item.cardPriceLabel ?? "—")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))

                if item.hasPricingForProfit {
                    HStack(spacing: 6) {
                        Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isUp
                                ? Color(red: 0.20, green: 0.70, blue: 0.45)
                                : Color(red: 0.92, green: 0.30, blue: 0.30))
                        Text(item.cardProfitUSDLabel ?? "")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isUp
                                ? Color(red: 0.20, green: 0.70, blue: 0.45)
                                : Color(red: 0.92, green: 0.30, blue: 0.30))
                        Text("· \(item.soldDateLabel())")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.42))
                    }
                } else {
                    Text(item.soldDateLabel())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.42))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(cardBackground)
    }

    private func carRow(_ car: Car) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.92, green: 0.96, blue: 1.0),
                                Color(red: 0.82, green: 0.90, blue: 1.0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                Image("AuthSneakerHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(featuredCarTitle(car))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineLimit(2)
                Text(featuredCarPrice(car))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var emptyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.slash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.25))
            Text(L10n.tr("dashboard.noItems"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.45))
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var itemThumbnail: some View {
        Group {
            if let path = itemImagePath(for: latestSold),
               let uiImage = StockImageLoader.cachedLocalImage(relativePath: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("AuthSneakerHero")
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            }
        }
        .frame(width: 72, height: 72)
        .background(Color(red: 0.94, green: 0.96, blue: 0.99))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white)
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func itemImagePath(for item: ClosetItem?) -> String? {
        guard let item else { return nil }
        if let cover = item.galleryCoverRelativePath, !cover.isEmpty { return cover }
        return item.imageFilename
    }

    private func featuredCarTitle(_ car: Car) -> String {
        let brand = car.brandName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nm = car.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = "\(brand) \(nm)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? L10n.tr("dashboard.item") : combined
    }

    private func featuredCarPrice(_ car: Car) -> String {
        guard let p = car.listPriceUSD, p > 0 else { return DealershipStatsViewModel.formatUSD(0) }
        return DealershipStatsViewModel.formatUSD(p)
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

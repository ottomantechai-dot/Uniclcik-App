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
            .navigationTitle(L10n.tr("tab.dashboard"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar { dashboardToolbar }
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
                    DashboardHeroBannerCard(onExplore: { tabRouter.selected = .closet })
                        .padding(.top, 12)
                        .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.05))
                    DashboardStatsOverview(stats: vm)
                        .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.15))
                    DashboardLatestSaleSection(closetItems: closetItems, cars: carsVM.cars)
                        .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.22))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                ClosetAnalytics.named("add_to_closet_opened")
                tabRouter.selected = .closet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .upsoledPresentAddToClosetMenu, object: nil)
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black)
            }
            .accessibilityLabel(L10n.tr("dashboard.quickAdd"))
        }
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
                    value: stats.totalStockValue,
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
                    value: stats.totalInvested,
                    subtitle: "Unrealized \(stats.unrealizedGainLabel)",
                    changePercent: stats.investedChangePercent,
                    isUp: stats.investedIsUp,
                    history: stats.stockValueHistory,
                    icon: "creditcard.fill"
                )
            }

            if !stats.categorySnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("By category")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))

                    HStack(spacing: 10) {
                        ForEach(stats.categorySnapshots) { row in
                            categoryMiniCard(row)
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
                        ForEach(stats.metricTiles) { tile in
                            metricTileCard(tile)
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
        value: String,
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
                trendBadge(changePercent: changePercent, isUp: isUp)
            }

            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.92))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.48))
            }

            if history.count >= 2 {
                PriceTrendSparkline(points: history, isUp: isUp)
                    .frame(height: 44)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.08))
                    .frame(height: 44)
                    .overlay {
                        Text("Add market prices to see trends")
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

            Text(row.valueLabel)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.90))
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            if let change = row.changePercent {
                trendBadge(changePercent: change, isUp: row.isUp, compact: true)
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
                    trendBadge(changePercent: change, isUp: tile.isUp, compact: true)
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

    private func trendBadge(changePercent: Double, isUp: Bool, compact: Bool = false) -> some View {
        let tint = isUp
            ? Color(red: 0.20, green: 0.70, blue: 0.45)
            : Color(red: 0.92, green: 0.30, blue: 0.30)

        return HStack(spacing: 3) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: compact ? 8 : 9, weight: .heavy))
            Text(DealershipStatsViewModel.formatChangePercent(changePercent))
                .font(.system(size: compact ? 9 : 11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

// MARK: - Hero banner (estilo UPSOLED)

/// Tarjeta hero superior con título grande, CTA y arte del lado derecho.
private struct DashboardHeroBannerCard: View {
    var onExplore: () -> Void
    @State private var sneakerBreathing = false
    @State private var pulseDot = false

    var body: some View {
        ZStack(alignment: .leading) {
            // Fondo azul degradado más rico (3 paradas)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.55, blue: 0.95),
                            Color(red: 0.18, green: 0.40, blue: 0.85),
                            Color(red: 0.12, green: 0.30, blue: 0.75),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    // Gloss superior tipo cristal
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .blendMode(.plusLighter)
                        .opacity(0.6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8)
                }
                .shadow(color: Color(red: 0.18, green: 0.40, blue: 0.85).opacity(0.30), radius: 18, x: 0, y: 10)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 12) {
                    // Eyebrow pill con punto pulsante
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 5, height: 5)
                            .scaleEffect(pulseDot ? 1.4 : 1.0)
                            .opacity(pulseDot ? 0.6 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseDot)
                        Text(L10n.tr("dashboard.new"))
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1.4)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(Color.white.opacity(0.20))
                    }

                    Text(L10n.tr("dashboard.heroTitle"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onExplore) {
                        HStack(spacing: 6) {
                            Text(L10n.tr("dashboard.heroCTA"))
                                .font(.system(size: 13, weight: .bold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .heavy))
                        }
                        .foregroundStyle(Color(red: 0.15, green: 0.32, blue: 0.75))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 18)
                .padding(.vertical, 18)

                Spacer(minLength: 0)

                Image("AuthSneakerHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(sneakerBreathing ? -16 : -20))
                    .scaleEffect(sneakerBreathing ? 1.04 : 1.0)
                    .offset(x: 18, y: sneakerBreathing ? -3 : 3)
                    .shadow(color: Color.black.opacity(0.35), radius: 18, x: -3, y: 8)
                    .shadow(color: Color(red: 0.18, green: 0.40, blue: 0.85).opacity(0.50), radius: 30, y: 12)
                    .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: sneakerBreathing)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 195)
        .frame(maxWidth: .infinity)
        .onAppear {
            sneakerBreathing = true
            pulseDot = true
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
               let uiImage = ImageStore.load(path) {
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

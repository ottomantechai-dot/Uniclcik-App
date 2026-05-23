import SwiftUI
import UIKit

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var carsVM: CarsViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var notificationsStore: DashboardNotificationsStore

    @StateObject private var vm = DealershipStatsViewModel()
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator
    @StateObject private var locationHub = DashboardLocationHub()
    @State private var homeSearchText = ""
    @State private var showFinancialStatsSheet = false
    @State private var showNotificationsSheet = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                    DashboardHomeTopBar(
                        initials: auth.userInitials,
                        profileImage: auth.profileAvatarImage,
                        searchText: $homeSearchText,
                        onStats: { showFinancialStatsSheet = true },
                        onNotifications: { showNotificationsSheet = true },
                        lightSurface: true
                    )
                    .appChromeHeaderOuterPadding()

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            DashboardHeroBannerCard(onExplore: { tabRouter.selected = .cars })
                                .padding(.top, 16)

                            DashboardLatestSaleSection(cars: carsVM.cars)

                            DashboardConnectAccountsSection()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 36)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.dashboardLightSurface, true)
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showFinancialStatsSheet) {
            DashboardFinancialDetailSheet(stats: vm)
        }
        .sheet(isPresented: $showNotificationsSheet) {
            DashboardNotificationsSheet(store: notificationsStore)
        }
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
        .onDisappear {
            locationHub.stopUpdates()
        }
        .task(id: carsVM.cars.count) {
            vm.refreshFromInventory(cars: carsVM.cars)
        }
        .onChange(of: carsVM.cars) { _, newCars in
            vm.refreshFromInventory(cars: newCars)
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

// MARK: - Hero banner (estilo UPSOLED)

/// Tarjeta hero superior con título grande, CTA y arte del lado derecho.
private struct DashboardHeroBannerCard: View {
    var onExplore: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            // Fondo azul degradado
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.78, blue: 0.95),
                            Color(red: 0.34, green: 0.63, blue: 0.88),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("El primer dashboard\nunificado del motor.")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onExplore) {
                        Text("Explorar ahora")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.20, green: 0.30, blue: 0.55))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color.white)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 20)
                .padding(.vertical, 22)

                Spacer(minLength: 0)

                Image(systemName: "car.side.fill")
                    .font(.system(size: 86, weight: .regular))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: -2, y: 4)
                    .padding(.trailing, 14)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 168)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Última venta (estilo UPSOLED)

/// Tarjeta con el último/mejor vehículo del inventario y su precio.
private struct DashboardLatestSaleSection: View {
    let cars: [Car]

    private var featured: Car? {
        cars
            .filter { ($0.listPriceEUR ?? 0) > 0 }
            .sorted { ($0.listPriceEUR ?? 0) > ($1.listPriceEUR ?? 0) }
            .first
            ?? cars.first
    }

    private static let priceFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "es_ES")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Última operación")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                Spacer()
                Button {} label: {
                    Text("Ver todas")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.96, green: 0.97, blue: 0.99))
                        .frame(width: 86, height: 86)
                    Image(systemName: featured?.icon ?? "car.fill")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.55))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(featuredTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(featuredPriceText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
                        Text("3.2%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
            }
        }
    }

    private var featuredTitle: String {
        guard let f = featured else { return "Sin operaciones todavía" }
        let brand = f.brandName ?? f.name
        return "\(brand) \(f.model)"
    }

    private var featuredPriceText: String {
        guard let f = featured, let price = f.listPriceEUR,
              let str = Self.priceFmt.string(from: NSNumber(value: price))
        else { return "—" }
        return str
    }
}

// MARK: - Conecta tus cuentas (estilo UPSOLED)

/// Fila con portales del motor (Coches.net / AutoScout24 / Wallapop) para conectar.
private struct DashboardConnectAccountsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conecta tus cuentas")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                Spacer()
                Button {} label: {
                    Text("Ver todas")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                ConnectAccountCard(
                    badgeAsset: "BadgeCochesNet",
                    fallbackSymbol: "car.2.fill",
                    title: "Coches.net"
                )
                ConnectAccountCard(
                    badgeAsset: "BadgeAutoScout24",
                    fallbackSymbol: "magnifyingglass.circle.fill",
                    title: "AutoScout24"
                )
                ConnectAccountCard(
                    badgeAsset: "BadgeWallapop",
                    fallbackSymbol: "tag.fill",
                    title: "Wallapop"
                )
            }
        }
    }
}

private struct ConnectAccountCard: View {
    let badgeAsset: String
    let fallbackSymbol: String
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if UIImage(named: badgeAsset) != nil {
                    Image(badgeAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 32)
                } else {
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.75))
                        .frame(height: 32)
                }
            }
            .frame(maxWidth: .infinity)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text("Conectar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthViewModel())
        .environmentObject(CarsViewModel())
        .environmentObject(MainTabRouter())
        .environmentObject(ChatNavigationCoordinator())
        .environmentObject(ChatInboxStore())
        .environmentObject(DashboardCommunityViewModel())
        .environmentObject(InvoiceHistoryStore())
        .environmentObject(DashboardNotificationsStore())
}

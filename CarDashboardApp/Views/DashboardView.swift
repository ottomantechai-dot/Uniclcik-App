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
    @State private var didAppear = false

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
                    .opacity(didAppear ? 1 : 0)
                    .offset(y: didAppear ? 0 : -8)
                    .animation(.easeOut(duration: 0.4), value: didAppear)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            DashboardStatsOverview(stats: vm)
                                .padding(.top, 12)
                                .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.05))

                            DashboardHeroBannerCard(onExplore: { tabRouter.selected = .cars })
                                .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.15))

                            DashboardQuickActionsLightRow(
                                onAddCar: { tabRouter.selected = .cars },
                                onInvoices: {},
                                onStats: { showFinancialStatsSheet = true },
                                onMore: {}
                            )
                            .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.25))

                            DashboardLatestSaleSection(cars: carsVM.cars)
                                .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.35))

                            DashboardConnectAccountsSection()
                                .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.45))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 36)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }
        }
        .onAppear {
            // Pequeño delay para asegurar que la transición se vea
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                didAppear = true
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

// MARK: - Brand logos (representaciones tipográficas estilizadas)

/// Insignia que recrea el estilo visual de cada marketplace usando tipografía e
/// iniciales — no son los logos oficiales sino representaciones aproximadas.
private struct BrandLogo: View {
    let brand: String

    var body: some View {
        switch brand {
        case "StockX":         stockXLogo
        case "GOAT":           goatLogo
        case "Grailed":        grailedLogo
        case "eBay":           ebayLogo
        case "Flight Club":    flightClubLogo
        case "Stadium Goods":  stadiumGoodsLogo
        default:               genericLogo
        }
    }

    // StockX: negro con "X" verde lima
    private var stockXLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.06))
            HStack(spacing: 0) {
                Text("S")
                    .foregroundStyle(.white)
                Text("X")
                    .foregroundStyle(Color(red: 0.20, green: 0.95, blue: 0.45))
            }
            .font(.system(size: 21, weight: .heavy, design: .rounded))
            .tracking(-1)
        }
    }

    // GOAT: blanco con "G" negra serif
    private var goatLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                }
            Text("g")
                .font(.system(size: 30, weight: .black, design: .serif))
                .foregroundStyle(Color.black)
                .offset(y: 1)
        }
    }

    // Grailed: blanco con "G" negra tipo sans
    private var grailedLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
                }
            Text("G")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Color.black)
        }
    }

    // eBay: blanco con "e" multicolor inspirado en su paleta
    private var ebayLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                }
            HStack(spacing: 0) {
                Text("e").foregroundStyle(Color(red: 0.90, green: 0.20, blue: 0.20))
                Text("b").foregroundStyle(Color(red: 0.15, green: 0.50, blue: 0.95))
                Text("a").foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.10))
                Text("y").foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.30))
            }
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .tracking(-0.5)
        }
    }

    // Flight Club: negro con "FC" en rojo
    private var flightClubLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.06))
            VStack(spacing: -2) {
                Text("FLIGHT")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                Text("CLUB")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Color(red: 0.92, green: 0.15, blue: 0.20))
            }
        }
    }

    // Stadium Goods: blanco con "SG" negro
    private var stadiumGoodsLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                }
            Text("SG")
                .font(.system(size: 17, weight: .black, design: .serif))
                .foregroundStyle(Color.black)
                .tracking(-1)
        }
    }

    private var genericLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.18))
            Text(String(brand.prefix(2)).uppercased())
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.65))
        }
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

/// Estilo de botón con scale spring al tap (efecto "press").
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.30, dampingFraction: 0.6), value: configuration.isPressed)
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

/// Tarjeta grande con valor total + 2 metric pills (vehículos / operaciones del mes).
private struct DashboardStatsOverview: View {
    @ObservedObject var stats: DealershipStatsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card principal valor total
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                    Text("Valor total del stock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }

                Text(stats.totalStockValue)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
                    Text("+3.2%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
                    Text("· \(stats.periodDisplayLabel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.42))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
            }

            // Dos KPIs en fila (sneakers + vendidos)
            HStack(spacing: 12) {
                miniKPI(
                    icon: "shoeprints.fill",
                    iconColor: Color(red: 0.20, green: 0.45, blue: 0.85),
                    title: "Sneakers en stock",
                    value: "\(stats.vehiclesInStock)"
                )
                miniKPI(
                    icon: "checkmark.seal.fill",
                    iconColor: Color(red: 0.20, green: 0.70, blue: 0.45),
                    title: "Vendidas",
                    value: "\(stats.carsSold)"
                )
            }
        }
    }

    private func miniKPI(icon: String, iconColor: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.50))
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.92))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
        }
    }
}

// MARK: - Acciones rápidas (estilo light)

private struct DashboardQuickActionsLightRow: View {
    var onAddCar: () -> Void
    var onInvoices: () -> Void
    var onStats: () -> Void
    var onMore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            quickItem(icon: "plus", title: "Añadir", color: Color(red: 0.20, green: 0.45, blue: 0.85), action: onAddCar)
            quickItem(icon: "doc.text.fill", title: "Facturas", color: Color(red: 0.55, green: 0.40, blue: 0.90), action: onInvoices)
            quickItem(icon: "chart.bar.fill", title: "Stats", color: Color(red: 0.95, green: 0.55, blue: 0.20), action: onStats)
            quickItem(icon: "ellipsis", title: "Más", color: Color(red: 0.20, green: 0.70, blue: 0.45), action: onMore)
        }
    }

    private func quickItem(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.70))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableButtonStyle())
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
                        Text("NUEVO")
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

                    Text("Tu imperio de\nsneakers en uno.")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onExplore) {
                        HStack(spacing: 6) {
                            Text("Explorar ahora")
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
                        .frame(width: 110, height: 110)
                    Image("AuthSneakerHero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-18))
                        .shadow(color: Color(red: 0.18, green: 0.40, blue: 0.85).opacity(0.35), radius: 12, y: 6)
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
        // Mock sneaker data — el modelo Car aún no se ha reemplazado por Sneaker
        "Jordan 1 Off-White UNC"
    }

    private var featuredPriceText: String {
        "1.840 €"
    }
}

// MARK: - Conecta tus cuentas (estilo UPSOLED)

/// Fila con portales del motor (Coches.net / AutoScout24 / Wallapop) para conectar.
private struct DashboardConnectAccountsSection: View {
    private let platforms: [(asset: String, symbol: String, title: String, tint: Color, connected: Bool)] = [
        ("BadgeStockX",      "chart.line.uptrend.xyaxis", "StockX",        Color(red: 0.00, green: 0.60, blue: 0.30), true),
        ("BadgeGoat",        "star.fill",                 "GOAT",          Color(red: 0.92, green: 0.30, blue: 0.20), true),
        ("BadgeGrailed",     "bag.fill",                  "Grailed",       Color(red: 0.20, green: 0.20, blue: 0.20), false),
        ("BadgeEbay",        "tag.fill",                  "eBay",          Color(red: 0.95, green: 0.35, blue: 0.20), false),
        ("BadgeFlightClub",  "airplane",                  "Flight Club",   Color(red: 0.85, green: 0.10, blue: 0.15), false),
        ("BadgeStadium",     "building.columns.fill",     "Stadium Goods", Color(red: 0.18, green: 0.18, blue: 0.22), false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dónde publicar")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.88))
                    Text("Conecta tus tiendas y publica con 1 toque")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.50))
                }
                Spacer()
                Button {} label: {
                    Text("Ver todas")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                }
                .buttonStyle(.plain)
            }

            // Grid de 3 columnas × 2 filas
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(Array(platforms.enumerated()), id: \.offset) { _, p in
                    ConnectAccountCard(
                        badgeAsset: p.asset,
                        fallbackSymbol: p.symbol,
                        title: p.title,
                        tint: p.tint,
                        connected: p.connected
                    )
                }
            }
        }
    }
}

private struct ConnectAccountCard: View {
    let badgeAsset: String
    let fallbackSymbol: String
    let title: String
    var tint: Color = Color(red: 0.20, green: 0.45, blue: 0.85)
    var connected: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            // Logo real del brand
            ZStack(alignment: .topTrailing) {
                BrandLogo(brand: title)
                    .frame(width: 48, height: 48)

                // Badge ✓ si está conectado
                if connected {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.20, green: 0.70, blue: 0.45))
                            .frame(width: 14, height: 14)
                            .overlay {
                                Circle().strokeBorder(Color.white, lineWidth: 1.5)
                            }
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 7, y: -4)
                }
            }
            .frame(height: 50)

            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.80)

            // Estado conectado vs CTA Conectar
            if connected {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(red: 0.20, green: 0.70, blue: 0.45))
                        .frame(width: 5, height: 5)
                    Text("Conectado")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.40))
                }
            } else {
                Text("Conectar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            connected ? Color(red: 0.20, green: 0.70, blue: 0.45).opacity(0.20) : Color.black.opacity(0.04),
                            lineWidth: connected ? 1 : 0.6
                        )
                }
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

import SwiftUI
import UIKit

struct DashboardView: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var carsVM: CarsViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter
    @StateObject private var vm = DealershipStatsViewModel()
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator
    @StateObject private var locationHub = DashboardLocationHub()
    @State private var didAppear = false
    @State private var showPriceCompareSheet = false

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .spanish
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    DashboardHeroBannerCard(onExplore: { tabRouter.selected = .cars })
                        .padding(.top, 12)
                        .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.05))

                    DashboardStatsOverview(stats: vm)
                        .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.15))

                    DashboardPriceCompareCard(
                        lang: appLanguage,
                        onTap: { showPriceCompareSheet = true }
                    )
                    .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.20))

                    DashboardLatestSaleSection(cars: carsVM.cars)
                        .modifier(EntranceAnimation(didAppear: didAppear, delay: 0.25))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
                .frame(minWidth: 0, maxWidth: .infinity)
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
        .sheet(isPresented: $showPriceCompareSheet) {
            PriceCompareSheet()
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

/// Tarjeta grande con valor total + 2 metric pills (vehículos / operaciones del mes).
private struct DashboardStatsOverview: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue
    @ObservedObject var stats: DealershipStatsViewModel

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .spanish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card principal valor total
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                    Text(L10n.tr("dashboard.totalStock", lang: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }

                Text(stats.totalStockValue)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.35))
                    Text("0%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.45))
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
                    title: L10n.tr("dashboard.sneakersInStock", lang: appLanguage),
                    value: "\(stats.vehiclesInStock)"
                )
                miniKPI(
                    icon: "checkmark.seal.fill",
                    iconColor: Color(red: 0.20, green: 0.70, blue: 0.45),
                    title: L10n.tr("dashboard.sold", lang: appLanguage),
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

// MARK: - Hero banner (estilo UPSOLED)

/// Tarjeta hero superior con título grande, CTA y arte del lado derecho.
private struct DashboardHeroBannerCard: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue
    var onExplore: () -> Void
    @State private var sneakerBreathing = false
    @State private var pulseDot = false

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .spanish
    }

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
                        Text(L10n.tr("dashboard.new", lang: appLanguage))
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

                    Text(L10n.tr("dashboard.heroTitle", lang: appLanguage))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onExplore) {
                        HStack(spacing: 6) {
                            Text(L10n.tr("dashboard.heroCTA", lang: appLanguage))
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
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue
    let cars: [Car]

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .spanish
    }

    private var featured: Car? {
        cars
            .filter { ($0.listPriceUSD ?? 0) > 0 }
            .sorted { ($0.listPriceUSD ?? 0) > ($1.listPriceUSD ?? 0) }
            .first
            ?? cars.first
    }

    private var priceFmt: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.maximumFractionDigits = 0
        f.locale = appLanguage.locale
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("dashboard.lastSale", lang: appLanguage))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                Spacer()
                Button {} label: {
                    Text(L10n.tr("dashboard.viewAll", lang: appLanguage))
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
                        Image(systemName: "minus.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.38))
                        Text("0%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.45))
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
        guard let car = featured else {
            return L10n.tr("dashboard.noItems", lang: appLanguage)
        }
        let brand = car.brandName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nm = car.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = "\(brand) \(nm)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? L10n.tr("dashboard.item", lang: appLanguage) : combined
    }

    private var featuredPriceText: String {
        guard let car = featured, let p = car.listPriceUSD, p > 0 else {
            return priceFmt.string(from: NSNumber(value: 0)) ?? "$0"
        }
        return priceFmt.string(from: NSNumber(value: Int(p.rounded()))) ?? "$\(Int(p.rounded()))"
    }
}

// MARK: - Tarjeta "Comparar precio de mercado"

/// Llama al servicio de comparativa de precios. Se abre como sheet al tocar.
struct DashboardPriceCompareCard: View {
    let lang: AppLanguage
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.30, green: 0.55, blue: 0.95),
                                    Color(red: 0.14, green: 0.36, blue: 0.85),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.35), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("price.compareTitle", lang: lang))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.88))
                    Text(L10n.tr("price.compareSubtitle", lang: lang))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.12))
                    }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.30, green: 0.55, blue: 0.95).opacity(0.25),
                                        Color.black.opacity(0.04),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.12), radius: 14, x: 0, y: 5)
            }
        }
        .buttonStyle(.plain)
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
}

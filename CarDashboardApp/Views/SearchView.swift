import SwiftUI

/// Pestaña Buscador: mismo criterio que Coches (`browseSearchText`, filtros y orden).
struct SearchView: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter

    @State private var showSortSheet = false
    @State private var showFilterSheet = false
    @FocusState private var browseSearchFieldFocused: Bool

    private var displayedCars: [Car] {
        carsVM.displayedBrowseCars()
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .spanish
    }

    private var resultCountText: String {
        displayedCars.count.formatted(.number.grouping(.automatic).locale(appLanguage.locale))
    }

    private var searchEmptyFootnote: String {
        carsVM.browseSearchText.isEmpty
            ? (appLanguage == .english ? "Type in the search bar or adjust filters." : "Escribe en el buscador o ajusta filtros.")
            : (appLanguage == .english ? "Try another term or clear filters." : "Prueba con otro término o limpia filtros.")
    }

    var body: some View {
        NavigationStack {
            RevolutChromeContainer {
                VStack(spacing: 0) {
                    stickyBrowseChrome

                    if auth.canAccessIASection {
                        iaShortcutRow
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 18) {
                            Text("\(resultCountText) \(appLanguage == .english ? "results" : "resultados")")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)

                            if carsVM.isLoadingVehicles && carsVM.cars.isEmpty {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.vertical, 32)
                            }

                            if !carsVM.isLoadingVehicles || !carsVM.cars.isEmpty {
                                if displayedCars.isEmpty {
                                    ContentUnavailableView(
                                        appLanguage == .english ? "No results" : "Sin resultados",
                                        systemImage: "magnifyingglass",
                                        description: Text(searchEmptyFootnote)
                                    )
                                    .foregroundStyle(.white)
                                    .symbolRenderingMode(.hierarchical)
                                    .tint(.white.opacity(0.85))
                                    .padding(.vertical, 24)
                                    .padding(.horizontal, 16)
                                } else {
                                    VStack(spacing: 20) {
                                        ForEach(displayedCars) { car in
                                            CarListingCard(
                                                car: car,
                                                isSelected: carsVM.isSelected(car)
                                            ) {
                                                carsVM.selectCar(car)
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(.bottom, 28)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                    .refreshable {
                        await carsVM.loadVehicles(companyId: auth.companyId)
                    }
                }
                .frame(maxWidth: .infinity)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        LiquidGlassKeyboardAccessoryBar {
                            browseSearchFieldFocused = false
                        }
                    }
                }
                .sheet(isPresented: $showSortSheet) {
                    CarsSortSheet(sort: $carsVM.browseSort)
                        .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showFilterSheet) {
                    CarsFilterSheet(
                        filters: $carsVM.browseFilters,
                        sourceCars: carsVM.cars,
                        resultCount: carsVM.displayedBrowseCars().count,
                        onClear: {}
                    )
                }
            }
        }
    }

    private var iaShortcutRow: some View {
        Button {
            tabRouter.selected = .ai
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.45, green: 0.35, blue: 0.95),
                                    Color(red: 0.2, green: 0.55, blue: 0.98),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(appLanguage == .english ? "AI — Team coordinator" : "IA — Coordinador de equipo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(appLanguage == .english ? "Live voice, tasks and messages by name" : "Voz en vivo, tareas y mensajes por nombre")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var stickyBrowseChrome: some View {
        CarsBrowseHeaderBar(
            searchText: $carsVM.browseSearchText,
            hasActiveFilters: carsVM.browseFilters.hasActiveFilters,
            searchFieldFocused: $browseSearchFieldFocused,
            onSort: { showSortSheet = true },
            onFilter: { showFilterSheet = true }
        )
        .appChromeHeaderOuterPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SearchView()
        .environmentObject(CarsViewModel())
        .environmentObject(AuthViewModel())
        .environmentObject(MainTabRouter())
}

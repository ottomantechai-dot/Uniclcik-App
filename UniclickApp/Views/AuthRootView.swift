import SwiftUI

/// Raíz: sesión Supabase → app principal.
struct AuthRootView: View {
    @ObservedObject var auth: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel

    var body: some View {
        Group {
            if Self.previewsShoeReport {
                // Solo desarrollo (-uniclickPreviewReport): informe de un zapato sin precios, para ver el giro 360°.
                SaleReportView(report: SaleReport(title: "adidas Yeezy Boost 350 V2 Steel Grey", sku: "IF3219", scannedCode: "",
                                                  imageURL: nil, size: "9.5", costUSD: nil, lines: [], priceIsEstimate: false))
            } else if Self.previewsNewSections {
                // Solo en compilaciones de desarrollo y con el argumento -uniclickPreview: enseña las
                // secciones nuevas sin iniciar sesión, para poder probarlas en el simulador.
                MainTabView()
            } else if auth.isRestoringSession {
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    ProgressView(L10n.tr("auth.connecting"))
                }
            } else if auth.isAuthenticated {
                MainTabView()
            } else {
                LoginView(auth: auth)
            }
        }
        .environmentObject(auth)
        .onOpenURL { url in
            SupabaseClientProvider.shared.auth.handle(url)
        }
    }
}

extension AuthRootView {
    static var previewsShoeReport: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uniclickPreviewReport")
        #else
        return false
        #endif
    }

    static var previewsNewSections: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uniclickPreview")
        #else
        return false
        #endif
    }
}

#Preview {
    AuthRootView(auth: AuthViewModel())
        .environmentObject(CarsViewModel())
        .environmentObject(SettingsViewModel())
}

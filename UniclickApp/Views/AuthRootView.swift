import SwiftUI

/// Raíz: sesión Supabase → app principal.
struct AuthRootView: View {
    @ObservedObject var auth: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel

    var body: some View {
        Group {
            if Self.previewsNewSections {
                // Solo en compilaciones de desarrollo y con el argumento -uniclickPreview: enseña las
                // secciones nuevas sin iniciar sesión, para poder probarlas en el simulador.
                NavigationStack { CardsHubView() }
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

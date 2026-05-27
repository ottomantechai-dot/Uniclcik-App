import SwiftUI

/// Raíz: sesión Supabase → app principal.
struct AuthRootView: View {
    @ObservedObject var auth: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .spanish
    }

    var body: some View {
        Group {
            if auth.isRestoringSession {
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    ProgressView(L10n.tr("auth.connecting", lang: appLanguage))
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

#Preview {
    AuthRootView(auth: AuthViewModel())
        .environmentObject(CarsViewModel())
        .environmentObject(SettingsViewModel())
}

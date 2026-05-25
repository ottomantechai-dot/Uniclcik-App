import Foundation
import SwiftData
import SwiftUI

/// SwiftData necesita que exista `Library/Application Support` antes de abrir la store en arranques “fríos”; si no, Core Data registra errores (a veces corrige después, pero mejor evitarlos).
private enum AppSandboxDirectories {
    static func ensureApplicationSupportAndClosetRoots() {
        let fm = FileManager.default
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        }
        _ = ImageStore.rootDirectory
    }
}

@main
struct CarDashboardAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var carsVM = CarsViewModel()
    @StateObject private var settingsVM = SettingsViewModel()

    init() {
        AppSandboxDirectories.ensureApplicationSupportAndClosetRoots()
    }

    var body: some Scene {
        WindowGroup {
            AppShellRoot(authVM: authVM)
                .environmentObject(carsVM)
                .environmentObject(settingsVM)
                /// Tema claro por defecto: barra de sistema (hora, señal, batería) en negro sobre UI blanca.
                .preferredColorScheme(.light)
                .modelContainer(for: [ClosetItem.self, Look.self, UserProfile.self])
        }
    }
}

/// Encapsula la raíz autenticada y el registro de notificaciones push.
private struct AppShellRoot: View {
    @ObservedObject var authVM: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel

    var body: some View {
        AuthRootView(auth: authVM)
            .environmentObject(carsVM)
            .environmentObject(settingsVM)
            .task(id: authVM.isAuthenticated) {
                guard authVM.isAuthenticated else { return }
                await RemotePushRegistration.requestAuthorizationAndRegister()
                await RemotePushRegistration.syncPendingTokenToSupabase()
            }
    }
}

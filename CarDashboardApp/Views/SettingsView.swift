import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var auth: AuthViewModel

    @AppStorage(VehicleImageDiagnostics.userDefaultsKey) private var logVehicleImageDiagnostics = false

    @State private var settingsSearchText = ""
    @FocusState private var settingsSearchFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                AppChromeHeaderRow(
                    initials: auth.userInitials,
                    profileImage: auth.profileAvatarImage,
                    searchText: $settingsSearchText,
                    prompt: Text("Buscar")
                        .foregroundStyle(Color.black.opacity(0.42)),
                    showsSearchClearButton: true,
                    searchFieldFocused: $settingsSearchFieldFocused
                ) {
                    HStack(spacing: AppChromeHeaderMetrics.hStackSpacing) {
                        AppChromeHeaderCircleIconButton(
                            systemName: "chart.bar.fill",
                            accessibilityLabel: "Estadísticas",
                            action: {}
                        )
                        AppChromeHeaderCircleIconButton(
                            systemName: "bell.fill",
                            accessibilityLabel: "Notificaciones",
                            action: {}
                        )
                    }
                }
                .appChromeHeaderOuterPadding()
                .environment(\.dashboardLightSurface, true)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        profileHeroSection
                            .padding(.top, 8)

                        Group {
                            sectionTitle("Información personal")
                            generalInfoSection
                        }

                        Group {
                            sectionTitle("Mi cuenta de vendedor")
                            sellerAccountsSection
                        }

                        if auth.isAuthenticated {
                            Group {
                                sectionTitle("Preferencias")
                                notificationsSection
                            }
                        }

                        Group {
                            sectionTitle("Avanzado")
                            developerSection
                        }

                        accountSection
                        aboutSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.light)
        .environment(\.dashboardLightSurface, true)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                LiquidGlassKeyboardAccessoryBar {
                    settingsSearchFieldFocused = false
                }
            }
        }
        .task(id: auth.session?.user.id) {
            guard let uid = auth.session?.user.id else { return }
            await settingsVM.loadNotifyTeamPush(
                client: SupabaseClientProvider.shared,
                userId: uid
            )
        }
    }

    // MARK: - Notificaciones

    private var notificationsSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Notificaciones")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.50))

                Toggle(
                    isOn: Binding(
                        get: { settingsVM.notifyTeamPushEnabled },
                        set: { new in
                            settingsVM.notifyTeamPushEnabled = new
                            if let uid = auth.session?.user.id {
                                Task {
                                    await settingsVM.persistNotifyTeamPush(
                                        new,
                                        client: SupabaseClientProvider.shared,
                                        userId: uid
                                    )
                                }
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avisos del equipo y tareas")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.85))
                        Text(
                            "Recibir push cuando te envíen un mensaje directo, aviso de grupo o una tarea desde Viera. Desactívalo si no quieres notificaciones en este dispositivo."
                        )
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.50))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(PremiumAccent.tabActive)
            }
        }
    }

    // MARK: - Profile

    // Profile hero — avatar grande centrado + nombre + email + rol
    private var profileHeroSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    if let photo = auth.profileAvatarImage {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
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
                        Text(String(auth.userDisplayName.prefix(1)).uppercased())
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 108, height: 108)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.30, green: 0.55, blue: 0.95).opacity(0.50),
                                    Color(red: 0.14, green: 0.36, blue: 0.85).opacity(0.15),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
                .shadow(color: Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.25), radius: 18, y: 8)

                // Edit camera button
                Button {} label: {
                    ZStack {
                        Circle()
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
                            .frame(width: 34, height: 34)
                            .overlay {
                                Circle().strokeBorder(Color.white, lineWidth: 2.5)
                            }
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.40), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 4) {
                Text(auth.userDisplayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .multilineTextAlignment(.center)

                Text(auth.session?.user.email ?? "Sin sesión")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.50))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // Rol pill
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("ADMIN")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                }
                .foregroundStyle(Color(red: 0.18, green: 0.40, blue: 0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.12))
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Título de sección estilo iOS Settings
    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color.black.opacity(0.48))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // Información personal — lista de rows
    private var generalInfoSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 0) {
            VStack(spacing: 0) {
                infoRow(icon: "person.fill", iconTint: Color(red: 0.20, green: 0.45, blue: 0.85), label: "Rol", value: "Admin")
                infoDivider
                infoRow(icon: "envelope.fill", iconTint: Color(red: 0.20, green: 0.45, blue: 0.85), label: "Email", value: auth.session?.user.email ?? "—")
                infoDivider
                infoRow(icon: "phone.fill", iconTint: Color(red: 0.20, green: 0.70, blue: 0.45), label: "Teléfono", value: "+34 600 000 000")
                infoDivider
                infoRow(icon: "shoeprints.fill", iconTint: Color(red: 0.95, green: 0.55, blue: 0.20), label: "Talla", value: "EU 42 · US 9")
                infoDivider
                infoRow(icon: "eurosign.circle.fill", iconTint: Color(red: 0.55, green: 0.30, blue: 0.85), label: "Divisa", value: "EUR (€)")
            }
            .padding(.vertical, 4)
        }
    }

    private var infoDivider: some View {
        Divider()
            .padding(.leading, 56)
            .padding(.trailing, 16)
    }

    private func infoRow(icon: String, iconTint: Color, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(iconTint.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(iconTint)
            }

            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.78))

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.80)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // Cuentas de vendedor — lista de plataformas con badge conectado
    private var sellerAccountsSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 0) {
            VStack(spacing: 0) {
                sellerRow(name: "StockX", color: Color(red: 0.00, green: 0.60, blue: 0.30), letter: "X", connected: true)
                infoDivider
                sellerRow(name: "GOAT", color: Color.black, letter: "g", connected: true)
                infoDivider
                sellerRow(name: "Grailed", color: Color.black, letter: "G", connected: false)
                infoDivider
                sellerRow(name: "eBay", color: Color(red: 0.20, green: 0.50, blue: 0.95), letter: "e", connected: false)
                infoDivider
                sellerRow(name: "Flight Club", color: Color(red: 0.85, green: 0.10, blue: 0.15), letter: "F", connected: false)
                infoDivider
                sellerRow(name: "Stadium Goods", color: Color(red: 0.18, green: 0.18, blue: 0.22), letter: "S", connected: false)
            }
            .padding(.vertical, 4)
        }
    }

    private func sellerRow(name: String, color: Color, letter: String, connected: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color)
                    .frame(width: 32, height: 32)
                Text(letter)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))

            Spacer(minLength: 8)

            if connected {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Conectado")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
            } else {
                Text("Conectar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Desarrollo (diagnóstico imágenes)

    private var developerSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Desarrollo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.50))

                Toggle(isOn: $logVehicleImageDiagnostics) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Diagnóstico de imágenes (consola Xcode)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.85))
                        Text(
                            "Al cargar Coches se imprimen columnas JSON, rutas Storage, user_id y cuántos slots ve la UI. Abre la consola con ⌘⇧Y y tira hacia abajo para refrescar el listado."
                        )
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.50))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(PremiumAccent.tabActive)
            }
        }
    }

    // MARK: - Cuenta

    private var accountSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 4) {
            VStack(spacing: 0) {
                Button {
                    Task { await auth.signOut() }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(0.10))
                                .frame(width: 32, height: 32)
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.red.opacity(0.92))
                        }
                        Text("Cerrar sesión")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.85))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Acerca de

    private var aboutSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 4) {
            VStack(spacing: 0) {
                settingsRow(
                    icon: "info.circle.fill",
                    iconColor: PremiumAccent.tabActive,
                    title: "Versión"
                ) {
                    Text("\(settingsVM.appVersion) (\(settingsVM.buildNumber))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.50))
                }
            }
        }
    }

    // MARK: - Helpers

    private func settingsRow<Trailing: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .frame(width: 32, height: 32)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.85))

            Spacer()

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AuthViewModel())
}

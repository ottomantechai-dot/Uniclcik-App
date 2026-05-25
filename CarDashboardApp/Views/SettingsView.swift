import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var auth: AuthViewModel

    @State private var showClosetFaceSetup = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

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

                    Group {
                        sectionTitle("Plataformas")
                        marketplaceLogosGallerySection
                    }

                    Group {
                        sectionTitle("Clóset y avatares")
                        closetAvatarSection
                    }

                    if auth.isAuthenticated {
                        Group {
                            sectionTitle("Preferencias")
                            notificationsSection
                        }
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
        .preferredColorScheme(.light)
        .environment(\.dashboardLightSurface, true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showClosetFaceSetup) {
            FaceSetupView()
                .presentationDragIndicator(Visibility.visible)
        }
        .task(id: auth.session?.user.id) {
            guard let uid = auth.session?.user.id else { return }
            await settingsVM.loadNotifyTeamPush(
                client: SupabaseClientProvider.shared,
                userId: uid
            )
        }
    }

    // MARK: - Clóset (rostro para avatares Gemini)

    private var closetAvatarSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Foto de referencia")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.50))

                Button {
                    showClosetFaceSetup = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.black.opacity(0.75))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mi rostro")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.88))
                            Text("Opcional: mejora cómo el avatar se parece a ti al generar looks (solo en este dispositivo).")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(Color.black.opacity(0.50))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.35))
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
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
                infoRow(icon: "dollarsign.circle.fill", iconTint: Color(red: 0.55, green: 0.30, blue: 0.85), label: "Divisa", value: "$")
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

    // Cuentas de vendedor — lista de plataformas con insignia estilizada y estado
    private var sellerAccountsSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 0) {
            VStack(spacing: 0) {
                sellerRow(name: "StockX", connected: true)
                infoDivider
                sellerRow(name: "GOAT", connected: true)
                infoDivider
                sellerRow(name: "Grailed", connected: false)
                infoDivider
                sellerRow(name: "eBay", connected: false)
                infoDivider
                sellerRow(name: "Flight Club", connected: false)
                infoDivider
                sellerRow(name: "Stadium Goods", connected: false)
            }
            .padding(.vertical, 4)
        }
    }

    /// Todas las referencias visuales de marketplace en rejilla (mismo estilo que en la lista anterior).
    private var marketplaceLogosGallerySection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Marcas disponibles para conectar.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 12
                ) {
                    ForEach(MarketplacePlatformDisplay.allCases, id: \.rawValue) { platform in
                        VStack(spacing: 8) {
                            StylizedMarketplaceLogo(brand: platform.rawValue)
                                .frame(width: 54, height: 54)

                            Text(platform.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.82))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func sellerRow(name: String, connected: Bool) -> some View {
        HStack(spacing: 14) {
            StylizedMarketplaceLogo(brand: name)
                .frame(width: 36, height: 36)

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

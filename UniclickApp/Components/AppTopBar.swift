import SwiftUI

// MARK: - Barra superior de la app
// Va arriba en Inicio, Zapatos y Cartas: el logo con el nombre de la sección a la izquierda y la
// foto de perfil a la derecha, que abre los ajustes a pantalla completa (antes eran una pestaña).

struct AppTopBar<Extra: View>: View {
    let title: String
    @ViewBuilder var extra: () -> Extra

    @EnvironmentObject private var auth: AuthViewModel
    @State private var showSettings = false

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image("UniclickMark").resizable().scaledToFill()
                        .frame(width: 30, height: 30).clipShape(.rect(cornerRadius: 9))
                    Text(title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
                }
                .padding(.leading, 7).padding(.trailing, 14).frame(height: 44)
                .glassEffect(.regular, in: .capsule)

                Spacer(minLength: 0)
                extra()

                Button { showSettings = true } label: {
                    ProfileAvatar(size: 36)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Perfil y ajustes")
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
        .fullScreenCover(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { showSettings = false } label: { Image(systemName: "xmark") }
                        }
                    }
            }
        }
    }
}

extension AppTopBar where Extra == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// Botón redondo de cristal para la barra superior.
struct TopBarGlassButton: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.black)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// Foto de perfil del usuario, o su inicial si no tiene foto.
struct ProfileAvatar: View {
    var size: CGFloat = 36
    @EnvironmentObject private var auth: AuthViewModel

    var body: some View {
        ZStack {
            if let photo = auth.profileAvatarImage {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.16, green: 0.44, blue: 0.98), Color(red: 0.45, green: 0.22, blue: 0.95)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                let initial = String(auth.userDisplayName.prefix(1)).uppercased()
                if initial.isEmpty {
                    Image(systemName: "person.fill").font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white)
                } else {
                    Text(initial).font(.system(size: size * 0.46, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }
}

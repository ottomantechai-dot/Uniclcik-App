import SwiftUI

// MARK: - Auth Upsoled

private enum AuthPhase {
    case welcome
    case signIn
    case signUp
}

private let authBlack = Color(red: 0.02, green: 0.04, blue: 0.09)
private let authNavy = Color(red: 0.05, green: 0.09, blue: 0.18)
private let upsoledAccent = Color(red: 0.22, green: 0.55, blue: 0.98)
private let upsoledAccentBright = Color(red: 0.45, green: 0.78, blue: 1.0)

struct LoginView: View {
    @ObservedObject var auth: AuthViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.spanish.rawValue

    @State private var phase: AuthPhase = .welcome
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var showPassword = false
    @State private var showResetSheet = false
    @State private var resetEmail = ""
    @State private var resetInfo: String?
    @State private var showHelpAlert = false
    @State private var showComingSoonAlert = false

    private var canSubmit: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6
    }

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 420 : 360
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .spanish
    }

    var body: some View {
        ZStack {
            authBackground

            switch phase {
            case .welcome:
                welcomeLayer
            case .signIn, .signUp:
                innerAuthLayer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.3), value: phase)
        .sheet(isPresented: $showResetSheet) {
            resetPasswordSheet
        }
        .alert(L10n.tr("auth.helpTitle", lang: appLanguage), isPresented: $showHelpAlert) {
            Button(L10n.tr("common.ok", lang: appLanguage), role: .cancel) {}
        } message: {
            Text(L10n.tr("auth.helpBody", lang: appLanguage))
        }
        .alert(L10n.tr("auth.comingSoonTitle", lang: appLanguage), isPresented: $showComingSoonAlert) {
            Button(L10n.tr("common.ok", lang: appLanguage), role: .cancel) {}
        } message: {
            Text(L10n.tr("auth.comingSoonBody", lang: appLanguage))
        }
    }

    // MARK: - Fondo

    private var authBackground: some View {
        ZStack {
            // Base oscura con un toque de azul muy profundo
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.07, blue: 0.18),
                    authNavy,
                    authBlack,
                    Color.black,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Glow azul principal detrás de la sneaker
            Circle()
                .fill(
                    RadialGradient(
                        colors: [upsoledAccent.opacity(0.35), upsoledAccent.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 300
                    )
                )
                .frame(width: 560, height: 560)
                .blur(radius: 10)
                .offset(y: phase == .welcome ? -20 : -120)

            // Glow secundario violeta-cian en la esquina opuesta para añadir profundidad
            if phase == .welcome {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.45, green: 0.30, blue: 0.95).opacity(0.22), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 220
                        )
                    )
                    .frame(width: 380, height: 380)
                    .blur(radius: 22)
                    .offset(x: -140, y: 220)
            }

        }
        .ignoresSafeArea()
    }

    // MARK: - Bienvenida (login premium estilo referencia)

    private var welcomeLayer: some View {
        VStack(spacing: 0) {
            // Header con margen seguro bajo el notch
            welcomeProHeader
                .padding(.top, 12)
                .padding(.horizontal, 20)

            // Spacer flexible empuja el form al fondo pero mantiene un mínimo
            Spacer(minLength: 4)

            // Form siempre completamente visible
            welcomeLoginForm
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: contentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    // Header premium: solo LOGO XL + sneaker (sin tagline)
    private var welcomeProHeader: some View {
        VStack(spacing: 0) {
            // LOGO XL centrado con halo (más grande aún)
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [upsoledAccent.opacity(0.45), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 220
                        )
                    )
                    .frame(width: 460, height: 200)
                    .blur(radius: 18)

                Image("UpsoledWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 210)
                    .padding(.horizontal, 8)
                    .shadow(color: upsoledAccent.opacity(0.60), radius: 26, y: 6)
                    .accessibilityLabel("Upsoled")
            }

            // SNEAKER protagonista
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                upsoledAccent.opacity(0.58),
                                upsoledAccent.opacity(0.20),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 240
                        )
                    )
                    .frame(width: 500, height: 500)
                    .blur(radius: 12)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [upsoledAccentBright.opacity(0.38), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 130
                        )
                    )
                    .frame(width: 280, height: 280)
                    .blur(radius: 4)

                welcomeLightStreaks
                    .scaleEffect(1.1)

                VStack(spacing: 0) {
                    Image("AuthSneakerHero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 320, height: 320)
                        .rotationEffect(.degrees(-22))
                        .shadow(color: .black.opacity(0.60), radius: 36, y: 22)
                        .shadow(color: upsoledAccent.opacity(0.60), radius: 70, y: 34)

                    // Reflejo
                    Image("AuthSneakerHero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 80)
                        .rotationEffect(.degrees(-22))
                        .scaleEffect(y: -1)
                        .mask {
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .blur(radius: 2.5)
                        .offset(y: -40)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 170)
            .padding(.top, 0)
        }
        .frame(maxWidth: .infinity)
    }

    // Formulario de login (sin card, mejor jerarquía y tamaños)
    private var welcomeLoginForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Título con accent line cyan
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Capsule()
                        .fill(upsoledAccentBright)
                        .frame(width: 4, height: 22)
                        .shadow(color: upsoledAccentBright.opacity(0.6), radius: 6, x: 0, y: 0)
                    Text(L10n.tr("auth.signInTitle", lang: appLanguage))
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(L10n.tr("auth.signInSubtitle", lang: appLanguage))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.leading, 14)
            }
            .padding(.bottom, 2)

            // Grupo de campos
            VStack(spacing: 10) {
                // Email
                authGlassField(icon: "envelope.fill") {
                TextField("", text: $email, prompt: Text(L10n.tr("auth.email", lang: appLanguage)).foregroundStyle(.white.opacity(0.40)))
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
            }

            // Password
            authGlassField(
                icon: "lock.fill",
                trailing: {
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.50))
                    }
                    .buttonStyle(.plain)
                }
            ) {
                Group {
                    if showPassword {
                        TextField("", text: $password, prompt: Text(L10n.tr("auth.password", lang: appLanguage)).foregroundStyle(.white.opacity(0.40)))
                    } else {
                        SecureField("", text: $password, prompt: Text(L10n.tr("auth.password", lang: appLanguage)).foregroundStyle(.white.opacity(0.40)))
                    }
                }
                .textContentType(.password)
                .foregroundStyle(.white)
            }
            } // cierra VStack de campos

            // Error
            if let msg = auth.lastErrorMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Olvidaste contraseña
            Button(L10n.tr("auth.forgot", lang: appLanguage)) {
                resetEmail = email
                showResetSheet = true
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(upsoledAccentBright)
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Login button — siempre activo y brillante (cyan saturado)
            Button {
                Task {
                    isBusy = true
                    defer { isBusy = false }
                    await auth.signIn(email: email, password: password)
                }
            } label: {
                HStack(spacing: 10) {
                    if isBusy {
                        ProgressView().tint(.white)
                    }
                    Spacer(minLength: 0)
                    Text(L10n.tr("auth.signIn", lang: appLanguage))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.30)))
                }
                .padding(.leading, 20)
                .padding(.trailing, 8)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background {
                    ZStack {
                        // Capa sólida base para evitar que el glass detrás mute el color
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.10, green: 0.32, blue: 0.85))

                        // Gradiente cyan → azul brillante SATURADO
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.30, green: 0.78, blue: 1.0),
                                        Color(red: 0.18, green: 0.55, blue: 1.0),
                                        Color(red: 0.10, green: 0.32, blue: 0.85),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        // Gloss superior brillante
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.42), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .blendMode(.plusLighter)
                            .opacity(0.60)

                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                    }
                }
                .shadow(color: upsoledAccent.opacity(0.65), radius: 22, y: 12)
                .shadow(color: upsoledAccentBright.opacity(0.40), radius: 40, y: 18)
            }
            .disabled(!canSubmit || isBusy)
            .buttonStyle(.plain)

            // Separador
            authOrSeparator
                .padding(.top, 2)

            // Social (Apple + Google como en la referencia)
            socialAuthButton(icon: "applelogo", title: L10n.tr("auth.continueApple", lang: appLanguage), style: .dark) {
                showComingSoonAlert = true
            }
            socialAuthButton(icon: "g.circle.fill", title: L10n.tr("auth.continueGoogle", lang: appLanguage), style: .light) {
                showComingSoonAlert = true
            }

            // Link a signup
            HStack(spacing: 5) {
                Text(L10n.tr("auth.noAccount", lang: appLanguage))
                    .foregroundStyle(.white.opacity(0.60))
                Button(L10n.tr("auth.signUp", lang: appLanguage)) {
                    phase = .signUp
                    auth.lastErrorMessage = nil
                }
                .foregroundStyle(upsoledAccentBright)
                .fontWeight(.bold)
            }
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // Haces de luz horizontales tipo "speed lines" tras la sneaker
    private var welcomeLightStreaks: some View {
        ZStack {
            // Halo radial detrás de la sneaker
            Circle()
                .fill(
                    RadialGradient(
                        colors: [upsoledAccent.opacity(0.45), upsoledAccent.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .blur(radius: 6)

            ForEach(0..<6, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                upsoledAccentBright.opacity(0.85),
                                upsoledAccent.opacity(0.35),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 320, height: i % 2 == 0 ? 2 : 1)
                    .blur(radius: 1.2)
                    .rotationEffect(.degrees(-6))
                    .offset(x: -20, y: CGFloat(i * 26 - 65))
                    .opacity(0.85)
            }
        }
        .frame(width: 320, height: 320)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var welcomeSneakerSize: CGFloat {
        horizontalSizeClass == .regular ? 320 : min(UIScreen.main.bounds.width * 0.72, 300)
    }

    private var welcomeLogoHeight: CGFloat {
        horizontalSizeClass == .regular ? 220 : min(UIScreen.main.bounds.width * 0.50, 200)
    }

    // MARK: - Registro (mismo estilo centrado que welcome)

    private var innerAuthLayer: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                // Back button arriba a la izquierda
                HStack {
                    circleNavButton(systemName: "chevron.left") {
                        phase = .welcome
                        auth.lastErrorMessage = nil
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)

                signUpProHeader
                    .padding(.horizontal, 24)

                authGlassFormCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // Header centrado para signIn/signUp — logo XL + sneaker grande + titular
    private var signUpProHeader: some View {
        VStack(spacing: 10) {
            // Logo XL con halo (como en welcome)
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [upsoledAccent.opacity(0.42), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                    .frame(width: 400, height: 170)
                    .blur(radius: 16)

                Image("UpsoledWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 180)
                    .padding(.horizontal, 12)
                    .shadow(color: upsoledAccent.opacity(0.60), radius: 22, y: 6)
                    .accessibilityLabel("Upsoled")
            }

            // Sneaker más grande con halos
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                upsoledAccent.opacity(0.50),
                                upsoledAccent.opacity(0.15),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                    .frame(width: 380, height: 380)
                    .blur(radius: 10)

                welcomeLightStreaks
                    .scaleEffect(0.7)

                Image("AuthSneakerHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-22))
                    .shadow(color: .black.opacity(0.55), radius: 24, y: 14)
                    .shadow(color: upsoledAccent.opacity(0.55), radius: 50, y: 24)
            }
            .frame(height: 170)

            // Titular + subtítulo centrados con accent line
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Capsule()
                        .fill(upsoledAccentBright)
                        .frame(width: 4, height: 22)
                        .shadow(color: upsoledAccentBright.opacity(0.6), radius: 6, x: 0, y: 0)
                    Text(phase == .signIn ? L10n.tr("auth.welcomeBack", lang: appLanguage) : L10n.tr("auth.createYourAccount", lang: appLanguage))
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(.white)
                        .tracking(-0.4)
                        .shadow(color: upsoledAccent.opacity(0.30), radius: 12, y: 4)
                }

                Group {
                    Text(
                        phase == .signIn
                            ? L10n.tr("auth.signInToEmpire", lang: appLanguage)
                            : L10n.tr("auth.startCollection", lang: appLanguage)
                    )
                    .foregroundStyle(.white.opacity(0.62))
                }
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var authGlassFormCard: some View {
        VStack(spacing: 12) {
            // Grupo de campos
            VStack(spacing: 10) {
                authGlassField(icon: "envelope.fill") {
                    TextField("", text: $email, prompt: Text(L10n.tr("auth.email", lang: appLanguage)).foregroundStyle(.white.opacity(0.40)))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                }

                authGlassField(
                    icon: "lock.fill",
                    trailing: {
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.50))
                        }
                        .buttonStyle(.plain)
                    }
                ) {
                    Group {
                        if showPassword {
                            TextField("", text: $password, prompt: Text(L10n.tr("auth.password", lang: appLanguage)).foregroundStyle(.white.opacity(0.40)))
                        } else {
                            SecureField("", text: $password, prompt: Text(L10n.tr("auth.password", lang: appLanguage)).foregroundStyle(.white.opacity(0.40)))
                        }
                    }
                    .textContentType(phase == .signUp ? .newPassword : .password)
                    .foregroundStyle(.white)
                }
            }

            if let msg = auth.lastErrorMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if phase == .signIn {
                Button(L10n.tr("auth.forgot", lang: appLanguage)) {
                    resetEmail = email
                    showResetSheet = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(upsoledAccentBright)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Button {
                Task {
                    isBusy = true
                    defer { isBusy = false }
                    if phase == .signUp {
                        await auth.signUp(email: email, password: password)
                    } else {
                        await auth.signIn(email: email, password: password)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if isBusy {
                        ProgressView().tint(.white)
                    }
                    Spacer(minLength: 0)
                    Text(phase == .signIn ? L10n.tr("auth.signIn", lang: appLanguage) : L10n.tr("auth.createAccount", lang: appLanguage))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.30)))
                }
                .padding(.leading, 20)
                .padding(.trailing, 8)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background {
                    ZStack {
                        // Capa sólida base para que el color no se mute
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.10, green: 0.32, blue: 0.85))

                        // Gradiente cyan → azul saturado
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.30, green: 0.78, blue: 1.0),
                                        Color(red: 0.18, green: 0.55, blue: 1.0),
                                        Color(red: 0.10, green: 0.32, blue: 0.85),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        // Gloss superior
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.42), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .blendMode(.plusLighter)
                            .opacity(0.60)

                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                    }
                }
                .shadow(color: upsoledAccent.opacity(0.65), radius: 22, y: 12)
                .shadow(color: upsoledAccentBright.opacity(0.40), radius: 40, y: 18)
            }
            .disabled(!canSubmit || isBusy)
            .buttonStyle(.plain)

            authOrSeparator

            socialAuthButton(icon: "applelogo", title: L10n.tr("auth.continueApple", lang: appLanguage), style: .dark) {
                showComingSoonAlert = true
            }

            socialAuthButton(icon: "g.circle.fill", title: L10n.tr("auth.continueGoogle", lang: appLanguage), style: .light) {
                showComingSoonAlert = true
            }

            HStack(spacing: 4) {
                Text(phase == .signIn ? L10n.tr("auth.noAccount", lang: appLanguage) : L10n.tr("auth.alreadyHaveAccount", lang: appLanguage))
                    .foregroundStyle(.white.opacity(0.55))
                Button(phase == .signIn ? L10n.tr("auth.signUp", lang: appLanguage) : L10n.tr("auth.signIn", lang: appLanguage)) {
                    phase = phase == .signIn ? .signUp : .signIn
                    auth.lastErrorMessage = nil
                }
                .foregroundStyle(upsoledAccentBright)
            }
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .padding(.top, 6)
    }

    private var authHighlightedSubtitle: some View {
        Group {
            if phase == .signIn {
                Text(L10n.tr("auth.signInToEmpire", lang: appLanguage))
                    .foregroundStyle(.white.opacity(0.62))
            } else {
                Text(L10n.tr("auth.startCollection", lang: appLanguage))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .font(.system(size: 15, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var upsoledWordmark: some View {
        Image("UpsoledWordmark")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: horizontalSizeClass == .regular ? 64 : 56)
            .accessibilityLabel("Upsoled")
    }

    private var authOrSeparator: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
            Text(L10n.tr("auth.orContinue", lang: appLanguage))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.42))
            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
        }
    }

    private func circleNavButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background {
                    DashboardChromeHeaderCircleBackground(size: 44)
                }
        }
        .buttonStyle(.plain)
    }

    private func authGlassField<Content: View, Trailing: View>(
        icon: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(upsoledAccentBright)
                .frame(width: 22)
            content()
                .font(.system(size: 15, weight: .medium))
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.32))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                }
        }
    }

    private enum SocialAuthButtonStyle { case dark, light }

    private func socialAuthButton(
        icon: String,
        title: String,
        style: SocialAuthButtonStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(style == .light ? .black : .white)
                    .frame(width: 22, alignment: .center)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(style == .light ? .black : .white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(style == .light ? Color.white : Color(red: 0.08, green: 0.14, blue: 0.28))
            }
        }
        .buttonStyle(.plain)
    }

    private var resetPasswordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.tr("auth.email", lang: appLanguage), text: $resetEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                if let resetInfo {
                    Section {
                        Text(resetInfo).font(.footnote)
                    }
                }
            }
            .navigationTitle(L10n.tr("auth.resetAccess", lang: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close", lang: appLanguage)) {
                        showResetSheet = false
                        resetInfo = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("common.send", lang: appLanguage)) {
                        Task {
                            resetInfo = await auth.resetPassword(email: resetEmail)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Glass helpers

private struct AuthDarkGlassPanel: View {
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            // Capa base ultraThinMaterial — blur del fondo
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)

            // Tinte azul premium
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            upsoledAccent.opacity(0.20),
                            Color.white.opacity(0.04),
                            upsoledAccent.opacity(0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Highlight superior (gloss de cristal)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .blendMode(.plusLighter)
                .opacity(0.55)

            // Borde con gradiente cyan refinado
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            upsoledAccentBright.opacity(0.60),
                            Color.white.opacity(0.15),
                            upsoledAccent.opacity(0.35),
                            upsoledAccentBright.opacity(0.20),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        }
        .shadow(color: upsoledAccent.opacity(0.35), radius: 32, y: 18)
        .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
    }
}

#Preview {
    LoginView(auth: AuthViewModel())
}

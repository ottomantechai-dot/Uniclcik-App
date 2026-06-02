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
private let upsoledBrandGradient = LinearGradient(
    colors: [
        Color(red: 0.25, green: 0.52, blue: 0.98),
        Color(red: 0.58, green: 0.38, blue: 0.96),
    ],
    startPoint: .leading,
    endPoint: .trailing
)

struct LoginView: View {
    @ObservedObject var auth: AuthViewModel

    @State private var phase: AuthPhase = .welcome
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var showPassword = false
    @State private var showResetSheet = false
    @State private var resetEmail = ""
    @State private var resetInfo: String?
    @State private var showHelpAlert = false
    @State private var rememberMe = true
    @AppStorage("auth.savedEmail") private var savedEmail = ""

    private var canSubmit: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6
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
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.3), value: phase)
        .onChange(of: phase) { _, new in
            if new == .signIn, !savedEmail.isEmpty {
                email = savedEmail
            }
        }
        .sheet(isPresented: $showResetSheet) {
            resetPasswordSheet
        }
        .alert(L10n.tr("auth.helpTitle"), isPresented: $showHelpAlert) {
            Button(L10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(L10n.tr("auth.helpBody"))
        }
    }

    // MARK: - Fondo

    private var authBackground: some View {
        ZStack {
            GeometryReader { geo in
                Image("FondoLogin")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            // Degradado suave arriba (titular) y abajo (botones).
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.88),
                        Color.white.opacity(0.35),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: min(UIScreen.main.bounds.height * 0.32, 280))

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.92),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: min(UIScreen.main.bounds.height * 0.42, 380))
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    // MARK: - Bienvenida (landing)

    private var welcomeLayer: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                welcomeLandingHeadline
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer(minLength: 24)

            welcomeLandingActions
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
        }
    }

    private var welcomeLandingHeadline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("auth.landingHeadline1"))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.90))

            Text(L10n.tr("auth.landingHeadline2"))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(upsoledBrandGradient)

            Text(L10n.tr("auth.landingSubtitle"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private var welcomeLandingActions: some View {
        VStack(spacing: 14) {
            Button {
                phase = .signUp
                auth.lastErrorMessage = nil
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 17, weight: .semibold))
                    Text(L10n.tr("auth.registerWithEmail"))
                        .font(.system(size: 17, weight: .bold))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .heavy))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.22)))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background {
                    Capsule(style: .continuous)
                        .fill(upsoledBrandGradient)
                        .shadow(color: Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.35), radius: 16, y: 8)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text(L10n.tr("auth.alreadyHaveAccountShort"))
                    .foregroundStyle(Color.black.opacity(0.45))
                Button(L10n.tr("auth.signIn")) {
                    phase = .signIn
                    auth.lastErrorMessage = nil
                }
                .foregroundStyle(Color(red: 0.58, green: 0.38, blue: 0.96))
                .fontWeight(.bold)
            }
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Sign in / Sign up

    private var innerAuthLayer: some View {
        VStack(spacing: 0) {
            HStack {
                circleNavButton(systemName: "chevron.left") {
                    phase = .welcome
                    auth.lastErrorMessage = nil
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            authFormHeader
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 16)

            authGlassFormCard
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
        }
    }

    private var authFormHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if phase == .signIn {
                Text(L10n.tr("auth.welcomeLine1"))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.90))
                Text(L10n.tr("auth.welcomeLine2"))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(upsoledBrandGradient)
            } else {
                Text(L10n.tr("auth.signUpLine1"))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.90))
                Text(L10n.tr("auth.signUpLine2"))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(upsoledBrandGradient)
            }

            Text(phase == .signIn ? L10n.tr("auth.signInCardSubtitle") : L10n.tr("auth.signUpCardSubtitle"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var authGlassFormCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                authGlassField(icon: "envelope.fill") {
                    TextField("", text: $email, prompt: Text(L10n.tr("auth.email")).foregroundStyle(Color.black.opacity(0.35)))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(Color.black.opacity(0.88))
                }

                authGlassField(
                    icon: "lock.fill",
                    trailing: {
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.40))
                        }
                        .buttonStyle(.plain)
                    }
                ) {
                    Group {
                        if showPassword {
                            TextField("", text: $password, prompt: Text(L10n.tr("auth.password")).foregroundStyle(Color.black.opacity(0.35)))
                        } else {
                            SecureField("", text: $password, prompt: Text(L10n.tr("auth.password")).foregroundStyle(Color.black.opacity(0.35)))
                        }
                    }
                    .textContentType(phase == .signUp ? .newPassword : .password)
                    .foregroundStyle(Color.black.opacity(0.88))
                }
            }

            if let msg = auth.lastErrorMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if phase == .signIn {
                HStack {
                    Button {
                        rememberMe.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(rememberMe ? Color(red: 0.58, green: 0.38, blue: 0.96) : Color.black.opacity(0.35))
                            Text(L10n.tr("auth.rememberMe"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.55))
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button(L10n.tr("auth.forgot")) {
                        resetEmail = email
                        showResetSheet = true
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.58, green: 0.38, blue: 0.96))
                }
            }

            authPrimaryButton(
                title: phase == .signIn ? L10n.tr("auth.signIn") : L10n.tr("auth.createAccount"),
                isBusy: isBusy
            ) {
                Task {
                    isBusy = true
                    defer { isBusy = false }
                    if phase == .signUp {
                        await auth.signUp(email: email, password: password)
                    } else {
                        if rememberMe {
                            savedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            savedEmail = ""
                        }
                        await auth.signIn(email: email, password: password)
                    }
                }
            }

            HStack(spacing: 4) {
                Text(phase == .signIn ? L10n.tr("auth.noAccount") : L10n.tr("auth.alreadyHaveAccount"))
                    .foregroundStyle(Color.black.opacity(0.45))
                Button(phase == .signIn ? L10n.tr("auth.signUp") : L10n.tr("auth.signIn")) {
                    phase = phase == .signIn ? .signUp : .signIn
                    auth.lastErrorMessage = nil
                }
                .foregroundStyle(Color(red: 0.58, green: 0.38, blue: 0.96))
                .fontWeight(.bold)
            }
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.96))
                .shadow(color: Color.black.opacity(0.10), radius: 24, y: 10)
        }
    }

    private func authPrimaryButton(title: String, isBusy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isBusy {
                    ProgressView().tint(.white)
                }
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .heavy))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.22)))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(upsoledBrandGradient)
                    .shadow(color: Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.35), radius: 16, y: 8)
            }
        }
        .disabled(!canSubmit || isBusy)
        .buttonStyle(.plain)
    }

    private func circleNavButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
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
                .foregroundStyle(upsoledAccent)
                .frame(width: 22)
            content()
                .font(.system(size: 15, weight: .medium))
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.96, green: 0.97, blue: 0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75)
                }
        }
    }

    private var resetPasswordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.tr("auth.email"), text: $resetEmail)
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
            .navigationTitle(L10n.tr("auth.resetAccess"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) {
                        showResetSheet = false
                        resetInfo = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("common.send")) {
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

import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject private var appLock: AppLockManager
    @EnvironmentObject private var auth: AuthViewModel

    @State private var pinEntry = ""

    var body: some View {
        ZStack {
            // Fondo gradiente azul oscuro tipo Upsoled
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.07, blue: 0.18),
                    Color(red: 0.05, green: 0.09, blue: 0.18),
                    Color(red: 0.02, green: 0.04, blue: 0.09),
                    Color.black,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Glow azul principal
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.22, green: 0.55, blue: 0.98).opacity(0.35),
                            Color(red: 0.22, green: 0.55, blue: 0.98).opacity(0.08),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 320
                    )
                )
                .frame(width: 560, height: 560)
                .blur(radius: 16)
                .offset(y: -160)
                .allowsHitTesting(false)

            // Sneaker decorativa en el fondo, sutil y desenfocada
            Image("AuthSneakerHero")
                .resizable()
                .scaledToFit()
                .frame(width: 360, height: 360)
                .rotationEffect(.degrees(-22))
                .opacity(0.10)
                .blur(radius: 1.5)
                .offset(x: 90, y: -200)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                profileBlock

                Text(timeGreeting + ", " + auth.shortGreetingName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                pinDotsRow
                    .padding(.top, 36)

                Spacer(minLength: 20)

                pinKeypad

                if let err = appLock.authError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                }

                Button {
                    Task {
                        if let uid = auth.session?.user.id {
                            appLock.clearPINForUser(uid)
                        }
                        await auth.signOut()
                    }
                } label: {
                    Text("¿Has olvidado tu clave de acceso?")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1)
        }
        .onAppear {
            pinEntry = ""
            appLock.authenticateWithBiometry()
        }
        .onChange(of: appLock.authError) { _, new in
            if new != nil {
                pinEntry = ""
            }
        }
        .onChange(of: appLock.isUnlocked) { _, unlocked in
            if unlocked {
                pinEntry = ""
            }
        }
    }

    private var profileBlock: some View {
        Group {
            if let img = auth.profileAvatarImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Text(auth.userInitials)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
            }
        }
    }

    private var pinDotsRow: some View {
        HStack(spacing: 14) {
            ForEach(0 ..< 6, id: \.self) { i in
                Circle()
                    .fill(i < pinEntry.count ? Color.white : Color.white.opacity(0.28))
                    .frame(width: 14, height: 14)
            }
        }
    }

    private var keypadButtonSize: CGFloat { 72 }

    private var pinKeypad: some View {
        VStack(spacing: 18) {
            ForEach(0 ..< 3, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(0 ..< 3, id: \.self) { col in
                        let digit = String(row * 3 + col + 1)
                        keypadDigitButton(digit)
                    }
                }
            }
            HStack(spacing: 18) {
                keypadBiometryButton
                keypadDigitButton("0")
                keypadDeleteButton
            }
        }
        .frame(maxWidth: 400)
        .padding(.horizontal, 40)
        .contentShape(Rectangle())
    }

    private func keypadDigitButton(_ digit: String) -> some View {
        Text(digit)
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(.white)
            .frame(minWidth: keypadButtonSize, minHeight: keypadButtonSize)
            .background(Color.white.opacity(0.18), in: Circle())
            .contentShape(Circle())
            .opacity(appLock.isAuthenticating ? 0.45 : 1)
            .allowsHitTesting(!appLock.isAuthenticating)
            .onTapGesture {
                guard pinEntry.count < 6 else { return }
                pinEntry.append(digit)
                if pinEntry.count == 6 {
                    appLock.submitPIN(pinEntry)
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Dígito \(digit)"))
    }

    private var keypadBiometryButton: some View {
        Button {
            appLock.authenticateWithBiometry()
        } label: {
            Image(systemName: biometrySymbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: keypadButtonSize, height: keypadButtonSize)
                .background(Color.white.opacity(0.18), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(appLock.isAuthenticating)
    }

    private var keypadDeleteButton: some View {
        Image(systemName: "delete.left")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(minWidth: keypadButtonSize, minHeight: keypadButtonSize)
            .background(Color.white.opacity(0.12), in: Circle())
            .contentShape(Circle())
            .opacity(appLock.isAuthenticating ? 0.45 : 1)
            .allowsHitTesting(!appLock.isAuthenticating)
            .onTapGesture {
                if !pinEntry.isEmpty {
                    pinEntry.removeLast()
                    appLock.authError = nil
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Borrar"))
    }

    private var biometrySymbol: String {
        switch appLock.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        @unknown default: return "lock.fill"
        }
    }

    private var timeGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5 ..< 12: return "Buenos días"
        case 12 ..< 20: return "Buenas tardes"
        default: return "Buenas noches"
        }
    }
}

#Preview {
    LockScreenView()
        .environmentObject(AppLockManager())
        .environmentObject(AuthViewModel())
}

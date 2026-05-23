import SwiftUI

/// Tras iniciar sesión por primera vez (sin PIN en Keychain): crear PIN de 6 dígitos dos veces.
struct PINSetupView: View {
    @EnvironmentObject private var appLock: AppLockManager
    @EnvironmentObject private var auth: AuthViewModel

    @State private var phase: Phase = .enterFirst
    @State private var firstPIN = ""
    @State private var currentEntry = ""
    @State private var mismatch = false

    private enum Phase {
        case enterFirst
        case confirm
    }

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

            // Sneaker decorativa de fondo
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
                Spacer(minLength: 32)

                Text(phase == .enterFirst ? "Crea tu PIN" : "Confirma tu PIN")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("6 dígitos para desbloquear la app. Face ID seguirá disponible.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)

                pinDotsRow
                    .padding(.top, 32)

                if mismatch {
                    Text("Los PIN no coinciden. Inténtalo de nuevo.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.top, 16)
                }

                Spacer(minLength: 24)

                setupKeypad

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1)
        }
        .onChange(of: currentEntry) { _, new in
            guard new.count == 6 else { return }
            switch phase {
            case .enterFirst:
                firstPIN = new
                currentEntry = ""
                phase = .confirm
                mismatch = false
            case .confirm:
                if new == firstPIN {
                    if let uid = auth.session?.user.id {
                        appLock.savePINAndUnlock(new, userId: uid)
                    } else {
                        mismatch = true
                        currentEntry = ""
                    }
                } else {
                    mismatch = true
                    currentEntry = ""
                }
            }
        }
    }

    private var pinDotsRow: some View {
        HStack(spacing: 14) {
            ForEach(0 ..< 6, id: \.self) { i in
                Circle()
                    .fill(i < currentEntry.count ? Color.white : Color.white.opacity(0.28))
                    .frame(width: 14, height: 14)
            }
        }
    }

    private var keypadButtonSize: CGFloat { 72 }

    /// Teclado numérico: `onTapGesture` + `contentShape` evita fallos de `Button` en iPad
    /// (comportamiento reportado en revisión de App Store sobre «Crea tu PIN»).
    private var setupKeypad: some View {
        VStack(spacing: 18) {
            ForEach(0 ..< 3, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(0 ..< 3, id: \.self) { col in
                        let digit = String(row * 3 + col + 1)
                        keypadDigitCell(digit)
                    }
                }
            }
            HStack(spacing: 18) {
                Color.clear
                    .frame(width: keypadButtonSize, height: keypadButtonSize)
                    .allowsHitTesting(false)
                keypadDigitCell("0")
                keypadDeleteCell
            }
        }
        .frame(maxWidth: 400)
        .padding(.horizontal, 40)
        .contentShape(Rectangle())
    }

    private func keypadDigitCell(_ digit: String) -> some View {
        Text(digit)
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(.white)
            .frame(minWidth: keypadButtonSize, minHeight: keypadButtonSize)
            .background(Color.white.opacity(0.18), in: Circle())
            .contentShape(Circle())
            .onTapGesture {
                guard currentEntry.count < 6 else { return }
                currentEntry.append(digit)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Dígito \(digit)"))
    }

    private var keypadDeleteCell: some View {
        Image(systemName: "delete.left")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(minWidth: keypadButtonSize, minHeight: keypadButtonSize)
            .background(Color.white.opacity(0.12), in: Circle())
            .contentShape(Circle())
            .onTapGesture {
                if !currentEntry.isEmpty {
                    currentEntry.removeLast()
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Borrar"))
    }
}

#Preview {
    PINSetupView()
        .environmentObject(AppLockManager())
        .environmentObject(AuthViewModel())
}

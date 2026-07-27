import SwiftUI

/// Conectar cuenta GOAT / Alias — solo correo y contraseña.
struct GoatConnectSheetView: View {
    @ObservedObject var goatVM: GoatAccountViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var account = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if goatVM.isConnected, let session = goatVM.session {
                        connectedView(session)
                    } else {
                        signInForm
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("GOAT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { dismiss() }
                        .foregroundStyle(Color.black)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                StylizedMarketplaceLogo(brand: "GOAT")
                    .frame(width: 56, height: 56)
                Spacer()
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("settings.goatSignInTitle"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.92))
                Text(L10n.tr("settings.goatSignInSubtitle"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.52))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))

                TextField("Correo", text: $account)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    }
                    .onChange(of: account) { _, _ in
                        goatVM.clearLastError()
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))

                SecureField("Contraseña", text: $password)
                    .textContentType(.password)
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    }
                    .onSubmit { performSignIn() }
                    .onChange(of: password) { _, _ in
                        goatVM.clearLastError()
                    }
            }

            if let err = goatVM.lastError {
                Text(err)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: performSignIn) {
                HStack(spacing: 8) {
                    if goatVM.isSigningIn {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(goatVM.isSigningIn ? L10n.tr("settings.goatSigningIn") : L10n.tr("settings.goatSignIn"))
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSignInReady ? Color.black : Color.black.opacity(0.35))
                }
            }
            .buttonStyle(.plain)
            .disabled(!isSignInReady)
            .padding(.top, 4)
        }
    }

    private func performSignIn() {
        guard isSignInReady else { return }
        Task {
            let ok = await goatVM.signIn(account: account, password: password)
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }

    private func connectedView(_ session: GoatAccountSession) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                StylizedMarketplaceLogo(brand: "GOAT")
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(L10n.tr("settings.approved"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))

                    Text(session.connectedLabel)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.92))

                    Text(session.accountEmail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.20, green: 0.70, blue: 0.45).opacity(0.08))
            }

            Button(role: .destructive) {
                goatVM.disconnect()
            } label: {
                Text(L10n.tr("settings.goatDisconnect"))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.bordered)
        }
    }

    private var isSignInReady: Bool {
        !password.isEmpty && !goatVM.isSigningIn
    }
}

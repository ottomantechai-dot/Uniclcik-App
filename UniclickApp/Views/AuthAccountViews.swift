import PhoneNumberKit
import SwiftUI

@MainActor
struct AuthPhoneEntry {
    private static let utility = PhoneNumberUtility()

    var number: String

    init(number: String = "") {
        self.number = number
        formatPastedNumber()
    }

    var internationalNumber: String? {
        parsedNumber.map { Self.utility.format($0, toType: .e164) }
    }

    private var parsedNumber: PhoneNumber? {
        guard let parsed = try? Self.utility.parse(number, withRegion: "US"),
              parsed.countryCode == 1,
              parsed.numberExtension == nil,
              Self.utility.getRegionCode(of: parsed) == "US" else { return nil }
        return parsed
    }

    mutating func formatPastedNumber() {
        guard number.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+"),
              let parsedNumber else { return }
        number = Self.utility.format(parsedNumber, toType: .national)
    }
}

struct AuthPhoneField: View {
    @Binding var phone: AuthPhoneEntry
    @FocusState private var isFocused: Bool

    private var showsInvalidNumber: Bool {
        phone.internationalNumber == nil
            && (isFocused ? phone.number.filter(\.isNumber).count >= 10 : !phone.number.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Phone number")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                USFlagBadge()
                    .accessibilityHidden(true)

                HStack {
                    Text("+1")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("(201) 555-0123", text: $phone.number)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($isFocused)
                        .accessibilityLabel("U.S. phone number, country code plus one")
                        .onChange(of: phone.number) { phone.formatPastedNumber() }
                }
                .authFieldContainer()
            }

            if showsInvalidNumber {
                Text("Enter a valid U.S. phone number.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct USFlagBadge: View {
    var body: some View {
        Canvas { context, size in
            let stripe = size.height / 13
            let canton = CGRect(x: 0, y: 0, width: size.width * 0.65, height: 7 * stripe)
            let red = Color(red: 0.70, green: 0.10, blue: 0.20)
            let blue = Color(red: 0.14, green: 0.21, blue: 0.40)

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for row in stride(from: 0, to: 13, by: 2) {
                let band = CGRect(x: 0, y: CGFloat(row) * stripe, width: size.width, height: stripe)
                context.fill(Path(band), with: .color(red))
            }
            context.fill(Path(canton), with: .color(blue))

            var stars = Path()
            let columnSpacing = canton.width / 12
            let rowSpacing = canton.height / 10
            let radius = stripe * 0.32
            for row in 1...9 {
                let columns = row.isMultiple(of: 2)
                    ? stride(from: 2, through: 10, by: 2)
                    : stride(from: 1, through: 11, by: 2)
                for column in columns {
                    let center = CGPoint(x: CGFloat(column) * columnSpacing, y: CGFloat(row) * rowSpacing)
                    for point in 0..<10 {
                        let angle = Double(point) * .pi / 5 - .pi / 2
                        let distance = point.isMultiple(of: 2) ? radius : radius * 0.4
                        let vertex = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                        if point == 0 { stars.move(to: vertex) } else { stars.addLine(to: vertex) }
                    }
                    stars.closeSubpath()
                }
            }
            context.fill(stars, with: .color(.white))
        }
        .frame(width: 33, height: 33)
        .clipShape(.circle)
        .overlay {
            Circle().strokeBorder(.white.opacity(0.52), lineWidth: 1)
        }
        .frame(width: 46, height: 46)
        .glassEffect(.regular, in: .circle)
    }
}

struct AuthRecoveryView: View {
    @ObservedObject var auth: AuthViewModel
    let onBack: () -> Void
    @State private var email: String
    @State private var phone = AuthPhoneEntry()
    @State private var mode: Mode = .email
    @State private var step: Step = .request
    @State private var input = ""
    @State private var isWorking = false

    private enum Mode: Hashable { case email, sms }
    private enum Step: Equatable { case request, emailSent, smsSent(String) }

    init(auth: AuthViewModel, email: String, onBack: @escaping () -> Void) {
        self.auth = auth
        self.onBack = onBack
        _email = State(initialValue: email)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recover your password")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .foregroundStyle(.secondary)

            switch step {
            case .request: requestForm
            case .emailSent: emailVerification
            case let .smsSent(target): smsVerification(target)
            }

            AuthInlineError(message: auth.lastErrorMessage)

            Button(action: onBack) {
                Text("Back to sign in")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AuthEntryStyle.red)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
        .padding(.top, 4)
        .task { await auth.refreshMethods() }
    }

    private var subtitle: String {
        switch step {
        case .request:
            "Choose how to verify that the account is yours."
        case .emailSent:
            "If an account matches, you’ll receive an email. Open its link on this iPhone or paste the original link below."
        case .smsSent:
            "If the phone is verified on an account, you’ll receive a code."
        }
    }

    private var requestForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Recovery method", selection: $mode) {
                Text("Email").tag(Mode.email)
                Text("SMS").tag(Mode.sms)
            }
            .pickerStyle(.segmented)
            .disabled(isWorking)
            .onChange(of: mode) { auth.lastErrorMessage = nil }

            if mode == .email {
                AuthEmailField(email: $email)

                AuthAccountButton(
                    title: "Send recovery link",
                    busy: isWorking,
                    enabled: email.contains("@") && email.contains(".")
                ) {
                    run {
                        if await auth.sendRecoveryEmail(email) { step = .emailSent }
                    }
                }
            } else {
                AuthPhoneField(phone: $phone)
                if auth.methods?.phoneEnabled != true {
                    Text("SMS recovery is unavailable. You can still use your email.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                AuthAccountButton(
                    title: "Send SMS code",
                    busy: isWorking,
                    enabled: auth.methods?.phoneEnabled == true && phone.internationalNumber != nil
                ) {
                    guard let number = phone.internationalNumber else { return }
                    run {
                        if await auth.sendRecoverySMS(number) { step = .smsSent(number) }
                    }
                }
            }
        }
    }

    private var emailVerification: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Paste the recovery link", text: $input)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .authFieldContainer()
            AuthAccountButton(
                title: "Verify link", busy: isWorking,
                enabled: !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                run { await auth.confirmRecoveryLink(input) }
            }
            restartButton
        }
    }

    private func smsVerification(_ target: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            AuthCodeField(code: $input)
            AuthAccountButton(
                title: "Verify code", busy: isWorking,
                enabled: AuthCodeField.isComplete(input)
            ) {
                run { await auth.confirmRecoverySMS(target, code: input) }
            }
            restartButton
        }
    }

    private var restartButton: some View {
        Button("Use a different email or phone") {
            auth.lastErrorMessage = nil
            input = ""
            step = .request
        }
        .font(.subheadline.weight(.semibold))
        .disabled(isWorking)
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            await action()
        }
    }
}

struct RecoveredPasswordView: View {
    @ObservedObject var auth: AuthViewModel
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isWorking = false

    var body: some View {
        AuthEntryScreen {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create a new password")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Enter at least six characters.")
                    .foregroundStyle(.secondary)

                AuthLabeledField(title: "New password", icon: "lock") {
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                }
                AuthLabeledField(title: "Confirm password", icon: "lock") {
                    SecureField("Confirm password", text: $confirmation)
                        .textContentType(.newPassword)
                }

                AuthInlineError(message: auth.lastErrorMessage)
                AuthAccountButton(
                    title: "Save password", busy: isWorking,
                    enabled: password.count >= 6 && password == confirmation
                ) {
                    isWorking = true
                    Task {
                        defer { isWorking = false }
                        await auth.changeRecoveredPassword(password)
                    }
                }
                Button(role: .cancel) {
                    isWorking = true
                    Task {
                        defer { isWorking = false }
                        await auth.cancelRecovery()
                    }
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AuthEntryStyle.red)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
            .padding(.top, 4)
        }
    }
}

struct RegistrationPhoneView: View {
    @ObservedObject var auth: AuthViewModel
    @State private var phone: AuthPhoneEntry
    @State private var pendingNumber: String?
    @State private var input = ""
    @State private var isWorking = false

    init(auth: AuthViewModel) {
        self.auth = auth
        _phone = State(initialValue: AuthPhoneEntry(number: auth.registrationPhone ?? ""))
    }

    var body: some View {
        AuthAccountScreen(
            title: "Finish your registration",
            subtitle: pendingNumber == nil
                ? "Add your phone number to continue to setup."
                : "Enter the verification code we sent you.",
            icon: "phone.circle"
        ) {
            if let target = pendingNumber {
                AuthCodeField(code: $input)
                AuthAccountButton(
                    title: "Verify phone",
                    busy: isWorking, enabled: AuthCodeField.isComplete(input)
                ) {
                    run { await auth.confirmRegistrationPhone(target, code: input) }
                }
                Button("Change number") {
                    auth.lastErrorMessage = nil
                    input = ""
                    pendingNumber = nil
                }
                .disabled(isWorking)
            } else {
                AuthPhoneField(phone: $phone)
                AuthAccountButton(
                    title: "Continue",
                    busy: isWorking, enabled: phone.internationalNumber != nil
                ) {
                    guard let number = phone.internationalNumber else { return }
                    run {
                        if await auth.saveRegistrationPhone(number) == .needsCode {
                            pendingNumber = number
                        }
                    }
                }
            }
            AuthInlineError(message: auth.lastErrorMessage)
            Button("Sign out", role: .cancel) {
                run { await auth.signOut() }
            }
            .disabled(isWorking)
        }
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            await action()
        }
    }
}

private struct AuthCodeField: View {
    @Binding var code: String

    static func isComplete(_ code: String) -> Bool {
        (6...10).contains(code.count) && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    var body: some View {
        TextField("Verification code", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .authFieldContainer()
    }
}

private struct AuthAccountScreen<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 52, height: 52)
                    .background(.red.opacity(0.08), in: .rect(cornerRadius: 16))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                content
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.immediately)
        .background(Color.white.ignoresSafeArea())
        .tint(Color(red: 0.78, green: 0.03, blue: 0.09))
    }
}

struct AuthAccountButton: View {
    let title: String
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if busy { ProgressView().tint(.white) } else { Text(title) }
            }
            .font(.headline)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(AuthEntryStyle.red.opacity(enabled || busy ? 1 : 0.8), in: .rect(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .accessibilityLabel(title)
    }
}

private struct AuthInlineError: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.red)
        }
    }
}

private extension View {
    func authFieldContainer() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .background(.white, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(red: 0.87, green: 0.84, blue: 0.85))
                    .allowsHitTesting(false)
            }
    }
}

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct LoginView: View {
    @ObservedObject var auth: AuthViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Mode { case signIn, signUp, recovery }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var phone = AuthPhoneEntry()
    @State private var isBusy = false
    @State private var showPassword = false
    @State private var registrationNotice: String?
    @State private var rememberMe = true
    @AppStorage("auth.savedEmail") private var savedEmail = ""

    private var isSignUp: Bool { mode == .signUp }
    private var passwordTitle: String { "Password" }

    private var actionTitle: String {
        isSignUp ? "Create account" : "Sign in"
    }

    private var canSubmit: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6
            && (!isSignUp || phone.internationalNumber != nil)
    }

    var body: some View {
        AuthEntryScreen {
            if mode == .recovery {
                AuthRecoveryView(auth: auth, email: email) { show(.signIn) }
            } else {
                form
            }
        }
        .onAppear {
            if email.isEmpty { email = savedEmail }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(actionTitle)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, isSignUp ? 20 : 10)

            VStack(spacing: 14) {
                AuthEmailField(email: $email, contentType: .username, showsGreeting: true)

                AuthLabeledField(title: passwordTitle, icon: "lock") {
                    Group {
                        if showPassword {
                            TextField(passwordTitle, text: $password)
                        } else {
                            SecureField(passwordTitle, text: $password)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(isSignUp ? .newPassword : .password)

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }

                if isSignUp {
                    AuthPhoneField(phone: $phone)
                }
            }

            if !isSignUp {
                signInOptions
                    .padding(.top, 4)
            }

            if let message = auth.lastErrorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AuthEntryStyle.red)
                    .padding(.top, 8)
            }

            if let registrationNotice {
                Label(registrationNotice, systemImage: "envelope.badge")
                    .font(.footnote.weight(.medium))
                    .padding(.top, 10)
            }

            submitButton
                .padding(.top, isSignUp ? 20 : 8)

            providerAccess
                .padding(.top, 20)

            accountSwitch
                .padding(.top, 16)
        }
        .padding(.top, 4)
    }

    private var signInOptions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                rememberButton
                Spacer(minLength: 0)
                forgotButton
            }

            VStack(alignment: .leading, spacing: 0) {
                rememberButton
                forgotButton
            }
        }
        .font(.footnote.weight(.semibold))
    }

    private var rememberButton: some View {
        Button {
            rememberMe.toggle()
        } label: {
            Label("Remember me", systemImage: rememberMe ? "checkmark.square.fill" : "square")
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(rememberMe ? .isSelected : [])
    }

    private var forgotButton: some View {
        Button {
            show(.recovery)
        } label: {
            Text("Forgot your password?")
                .foregroundStyle(AuthEntryStyle.red)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private var submitButton: some View {
        AuthAccountButton(title: actionTitle, busy: isBusy, enabled: canSubmit) {
            guard canSubmit, !isBusy else { return }
            isBusy = true
            Task {
                defer { isBusy = false }
                if isSignUp {
                    guard let number = phone.internationalNumber else { return }
                    registrationNotice = nil
                    registrationNotice = await auth.signUp(email: email, password: password, phone: number)
                    if registrationNotice != nil { password = "" }
                } else {
                    savedEmail = rememberMe ? email.trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    await auth.signIn(email: email, password: password)
                }
            }
        }
    }

    private var providerAccess: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Rectangle().fill(AuthEntryStyle.fieldBorder).frame(height: 1).accessibilityHidden(true)
                Text("Or continue with")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Rectangle().fill(AuthEntryStyle.fieldBorder).frame(height: 1).accessibilityHidden(true)
            }

            GlassEffectContainer(spacing: 8) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))

                layout {
                    ForEach(AuthViewModel.IdentityProvider.allCases, id: \.self) { provider in
                        Button {
                            isBusy = true
                            registrationNotice = nil
                            Task {
                                defer { isBusy = false }
                                await auth.signIn(with: provider)
                            }
                        } label: {
                            providerLabel(provider)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(.capsule)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Continue with \(provider.rawValue)")
                    }
                }
            }
            .disabled(isBusy)
        }
    }

    @ViewBuilder
    private func providerLabel(_ provider: AuthViewModel.IdentityProvider) -> some View {
        switch provider {
        case .google:
            Label {
                Text(provider.rawValue)
            } icon: {
                Image("Social-google")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 19, height: 19)
            }
        case .stockX:
            Image("stockx")
                .resizable()
                .scaledToFit()
                .frame(width: 74, height: 24)
        case .apple:
            Label(provider.rawValue, systemImage: "apple.logo")
        }
    }

    private var accountSwitch: some View {
        Button {
            withAnimation(.snappy) { show(isSignUp ? .signIn : .signUp) }
        } label: {
            let prompt = isSignUp
                ? "Already have an account?"
                : "Don't have an account?"
            let action = isSignUp ? "Sign in" : "Sign up"

            Text("\(Text(prompt).foregroundStyle(.secondary)) \(Text(action).bold().foregroundStyle(AuthEntryStyle.red))")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func show(_ mode: Mode) {
        auth.lastErrorMessage = nil
        registrationNotice = nil
        showPassword = false
        self.mode = mode
    }

}

enum AuthEntryStyle {
    static let red = Color(red: 0.78, green: 0.03, blue: 0.09)
    static let headerRed = Color(red: 1, green: 0.10, blue: 0.12)
    static let ink = Color(red: 0.08, green: 0.07, blue: 0.08)
    static let fieldBorder = Color(red: 0.87, green: 0.84, blue: 0.85)
}

struct AuthEntryScreen<Content: View>: View {
    @ViewBuilder let content: Content

    private let headerMarks: [(x: CGFloat, y: CGFloat, scale: CGFloat, opacity: Double)] = [
        (0.09, 0.19, 0.76, 0.46), (0.32, 0.045, 1.1, 0.64),
        (0.68, 0.055, 0.99, 0.42), (0.98, 0.135, 1.02, 0.60),
        (0.23, 0.44, 0.72, 0.30), (0.50, 0.39, 0.94, 0.53),
        (0.80, 0.46, 0.90, 0.47), (0.34, 0.69, 0.68, 0.31),
        (0.65, 0.77, 0.84, 0.26), (0.99, 0.75, 0.78, 0.20),
        (0.13, 1.02, 0.82, 0.30), (0.48, 1.06, 0.90, 0.33),
        (0.83, 1.03, 0.77, 0.28), (0.31, 1.29, 0.78, 0.29),
        (0.69, 1.31, 0.91, 0.27), (0.10, 1.50, 0.73, 0.23),
        (0.52, 1.53, 0.84, 0.25), (0.92, 1.49, 0.72, 0.22)
    ]

    var body: some View {
        GeometryReader { viewport in
            let topInset = viewport.safeAreaInsets.top
            let bottomInset = viewport.safeAreaInsets.bottom
            let screenHeight = viewport.size.height + topInset + bottomInset
            let topFadeEnd = min(1, (topInset + 14) / max(screenHeight, 1))
            let width = viewport.size.width
            let artworkWidth = min(width, 500)
            let cardHeight = artworkWidth * 0.625
            let heroHeight = cardHeight + 26

            ScrollView {
                VStack(spacing: 0) {
                    hero(width: artworkWidth, cardHeight: cardHeight, height: heroHeight)
                        .frame(width: width)
                        .padding(.top, topInset)

                    content
                        .padding(.horizontal, 24)
                        .padding(.bottom, max(24, bottomInset + 12))
                        .frame(maxWidth: 452)
                        .frame(maxWidth: .infinity)
                        .background(.white)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectHidden(true, for: .bottom)
            .scrollDismissesKeyboard(.immediately)
            .mask {
                // Fade only under the status bar, keeping the entire bottom edge visible.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.45), location: topFadeEnd / 2),
                        .init(color: .black, location: topFadeEnd),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .background(alignment: .top) {
                headerBackdrop(topInset: topInset, heroHeight: heroHeight)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .foregroundStyle(AuthEntryStyle.ink)
        .tint(AuthEntryStyle.red)
    }

    private func headerBackdrop(topInset: CGFloat, heroHeight: CGFloat) -> some View {
        let referenceHeight = topInset + 106
        let patternHeight = min(topInset + heroHeight, referenceHeight * 1.78)

        return VStack(spacing: 0) {
            AuthEntryStyle.headerRed.frame(height: topInset)
            LinearGradient(
                stops: [
                    .init(color: AuthEntryStyle.headerRed, location: 0),
                    .init(color: Color(red: 1, green: 0.72, blue: 0.71), location: 0.53),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: heroHeight)
        }
        .overlay(alignment: .top) {
            Canvas { context, size in
                let mark = context.resolve(Image("LoginBrandPattern"))
                let unit = min(size.width / 8, 54)

                for tile in headerMarks {
                    let width = unit * tile.scale
                    let height = width * 726 / 663
                    let rect = CGRect(
                        x: size.width * tile.x - width / 2,
                        y: referenceHeight * tile.y - height / 2,
                        width: width,
                        height: height
                    )
                    var layer = context
                    layer.opacity = tile.opacity
                    layer.draw(mark, in: rect)
                }
            }
            .frame(height: patternHeight)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.57),
                        .init(color: .black.opacity(0.60), location: 0.86),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func hero(width: CGFloat, cardHeight: CGFloat, height: CGFloat) -> some View {
        let sideCardHeight = cardHeight * 0.90
        let cardCenter = cardHeight / 2 + 7

        return ZStack {
            ZStack {
                CollectibleSlabCard(card: .charizardEX, height: sideCardHeight)
                    .shadow(color: .black.opacity(0.13), radius: 6, y: 4)
                    .rotationEffect(.degrees(-11))
                    .position(x: width * 0.18, y: cardCenter + 10)
                CollectibleSlabCard(card: .megaBlastoiseEX, height: sideCardHeight)
                    .shadow(color: .black.opacity(0.13), radius: 6, y: 4)
                    .rotationEffect(.degrees(12))
                    .position(x: width * 0.82, y: cardCenter + 10)
                CollectibleSlabCard(card: .charizard, height: cardHeight)
                    .shadow(color: .black.opacity(0.13), radius: 6, y: 4)
                    .position(x: width / 2, y: cardCenter)
            }
            .frame(width: width, height: height)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.54),
                    .init(color: .white.opacity(0.30), location: 0.73),
                    .init(color: .white.opacity(0.82), location: 0.90),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityHidden(true)
    }

}

struct AuthEmailField: View {
    @Binding var email: String
    var contentType: UITextContentType = .emailAddress
    var showsGreeting = false

    var body: some View {
        AuthLabeledField(title: "Email address", icon: "envelope", showsGreeting: showsGreeting) {
            TextField("Email address", text: $email, prompt: Text("name@example.com"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(contentType)
        }
    }
}

struct AuthLabeledField<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    let title: String
    let icon: String
    var showsGreeting = false
    @ViewBuilder let content: Content

    private let greetingSize: CGFloat = 64
    private let fieldSpacing: CGFloat = 6
    var body: some View {
        VStack(alignment: .leading, spacing: fieldSpacing) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.trailing, showsGreeting ? greetingSize + 26 : 0)
                .frame(
                    minHeight: showsGreeting ? greetingSize - fieldSpacing : 0,
                    alignment: .bottomLeading
                )
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                content
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 54)
            .background(.white, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(AuthEntryStyle.fieldBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .background(alignment: .topTrailing) {
                if showsGreeting {
                    danielGreeting
                        .padding(.trailing, 20)
                        // Tuck the animation one physical pixel behind the top of the field.
                        .offset(y: -greetingSize + 1 / displayScale)
                }
            }
        }
    }

    private var danielGreeting: some View {
        Group {
            if reduceMotion {
                Image("DanielSticker").resizable().scaledToFit()
            } else {
                DanielVideo(pose: "hola")
            }
        }
        .frame(width: greetingSize, height: greetingSize)
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

}

struct CollectibleSlabCard: View {
    struct Card {
        let image: String
        let name: String
        let releaseDate: String
        let expansion: String
        let rarity: String
        let number: String
        let barcodeValue: String
        let barcodeImage: CGImage?

        init(image: String, name: String, releaseDate: String, expansion: String, rarity: String, number: String, barcodeValue: String) {
            self.image = image
            self.name = name
            self.releaseDate = releaseDate
            self.expansion = expansion
            self.rarity = rarity
            self.number = number
            self.barcodeValue = barcodeValue

            let filter = CIFilter.code128BarcodeGenerator()
            filter.message = Data(barcodeValue.utf8)
            filter.quietSpace = 10
            filter.barcodeHeight = 22
            barcodeImage = filter.outputImage.flatMap { Self.barcodeContext.createCGImage($0, from: $0.extent) }
        }

        private static let barcodeContext = CIContext()

        static let charizard = Card(
            image: "LoginCharizard", name: "Charizard", releaseDate: "02 NOV 2016",
            expansion: "XY—EVOLUTIONS", rarity: "HOLO", number: "11/108", barcodeValue: "DEMO-011"
        )
        static let charizardEX = Card(
            image: "LoginCharizardEX", name: "Charizard-EX", releaseDate: "02 NOV 2016",
            expansion: "XY—EVOLUTIONS", rarity: "HOLO EX", number: "12/108", barcodeValue: "DEMO-012"
        )
        static let megaBlastoiseEX = Card(
            image: "LoginMegaBlastoiseEX", name: "M Blastoise-EX", releaseDate: "02 NOV 2016",
            expansion: "XY—EVOLUTIONS", rarity: "HOLO EX", number: "22/108", barcodeValue: "DEMO-022"
        )
    }

    let card: Card
    let height: CGFloat

    private static let holderSize = CGSize(width: 758, height: 1280)
    static var aspectRatio: CGFloat { holderSize.width / holderSize.height }
    // Coordinates from card.svg. The badge overlaps the bottom edge of the label.
    private static let labelOpening = CGRect(x: 74, y: 71, width: 613, height: 153)
    private static let psaBadge = CGRect(x: 335, y: 186, width: 86, height: 58)
    private static let cardOpening = CGRect(x: 79, y: 342, width: 600, height: 841)

    private var scale: CGFloat { height / Self.holderSize.height }
    private var width: CGFloat { Self.holderSize.width * scale }

    var body: some View {
        let sizing = CGAffineTransform(scaleX: scale, y: scale)
        let label = Self.labelOpening.applying(sizing)
        let badge = Self.psaBadge.intersection(Self.labelOpening).applying(sizing)
        let artwork = Self.cardOpening.applying(sizing)

        ZStack(alignment: .topLeading) {
            Image(card.image)
                .resizable()
                .scaledToFit()
                .frame(width: artwork.width, height: artwork.height)
                .background(Color(white: 0.96))
                .position(x: artwork.midX, y: artwork.midY)

            cardLabel
                .frame(width: label.width, height: label.height)
                .background(.white)
                .position(x: label.midX, y: label.midY)

            Image("LoginSlabFrame")
                .resizable()
                .frame(width: width, height: height)
                .mask {
                    Canvas { context, size in
                        var holder = Path(CGRect(origin: .zero, size: size))
                        holder.addRect(label)
                        holder.addRect(artwork)
                        holder.addRect(badge)
                        context.fill(holder, with: .color(.white), style: FillStyle(eoFill: true))
                    }
                }

        }
        .frame(width: width, height: height)
    }

    private var cardLabel: some View {
        VStack(alignment: .leading, spacing: 0) {
            labelRow("\(card.releaseDate) · POKÉMON", trailing: "#\(card.number)")
            labelRow(card.name.uppercased(), trailing: "SAMPLE")
            labelRow("\(card.expansion) · \(card.rarity)")

            HStack {
                if let barcodeImage = card.barcodeImage {
                    Image(decorative: barcodeImage, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: scale * 218, height: scale * 33)
                }
                Spacer(minLength: 0)
                Text(verbatim: card.barcodeValue)
                    .font(.system(size: scale * 29))
                    .monospacedDigit()
            }
            .frame(height: scale * 36)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundStyle(.black)
        .padding(.horizontal, scale * 15)
    }

    private func labelRow(_ title: String, trailing: String? = nil) -> some View {
        HStack(spacing: scale * 16) {
            Text(verbatim: title)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Text(verbatim: trailing)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(.system(size: scale * 31))
        .frame(height: scale * 36)
    }
}

#Preview {
    LoginView(auth: AuthViewModel())
}

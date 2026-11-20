import SwiftUI

/// Raíz: sesión Supabase → app principal.
struct AuthRootView: View {
    @ObservedObject var auth: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel

    var body: some View {
        Group {
            if Self.previewsShoeReport {
                // Solo desarrollo (-uniclickPreviewReport): informe de un zapato sin precios, para ver el giro 360°.
                SaleReportView(report: SaleReport(title: "adidas Yeezy Boost 350 V2 Steel Grey", sku: "IF3219", scannedCode: "",
                                                  imageURL: nil, size: "9.5", costUSD: nil, lines: [], priceIsEstimate: false))
            } else if Self.previewsNewSections {
                // Solo en compilaciones de desarrollo y con el argumento -uniclickPreview: enseña las
                // secciones nuevas sin iniciar sesión, para poder probarlas en el simulador.
                MainTabView()
            } else if auth.isRestoringSession {
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    ProgressView(L10n.tr("auth.connecting"))
                }
            } else if Self.previewsOnboarding {
                // Solo desarrollo (-uniclickOnboarding): el onboarding y el recorrido sin iniciar sesión.
                OnboardedRoot(uid: "preview", force: true)
            } else if auth.isAuthenticated {
                // La primera vez que una cuenta entra en este teléfono pasa por el onboarding.
                let uid = auth.session?.user.id.uuidString ?? "guest"
                OnboardedRoot(uid: uid).id(uid)
            } else {
                LoginView(auth: auth)
            }
        }
        .environmentObject(auth)
        .onOpenURL { url in
            SupabaseClientProvider.shared.auth.handle(url)
        }
    }
}

extension AuthRootView {
    static var previewsShoeReport: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uniclickPreviewReport")
        #else
        return false
        #endif
    }

    static var previewsOnboarding: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uniclickOnboarding")
        #else
        return false
        #endif
    }

    static var previewsNewSections: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uniclickPreview")
        #else
        return false
        #endif
    }
}

#Preview {
    AuthRootView(auth: AuthViewModel())
        .environmentObject(CarsViewModel())
        .environmentObject(SettingsViewModel())
}

// MARK: - Textos en dos idiomas

/// La app está en inglés; si el teléfono está en español, el onboarding y el recorrido salen en español.
enum Tx {
    static let spanish = Locale.preferredLanguages.first?.hasPrefix("es") ?? false
    static func s(_ en: String, _ es: String) -> String { spanish ? es : en }
}

// MARK: - Daniel, el personaje guía

/// GIF animado de Daniel, guardado como dato en Assets (carpeta Daniel).
struct DanielGIF: UIViewRepresentable {
    let pose: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GIFPlayerContainerView {
        let view = GIFPlayerContainerView()
        view.playerView.contentMode = .scaleAspectFit
        load(into: view, context: context)
        return view
    }

    func updateUIView(_ view: GIFPlayerContainerView, context: Context) { load(into: view, context: context) }

    private func load(into view: GIFPlayerContainerView, context: Context) {
        guard context.coordinator.pose != pose else { return }
        context.coordinator.pose = pose
        view.playerView.configure(with: NSDataAsset(name: "Daniel-\(pose)")?.data ?? Data())
    }

    final class Coordinator { var pose: String? }
}

// MARK: - Onboarding de primer registro

enum OnboardingStore {
    private static func key(_ uid: String) -> String { "onboarding.done.\(uid)" }
    static func isDone(_ uid: String) -> Bool { UserDefaults.standard.bool(forKey: key(uid)) }
    static func finish(uid: String, answers: [String: [String]]) {
        UserDefaults.standard.set(true, forKey: key(uid))
        UserDefaults.standard.set(answers, forKey: "onboarding.answers.\(uid)")
    }
}

/// Raíz con sesión: onboarding la primera vez y, después, la app con el recorrido de Daniel.
struct OnboardedRoot: View {
    let uid: String
    @State private var done: Bool

    init(uid: String, force: Bool = false) {
        self.uid = uid
        _done = State(initialValue: force ? false : OnboardingStore.isDone(uid))
    }

    var body: some View {
        ZStack {
            if done {
                MainTabView().transition(.opacity)
            } else {
                OnboardingView { answers, start in
                    OnboardingStore.finish(uid: uid, answers: answers)
                    AppTour.shared.pending = start
                    AppTour.shared.autoStart = true
                    withAnimation(.smooth(duration: 0.45)) { done = true }
                }
                .transition(.opacity)
            }
        }
    }
}

private struct OnboardingOption: Identifiable {
    let id: String
    let icon: String
    let title: String
    var detail: String = ""
    /// Logo de la plataforma (StockX, GOAT…) en lugar del icono.
    var logo: String?
}

struct OnboardingView: View {
    /// Respuestas y por dónde quiere empezar (escanear, buscar o ver cartas).
    let onFinish: ([String: [String]], AppTour.StartAction) -> Void

    @State private var step = 0
    @State private var forward = true
    @State private var selling: String?
    @State private var goals: Set<String> = []
    @State private var profile: String?
    @State private var platforms: Set<String> = []
    @State private var heardFrom: String?

    private let lastStep = 5

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    page
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                        .padding(.horizontal, 22)
                        .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
            }
        }
        .preferredColorScheme(.light)
        .sensoryFeedback(.selection, trigger: step)
    }

    // Fondo claro con dos manchas suaves de color, como el resto de la app.
    private var background: some View {
        ZStack {
            Color(red: 0.965, green: 0.965, blue: 0.975)
            Circle().fill(Color(red: 0.93, green: 0.07, blue: 0.06).opacity(0.10)).frame(width: 380).blur(radius: 90).offset(x: -140, y: -300)
            Circle().fill(Color(red: 0.16, green: 0.44, blue: 0.98).opacity(0.10)).frame(width: 360).blur(radius: 90).offset(x: 160, y: -180)
        }
        .ignoresSafeArea()
    }

    // MARK: Cabecera: volver, progreso y omitir

    private var header: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if step > 0 {
                Button { go(to: step - 1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(.black)
                        .frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tx.s("Back", "Atrás"))

                HStack(spacing: 5) {
                    ForEach(1...lastStep, id: \.self) { index in
                        Capsule().fill(index <= step ? Color.black : Color.black.opacity(0.12))
                            .frame(height: 5)
                            .animation(.smooth(duration: 0.35), value: step)
                    }
                }
                .padding(.horizontal, 14).frame(height: 44)
                .glassEffect(.regular, in: .capsule)
                } else {
                    Spacer(minLength: 0)
                }

                Button { finish(.none) } label: {
                    Text(Tx.s("Skip", "Omitir")).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black.opacity(0.7))
                        .padding(.horizontal, 14).frame(height: 44).glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
    }

    // MARK: Páginas

    @ViewBuilder
    private var page: some View {
        switch step {
        case 0: welcome
        case 1:
            question(pose: "productos",
                     title: Tx.s("What do you sell or collect?", "¿Qué vendes o coleccionas?"),
                     subtitle: Tx.s("We'll shape the app around it.", "Así adaptamos la app a ti desde el principio.")) {
                ForEach(sellingOptions) { option in
                    row(option, selected: selling == option.id) { selling = option.id }
                }
            }
        case 2:
            question(pose: "precios",
                     title: Tx.s("What's your main goal?", "¿Cuál es tu objetivo principal?"),
                     subtitle: Tx.s("Pick as many as you like.", "Puedes elegir varios.")) {
                ForEach(goalOptions) { option in
                    row(option, selected: goals.contains(option.id)) { toggle(&goals, option.id) }
                }
            }
        case 3:
            question(pose: "pensando",
                     title: Tx.s("What kind of user are you?", "¿Qué tipo de usuario eres?"),
                     subtitle: Tx.s("Just so we show you what matters.", "Para enseñarte lo que más te sirve.")) {
                ForEach(profileOptions) { option in
                    row(option, selected: profile == option.id) { profile = option.id }
                }
            }
        case 4:
            question(pose: "ok",
                     title: Tx.s("Which platforms do you use?", "¿Qué plataformas usas?"),
                     subtitle: Tx.s("Connecting your accounts is optional. You can do it later from your profile.",
                                    "Conectar tus cuentas es opcional. Puedes hacerlo luego desde tu perfil.")) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(platformOptions) { option in
                        platformTile(option, selected: platforms.contains(option.id)) { toggle(&platforms, option.id) }
                    }
                }
            }
        default: firstProduct
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            daniel("hola", size: 250).padding(.top, 8)
            Text(Tx.s("All your market.\nOne app.", "Todo tu mercado.\nUna sola aplicación."))
                .font(.system(size: 34, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                .foregroundStyle(.black)
            Text(Tx.s("Find out what your sneakers and Pokémon cards are worth, compare prices and sell on several platforms from one place.",
                      "Descubre cuánto valen tus sneakers y cartas Pokémon, compara precios y vende en varias plataformas desde un solo lugar."))
                .font(.system(size: 16)).multilineTextAlignment(.center).foregroundStyle(.black.opacity(0.6))
                .padding(.horizontal, 6)
            HStack(spacing: 8) {
                Image(systemName: "hand.wave.fill").foregroundStyle(Color(red: 0.93, green: 0.07, blue: 0.06))
                Text(Tx.s("I'm Daniel. Five quick questions and you're in.", "Soy Daniel. Cinco preguntas rápidas y entras."))
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.black.opacity(0.75))
            }
            .padding(.horizontal, 16).frame(height: 44).glassEffect(.regular, in: .capsule).padding(.top, 6)
        }
    }

    private var firstProduct: some View {
        VStack(spacing: 14) {
            daniel("celebra", size: 190)
            Text(Tx.s("Find out what your first product is worth", "Descubre el valor de tu primer producto"))
                .font(.system(size: 27, weight: .bold, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(.black)
            Text(Tx.s("Scan it or search it, compare the prices and start selling.", "Escanéalo o búscalo, compara los precios y empieza a vender."))
                .font(.system(size: 15)).multilineTextAlignment(.center).foregroundStyle(.black.opacity(0.6))

            VStack(spacing: 10) {
                startButton(icon: "barcode.viewfinder", title: Tx.s("Scan a box", "Escanear una caja"),
                            detail: Tx.s("Point at the barcode", "Apunta al código de barras"), primary: true) { finish(.scan) }
                startButton(icon: "magnifyingglass", title: Tx.s("Search a sneaker", "Buscar un sneaker"),
                            detail: Tx.s("By name or SKU", "Por nombre o SKU"), primary: false) { finish(.search) }
                startButton(icon: "rectangle.portrait.on.rectangle.portrait.fill", title: Tx.s("Browse cards", "Ver cartas"),
                            detail: Tx.s("Market price by grade", "Precio de mercado por grado"), primary: false) { finish(.cards) }
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text(Tx.s("How did you hear about us?", "¿Cómo nos conociste?"))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["Instagram", "TikTok", "Google", Tx.s("Friends", "Amigos"), Tx.s("Other", "Otro")], id: \.self) { source in
                            Button { heardFrom = heardFrom == source ? nil : source } label: {
                                Text(source).font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(heardFrom == source ? .white : .black)
                                    .padding(.horizontal, 16).frame(height: 40)
                                    .background(heardFrom == source ? Color.black : Color.clear, in: .capsule)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
            .padding(.top, 10)
        }
    }

    private func question<Options: View>(pose: String, title: String, subtitle: String, @ViewBuilder options: () -> Options) -> some View {
        VStack(spacing: 10) {
            daniel(pose, size: 150)
            Text(title).font(.system(size: 27, weight: .bold, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(.black)
            Text(subtitle).font(.system(size: 15)).multilineTextAlignment(.center).foregroundStyle(.black.opacity(0.6))
                .padding(.bottom, 8)
            GlassEffectContainer(spacing: 10) { VStack(spacing: 10) { options() } }
        }
    }

    private func daniel(_ pose: String, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(.white).frame(width: size * 0.86, height: size * 0.86)
                .shadow(color: .black.opacity(0.08), radius: 24, y: 10)
            DanielGIF(pose: pose).frame(width: size, height: size)
                // El dibujo acaba en la cintura: se funde por abajo en vez de cortarse en seco.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.84), .init(color: .clear, location: 0.99)], startPoint: .top, endPoint: .bottom))
        }
        .frame(height: size)
        .accessibilityHidden(true)
    }

    // Opción grande: icono, título y detalle. Seleccionada = anillo negro, sin insignia.
    private func row(_ option: OnboardingOption, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { action() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.icon).font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? .white : .black)
                    .frame(width: 44, height: 44)
                    .background(selected ? Color.black : Color.black.opacity(0.06), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.black)
                    if !option.detail.isEmpty {
                        Text(option.detail).font(.system(size: 13)).foregroundStyle(.black.opacity(0.55))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).frame(minHeight: 68)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            .background(Color.black.opacity(selected ? 0.05 : 0), in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.black, lineWidth: 3).opacity(selected ? 1 : 0) }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func platformTile(_ option: OnboardingOption, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { action() }
        } label: {
            VStack(spacing: 8) {
                Group {
                    if let logo = option.logo {
                        StylizedMarketplaceLogo(brand: logo).frame(height: 30)
                    } else {
                        Image(systemName: option.icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(.black)
                    }
                }
                .frame(height: 34)
                Text(option.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity).frame(height: 96)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            .background(Color.black.opacity(selected ? 0.05 : 0), in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.black, lineWidth: 3).opacity(selected ? 1 : 0) }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func startButton(icon: String, title: String, detail: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(primary ? .black : .white)
                    .frame(width: 44, height: 44)
                    .background(primary ? Color.white : Color.black, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(primary ? .white : .black)
                    Text(detail).font(.system(size: 13)).foregroundStyle(primary ? .white.opacity(0.7) : .black.opacity(0.55))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(primary ? .white : .black.opacity(0.5))
            }
            .padding(.horizontal, 14).frame(height: 68)
            .background(primary ? Color.black : Color.clear, in: .rect(cornerRadius: 22))
            .glassEffect(primary ? .identity : .regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    // MARK: Pie: continuar

    @ViewBuilder
    private var footer: some View {
        if step < lastStep {
            Button { go(to: step + 1) } label: {
                Text(step == 0 ? Tx.s("Get started", "Empezar") : Tx.s("Continue", "Continuar"))
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(Color.black.opacity(canContinue ? 1 : 0.25), in: .capsule)
            }
            .buttonStyle(.plain).disabled(!canContinue)
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 10)
            .animation(.smooth(duration: 0.2), value: canContinue)
        }
    }

    private var canContinue: Bool {
        switch step {
        case 1: return selling != nil
        case 2: return !goals.isEmpty
        case 3: return profile != nil
        default: return true
        }
    }

    private func go(to next: Int) {
        guard (0...lastStep).contains(next) else { return }
        forward = next > step
        withAnimation(.smooth(duration: 0.38)) { step = next }
    }

    private func toggle(_ set: inout Set<String>, _ id: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func finish(_ start: AppTour.StartAction) {
        var answers: [String: [String]] = ["goals": goals.sorted(), "platforms": platforms.sorted()]
        if let selling { answers["selling"] = [selling] }
        if let profile { answers["profile"] = [profile] }
        if let heardFrom { answers["heardFrom"] = [heardFrom] }
        onFinish(answers, start)
    }

    // MARK: Opciones

    private var sellingOptions: [OnboardingOption] {
        [.init(id: "sneakers", icon: "shoe.fill", title: "Sneakers", detail: Tx.s("Plus apparel, bags and caps", "Y también ropa, bolsos y gorras")),
         .init(id: "cards", icon: "rectangle.portrait.on.rectangle.portrait.fill", title: Tx.s("Pokémon cards", "Cartas Pokémon"), detail: Tx.s("Raw and graded", "Sueltas y gradeadas")),
         .init(id: "both", icon: "square.grid.2x2.fill", title: Tx.s("Both", "Ambos"), detail: Tx.s("Everything in one place", "Todo en un solo lugar"))]
    }

    private var goalOptions: [OnboardingOption] {
        [.init(id: "prices", icon: "tag.fill", title: Tx.s("Check prices", "Consultar precios")),
         .init(id: "compare", icon: "arrow.left.arrow.right", title: Tx.s("Compare marketplaces", "Comparar marketplaces")),
         .init(id: "sell", icon: "paperplane.fill", title: Tx.s("Sell on several platforms", "Vender en varias plataformas")),
         .init(id: "inventory", icon: "shippingbox.fill", title: Tx.s("Manage my inventory", "Administrar mi inventario")),
         .init(id: "deals", icon: "chart.line.uptrend.xyaxis", title: Tx.s("Find resale opportunities", "Encontrar oportunidades de reventa"))]
    }

    private var profileOptions: [OnboardingOption] {
        [.init(id: "collector", icon: "heart.fill", title: Tx.s("Collector", "Coleccionista"), detail: Tx.s("I buy to keep", "Compro para guardar")),
         .init(id: "casual", icon: "person.fill", title: Tx.s("Occasional seller", "Vendedor ocasional"), detail: Tx.s("I sell from time to time", "Vendo de vez en cuando")),
         .init(id: "reseller", icon: "bolt.fill", title: Tx.s("Pro reseller", "Revendedor profesional"), detail: Tx.s("Buying and selling is my business", "Comprar y vender es mi negocio")),
         .init(id: "store", icon: "storefront.fill", title: Tx.s("Store", "Tienda"), detail: Tx.s("I have a shop or a team", "Tengo tienda o equipo"))]
    }

    private var platformOptions: [OnboardingOption] {
        [.init(id: "stockx", icon: "", title: "StockX", logo: "StockX"),
         .init(id: "goat", icon: "", title: "GOAT", logo: "GOAT"),
         .init(id: "ebay", icon: "", title: "eBay", logo: "eBay"),
         .init(id: "flightclub", icon: "", title: "Flight Club", logo: "Flight Club"),
         .init(id: "other", icon: "ellipsis", title: Tx.s("Other", "Otra")),
         .init(id: "none", icon: "minus.circle", title: Tx.s("None yet", "Ninguna aún"))]
    }
}

// MARK: - App Tour con Daniel

/// Estado del recorrido guiado: paso actual y dónde está cada opción en pantalla.
@MainActor
final class AppTour: ObservableObject {
    static let shared = AppTour()

    enum StartAction { case none, scan, search, cards }

    /// Paso actual; `nil` si el recorrido no está en marcha.
    @Published var index: Int?
    /// Sube para pedir a las opciones marcadas que vuelvan a decir dónde están.
    @Published var tick = 0
    /// El onboarding acaba de terminar: el recorrido arranca solo al entrar en la app.
    var autoStart = false
    /// Lo que eligió el usuario al final del onboarding; se abre al acabar el recorrido.
    var pending: StartAction = .none
    private(set) var frames: [String: CGRect] = [:]

    func start() {
        frames["shop.tile"] = nil
        tick += 1
        index = 0
    }

    func refreshFrames() {
        frames["shop.tile"] = nil
        tick += 1
    }

    func report(_ id: String, _ rect: CGRect) {
        guard rect.width > 1, rect.height > 1 else { return }
        if id == "shop.tile" {
            // De todas las fichas visibles, la de arriba a la izquierda.
            let screen = UIScreen.main.bounds
            guard rect.minY > 110, rect.maxY < screen.height - 90, rect.minX >= 0, rect.maxX <= screen.width else { return }
            if let old = frames[id] {
                let higher = rect.minY < old.minY - 4
                let sameRowLeft = abs(rect.minY - old.minY) <= 4 && rect.minX < old.minX
                guard higher || sameRowLeft else { return }
            }
        }
        guard frames[id] != rect else { return }
        frames[id] = rect
        if index != nil { objectWillChange.send() }
    }
}

private struct TourFrameReporter: View {
    let id: String

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            Color.clear
                .onAppear { AppTour.shared.report(id, frame) }
                .onChange(of: frame) { _, new in AppTour.shared.report(id, new) }
                .onReceive(AppTour.shared.$tick) { _ in AppTour.shared.report(id, geo.frame(in: .global)) }
        }
    }
}

extension View {
    /// Marca una opción para que el recorrido de Daniel pueda remarcarla.
    func tourTarget(_ id: String) -> some View { background(TourFrameReporter(id: id)) }
}

private struct TourStep {
    enum Target { case none, tab(Int), frame(String) }
    let target: Target
    /// Pestaña que tiene que estar abierta para que la opción exista.
    var needs: UpsoledMainTab?
    let pose: String
    let title: String
    let text: String
}

struct AppTourOverlay: View {
    @ObservedObject var router: MainTabRouter
    @ObservedObject private var tour = AppTour.shared
    /// La opción remarcada ya está localizada y se puede enseñar el paso.
    @State private var shown = false
    @State private var pulse = false

    private let steps: [TourStep] = [
        .init(target: .none, pose: "hola",
              title: Tx.s("Hi, I'm Daniel", "Hola, soy Daniel"),
              text: Tx.s("Let me show you around in under a minute. I'll highlight each option: tap it to keep going.",
                         "Te enseño la app en menos de un minuto. Voy remarcando cada opción: tócala para seguir.")),
        .init(target: .tab(0), pose: "abajo",
              title: Tx.s("Home", "Inicio"),
              text: Tx.s("Your stock value and what's moving in the market, at a glance.",
                         "El valor de tu stock y lo que se mueve en el mercado, de un vistazo.")),
        .init(target: .frame("home.search"), needs: .home, pose: "arriba",
              title: Tx.s("Search", "Buscar"),
              text: Tx.s("Type any sneaker by name or SKU and see its market price.",
                         "Escribe cualquier sneaker por nombre o SKU y mira su precio de mercado.")),
        .init(target: .frame("home.scan"), needs: .home, pose: "arriba",
              title: Tx.s("Scan a box", "Escanear una caja"),
              text: Tx.s("Point the camera at the barcode and you get the product and its price right away.",
                         "Apunta la cámara al código de barras y te sale el producto con su precio al momento.")),
        .init(target: .tab(1), pose: "abajo",
              title: Tx.s("Shop", "Tienda"),
              text: Tx.s("Sneakers, apparel, bags and caps, all in the same place.",
                         "Sneakers, ropa, bolsos y gorras, todo en el mismo sitio.")),
        .init(target: .frame("shop.tile"), needs: .closet, pose: "precios",
              title: Tx.s("Market price", "Precio de mercado"),
              text: Tx.s("Each product shows its lowest ask. Open it to see the price by size, the comparison between StockX, GOAT, eBay and Flight Club, the price history and the Sell button.",
                         "Cada producto enseña su precio más bajo. Al abrirlo ves el precio por talla, la comparativa entre StockX, GOAT, eBay y Flight Club, el historial de precios y el botón de vender.")),
        .init(target: .frame("shop.filters"), needs: .closet, pose: "arriba",
              title: Tx.s("Filters", "Filtros"),
              text: Tx.s("Filter by product type, brand and platform, and change the order.",
                         "Filtra por tipo de producto, marca y plataforma, y cambia el orden.")),
        .init(target: .tab(2), pose: "abajo",
              title: Tx.s("Cards", "Cartas"),
              text: Tx.s("Pokémon cards with their market price by grade and their price history.",
                         "Cartas Pokémon con su precio de mercado por grado y su historial de precios.")),
        .init(target: .frame("cards.search"), needs: .cards, pose: "arriba",
              title: Tx.s("Find a card", "Buscar una carta"),
              text: Tx.s("Search by name, or use the filter next to it to browse a whole set.",
                         "Busca por nombre, o usa el filtro de al lado para ver un set entero.")),
        .init(target: .frame("top.profile"), pose: "arriba",
              title: Tx.s("Your profile", "Tu perfil"),
              text: Tx.s("Your account, your settings and your marketplace connections. You can replay this tour from here.",
                         "Tu cuenta, tus ajustes y tus conexiones con los marketplaces. Desde aquí puedes repetir este recorrido.")),
        .init(target: .none, pose: "celebra",
              title: Tx.s("You're all set", "Ya lo tienes"),
              text: Tx.s("Scan or search your first product and see what it's worth.",
                         "Escanea o busca tu primer producto y mira cuánto vale.")),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let index = tour.index, steps.indices.contains(index) {
                    let step = steps[index]
                    let hole = holeRect(for: step, in: geo.size)
                    // Nada de lo de debajo se puede tocar mientras dura el recorrido.
                    Color.black.opacity(0.001).contentShape(.rect).onTapGesture {}
                    if shown {
                        dim(hole: hole, size: geo.size)
                        if let hole {
                            ring(hole)
                            Button { advance(from: step) } label: { Color.clear.contentShape(.rect) }
                                .buttonStyle(.plain)
                                .frame(width: hole.width, height: hole.height)
                                .position(x: hole.midX, y: hole.midY)
                                .accessibilityLabel(step.title)
                        }
                        bubble(step, index: index, hole: hole, size: geo.size)
                            .id(index)
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(tour.index != nil)
        .animation(.smooth(duration: 0.3), value: shown)
        .onAppear {
            guard tour.autoStart else { return }
            tour.autoStart = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { tour.start() }
        }
        .onChange(of: tour.index) { _, new in if let new { enter(new) } }
        .sensoryFeedback(.impact(weight: .light), trigger: tour.index)
    }

    // MARK: Pasos

    /// Prepara un paso: abre la pestaña que necesita, localiza la opción y lo enseña (o lo salta si no existe).
    private func enter(_ index: Int) {
        guard steps.indices.contains(index) else { finish(); return }
        let step = steps[index]
        shown = false
        pulse = false
        if let needs = step.needs, router.selected != needs { router.selected = needs }
        tour.refreshFrames()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard tour.index == index else { return }
            if case .frame(let id) = step.target, tour.frames[id] == nil {
                tour.index = index + 1
                return
            }
            shown = true
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func advance(from step: TourStep) {
        if case .tab(let tab) = step.target {
            router.selected = [UpsoledMainTab.home, .closet, .cards][tab]
        }
        next()
    }

    private func next() {
        guard let index = tour.index else { return }
        if index + 1 >= steps.count { finish() } else { tour.index = index + 1 }
    }

    private func finish() {
        shown = false
        tour.index = nil
        let pending = tour.pending
        tour.pending = .none
        switch pending {
        case .scan:
            router.scanRequested = true
            router.selected = .closet
        case .search:
            router.selected = .home
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.homeSearchTick += 1 }
        case .cards: router.selected = .cards
        case .none: break
        }
    }

    // MARK: Dibujo

    private func holeRect(for step: TourStep, in size: CGSize) -> CGRect? {
        switch step.target {
        case .none: return nil
        case .tab(let tab):
            // Barra de pestañas nativa: tres iconos centrados, a unos 85 pt uno de otro.
            let center = CGPoint(x: size.width / 2 + CGFloat(tab - 1) * 85, y: size.height - 52)
            return CGRect(x: center.x - 39, y: center.y - 29, width: 78, height: 58)
        case .frame(let id):
            return tour.frames[id]?.insetBy(dx: -7, dy: -7)
        }
    }

    private func corner(_ hole: CGRect) -> CGFloat { min(hole.height / 2, 28) }

    private func dim(hole: CGRect?, size: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: corner(hole), height: corner(hole))) }
        }
        .fill(Color(.sRGB, red: 0.03, green: 0.03, blue: 0.05, opacity: 0.80), style: FillStyle(eoFill: true))
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }

    private func ring(_ hole: CGRect) -> some View {
        RoundedRectangle(cornerRadius: corner(hole) + 4, style: .continuous)
            .strokeBorder(Color.white, lineWidth: 2.5)
            .frame(width: hole.width + 8, height: hole.height + 8)
            .scaleEffect(pulse ? 1.08 : 1)
            .opacity(pulse ? 0.55 : 1)
            .position(x: hole.midX, y: hole.midY)
            .allowsHitTesting(false)
    }

    private func bubble(_ step: TourStep, index: Int, hole: CGRect?, size: CGSize) -> some View {
        let below = (hole?.midY ?? 0) < size.height / 2
        return VStack(spacing: 0) {
            card(step, index: index)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hole == nil ? .center : (below ? .top : .bottom))
        .padding(.top, hole != nil && below ? (hole?.maxY ?? 0) + 64 : 0)
        .padding(.bottom, hole != nil && !below ? size.height - (hole?.minY ?? 0) + 22 : 0)
    }

    private func card(_ step: TourStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                DanielGIF(pose: step.pose).frame(width: 104, height: 104).offset(y: -46).padding(.bottom, -46)
                    .accessibilityHidden(true)
                Spacer()
                Text("\(index + 1) / \(steps.count)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.black.opacity(0.4))
                if index + 1 < steps.count {
                    Button { finish() } label: {
                        Text(Tx.s("Skip", "Omitir")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black.opacity(0.75))
                            .padding(.horizontal, 12).frame(height: 32).background(Color.black.opacity(0.07), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(step.title).font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(.black)
            Text(step.text).font(.system(size: 15)).foregroundStyle(.black.opacity(0.68)).fixedSize(horizontal: false, vertical: true)
            if case .none = step.target {
                Button { next() } label: {
                    Text(index == 0 ? Tx.s("Let's go", "Vamos") : Tx.s("Start", "Empezar"))
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50).background(Color.black, in: .capsule)
                }
                .buttonStyle(.plain).padding(.top, 4)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                    Text(Tx.s("Tap the highlighted option", "Toca la opción remarcada"))
                }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(red: 0.93, green: 0.07, blue: 0.06))
                .padding(.top, 2)
            }
        }
        .padding(18)
        .background(.white, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
    }
}

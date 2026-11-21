import SwiftUI

/// Raíz: sesión Supabase → app principal.
struct AuthRootView: View {
    @ObservedObject var auth: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @State private var previewsBooster = Self.previewsBoosterPack

    var body: some View {
        Group {
            if let barcode = Self.previewBarcode {
                StockBarcodeLookupPreview(barcode: barcode)
            } else if Self.previewsShoeReport {
                // Solo desarrollo (-uniclickPreviewReport): informe de un zapato sin precios, para ver el giro 360°.
                SaleReportView(report: SaleReport(title: "adidas Yeezy Boost 350 V2 Steel Grey", sku: "IF3219", scannedCode: "",
                                                  imageURL: nil, size: "9.5", costUSD: nil, lines: [], priceIsEstimate: false))
            } else if Self.previewsNewSections {
                // Solo en compilaciones de desarrollo y con el argumento -uniclickPreview: enseña las
                // secciones nuevas sin iniciar sesión, para poder probarlas en el simulador.
                MainTabView()
                    .fullScreenCover(isPresented: $previewsBooster) { BoosterPacksView() }
            } else if auth.isRestoringSession {
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    ProgressView(L10n.tr("auth.connecting"))
                }
            } else if Self.previewsOnboarding {
                // Solo desarrollo (-uniclickOnboarding): el onboarding y el recorrido sin iniciar sesión.
                OnboardedRoot(uid: "preview", force: true)
            } else if auth.isAuthenticated && auth.isVerifyingRecovery {
                ProgressView("Verifying recovery…")
            } else if auth.needsNewPassword {
                RecoveredPasswordView(auth: auth)
            } else if auth.needsRegistrationPhone {
                RegistrationPhoneView(auth: auth)
            } else if auth.isAuthenticated {
                // La primera vez que una cuenta entra en este teléfono pasa por el onboarding.
                let uid = auth.session?.user.id.uuidString ?? "guest"
                OnboardedRoot(uid: uid).id(uid)
            } else {
                LoginView(auth: auth)
            }
        }
        .environmentObject(auth)
        .task { await auth.refreshMethods() }
        .onOpenURL { url in
            Task { await auth.handleCallback(url) }
        }
        .alert(
            "Account access",
            isPresented: Binding(
                get: { auth.callbackNotice != nil },
                set: { if !$0 { auth.callbackNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(auth.callbackNotice ?? "")
        }
    }
}

extension AuthRootView {
    private static var previewsBoosterPack: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uniclickPreviewBooster")
        #else
        false
        #endif
    }

    private static var previewBarcode: String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uniclickPreviewBarcode"), arguments.indices.contains(index + 1) {
            return arguments[index + 1]
        }
        #endif
        return nil
    }

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

private struct StockBarcodeLookupPreview: View {
    let barcode: String
    @State private var result: StockScanLookupPayload?

    var body: some View {
        Group {
            if let result {
                StockScanResultSheet(payload: result, onViewStockItem: { _ in }, onDismiss: { })
            } else {
                ProgressView("Looking up barcode…")
            }
        }
        .task { result = await StockScanLookupService.lookup(code: barcode, stock: []) }
    }
}

#Preview {
    AuthRootView(auth: AuthViewModel())
        .environmentObject(CarsViewModel())
        .environmentObject(SettingsViewModel())
}

// MARK: - Daniel, el personaje guía

import AVFoundation

/// Vídeo en bucle de Daniel (hecho con Higgsfield), guardado como dato en Assets (carpeta Daniel).
struct DanielVideo: UIViewRepresentable {
    let pose: String

    func makeUIView(context: Context) -> DanielPlayerView {
        let view = DanielPlayerView()
        view.play(pose)
        return view
    }

    func updateUIView(_ view: DanielPlayerView, context: Context) { view.play(pose) }
}

final class DanielPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var pose: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func resume() { player?.play() }

    func play(_ pose: String) {
        guard pose != self.pose else { return }
        self.pose = pose
        guard let url = Self.fileURL(pose), let videoLayer = layer as? AVPlayerLayer else { return }
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.allowsExternalPlayback = false
        queue.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        videoLayer.videoGravity = .resizeAspect
        videoLayer.player = queue
        queue.play()
        player = queue
    }

    /// El reproductor necesita un archivo: el vídeo se copia una vez a la carpeta de caché.
    private static func fileURL(_ pose: String) -> URL? {
        guard let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = folder.appendingPathComponent("daniel-\(pose)-v3.mp4")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard let data = NSDataAsset(name: "Daniel-\(pose)")?.data else { return nil }
            try? data.write(to: url)
        }
        return url
    }
}

/// Daniel dentro de su círculo blanco, como un avatar.
struct DanielAvatar: View {
    let pose: String
    var size: CGFloat

    var body: some View {
        DanielVideo(pose: pose)
            .frame(width: size, height: size)
            .clipShape(.circle)
            .background(.white, in: .circle)
            .overlay { Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 1) }
            .shadow(color: .black.opacity(0.10), radius: size * 0.10, y: size * 0.04)
            .accessibilityHidden(true)
    }
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
    var icon: String = ""
    let title: String
    var detail: String = ""
    /// Logo de plataforma (StockX, GOAT…) o imagen de Assets (redes sociales) en lugar del icono.
    var marketplace: String?
    var asset: String?
}

private let onboardingGray = Color(red: 0.965, green: 0.965, blue: 0.975)

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

    private let lastStep = 6

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            page
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 30)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background(onboardingGray.ignoresSafeArea())
        .preferredColorScheme(.light)
        .sensoryFeedback(.selection, trigger: step)
    }

    // MARK: Cabecera, igual que la del flujo de venta: volver, puntos de progreso y omitir

    private var header: some View {
        HStack {
            Button { go(to: step - 1) } label: { TopBarGlassButton(systemImage: "chevron.left") }
                .buttonStyle(.plain).opacity(step > 0 ? 1 : 0).disabled(step == 0)
                .accessibilityLabel("Back")
            Spacer()
            if step > 0 {
                HStack(spacing: 6) {
                    ForEach(1...lastStep, id: \.self) { index in
                        Capsule().fill(index <= step ? Color.black : Color.black.opacity(0.12))
                            .frame(width: index == step ? 26 : 10, height: 6)
                    }
                }
                .padding(.horizontal, 14).frame(height: 30)
                .background(.white, in: .capsule).glassEffect(.regular, in: .capsule)
                .animation(.snappy(duration: 0.3), value: step)
            }
            Spacer()
            Button { finish(.none) } label: {
                Text("Skip").font(.system(size: 14, weight: .semibold)).foregroundStyle(.black.opacity(0.6))
                    .frame(width: 60, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
        .background { SellEdgeFade(edge: .top) }
    }

    // MARK: Páginas

    @ViewBuilder
    private var page: some View {
        switch step {
        case 0: welcome
        case 1:
            question(pose: "productos",
                     title: "What do you sell or collect?",
                     subtitle: "We shape the app around it.") {
                ForEach(sellingOptions) { option in row(option, selected: selling == option.id) { selling = option.id } }
            }
        case 2:
            question(pose: "precios",
                     title: "What's your main goal?",
                     subtitle: "Pick as many as you like.") {
                ForEach(goalOptions) { option in row(option, selected: goals.contains(option.id), multiple: true) { toggle(&goals, option.id) } }
            }
        case 3:
            question(pose: "pensando",
                     title: "What kind of user are you?",
                     subtitle: "So we show you what matters most.") {
                ForEach(profileOptions) { option in row(option, selected: profile == option.id) { profile = option.id } }
            }
        case 4:
            question(pose: "ok",
                     title: "Which platforms do you use?",
                     subtitle: "Connecting your accounts is optional. You can do it later from your profile.") {
                grid(platformOptions, columns: 2) { option in
                    tile(option, selected: platforms.contains(option.id)) { toggle(&platforms, option.id) }
                }
            }
        case 5:
            question(pose: "hola",
                     title: "How did you hear about us?",
                     subtitle: "It helps us reach more people like you.") {
                grid(sourceOptions, columns: 3) { option in
                    tile(option, selected: heardFrom == option.id) { heardFrom = heardFrom == option.id ? nil : option.id }
                }
            }
        default: firstProduct
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            DanielAvatar(pose: "hola", size: 230).padding(.top, 18)
            Text("All your market.\nOne app.")
                .font(.system(size: 34, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                .foregroundStyle(.black).padding(.top, 8)
            Text("See what your sneakers and Pokémon cards are worth, compare prices and sell on several platforms from one place.")
                .font(.system(size: 16, weight: .medium)).multilineTextAlignment(.center).foregroundStyle(.black.opacity(0.55))
                .padding(.horizontal, 10)
            HStack(spacing: 10) {
                ForEach(["StockX", "GOAT", "eBay", "Flight Club"], id: \.self) { name in
                    StylizedMarketplaceLogo(brand: name).frame(width: 40, height: 15)
                        .frame(width: 62, height: 62).background(.white, in: .circle).glassEffect(.regular, in: .circle)
                }
            }
            .padding(.top, 10)
        }
    }

    private var firstProduct: some View {
        VStack(spacing: 12) {
            DanielAvatar(pose: "celebra", size: 150).padding(.top, 4)
            Text("See what your first product is worth")
                .font(.system(size: 26, weight: .heavy, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(.black)
            Text("Scan it or search it, compare the prices and start selling.")
                .font(.system(size: 15, weight: .medium)).multilineTextAlignment(.center).foregroundStyle(.black.opacity(0.55))
                .padding(.bottom, 6)
            startButton(icon: "barcode.viewfinder", title: "Scan a box",
                        detail: "Point at the barcode.") { finish(.scan) }
            startButton(icon: "magnifyingglass", title: "Search a sneaker",
                        detail: "By name or SKU.") { finish(.search) }
            startButton(icon: "rectangle.portrait.on.rectangle.portrait", title: "Browse cards",
                        detail: "Market price by grade.") { finish(.cards) }
        }
    }

    private func question<Options: View>(pose: String, title: String, subtitle: String, @ViewBuilder options: () -> Options) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                DanielAvatar(pose: pose, size: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(.black.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)
            options()
        }
    }

    private func grid<Cell: View>(_ options: [OnboardingOption], columns: Int, @ViewBuilder cell: @escaping (OnboardingOption) -> Cell) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(options) { option in cell(option) }
        }
    }

    // Opción en fila, con el mismo lenguaje que «Select the condition» del flujo de venta.
    private func row(_ option: OnboardingOption, selected: Bool, multiple: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(selected ? .white : .black)
                    .frame(width: 40, height: 40).background(selected ? Color.black : Color.black.opacity(0.05), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                    if !option.detail.isEmpty {
                        Text(option.detail).font(.system(size: 12, weight: .medium)).foregroundStyle(.black.opacity(0.5)).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? (multiple ? "checkmark.square.fill" : "checkmark.circle.fill") : (multiple ? "square" : "circle"))
                    .font(.system(size: 20)).foregroundStyle(selected ? .black : .black.opacity(0.2))
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: 20))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? Color.black : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // Opción en ficha, con logo: plataformas y redes.
    private func tile(_ option: OnboardingOption, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            VStack(spacing: 10) {
                Group {
                    if let marketplace = option.marketplace {
                        StylizedMarketplaceLogo(brand: marketplace).frame(width: 78, height: 26)
                    } else if let asset = option.asset {
                        Image(asset).resizable().scaledToFit().frame(width: 44, height: 44)
                    } else {
                        Image(systemName: option.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.black)
                            .frame(width: 44, height: 44).background(Color.black.opacity(0.05), in: .circle)
                    }
                }
                .frame(height: 46)
                Text(option.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.black).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).frame(height: 104)
            .background(.white, in: .rect(cornerRadius: 20))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? Color.black : .clear, lineWidth: 1.5) }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(.black)
                    .background(.white, in: .circle).padding(8).opacity(selected ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func startButton(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Color.black, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                    Text(detail).font(.system(size: 12, weight: .medium)).foregroundStyle(.black.opacity(0.5))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black.opacity(0.45))
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: 20))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    // MARK: Pie, igual que el del flujo de venta

    private var footer: some View {
        Button {
            if step == lastStep { finish(.none) } else { go(to: step + 1) }
        } label: {
            Text(step == 0 ? "Get started" : step == lastStep ? "Explore the app" : "Next")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(canContinue ? Color.black : Color.black.opacity(0.28), in: .capsule)
        }
        .buttonStyle(.plain).disabled(!canContinue)
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
        .background { SellEdgeFade(edge: .bottom) }
        .animation(.smooth(duration: 0.2), value: canContinue)
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
        withAnimation(.smooth(duration: 0.36)) { step = next }
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
        [.init(id: "sneakers", icon: "shoe", title: "Sneakers", detail: "Plus apparel, bags and caps."),
         .init(id: "cards", icon: "rectangle.portrait.on.rectangle.portrait", title: "Pokémon cards", detail: "Raw and graded."),
         .init(id: "both", icon: "square.grid.2x2", title: "Both", detail: "Everything in one place.")]
    }

    private var goalOptions: [OnboardingOption] {
        [.init(id: "prices", icon: "tag", title: "Check prices"),
         .init(id: "compare", icon: "arrow.left.arrow.right", title: "Compare marketplaces"),
         .init(id: "sell", icon: "paperplane", title: "Sell on several platforms"),
         .init(id: "inventory", icon: "shippingbox", title: "Manage my inventory"),
         .init(id: "deals", icon: "chart.line.uptrend.xyaxis", title: "Find resale opportunities")]
    }

    private var profileOptions: [OnboardingOption] {
        [.init(id: "collector", icon: "heart", title: "Collector", detail: "I buy to keep."),
         .init(id: "casual", icon: "person", title: "Occasional seller", detail: "I sell from time to time."),
         .init(id: "reseller", icon: "bolt", title: "Pro reseller", detail: "Buying and selling is my business."),
         .init(id: "store", icon: "storefront", title: "Store", detail: "I have a shop or a team.")]
    }

    private var platformOptions: [OnboardingOption] {
        [.init(id: "stockx", title: "StockX", marketplace: "StockX"),
         .init(id: "goat", title: "GOAT", marketplace: "GOAT"),
         .init(id: "ebay", title: "eBay", marketplace: "eBay"),
         .init(id: "flightclub", title: "Flight Club", marketplace: "Flight Club"),
         .init(id: "other", icon: "ellipsis", title: "Other"),
         .init(id: "none", icon: "minus", title: "None yet")]
    }

    private var sourceOptions: [OnboardingOption] {
        [.init(id: "instagram", title: "Instagram", asset: "Social-instagram"),
         .init(id: "tiktok", title: "TikTok", asset: "Social-tiktok"),
         .init(id: "youtube", title: "YouTube", asset: "Social-youtube"),
         .init(id: "google", title: "Google", asset: "Social-google"),
         .init(id: "friends", icon: "person.2", title: "Friends"),
         .init(id: "other", icon: "ellipsis", title: "Other")]
    }
}

// MARK: - App Tour con Daniel

/// Ventana propia del recorrido: va por encima de toda la app (también de las pantallas completas).
/// Solo deja pasar el toque dentro de la opción remarcada.
final class TourWindow: UIWindow {
    var passRect: CGRect?
    var onPass: (() -> Void)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let passRect, passRect.contains(point) {
            onPass?()
            return nil
        }
        return super.hitTest(point, with: event)
    }
}

/// Lo que el recorrido hace por su cuenta en la app: cerrar pantallas y mover el scroll.
@MainActor
enum TourNav {
    static var appWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).filter { !($0 is TourWindow) }
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    private static func top(_ controller: UIViewController) -> UIViewController {
        var current = controller
        while let presented = current.presentedViewController, !presented.isBeingDismissed { current = presented }
        return current
    }

    private static func navigators(in controller: UIViewController) -> [UINavigationController] {
        var found: [UINavigationController] = []
        if let navigation = controller as? UINavigationController { found.append(navigation) }
        for child in controller.children { found += navigators(in: child) }
        return found
    }

    /// Cierra las pantallas completas abiertas y vuelve al principio de la pestaña.
    static func closeAll() {
        guard let root = appWindow?.rootViewController else { return }
        if root.presentedViewController != nil { root.dismiss(animated: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for navigation in navigators(in: root) where navigation.viewControllers.count > 1 && navigation.view.window != nil {
                navigation.popToRootViewController(animated: true)
            }
        }
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        var found: [UIScrollView] = []
        if let scroll = view as? UIScrollView { found.append(scroll) }
        for sub in view.subviews { found += scrollViews(in: sub) }
        return found
    }

    /// Mueve el scroll de la pantalla de arriba para dejar la opción a la vista, con sitio para Daniel.
    static func reveal(_ rect: CGRect) {
        guard let window = appWindow, let root = window.rootViewController else { return }
        let screen = window.bounds
        let delta = rect.height > screen.height * 0.4 ? rect.minY - 116 : rect.midY - screen.height * 0.34
        guard abs(delta) > 24 else { return }
        let center = CGPoint(x: screen.midX, y: screen.midY)
        let candidates = scrollViews(in: top(root).view).filter { scroll in
            scroll.window != nil && !scroll.isHidden && scroll.isScrollEnabled
                && scroll.contentSize.height > scroll.bounds.height + 1
                && scroll.convert(scroll.bounds, to: window).contains(center)
        }
        guard let scroll = candidates.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { return }
        let lowest = -scroll.adjustedContentInset.top
        let highest = max(lowest, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let y = min(max(scroll.contentOffset.y + delta, lowest), highest)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: true)
    }
}

/// El recorrido guiado: pasos, paso actual y dónde está cada opción en pantalla.
@MainActor
final class AppTour: ObservableObject {
    static let shared = AppTour()

    enum StartAction { case none, scan, search, cards }
    /// `button`: Daniel habla y hay un botón. `tap`: hay que tocar la opción de verdad (el toque le llega).
    /// `info`: Daniel explica la opción; tocarla solo avanza.
    enum Kind { case button, tap, info }

    struct Step {
        var target: String?
        var tab: Int?
        var kind: Kind = .info
        /// Pestaña que tiene que estar abierta para que la opción exista.
        var needs: UpsoledMainTab?
        /// La opción puede estar fuera de la vista: se mueve el scroll hasta ella.
        var scroll = false
        /// Al terminar el paso se cierran las pantallas abiertas y se vuelve a la pestaña.
        var closes = false
        let pose: String
        let title: String
        let text: String
    }

    @Published private(set) var index: Int?
    @Published private(set) var shown = false
    @Published private(set) var hole: CGRect?
    /// Sube para pedir a las opciones marcadas que digan dónde están.
    @Published var tick = 0

    /// El onboarding acaba de terminar: el recorrido arranca solo al entrar en la app.
    var autoStart = false
    /// Lo que eligió el usuario al final del onboarding; se abre al acabar el recorrido.
    var pending: StartAction = .none
    private var frames: [String: CGRect] = [:]
    private weak var router: MainTabRouter?
    private var window: TourWindow?
    private var task: Task<Void, Never>?
    private var lastPass = Date.distantPast

    var step: Step? { index.flatMap { steps.indices.contains($0) ? steps[$0] : nil } }
    var count: Int { steps.count }

    func attach(_ router: MainTabRouter) {
        self.router = router
        guard autoStart else { return }
        autoStart = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.start() }
    }

    func start() {
        guard index == nil, let scene = TourNav.appWindow?.windowScene else { return }
        let window = TourWindow(windowScene: scene)
        let host = UIHostingController(rootView: AppTourOverlay())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.windowLevel = .normal + 5
        window.backgroundColor = .clear
        window.onPass = { [weak self] in DispatchQueue.main.async { self?.passed() } }
        window.isHidden = false
        self.window = window
        index = 0
        enter()
    }

    func report(_ id: String, _ rect: CGRect) {
        guard !id.isEmpty, rect.width > 1, rect.height > 1 else { return }
        if id == "shop.tile" || id == "cards.tile" {
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
        // La opción remarcada se ha movido (scroll o animación): el resalte la sigue.
        if shown, step?.target == id {
            hole = fitted(rect)
            if step?.kind == .tap { window?.passRect = hole }
        }
    }

    // MARK: Pasos

    /// Prepara el paso actual: abre su pestaña, localiza la opción, la deja a la vista y lo enseña.
    /// Si la opción no existe en esta pantalla, el paso se salta.
    private func enter() {
        task?.cancel()
        guard let index, let step else { finish(); return }
        shown = false
        hole = nil
        window?.passRect = nil
        if let needs = step.needs, router?.selected != needs { router?.selected = needs }
        frames.removeAll()
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            var rect: CGRect?
            if let id = step.target {
                for _ in 0..<14 {
                    if Task.isCancelled { return }
                    tick += 1
                    try? await Task.sleep(for: .milliseconds(160))
                    if let found = frames[id] { rect = found; break }
                }
                guard var found = rect else {
                    if !Task.isCancelled { self.index = index + 1; enter() }
                    return
                }
                if step.scroll {
                    TourNav.reveal(found)
                    try? await Task.sleep(for: .milliseconds(620))
                    tick += 1
                    try? await Task.sleep(for: .milliseconds(160))
                    found = frames[id] ?? found
                }
                rect = found
            } else if let tab = step.tab {
                // Barra de pestañas nativa: tres iconos centrados, a unos 85 pt uno de otro.
                let screen = UIScreen.main.bounds
                let center = CGPoint(x: screen.width / 2 + CGFloat(tab - 1) * 85, y: screen.height - 52)
                rect = CGRect(x: center.x - 32, y: center.y - 22, width: 64, height: 44)
            }
            if Task.isCancelled { return }
            hole = rect.map(fitted)
            window?.passRect = step.kind == .tap ? hole : nil
            shown = true
        }
    }

    /// El resalte: la opción con un pequeño margen, sin salirse de la pantalla ni tapar el sitio de Daniel.
    private func fitted(_ rect: CGRect) -> CGRect {
        let screen = UIScreen.main.bounds
        var hole = rect.insetBy(dx: -7, dy: -7)
        let top = max(hole.minY, 54)
        var bottom = min(hole.maxY, screen.height - 16)
        if bottom - top > screen.height * 0.46 { bottom = top + screen.height * 0.46 }
        hole = CGRect(x: max(hole.minX, 6), y: top, width: min(hole.maxX, screen.width - 6) - max(hole.minX, 6), height: max(bottom - top, 30))
        return hole
    }

    /// El usuario tocó la opción remarcada de verdad (el toque le llegó a la app).
    private func passed() {
        guard shown, step?.kind == .tap, Date().timeIntervalSince(lastPass) > 0.9 else { return }
        lastPass = Date()
        window?.passRect = nil
        shown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.next() }
    }

    func next() {
        guard let index, let step else { return }
        if step.closes {
            shown = false
            TourNav.closeAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { self.advance(from: index) }
        } else {
            advance(from: index)
        }
    }

    private func advance(from index: Int) {
        guard self.index == index else { return }
        if index + 1 >= steps.count { finish() } else { self.index = index + 1; enter() }
    }

    func finish() {
        task?.cancel()
        shown = false
        hole = nil
        index = nil
        window?.isHidden = true
        window = nil
        let action = pending
        pending = .none
        switch action {
        case .scan:
            router?.scanRequested = true
            router?.selected = .closet
        case .search:
            router?.selected = .home
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.router?.homeSearchTick += 1 }
        case .cards: router?.selected = .cards
        case .none: break
        }
    }

    // MARK: Guion

    private let steps: [Step] = [
        Step(kind: .button, pose: "hola",
             title: "Hi, I'm Daniel",
             text: "I'll walk you through the whole app: prices, sizes, market data and how to sell. I highlight each option and you tap it."),
        // Inicio
        Step(tab: 0, kind: .tap, pose: "abajo",
             title: "Home",
             text: "Your stock value and what's moving in the market, at a glance."),
        Step(target: "home.search", needs: .home, pose: "arriba",
             title: "Search",
             text: "Type any sneaker by name or SKU and see its market price."),
        Step(target: "home.scan", needs: .home, pose: "arriba",
             title: "Scan a box",
             text: "Point the camera at the barcode and you get the product with its price."),
        // Tienda
        Step(tab: 1, kind: .tap, pose: "abajo",
             title: "Shop",
             text: "Sneakers, apparel, bags and caps, all in the same place."),
        Step(target: "shop.filters", needs: .closet, pose: "arriba",
             title: "Filters",
             text: "Filter by product type, brand and platform, and change the order."),
        Step(target: "shop.tile", kind: .tap, needs: .closet, pose: "productos",
             title: "Open a product",
             text: "The tag on each photo is its lowest price right now. Tap this sneaker to go inside."),
        // Ficha del zapato
        Step(target: "shoe.size", kind: .tap, scroll: true, pose: "arriba",
             title: "Sizes",
             text: "The price is not the same in every size. Tap here to open the sizes."),
        Step(target: "shoe.sizeOption", kind: .tap, pose: "abajo",
             title: "Pick a size",
             text: "Tap this size and watch the price change."),
        Step(target: "shoe.price", scroll: true, pose: "precios",
             title: "The price for your size",
             text: "Buy now is the cheapest listing in that size and where it is. Below: the last sale, the highest offer and the retail price."),
        Step(target: "market.open", kind: .tap, scroll: true, pose: "abajo",
             title: "Market data",
             text: "Here is everything that's happening with this sneaker. Tap to open it."),
        Step(target: "market.tabs", pose: "arriba",
             title: "Asks, bids and sales",
             text: "Asks: what sellers are asking. Bids: what buyers are offering. Sales: what it actually sold for."),
        Step(target: "market.sizes", pose: "arriba",
             title: "Filter by size",
             text: "Pick a size to see only its asks, bids and sales."),
        Step(target: "market.close", kind: .tap, pose: "arriba",
             title: "Close",
             text: "Tap the X to go back to the sneaker."),
        Step(target: "shoe.compare", scroll: true, pose: "precios",
             title: "Price comparison",
             text: "The same sneaker on StockX, GOAT, eBay and Flight Club, size by size. The best price is highlighted."),
        Step(target: "shoe.history", scroll: true, pose: "precios",
             title: "Price history",
             text: "How its price has moved over time, so you know when to buy or sell."),
        // Vender
        Step(target: "sell.open", kind: .tap, scroll: true, pose: "abajo",
             title: "Sell this item",
             text: "Now let's sell it. Tap here."),
        Step(target: "sell.condition", kind: .tap, pose: "arriba",
             title: "Condition",
             text: "First, say how it is: new with box, new without box or used. Tap this one."),
        Step(target: "sell.next", kind: .tap, pose: "abajo",
             title: "Next",
             text: "Tap Next to choose the size and the price."),
        Step(target: "sell.sizeOption", kind: .tap, pose: "abajo",
             title: "Size",
             text: "Each size shows in green the best offer a buyer is making for it. Tap this one."),
        Step(target: "sell.suggest", kind: .tap, scroll: true, pose: "precios",
             title: "Set your price",
             text: "Sell now, sell faster or earn more: three prices taken from the market. Tap one, or type your own."),
        Step(target: "sell.next", kind: .tap, pose: "abajo",
             title: "Review",
             text: "Tap to review the listing."),
        Step(target: "sell.platforms", scroll: true, pose: "ok",
             title: "Where to sell",
             text: "Choose one platform or several at once. Under each logo you see what you keep after its fee."),
        Step(target: "sell.fees", scroll: true, pose: "precios",
             title: "Fees, clear",
             text: "Your price, each platform's fee and what you actually receive."),
        Step(target: "sell.next", closes: true, pose: "abajo",
             title: "Submit",
             text: "After the final checks, this button publishes it on every platform you chose. We won't publish anything now: tap it and we move on."),
        // Cartas
        Step(tab: 2, kind: .tap, pose: "abajo",
             title: "Cards",
             text: "Now the cards. Tap here."),
        Step(target: "cards.search", needs: .cards, pose: "arriba",
             title: "Find a card",
             text: "Search by name, or use the filter next to it to browse a whole set."),
        Step(target: "cards.tile", kind: .tap, needs: .cards, pose: "productos",
             title: "Open a card",
             text: "Tap this card to see its market."),
        Step(target: "card.price", scroll: true, pose: "precios",
             title: "Market price",
             text: "Its market price, the last sale and how much it has moved."),
        Step(target: "card.grades", scroll: true, pose: "precios",
             title: "Price by grade",
             text: "Raw, PSA 8, 9 and 10, compared between Collectr, TCGplayer and eBay."),
        Step(target: "sell.open", kind: .tap, scroll: true, pose: "abajo",
             title: "Sell the card",
             text: "Selling a card works the same way. Tap here."),
        Step(target: "sell.condition", closes: true, pose: "ok",
             title: "Same three steps",
             text: "Condition, grade and price, and where to publish it (eBay and StockX). Tap to continue."),
        // Perfil y cierre
        Step(target: "top.profile", pose: "arriba",
             title: "Your profile",
             text: "Your account, your settings and your marketplace connections. You can replay this tour from here."),
        Step(kind: .button, pose: "celebra",
             title: "You're all set",
             text: "Scan or search your first product and see what it's worth."),
    ]
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

/// Lo que se ve del recorrido: el oscurecido con el hueco, el anillo y la tarjeta de Daniel.
struct AppTourOverlay: View {
    @ObservedObject private var tour = AppTour.shared
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let index = tour.index, let step = tour.step {
                    // Nada de lo de debajo se puede tocar mientras dura el recorrido.
                    Color.black.opacity(0.001).contentShape(.rect).onTapGesture {}
                    if tour.shown {
                        dim(hole: tour.hole, size: geo.size).transition(.opacity)
                        if let hole = tour.hole {
                            ring(hole)
                            if step.kind == .info {
                                Button { tour.next() } label: { Color.clear.contentShape(.rect) }
                                    .buttonStyle(.plain)
                                    .frame(width: hole.width, height: hole.height)
                                    .position(x: hole.midX, y: hole.midY)
                                    .accessibilityLabel(step.title)
                            }
                        }
                        bubble(step, index: index, hole: tour.hole, size: geo.size)
                            .id(index)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.28), value: tour.shown)
        .animation(.smooth(duration: 0.25), value: tour.hole)
        .onChange(of: tour.shown) { _, shown in
            pulse = false
            if shown { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tour.index)
        .preferredColorScheme(.light)
    }

    private func corner(_ hole: CGRect) -> CGFloat { min(hole.height / 2, 26) }

    private func dim(hole: CGRect?, size: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: corner(hole), height: corner(hole))) }
        }
        .fill(Color(.sRGB, red: 0.03, green: 0.03, blue: 0.05, opacity: 0.72), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func ring(_ hole: CGRect) -> some View {
        RoundedRectangle(cornerRadius: corner(hole) + 4, style: .continuous)
            .strokeBorder(Color.white, lineWidth: 2.5)
            .frame(width: hole.width + 8, height: hole.height + 8)
            .scaleEffect(pulse ? 1.05 : 1)
            .opacity(pulse ? 0.5 : 1)
            .position(x: hole.midX, y: hole.midY)
            .allowsHitTesting(false)
    }

    /// La tarjeta va donde hay sitio: debajo de la opción, encima, o abajo del todo si la opción es muy alta.
    private func bubble(_ step: AppTour.Step, index: Int, hole: CGRect?, size: CGSize) -> some View {
        let below = hole.map { size.height - $0.maxY >= 270 } ?? false
        let above = hole.map { $0.minY >= 300 } ?? false
        let alignment: Alignment = hole == nil ? .center : (below ? .top : .bottom)
        let top = below ? (hole?.maxY ?? 0) + 62 : 0
        let bottom = hole == nil || below ? 0 : (above ? size.height - (hole?.minY ?? 0) + 20 : 34)
        return card(step, index: index)
            .padding(.horizontal, 16)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(.top, top)
            .padding(.bottom, bottom)
    }

    private func card(_ step: AppTour.Step, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                DanielAvatar(pose: step.pose, size: 92).offset(y: -44).padding(.bottom, -44)
                Spacer()
                Text("\(index + 1) / \(tour.count)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.black.opacity(0.4))
                if index + 1 < tour.count {
                    Button { tour.finish() } label: {
                        Text("Skip").font(.system(size: 13, weight: .semibold)).foregroundStyle(.black.opacity(0.75))
                            .padding(.horizontal, 12).frame(height: 32).background(Color.black.opacity(0.07), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(step.title).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.black).padding(.top, 2)
            Text(step.text).font(.system(size: 15, weight: .medium)).foregroundStyle(.black.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
            if step.kind == .button {
                Button { tour.next() } label: {
                    Text(index == 0 ? "Let's go" : "Start")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50).background(Color.black, in: .capsule)
                }
                .buttonStyle(.plain).padding(.top, 6)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                    Text("Tap the highlighted option")
                }
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                .padding(.horizontal, 12).frame(height: 32).background(Color.black.opacity(0.06), in: .capsule)
                .padding(.top, 4)
            }
            // Avance del recorrido.
            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.08))
                    Capsule().fill(Color.black).frame(width: bar.size.width * CGFloat(index + 1) / CGFloat(max(tour.count, 1)))
                }
            }
            .frame(height: 4).padding(.top, 6)
        }
        .padding(18)
        .background(.white, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
    }
}

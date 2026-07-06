import SwiftUI
import SwiftData
import UIKit
import PhotosUI

// MARK: - Notificaciones entre pestañas (p. ej. abrir «Añadir» desde Inicio)

extension Notification.Name {
    /// Catálogo creado o editado — Inicio refresca totales.
    static let upsoledCatalogDidChange = Notification.Name("Upsoled.catalogDidChange")
    /// Prenda guardada, eliminada o precio cambiado — listas y KPIs refrescan.
    static let closetInventoryDidChange = Notification.Name("Upsoled.closetInventoryDidChange")
}

enum UpsoledMainTab: Hashable {
    case home
    case closet
    case settings
}

@MainActor
final class MainTabRouter: ObservableObject {
    @Published var selected: UpsoledMainTab = .home
    /// Presenta el flujo «Añadir al stock» desde Your stock (antes era una pestaña).
    @Published var showAddStockFlow = false
    /// Abre el pipeline de revisión al entrar en Añadir (p. ej. borradores desde stock).
    @Published var addTabOpenPipeline = false
}

/// Abre un hilo concreto al cambiar a la pestaña Chat (p. ej. grupo «Mi equipo» desde Inicio).
@MainActor
final class ChatNavigationCoordinator: ObservableObject {
    @Published var threadToOpen: ChatThread?
}

// MARK: - Pestañas (TabView nativo iOS 26 + Liquid Glass del sistema)

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var tabRouter = MainTabRouter()
    @StateObject private var invoiceHistory = InvoiceHistoryStore()
    @StateObject private var chatInbox = ChatInboxStore()
    @StateObject private var communityVM = DashboardCommunityViewModel()
    @StateObject private var chatNav = ChatNavigationCoordinator()
    @State private var chatSearchText = ""
    @StateObject private var addClosetFlowVM = AddToClosetFlowViewModel()

    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel

    /// Pausa el refresco periódico de comunidad cuando la app pasa a segundo plano.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        mainTabChrome
    }

    /// Cuerpo partido para el type-check del compilador (`TabView` + muchos modificadores).
    private var mainTabChrome: some View {
        bareTabView
        .environmentObject(chatInbox)
        .environmentObject(tabRouter)
        .environmentObject(chatNav)
        .environmentObject(communityVM)
        .environmentObject(invoiceHistory)
            .environmentObject(addClosetFlowVM)
            /// Ítem seleccionado: azul marca; ítems no seleccionados: negro (`MainTabBarAppearance`).
            .accentColor(PremiumAccent.tabActive)
            .tint(PremiumAccent.tabActive)
        .onAppear {
            ClosetInventoryRepair.restoreAllSoldToStock(in: modelContext)
            MainTabBarAppearance.applyBlackInactiveBlueSelected()
            communityVM.attach(auth: auth)
            communityVM.startPeriodicRefresh()
            Task { await communityVM.refresh() }
        }
        .onDisappear {
            communityVM.stopPeriodicRefresh()
        }
        .onChange(of: auth.session?.user.id) { _, _ in
            communityVM.attach(auth: auth)
            Task { await communityVM.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                communityVM.startPeriodicRefresh()
                Task { await communityVM.refresh() }
                Task { await PriceAlertChecker.checkAll() }
            case .background, .inactive:
                communityVM.stopPeriodicRefresh()
            @unknown default:
                break
            }
        }
        .task {
            // Chequeo de alertas de precio al arrancar (best-effort en foreground).
            await PriceAlertChecker.checkAll()
        }
        .toolbarBackground(PremiumAccent.tabBarDockBackgroundGradient, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.light, for: .tabBar)
        .tabBarMinimizeBehavior(.never)
        .task {
            await carsVM.loadVehicles(companyId: auth.companyId)
        }
            .task(id: auth.session?.user.id) {
                guard let uid = auth.session?.user.id else { return }
                await chatInbox.refreshCoordinatorTasksFromServer(currentUserId: uid)
            }
        .onReceive(NotificationCenter.default.publisher(for: .coordinatorTaskAcceptedFromPush)) { _ in
            guard let uid = auth.session?.user.id else { return }
            Task {
                await chatInbox.refreshCoordinatorTasksFromServer(currentUserId: uid)
            }
        }
    }

    /// Solo el `TabView` con sus ítems; los `.environmentObject`/`task`/`onReceive` van en `mainTabChrome`.
    private var bareTabView: some View {
        TabView(selection: $tabRouter.selected) {
            Tab(L10n.tr("tab.dashboard"), systemImage: "square.grid.2x2.fill", value: UpsoledMainTab.home) {
                NavigationStack {
                    DashboardView()
                }
            }

            Tab(L10n.tr("tab.closet"), systemImage: "archivebox.fill", value: UpsoledMainTab.closet) {
                NavigationStack {
                    ClosetView()
                }
            }

            Tab(L10n.tr("tab.settings"), systemImage: "gearshape.fill", value: UpsoledMainTab.settings) {
        NavigationStack {
                    SettingsView()
                }
            }
        }
    }
}

// MARK: - Pestaña Añadir (sección fija, barra inferior visible)

enum AddStockRoute: Hashable {
    case gallery
    case camera
    case fourPhotoChoice
    case shoe360Private
    case shoe360FromGallery
    case apparelLookbook
    case pipeline
}

private enum AddStockDesign {
    static let purple = Color(red: 0.39, green: 0.40, blue: 0.95)
    static let purpleSoft = Color(red: 0.93, green: 0.92, blue: 0.99)
    static let green = Color(red: 0.18, green: 0.72, blue: 0.55)
    static let pageBG = Color(red: 0.98, green: 0.98, blue: 0.99)
    static let cardStroke = Color.black.opacity(0.07)
    static let subtitle = Color.black.opacity(0.48)
    static let darkCard = Color(red: 0.11, green: 0.12, blue: 0.16)
}

struct AddToStockTabView: View {
    @EnvironmentObject private var addFlow: AddToClosetFlowViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter

    @State private var path = NavigationPath()
    @State private var pickedGalleryItems: [PhotosPickerItem] = []
    @State private var stagingFiveGalleryImages: [UIImage] = []
    @State private var shoe360GalleryImagesPrepared: [UIImage] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical, showsIndicators: false) {
                addMenuContent
            }
            .background(AddStockDesign.pageBG.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if path.isEmpty {
                        Button {
                            closeAddFlow()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.72))
                        }
                        .accessibilityLabel("Back")
                    }
                }
            }
            .navigationDestination(for: AddStockRoute.self) { route in
                destination(for: route)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.light)
        .toastOverlay(
            message: Binding(
                get: { addFlow.toast },
                set: { addFlow.toast = $0 }
            ))
        .onAppear(perform: consumePendingPipelineRequest)
        .onChange(of: tabRouter.addTabOpenPipeline) { _, open in
            if open { consumePendingPipelineRequest() }
        }
        .onChange(of: tabRouter.showAddStockFlow) { _, open in
            if !open { path = NavigationPath() }
        }
    }

    private func closeAddFlow() {
        tabRouter.addTabOpenPipeline = false
        path = NavigationPath()
        tabRouter.showAddStockFlow = false
    }

    @ViewBuilder
    private func destination(for route: AddStockRoute) -> some View {
        Group {
            switch route {
            case .gallery:
                AddStockGalleryStepView(
                    pickedGalleryItems: $pickedGalleryItems,
                    onContinue: { Task { await ingestPhotoPickerItems(pickedGalleryItems) } }
                )
            case .camera:
                AddStockCameraCaptureStep { image in
                    if !path.isEmpty { path.removeLast() }
                    path.append(AddStockRoute.pipeline)
                    addFlow.beginProcessing(images: [image])
                }
            case .fourPhotoChoice:
                AddStockFourPhotoChoiceView(
                    onShoe360: {
                        shoe360GalleryImagesPrepared = stagingFiveGalleryImages
                        stagingFiveGalleryImages = []
                        if !path.isEmpty { path.removeLast() }
                        path.append(AddStockRoute.shoe360FromGallery)
                    },
                    onOutfit: {
                        let snap = stagingFiveGalleryImages
                        stagingFiveGalleryImages = []
                        if !path.isEmpty { path.removeLast() }
                        path.append(AddStockRoute.pipeline)
                        addFlow.beginProcessing(images: snap)
                    },
                    onCancel: {
                        stagingFiveGalleryImages = []
                        if !path.isEmpty { path.removeLast() }
                    }
                )
            case .shoe360Private:
                ClosetShoe360FlowView()
            case .shoe360FromGallery:
                if shoe360GalleryImagesPrepared.count == ShoeAngle.allCases.count {
                    ClosetShoe360FlowView(prefilledCapturedInCanonicalOrder: shoe360GalleryImagesPrepared)
                } else {
                    AddStockMissingImagesFallback(onBack: popToMenu)
                }
            case .apparelLookbook:
                ClosetGarmentLookbookStandaloneFlowView()
            case .pipeline:
                AddToClosetPipelineView(isPresented: .constant(false))
                    .environmentObject(addFlow)
            }
        }
    }

    private var addMenuContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            addStockHeroHeader
            addStockPhotoSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 36)
    }

    private var addStockHeroHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AddStockDesign.purple)
                .frame(width: 32, height: 32)
                .background(Circle().fill(AddStockDesign.purpleSoft))

            Text(L10n.tr("closet.addSheetTitle"))
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.tr("closet.addSheetSubtitle"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AddStockDesign.subtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var addStockPhotoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            addStockSectionLabel(number: "01", title: L10n.tr("closet.addSheetSectionPhotos"))

            HStack(spacing: 12) {
                addStockMethodCard(
                    icon: "photo.on.rectangle.angled",
                    iconTint: AddStockDesign.purple,
                    iconBackground: AddStockDesign.purpleSoft,
                    arrowTint: AddStockDesign.purple,
                    title: L10n.tr("closet.addSheetGallery"),
                    subtitle: L10n.tr("closet.addSheetGallerySub")
                ) {
                    ClosetAnalytics.named("add_to_closet_opened")
                    path.append(AddStockRoute.gallery)
                }

                addStockMethodCard(
                    icon: "camera.fill",
                    iconTint: AddStockDesign.green,
                    iconBackground: AddStockDesign.green.opacity(0.14),
                    arrowTint: AddStockDesign.green,
                    title: L10n.tr("closet.addSheetCamera"),
                    subtitle: L10n.tr("closet.addSheetCameraSub")
                ) {
                    ClosetAnalytics.named("add_to_closet_opened")
                    path.append(AddStockRoute.camera)
                }
            }
        }
    }


    private func addStockSectionLabel(number: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(AddStockDesign.purple)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(AddStockDesign.purple)
                .tracking(0.4)
        }
    }

    private func addStockMethodCard(
        icon: String,
        iconTint: Color,
        iconBackground: Color,
        arrowTint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(iconTint)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(iconBackground))

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(arrowTint)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(arrowTint.opacity(0.12)))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.90))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AddStockDesign.subtitle)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 14, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AddStockDesign.cardStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }


    private func consumePendingPipelineRequest() {
        guard tabRouter.addTabOpenPipeline else { return }
        tabRouter.addTabOpenPipeline = false
        path = NavigationPath()
        path.append(AddStockRoute.pipeline)
    }

    private func popToMenu() {
        path = NavigationPath()
    }

    @MainActor
    private func ingestPhotoPickerItems(_ items: [PhotosPickerItem]) async {
        var images = [UIImage]()
        for pi in items {
            if let data = try? await pi.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                images.append(ui.closetFlattenedOrientation())
            }
        }
        guard !images.isEmpty else {
            pickedGalleryItems.removeAll()
            if !path.isEmpty { path.removeLast() }
            return
        }
        pickedGalleryItems.removeAll()
        if !path.isEmpty { path.removeLast() }

        if images.count == ShoeAngle.allCases.count {
            stagingFiveGalleryImages = images
            path.append(AddStockRoute.fourPhotoChoice)
        } else {
            path.append(AddStockRoute.pipeline)
            addFlow.beginProcessing(images: images)
        }
    }
}

private struct AddStockGalleryStepView: View {
    @Binding var pickedGalleryItems: [PhotosPickerItem]
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            AddStockStepHeader(step: 1, total: 2, title: "Choose photos")

            Text(
                "Choose up to 5 photos. With exactly 4 you can pick a 360° shoe view (front, right, back, left, in order) or analyze an outfit with the photos you choose."
            )
            .font(.system(size: 14))
            .foregroundStyle(ClosetFlowPalette.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.top, 4)

            PhotosPicker(
                selection: $pickedGalleryItems,
                maxSelectionCount: 5,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Open photos", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)

            Button(action: onContinue) {
                Label("Continue", systemImage: "arrow.forward.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.black.opacity(0.82))
            .disabled(pickedGalleryItems.isEmpty)

            Text("Select photos and tap Continue (pick 4 in order for 360° shoes or another amount for an outfit).")
                .font(.system(size: 11))
                .foregroundStyle(Color.black.opacity(0.42))
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AddStockCameraCaptureStep: View {
    var onCaptured: (UIImage) -> Void

    @State private var image: UIImage?

    var body: some View {
        ClosetUIImagePickerBridge(image: $image)
            .background(Color.black)
            .ignoresSafeArea()
            .navigationTitle(L10n.tr("closet.addSheetCamera"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: image) { _, newValue in
                guard let newValue else { return }
                onCaptured(newValue)
            }
    }
}

private struct AddStockFourPhotoChoiceView: View {
    var onShoe360: () -> Void
    var onOutfit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            AddStockStepHeader(step: 2, total: 2, title: "Use your 4 photos")

            Text("4 photos selected")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.black)

            Text(
                "Shoes? Photos 1→4 map to: front, right side, back, and left side. "
                    + "You can correct any angle afterward."
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.52))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)

            VStack(spacing: 11) {
                Button(action: onShoe360) {
                    VStack(spacing: 5) {
                        Text("Product — 360° studio")
                            .font(.system(size: 17, weight: .semibold))
                        Text("4 photos → professional white-background catalog images you can spin through")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(Color.black)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)

                Button(action: onOutfit) {
                    Text("Detect garments in outfit")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 26).fill(ClosetFlowPalette.darkerPillFill))
                }
                .buttonStyle(.plain)
            }

            Button("Cancel", role: .cancel, action: onCancel)
                .font(.system(size: 15))

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Use your 4 photos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AddStockMissingImagesFallback: View {
    var onBack: () -> Void

    var body: some View {
        ContentUnavailableView(
            "Missing photos",
            systemImage: "photo.on.rectangle.angled",
            description: Text("Go back and choose 4 photos in order.")
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.tr("common.close"), action: onBack)
            }
        }
    }
}

private struct AddStockStepHeader: View {
    let step: Int
    let total: Int
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Text("Step \(step) of \(total)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.58, green: 0.38, blue: 0.96))
                .textCase(.uppercase)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.88))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UITabBar (inactivos negro, seleccionados azul Upsoled)

private enum MainTabBarAppearance {
    static func applyBlackInactiveBlueSelected() {
        let inactive = UIColor.black
        let selected = UIColor(red: 0.16, green: 0.44, blue: 0.98, alpha: 1.0)

        let item = UITabBarItemAppearance()
        item.normal.iconColor = inactive
        item.normal.titleTextAttributes = [.foregroundColor: inactive]
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [.foregroundColor: selected]

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowImage = UIImage()
        appearance.shadowColor = .clear

        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        let bar = UITabBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.isTranslucent = true
        bar.tintColor = selected
        bar.unselectedItemTintColor = inactive
        bar.barTintColor = nil
        bar.backgroundColor = .clear
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
        .environmentObject(CarsViewModel())
        .environmentObject(SettingsViewModel())
}

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

// MARK: - Paleta modo claro

private enum ClosetFlowPalette {
    static let secondaryText = Color.black.opacity(0.55)
    static let mutedBackground = Color(.secondarySystemBackground)
    static let darkerPillFill = Color(white: 0.22)
    static let destructive = Color(red: 229 / 255, green: 57 / 255, blue: 53 / 255)
}

/// Token para `.sheet(item:)` al flujo 360° en borrador guardarropa.
private struct Shoe360DraftSheetPieceID: Identifiable, Hashable {
    let pieceID: UUID
    var id: UUID { pieceID }
}

// MARK: - Miniatura desde ImageStore

private struct ClosetDiskThumbnail: View {
    let relativePath: String

    var body: some View {
        Group {
            if let ui = ImageStore.load(relativePath) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color.white
                    ProgressView()
                        .tint(.black)
                }
            }
        }
        .background(Color.white)
    }
}

// MARK: - Cámara

struct ClosetUIImagePickerBridge: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    final class Delegate: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ClosetUIImagePickerBridge

        init(_ parent: ClosetUIImagePickerBridge) { self.parent = parent }

        func imagePickerController(
            _ _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = (info[.originalImage] as? UIImage)?.closetFlattenedOrientation()
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ _: UIImagePickerController) {
            parent.dismiss()
        }
    }

    func makeCoordinator() -> Delegate { Delegate(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ _: UIImagePickerController, context _: Context) {}
}

extension UIImage {
    /// Evita miniaturas volteadas al capturar con cámara.
    fileprivate func closetFlattenedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let out = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return out
    }
}

// MARK: - Pestaña clóset + FAB + sheet entrada

struct ClosetView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var addFlow: AddToClosetFlowViewModel
    @Query(sort: \ClosetItem.createdAt, order: .reverse) private var closetItems: [ClosetItem]
    @Query(sort: \Look.createdAt, order: .reverse) private var closetLooks: [Look]

    @State private var showAddMenuSheet = false
    @State private var showCamera = false
    @State private var showGalleryPickSheet = false
    @State private var pickedGalleryItems: [PhotosPickerItem] = []
    @State private var cameraImage: UIImage?
    @State private var showPipeline = false
    @State private var closetItemPendingDelete: ClosetItem?
    @State private var closetSelectionMode = false
    @State private var closetSelectedIDs = Set<UUID>()
    @State private var confirmBulkDelete = false

    /// Ficha grande de una prenda (estudio).
    @State private var garmentDetailSheetItem: ClosetItem?
    @State private var showCreateLookSheet = false
    @State private var openedLookSheet: Look?

    /// Tras elegir exactamente 4 fotos: elegir «outfit» o «zapatos 360°».
    @State private var stagingFiveGalleryImages: [UIImage] = []
    @State private var showFivePhotosUseModeSheet = false
    /// Fullscreen vista 360° cuando el usuario elige usar 4 fotos como zapatos (galería).
    @State private var showShoe360FiveGalleryFlow = false
    @State private var shoe360FiveGalleryImagesPrepared: [UIImage] = []
    /// Zapatos foto a foto desde el FAB (sin obligar al flujo de outfit / galería).
    @State private var showPrivateShoe360Flow = false
    /// Ropa lookbook foto a foto: camisetas, pantalones, cintos, calcetines, etc. (no zapatos).
    @State private var showPrivateGarmentLookbookFlow = false

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(minimum: 156), spacing: 16),
        GridItem(.flexible(minimum: 156), spacing: 16),
    ]

    /// Orden visual del armario por categoría (solo se pintan bloques con prendas).
    private static let stockCategoryPresentationOrder: [ClothingCategory] = [
        .tops, .dressesJumpsuits, .pantsSkirts, .coats, .shoes, .bags, .accessories, .underwear,
    ]

    private struct ClosetStockSection: Identifiable {
        var id: String { category.rawValue }
        let category: ClothingCategory
        let items: [ClosetItem]
    }

    private var closetStockSections: [ClosetStockSection] {
        let grouped = Dictionary(grouping: closetItems) { $0.category }
        return Self.stockCategoryPresentationOrder.compactMap { cat in
            guard let arr = grouped[cat], !arr.isEmpty else { return nil }
            let sorted = arr.sorted { $0.createdAt > $1.createdAt }
            return ClosetStockSection(category: cat, items: sorted)
        }
    }

    private var draftBannerCount: Int { ClosetLocalDraftStore.pendingCount }

    /// Espacio bajo la rejilla para FAB, banner de borradores y barra de eliminar en bloque.
    private var bottomInsetForClosetGrid: CGFloat {
        var h: CGFloat = draftBannerCount > 0 ? 148 : 120
        if closetSelectionMode, !closetSelectedIDs.isEmpty {
            h += 88
        }
        if !closetLooks.isEmpty {
            h += 154
        }
        return h
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    closetHeaderRow

                    if !closetLooks.isEmpty {
                        looksRibbon
                    }

                    if closetItems.isEmpty {
                        Text("Tus prendas guardadas aparecerán aquí. Pulsa + para analizar fotos con IA.")
                            .font(.system(size: 14))
                            .foregroundStyle(ClosetFlowPalette.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.bottom, bottomInsetForClosetGrid)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(closetStockSections) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("\(section.category.emoji) \(section.category.displayName)")
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundStyle(Color.black)
                                        Spacer(minLength: 8)
                                        Text("\(section.items.count)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.black.opacity(0.42))
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
                                            )
                                    }
                                    .padding(.horizontal, 16)

                                    LazyVGrid(columns: gridColumns, spacing: 16) {
                                        ForEach(section.items) { item in
                                            closetCell(item)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                }
                            }
                        }
                        .padding(.bottom, bottomInsetForClosetGrid)
                    }
                }
            }

            if draftBannerCount > 0 {
                draftResumeBanner
            }

            if closetSelectionMode, !closetSelectedIDs.isEmpty {
                closetBulkDeleteBar
            }

            if !closetSelectionMode {
                plusFloatingButton
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showAddMenuSheet) {
            addToClosetIntroSheet
                .presentationDragIndicator(.visible)
                .presentationDetents([.height(720)])
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: consumeCameraPickIfNeeded) {
            ClosetUIImagePickerBridge(image: $cameraImage)
                .background(Color.black)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showGalleryPickSheet) {
            NavigationStack {
                VStack(spacing: 22) {
                    Text(
                        "Elige hasta 5 fotos. Con exactamente 4 podrás elegir vista 360° de zapatos (frontal, derecha, trasera, izquierda, en orden) o analizar outfit con las fotos que elijas."
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(ClosetFlowPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                    PhotosPicker(
                        selection: $pickedGalleryItems,
                        maxSelectionCount: 5,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Abrir fotos", systemImage: "photo.on.rectangle.angled")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)

                    Button {
                        Task { await ingestPhotoPickerItems(pickedGalleryItems) }
                    } label: {
                        Label("Continuar", systemImage: "arrow.forward.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.black.opacity(0.82))
                    .disabled(pickedGalleryItems.isEmpty)

                    Text("Selecciona las fotos y pulsa Continuar (elige 4 en orden para zapatos 360° u otra cantidad para outfit).")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.black.opacity(0.42))
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .navigationTitle("Galería")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") {
                            pickedGalleryItems.removeAll()
                            showGalleryPickSheet = false
                        }
                    }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showPipeline) {
            AddToClosetPipelineView(isPresented: $showPipeline)
                .environmentObject(addFlow)
                .preferredColorScheme(.light)
        }
        .fullScreenCover(isPresented: $showShoe360FiveGalleryFlow, onDismiss: {
            shoe360FiveGalleryImagesPrepared = []
        }) {
            if shoe360FiveGalleryImagesPrepared.count == ShoeAngle.allCases.count {
                ClosetShoe360FlowView(prefilledCapturedInCanonicalOrder: shoe360FiveGalleryImagesPrepared)
                    .preferredColorScheme(.light)
            }
        }
        .fullScreenCover(isPresented: $showPrivateShoe360Flow) {
            ClosetShoe360FlowView()
                .preferredColorScheme(.light)
        }
        .fullScreenCover(isPresented: $showPrivateGarmentLookbookFlow) {
            ClosetGarmentLookbookStandaloneFlowView()
                .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showFivePhotosUseModeSheet) {
            fivePhotosUseModeSheet
                .presentationDragIndicator(.visible)
                .presentationDetents([.height(380)])
                .presentationBackground(Color.white)
                .preferredColorScheme(.light)
        }
        .toastOverlay(
            message: Binding(
                get: { addFlow.toast },
                set: { addFlow.toast = $0 }
            ))
        .sheet(isPresented: $showCreateLookSheet) {
            CreateLookComposerView()
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
                .preferredColorScheme(.light)
        }
        .sheet(item: $garmentDetailSheetItem) { item in
            ClosetGarmentDetailView(item: item)
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
                .preferredColorScheme(.light)
        }
        .sheet(item: $openedLookSheet) { look in
            ClosetLookDetailSheet(look: look)
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
                .preferredColorScheme(.light)
        }
        .confirmationDialog(
            "¿Eliminar esta prenda del clóset?",
            isPresented: Binding(
                get: { closetItemPendingDelete != nil },
                set: { if !$0 { closetItemPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let item = closetItemPendingDelete {
                    deleteClosetItem(item)
                }
                closetItemPendingDelete = nil
            }
            Button("Cancelar", role: .cancel) {
                closetItemPendingDelete = nil
            }
        } message: {
            if let item = closetItemPendingDelete {
                Text("Se borrará «\(item.name)» y sus archivos en este dispositivo.")
            }
        }
        .alert(
            closetSelectedIDs.count <= 1
                ? "¿Eliminar esta prenda del clóset?"
                : "¿Eliminar \(closetSelectedIDs.count) prendas?",
            isPresented: $confirmBulkDelete
        ) {
            Button("Eliminar", role: .destructive) {
                bulkDeleteSelectedClosetItems()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(
                closetSelectedIDs.count <= 1
                    ? "Se borrarán sus archivos en este dispositivo."
                    : "Se borrarán las prendas seleccionadas y sus archivos locales."
            )
        }
    }

    private var fivePhotosUseModeSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("4 fotos seleccionadas")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.black)

                Text(
                    "¿Zapatos? Las fotos 1→4 se asignan a: frontal, lateral derecho, trasera y lateral izquierdo. "
                        + "Luego puedes corregir cualquier ángulo."
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.52))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

                VStack(spacing: 11) {
                    Button {
                        let snap = stagingFiveGalleryImages
                        stagingFiveGalleryImages = []
                        showFivePhotosUseModeSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                            shoe360FiveGalleryImagesPrepared = snap
                            showShoe360FiveGalleryFlow = true
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text("👞 Zapatos — vista 360°")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Las 4 fotos = giro fluido al arrastrar (transición suave entre vistas)")
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

                    Button {
                        let snap = stagingFiveGalleryImages
                        stagingFiveGalleryImages = []
                        showFivePhotosUseModeSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                            showPipeline = true
                            addFlow.beginProcessing(images: snap)
                        }
                    } label: {
                        Text("Detectar prendas en outfit")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 26).fill(ClosetFlowPalette.darkerPillFill))
                    }
                    .buttonStyle(.plain)
                }

                Button("Cancelar", role: .cancel) {
                    stagingFiveGalleryImages = []
                    showFivePhotosUseModeSheet = false
                }
                .font(.system(size: 15))

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .navigationTitle("Usar tus 4 fotos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        stagingFiveGalleryImages = []
                        showFivePhotosUseModeSheet = false
                    }
                    .foregroundStyle(Color.black)
                }
            }
        }
    }

    /// Fila superior: título y entrada/salida del modo selección.
    private var closetHeaderRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Mi clóset")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.black)

            Spacer(minLength: 8)

            if closetItems.count >= 2 {
                Button("Crear look") {
                    showCreateLookSheet = true
                    ClosetAnalytics.named("closet_create_look_opened")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .disabled(closetSelectionMode)
            }

            if !closetItems.isEmpty {
                Button(closetSelectionMode ? "Listo" : "Seleccionar") {
                    if closetSelectionMode {
                        closetSelectionMode = false
                        closetSelectedIDs.removeAll()
                    } else {
                        closetSelectionMode = true
                        closetSelectedIDs.removeAll()
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var closetBulkDeleteBar: some View {
        Button {
            confirmBulkDelete = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash.fill")
                Text("Eliminar (\(closetSelectedIDs.count))")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(ClosetFlowPalette.destructive))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 94)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeOut(duration: 0.2), value: closetSelectedIDs.count)
    }

    /// Quita ficheros del sandbox y el registro en SwiftData.
    private func deleteClosetItem(_ item: ClosetItem) {
        ImageStore.deleteIfExists(item.imageFilename)
        if let path = item.originalCropFilename {
            ImageStore.deleteIfExists(path)
        }
        if let path = item.sourceOutfitFilename {
            ImageStore.deleteIfExists(path)
        }
        for path in item.multiAngleFilenames {
            ImageStore.deleteIfExists(path)
        }
        for path in item.lookbookStudio {
            ImageStore.deleteIfExists(path)
        }
        for path in item.lookbookLifestyle {
            ImageStore.deleteIfExists(path)
        }
        for path in item.spin360Filenames {
            ImageStore.deleteIfExists(path)
        }
        modelContext.delete(item)
        try? modelContext.save()
        ClosetAnalytics.named("closet_item_deleted")
    }

    private func bulkDeleteSelectedClosetItems() {
        let toRemove = closetItems.filter { closetSelectedIDs.contains($0.id) }
        guard !toRemove.isEmpty else {
            confirmBulkDelete = false
            return
        }
        for item in toRemove {
            ImageStore.deleteIfExists(item.imageFilename)
            if let path = item.originalCropFilename { ImageStore.deleteIfExists(path) }
            if let path = item.sourceOutfitFilename { ImageStore.deleteIfExists(path) }
            for path in item.multiAngleFilenames { ImageStore.deleteIfExists(path) }
            for path in item.lookbookStudio { ImageStore.deleteIfExists(path) }
            for path in item.lookbookLifestyle { ImageStore.deleteIfExists(path) }
            for path in item.spin360Filenames { ImageStore.deleteIfExists(path) }
            modelContext.delete(item)
        }
        try? modelContext.save()
        ClosetAnalytics.named("closet_items_deleted_bulk", params: "count:\(toRemove.count)")
        closetSelectedIDs.removeAll()
        closetSelectionMode = false
        confirmBulkDelete = false
    }

    private func lookRibbonBadge(_ look: Look) -> String {
        let short = look.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if short.isEmpty {
            if let g = look.avatarGenderRaw, let ag = AvatarGender(rawValue: g) {
                return ag.displayNameSpanish
            }
            return "Look"
        }
        return short.count <= 14 ? short : String(short.prefix(12)) + "…"
    }

    private var looksRibbon: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mis looks tipo estudio")
                .font(.system(size: 15, weight: .heavy))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(closetLooks) { look in
                        Button {
                            openedLookSheet = look
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white)

                                if let rel = ImageStore.lookRibbonThumbnailRelativePath(look: look) {
                                    ClosetDiskThumbnail(relativePath: rel)
                                        .padding(10)
                                        .aspectRatio(9 / 16, contentMode: .fit)
                                } else {
                                    Image(systemName: "sparkles.rectangle.stack")
                                        .foregroundStyle(Color.black.opacity(0.25))
                                        .font(.system(size: 30))
                                }

                                VStack {
                                    Spacer()
                                    Text(lookRibbonBadge(look))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(Color.black.opacity(0.55)))
                                        .padding(8)
                                }
                            }
                            .frame(width: 112)
                            .aspectRatio(9 / 16, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var plusFloatingButton: some View {
        Button {
            ClosetAnalytics.named("add_to_closet_opened")
            showAddMenuSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.black))
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
        }
        .padding(.bottom, 86)
    }

    private var draftResumeBanner: some View {
        Button {
            let decoded = ClosetLocalDraftStore.decoded()
            addFlow.resumePersistedDrafts(decoded: decoded)
            showPipeline = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Artículos en borrador")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(draftBannerCount) artículos pendientes")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.92))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 118)
    }

    private var addToClosetIntroSheet: some View {
        VStack(spacing: 14) {
            Text("Add to closet")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)

            Text(
                "Personalize your future outfits and see how to style your closet items"
            )
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Color.black.opacity(0.55))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Text("📷 Elige tus fotos del outfit")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 11) {
                HStack(spacing: 11) {
                    Button {
                        showAddMenuSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            showGalleryPickSheet = true
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 22, weight: .semibold))
                            Text("Galería")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Hasta 5 fotos")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .foregroundStyle(Color.black)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showAddMenuSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            showCamera = true
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 22, weight: .semibold))
                            Text("Cámara")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Una foto al instante")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .foregroundStyle(Color.black)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 4) {
                    Text("Con fotos de tu armario")
                        .font(.system(size: 16, weight: .semibold))
                    Text("La IA detecta prendas y el estudio opcional («Generar ✨») puede pulir cada pieza.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(Color.black)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.white))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.black.opacity(0.07), lineWidth: 1)
                }

                shoePrivateStandalonePill

                garmentPrivateStandalonePill

                secondaryIntroPill(title: "Buscar artículos") {
                    addFlow.showToast("Próximamente")
                    showAddMenuSheet = false
                }
                secondaryIntroPill(title: "Reenviar recibos") {
                    addFlow.showToast("Próximamente")
                    showAddMenuSheet = false
                }
            }
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .presentationBackground(Color.white)
    }

    private func secondaryIntroPill(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 28).fill(ClosetFlowPalette.darkerPillFill))
        }
        .buttonStyle(.plain)
    }

    /// Entrada aparte del outfit de galería: subir sólo zapatos y decidir foto por ángulo.
    private var shoePrivateStandalonePill: some View {
        Button {
            ClosetAnalytics.named("closet_shoe360_private_opened")
            showAddMenuSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                showPrivateShoe360Flow = true
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "shoe.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.2)))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Zapatos solo tuyos (360°)")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color.white)
                    Text("Frontal, lateral derecho, trasera e izquierda: toca cada lado y pon o cambia su foto.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.88)))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    /// Entrada paralela «Zapatos 360»: ropa/complementos sin calzado → 5 referencias guiadas → 10 vistas IA estudio + lifestyle.
    private var garmentPrivateStandalonePill: some View {
        Button {
            ClosetAnalytics.named("closet_ropa_lookbook_standalone_opened")
            showAddMenuSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                showPrivateGarmentLookbookFlow = true
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.22)))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ropa · lookbook con IA")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color.white)
                    Text(
                        "Camisas, pantalones, medias, cinturones… 5 fotos guía "
                            + "(frente, espalda, detalles) y generamos imágenes de catálogo y lifestyle para pasarlas con el dedo.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.74)))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func closetCell(_ item: ClosetItem) -> some View {
        let selected = closetSelectedIDs.contains(item.id)
        return VStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)

                ClosetDiskThumbnail(relativePath: ImageStore.displayRelativePath(for: item))
                    .padding(10)
                    .scaledToFit()

                if closetSelectionMode {
                    Color.black.opacity(selected ? 0.12 : 0)

                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(selected ? Color.black : Color.white.opacity(0.95))
                                    .frame(width: 28, height: 28)
                                    .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
                                if !selected {
                                    Circle().stroke(Color.black.opacity(0.35), lineWidth: 1.5)
                                        .frame(width: 28, height: 28)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.white)
                                }
                            }
                            .padding(8)
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(selected ? Color.black : Color.clear, lineWidth: 3)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)

            let brandLine = item.brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Text(brandLine.isEmpty ? "Unknown Brand" : brandLine)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(Color.black.opacity(0.55))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Text(item.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.88))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if closetSelectionMode {
                if selected {
                    closetSelectedIDs.remove(item.id)
                } else {
                    closetSelectedIDs.insert(item.id)
                }
            } else {
                garmentDetailSheetItem = item
                ClosetAnalytics.named("closet_item_detail_open")
            }
        }
        .contextMenu {
            if !closetSelectionMode {
                Button(role: .destructive) {
                    closetItemPendingDelete = item
                } label: {
                    Label("Eliminar prenda", systemImage: "trash")
                }
            }
        }
    }

    @MainActor
    private func consumeCameraPickIfNeeded() {
        defer { cameraImage = nil }
        guard let img = cameraImage else { return }
        pickedGalleryItems.removeAll()
        showGalleryPickSheet = false
        showPipeline = true
        addFlow.beginProcessing(images: [img])
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
            showGalleryPickSheet = false
            return
        }
        pickedGalleryItems.removeAll()
        showGalleryPickSheet = false
        if images.count == ShoeAngle.allCases.count {
            stagingFiveGalleryImages = images
            showFivePhotosUseModeSheet = true
        } else {
            showPipeline = true
            addFlow.beginProcessing(images: images)
        }
    }
}

// MARK: - Zapatos 360° (galería o solo zapatos / “privados”)

/// Pantalla puente: nombre + `ShoeMultiAngleCaptureView`. Opcionalmente trae las 4 fotos ya ordenadas desde galería; si es `nil`, configuración foto a foto.
private struct ClosetShoe360FlowView: View {
    var prefilledCapturedInCanonicalOrder: [UIImage]? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var shoeName = "Zapatos"

    private var trimmedName: String {
        let t = shoeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Zapatos" : t
    }

    private var isPrivateFlow: Bool { prefilledCapturedInCanonicalOrder == nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        isPrivateFlow
                            ? "Toca cada ángulo (frontal, derecha, trasera, izquierda) y usa Cámara o Galería para poner esa vista. Aquí decides qué foto es cada lado del zapato."
                            : "Las fotos se tomaron en el orden que elegiste en la galería — toca un ángulo para corregirlo."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    TextField("Nombre del zapato", text: $shoeName)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.black)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground)))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)

                ShoeMultiAngleCaptureView(
                    garmentName: trimmedName,
                    prefilledCapturedInAngleOrder: prefilledCapturedInCanonicalOrder,
                    showsCloseButton: false,
                    onOrderedPathsCommitted: saveToCloset
                )
                .id(prefilledCapturedInCanonicalOrder?.count.description ?? "private")
            }
            .navigationTitle(isPrivateFlow ? "Zapatos — solo tus fotos" : "Zapatos — 360°")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(Color.black)
                }
            }
        }
        .preferredColorScheme(.light)
        .background(Color.white)
    }

    private func saveToCloset(paths: [String]) {
        guard paths.count == ShoeAngle.allCases.count else { return }
        let imageFile = paths[0]

        var paletteJSON: String?
        if let ui = ImageStore.load(imageFile) {
            let hexes = ColorPaletteExtractor.extract(from: ui, count: 5)
            if let data = try? JSONEncoder().encode(hexes),
               let s = String(data: data, encoding: .utf8) {
                paletteJSON = s
            }
        }

        let row = ClosetItem(
            name: trimmedName,
            brand: "Unknown Brand",
            priceText: nil,
            colorPaletteJSON: paletteJSON,
            dressCodesRaw: nil,
            seasonsRaw: nil,
            aiColorsJSON: nil,
            multiAngleFilenamesJSON: nil,
            category: .shoes,
            imageFilename: imageFile,
            originalCropFilename: nil,
            sourceOutfitFilename: nil,
            boundingBox: nil,
            isDraft: false
        )
        row.multiAngleFilenames = paths
        modelContext.insert(row)
        try? modelContext.save()
        ClosetAnalytics.named(
            isPrivateFlow ? "closet_shoe360_private_saved" : "closet_shoe360_gallery_saved")
    }
}

// MARK: - Ropa / complementos · lookbook (entradas paralelas sin outfit)

private struct ClosetGarmentLookbookStandaloneFlowView: View {
    /// Categorías con lookbook tipo catálogo; el calzado sigue usando «Zapatos solo tuyos (360°)».
    private static let categoryChoices: [ClothingCategory] = ClothingCategory.allCases.filter { $0 != .shoes }

    /// Miniatura válida sólo hasta guardar la primera foto de IA de estudio — se borra si el usuario abandona antes.
    private static func provisionalPlaceholderCropPath() throws -> String {
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw NSError(domain: "ClosetGarmentLookbookStandalone", code: -1)
        }
        return try ImageStore.save(
            data,
            inFolder: "crops",
            filename: "pending_lookbook_\(UUID().uuidString.lowercased()).jpg")
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var garmentName = ""
    @State private var category: ClothingCategory = .tops
    @State private var draftRow: ClosetItem?

    private var trimmedName: String {
        let t = garmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Prenda nueva" : t
    }

    var body: some View {
        NavigationStack {
            Group {
                if let row = draftRow {
                    GarmentLookbookCaptureView(
                        item: row,
                        onAbortStandaloneDraftNotYetSaved: abandonStandaloneDraft
                    )
                } else {
                    garmentLookbookIntroForm
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var garmentLookbookIntroForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    "Camisas, pantalones, medias y cinturones comparten esta ruta en lugar de zapato "
                        + "(ahí tienes vista 360°). Tras crear la ficha vas a hacer 5 fotos de tu prenda por frente, espalda y detalles; "
                        + "Gemini creará vistas de catálogo (fondo blanco) más escenarios lifestyle.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.52))

                TextField("Nombre (ej.: camisa denim azul)", text: $garmentName)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.black)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tipo de pieza").font(.subheadline.weight(.semibold))
                    Menu {
                        ForEach(Self.categoryChoices, id: \.rawValue) { cat in
                            Button {
                                category = cat
                            } label: {
                                HStack {
                                    Text("\(cat.emoji) \(cat.displayName)")
                                    Spacer(minLength: 8)
                                    if cat == category {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("\(category.emoji) \(category.displayName)")
                                .foregroundStyle(Color.black)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(Color.black.opacity(0.42))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
                    }
                }

                Button {
                    guard draftRow == nil else { return }
                    do {
                        let path = try Self.provisionalPlaceholderCropPath()
                        let row = ClosetItem(
                            name: trimmedName,
                            brand: "Unknown Brand",
                            category: category,
                            imageFilename: path,
                            originalCropFilename: path,
                            isDraft: false
                        )
                        modelContext.insert(row)
                        try? modelContext.save()
                        draftRow = row
                        ClosetAnalytics.named("closet_ropa_lookbook_draft_started", params: "cat:\(category.rawValue)")
                    } catch {
                        // Silenciar; siguiente intento válido
                    }
                } label: {
                    Label("Ir a las 5 fotos", systemImage: "camera.aperture")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black))
                }
                .padding(.top, 6)
            }
            .padding(20)
        }
        .navigationTitle("Ropa — lookbook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar") { dismiss() }
                    .foregroundStyle(Color.black)
            }
        }
    }

    private func abandonStandaloneDraft(_ item: ClosetItem) {
        ImageStore.deleteIfExists(item.imageFilename)
        if let oc = item.originalCropFilename { ImageStore.deleteIfExists(oc) }
        for p in item.lookbookStudio { ImageStore.deleteIfExists(p) }
        for p in item.lookbookLifestyle { ImageStore.deleteIfExists(p) }
        modelContext.delete(item)
        try? modelContext.save()
        ClosetAnalytics.named("closet_ropa_lookbook_draft_abort")
    }
}

// MARK: - Pipeline fullscreen

struct AddToClosetPipelineView: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var flow: AddToClosetFlowViewModel

    @State private var savingAll = false
    @State private var editingPieceId: UUID?
    @State private var editNameDraft = ""
    @State private var categoryPickerPieceID: UUID?
    @State private var shoe360DraftSheetPieceID: Shoe360DraftSheetPieceID?
    @State private var prettifyBusy = Set<UUID>()
    /// Sheet 360° mostrado automáticamente al menos una vez por pieza; se resetea si completas ángulos o cambias categoría.
    @State private var offeredShoe360DraftWizardPieceIDs = Set<UUID>()
    /// Retaso único ante varios cambios seguidos en el borrador.
    @State private var shoe360WizardDelayTask: Task<Void, Never>?
    /// Micro-animación al guardar todas (efecto de escala solicitado).
    @State private var saveAllBump = false

    /// Gemini u OpenAI: al menos uno habilita el lote «Generar» (Prettify intenta Gemini primero).
    private var studioBatchAvailable: Bool {
        GeminiService.apiKeyConfigured
    }

    private var shoePiecesAutoWizardFingerprint: String {
        flow.pieces
            .map { "\($0.id.uuidString)|\($0.category?.rawValue ?? "-")|\($0.shoe360Complete)|\($0.name)" }
            .sorted()
            .joined(separator: ";")
    }

    /// Hay zapatos en revisión pendientes del flujo guiado de 4 ángulos.
    private var hasIncompleteShoesInReview: Bool {
        flow.phase == .review &&
            flow.pieces.contains(where: { $0.category == .shoes && !$0.shoe360Complete })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if !flow.uploadRows.isEmpty {
                            uploadingSection
                        }
                        if flow.phase == .review, !flow.pieces.isEmpty {
                            reviewSection
                        }
                        if flow.phase == .idle, flow.uploadRows.isEmpty, flow.pieces.isEmpty {
                            idleHint
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        closePipelineTapped()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await flow.generateAllStudio() }
                    } label: {
                        HStack(spacing: 5) {
                            if flow.isGeneratingStudioBatch {
                                ProgressView().scaleEffect(0.82).tint(.white)
                                Text("Generando…")
                            } else {
                                Image(systemName: "sparkles")
                                Text(flow.studioBatchInvocationFinished ? "Regenerar ✨" : "Generar ✨")
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black))
                    }
                    .disabled(
                        flow.phase != .review || flow.pieces.isEmpty || flow.isGeneratingStudioBatch
                            || !studioBatchAvailable)

                    Button {
                        Task { await saveAllTapped() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                            Text("Agregar todo")
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(
                            flow.canSaveAll && !flow.isGeneratingStudioBatch ? Color.black : Color(.tertiaryLabel)
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(flow.canSaveAll && !flow.isGeneratingStudioBatch ? Color(.secondarySystemBackground) : Color(.tertiarySystemFill))
                        )
                    }
                    .disabled(!flow.canSaveAll || savingAll || flow.isGeneratingStudioBatch)
                    .scaleEffect(saveAllBump ? 0.96 : 1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.66), value: saveAllBump)
                }
            }
        }
        .alert("Nombre de la prenda", isPresented: Binding(
            get: { editingPieceId != nil },
            set: { if !$0 { editingPieceId = nil } }
        )) {
            TextField("Nombre", text: $editNameDraft)
            Button("Guardar") {
                guard let id = editingPieceId, let ix = flow.pieces.firstIndex(where: { $0.id == id }) else { return }
                flow.pieces[ix].name = editNameDraft
                editingPieceId = nil
            }
            Button("Cancelar", role: .cancel) { editingPieceId = nil }
        }
        .sheet(isPresented: Binding(
            get: { categoryPickerPieceID != nil },
            set: { if !$0 { categoryPickerPieceID = nil } }
        )) {
            if let cid = categoryPickerPieceID {
                categoryPickerSheet(pieceID: cid)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $shoe360DraftSheetPieceID) { token in
            NavigationStack {
                ShoeMultiAngleCaptureView(
                    garmentName:
                        flow.pieces.first(where: { $0.id == token.pieceID })?.name ?? "Zapatos"
                ) { paths in
                    flow.applyShoe360Catalog(orderedPrettyPaths: paths, pieceID: token.pieceID)
                }
            }
            .presentationDragIndicator(.visible)
            .presentationDetents([.large])
        }
        .toastOverlay(
            message: Binding(
                get: { flow.toast },
                set: { flow.toast = $0 }
            ))
        .onChange(of: shoePiecesAutoWizardFingerprint) { _, _ in
            queueAutoShoe360WizardDeferred()
        }
        .onAppear {
            queueAutoShoe360WizardDeferred()
        }
        .onChange(of: categoryPickerPieceID) { _, id in
            if id == nil {
                queueAutoShoe360WizardDeferred()
            }
        }
    }

    private func closePipelineTapped() {
        shoe360WizardDelayTask?.cancel()
        shoe360WizardDelayTask = nil
        if !flow.pieces.isEmpty {
            flow.persistPiecesForLater()
        }
        flow.clearEphemeralPresentationState()
        isPresented = false
    }

    private func queueAutoShoe360WizardDeferred() {
        shoe360WizardDelayTask?.cancel()
        shoe360WizardDelayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled else { return }
            defer { shoe360WizardDelayTask = nil }
            guard flow.phase == .review else { return }
            guard shoe360DraftSheetPieceID == nil, categoryPickerPieceID == nil else { return }
            for piece in flow.pieces where piece.shoe360Complete {
                offeredShoe360DraftWizardPieceIDs.remove(piece.id)
            }
            guard let candidate = flow.pieces.first(where: {
                $0.category == .shoes &&
                    !$0.shoe360Complete &&
                    !offeredShoe360DraftWizardPieceIDs.contains($0.id)
            }) else { return }
            offeredShoe360DraftWizardPieceIDs.insert(candidate.id)
            shoe360DraftSheetPieceID = Shoe360DraftSheetPieceID(pieceID: candidate.id)
        }
    }

    @ViewBuilder
    private var idleHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "tshirt.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.black.opacity(0.18))
            Text("Aquí aparecerán las prendas detectadas tras elegir tus fotos.")
                .multilineTextAlignment(.center)
                .foregroundStyle(ClosetFlowPalette.secondaryText)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private var uploadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Procesando")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.black)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(flow.uploadRows) { row in
                    ZStack {
                        Image(uiImage: row.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 100)
                            .clipped()
                            .cornerRadius(12)

                        if !row.finished {
                            Color.white.opacity(0.5)
                            ProgressView().tint(.black)
                        }
                    }
                    .aspectRatio(0.92, contentMode: .fit)
                    .cornerRadius(12)
                }
            }
        }
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.97).combined(with: .opacity),
                removal: .opacity))
        .animation(.spring(response: 0.52, dampingFraction: 0.82), value: flow.uploadRows.count)
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Revisión")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.black)

            if hasIncompleteShoesInReview {
                HStack(alignment: .top, spacing: 10) {
                    Text("👞")
                        .font(.system(size: 20))
                    Text(
                        "Para zapatos, la app abrirá la vista 360° con 4 fotos guiadas "
                            + "(frontal, lateral derecho, trasera y lateral izquierdo)."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemGray6))
                }
            }

            ForEach(Array(flow.pieces.enumerated()), id: \.element.id) { _, piece in
                pieceCard(piece)
                    .transition(
                        .asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity))
            }
            .animation(.spring(response: 0.52, dampingFraction: 0.84), value: flow.pieces.map(\.id))
        }
    }

    private func pieceCard(_ piece: ClosetDraftPiece) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                thumb(for: piece)
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        editingPieceId = piece.id
                        editNameDraft = piece.name
                    } label: {
                        HStack(spacing: 6) {
                            Text(piece.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.black)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.42))
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)

                    brandField(
                        Binding(
                            get: {
                                if let ix = flow.pieces.firstIndex(where: { $0.id == piece.id }) {
                                    return flow.pieces[ix].brand
                                }
                                return ""
                            },
                            set: { newVal in
                                guard let ix = flow.pieces.firstIndex(where: { $0.id == piece.id }) else { return }
                                flow.pieces[ix].brand = newVal
                            }))

                    Divider().foregroundStyle(Color.black.opacity(0.06))

                    categoryRow(piece)
                }
            }

            HStack(spacing: 10) {
                if piece.category == .shoes {
                    miniPill(
                        title: piece.shoe360Complete ? "Editar vista 360°" : "Vista 360° 👞",
                        foreground: Color.black.opacity(0.88),
                        background: ClosetFlowPalette.mutedBackground
                    ) {
                        shoe360DraftSheetPieceID = Shoe360DraftSheetPieceID(pieceID: piece.id)
                    }
                    .opacity(flow.generatingPieceIDs.contains(piece.id) ? 0.35 : 1)
                    .disabled(flow.generatingPieceIDs.contains(piece.id))
                } else {
                    miniPill(
                        title: prettifyBusy.contains(piece.id) ? "… Prettify" : "Prettify ✨",
                        foreground: Color.black.opacity(0.88),
                        background: ClosetFlowPalette.mutedBackground
                    ) {
                        prettifyBusy.insert(piece.id)
                        Task {
                            await flow.prettify(pieceID: piece.id)
                            prettifyBusy.remove(piece.id)
                        }
                    }
                    .opacity(prettifyBlocked(piece) ? 0.35 : 1)
                    .disabled(prettifyBlocked(piece))
                }

                miniPill(title: "Agregar ✓", foreground: Color.white, background: Color.black) {
                    do {
                        try flow.insertOne(pieceID: piece.id, modelContext: modelContext)
                    } catch {
                        flow.showToast(error.localizedDescription)
                    }
                }
                .opacity(piece.category != nil && piece.isCatalogImageReady ? 1 : 0.35)
                .disabled(piece.category == nil || !piece.isCatalogImageReady)
            }

            if piece.prettifyFailedBadge {
                Text("Error al generar")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(ClosetFlowPalette.destructive)
            } else if flow.phase == .review, piece.prettifiedRelativePath == nil,
                      piece.category != .shoes,
                      !flow.generatingPieceIDs.contains(piece.id)
            {
                Text("Sin generar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
            }

            if piece.category == .shoes, !piece.shoe360Complete,
               !flow.generatingPieceIDs.contains(piece.id)
            {
                Text("Zapatos: captura frontal, derecha, atrás e izquierda antes de guardar.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ClosetFlowPalette.destructive.opacity(0.92))
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ClosetFlowPalette.mutedBackground)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                flow.removeDraftPiece(id: piece.id)
                prettifyBusy.remove(piece.id)
                offeredShoe360DraftWizardPieceIDs.remove(piece.id)
                if editingPieceId == piece.id {
                    editingPieceId = nil
                }
                if categoryPickerPieceID == piece.id {
                    categoryPickerPieceID = nil
                }
                if shoe360DraftSheetPieceID?.pieceID == piece.id {
                    shoe360DraftSheetPieceID = nil
                }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ClosetFlowPalette.destructive)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eliminar del borrador")
            .padding(8)
        }
    }

    private func prettifyBlocked(_ piece: ClosetDraftPiece) -> Bool {
        prettifyBusy.contains(piece.id) || flow.generatingPieceIDs.contains(piece.id)
    }

    private func thumb(for piece: ClosetDraftPiece) -> some View {
        let path = piece.prettifiedRelativePath ?? piece.originalCropRelativePath
        let busy = prettifyBusy.contains(piece.id) || flow.generatingPieceIDs.contains(piece.id)
        return ZStack {
            Color.white
            if let ui = ImageStore.load(path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                ProgressView().tint(.black)
            }
            if busy {
                Color.white.opacity(0.55)
                ProgressView().tint(.black)
            }
        }
    }

    private func categoryRow(_ piece: ClosetDraftPiece) -> some View {
        Button {
            categoryPickerPieceID = piece.id
        } label: {
            if let cat = piece.category {
                HStack {
                    Text(cat.emoji).font(.system(size: 18))
                    Text(cat.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black)
                    Spacer()
                }
            } else {
                Text("Seleccionar categoría")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(ClosetFlowPalette.destructive)
            }
        }
        .buttonStyle(.plain)
    }

    private func brandField(_ binding: Binding<String>) -> some View {
        TextField("Agregar marca", text: binding)
            .font(.system(size: 14))
            .foregroundStyle(Color.black.opacity(0.88))
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
            }
    }

    private func miniPill(
        title: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Capsule().fill(background))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func categoryPickerSheet(pieceID: UUID) -> some View {
        NavigationStack {
            List {
                ForEach(ClothingCategory.allCases, id: \.self) { cat in
                    Button {
                        if let ix = flow.pieces.firstIndex(where: { $0.id == pieceID }) {
                            let prev = flow.pieces[ix].category
                            flow.pieces[ix].category = cat
                            if prev == .shoes && cat != .shoes {
                                flow.discardDraftShoeAngles(at: ix)
                                offeredShoe360DraftWizardPieceIDs.remove(pieceID)
                            }
                            categoryPickerPieceID = nil
                        }
                    } label: {
                        HStack {
                            Text(cat.emoji).font(.system(size: 20))
                            Text(cat.displayName)
                                .foregroundStyle(Color.black)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Categoría")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Listo") { categoryPickerPieceID = nil }
                }
            }
        }
    }

    private func saveAllTapped() async {
        guard flow.canSaveAll else { return }
        savingAll = true
        saveAllBump = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { saveAllBump = false }

        defer { savingAll = false }
        do {
            try flow.insertAll(modelContext: modelContext)
            flow.resetClearingDraftFile()
            isPresented = false
        } catch {
            flow.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Toast ligero

private struct ToastBannerModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let msg = message {
                    Text(msg)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.black.opacity(0.9)))
                        .padding(.bottom, 48)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.85), value: message)
    }
}

extension View {
    func toastOverlay(message: Binding<String?>) -> some View {
        modifier(ToastBannerModifier(message: message))
    }
}

import SwiftData
import SwiftUI
import UIKit

// MARK: - Fila miniatura durante procesamiento

struct ClosetUploadRow: Identifiable, Equatable {
    let id: UUID
    let thumbnail: UIImage
    var finished: Bool
}

// MARK: - Flujo local: fotos → Gemini → revisión → SwiftData

@MainActor
final class AddToClosetFlowViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case processing
        case review
    }

    @Published var phase = Phase.idle
    @Published var toast: String?
    @Published var pieces: [ClosetDraftPiece] = []
    @Published private(set) var activeProcessingCount = 0
    @Published private(set) var uploadRows: [ClosetUploadRow] = []
    /// Spinner por card durante «Generar ✨» (lote).
    @Published private(set) var generatingPieceIDs = Set<UUID>()
    @Published private(set) var isGeneratingStudioBatch = false
    /// El usuario ya lanzó una generación de catálogo (lote terminado; puede regenerar).
    @Published private(set) var studioBatchInvocationFinished = false

    var isBusyProcessingOutfits: Bool {
        phase == .processing || activeProcessingCount > 0 || isGeneratingStudioBatch
    }

    var canSaveAll: Bool {
        guard phase == .review, !isBusyProcessingOutfits, !pieces.isEmpty else { return false }
        guard pieces.allSatisfy({ $0.category != nil }) else { return false }
        guard studioBatchInvocationFinished else { return false }
        return pieces.allSatisfy(\.isCatalogImageReady)
    }

    func showToast(_ s: String) {
        toast = s
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if toast == s { toast = nil }
        }
    }

    func beginProcessing(images: [UIImage]) {
        ClosetAnalytics.named("photos_selected", params: "count:\(images.count)")
        let rows = images.map { ClosetUploadRow(id: UUID(), thumbnail: $0, finished: false) }
        uploadRows = rows
        pieces = []
        studioBatchInvocationFinished = false
        phase = .processing
        activeProcessingCount = rows.count
        ClosetLocalDraftStore.clear()

        Task {
            await withTaskGroup(of: Void.self) { group in
                for row in rows {
                    group.addTask {
                        await self.processOneOutfitPhoto(rowID: row.id, image: row.thumbnail)
                    }
                }
            }

            if pieces.isEmpty {
                phase = .idle
                uploadRows.removeAll()
                showToast(
                    "No pudimos detectar prendas en esta foto. Inténtalo con mejor iluminación o otra toma."
                )
            } else {
                phase = .review
            }
            ClosetAnalytics.named("detection_completed", params: "pieces:\(pieces.count)")
        }
    }

    func resumePersistedDrafts(decoded: [ClosetDraftPiece]) {
        guard !decoded.isEmpty else { return }
        pieces = decoded
        uploadRows = []
        phase = .review
        studioBatchInvocationFinished = decoded.allSatisfy(\.isCatalogImageReady)
    }

    func persistPiecesForLater() {
        ClosetLocalDraftStore.save(pieces)
    }

    func clearEphemeralPresentationState() {
        phase = .idle
        pieces = []
        uploadRows = []
        activeProcessingCount = 0
        toast = nil
    }

    func resetClearingDraftFile() {
        phase = .idle
        pieces = []
        uploadRows = []
        activeProcessingCount = 0
        toast = nil
        ClosetLocalDraftStore.clear()
    }

    /// Quita una prenda del borrador, borra sus ficheros locales y sincroniza el JSON de borrador.
    func removeDraftPiece(id: UUID) {
        guard let idx = pieces.firstIndex(where: { $0.id == id }) else { return }
        let removed = pieces[idx]
        pieces.remove(at: idx)
        generatingPieceIDs.remove(id)

        ImageStore.deleteIfExists(removed.originalCropRelativePath)
        if let pr = removed.prettifiedRelativePath {
            ImageStore.deleteIfExists(pr)
        }
        for path in removed.multiAngleFilenames {
            ImageStore.deleteIfExists(path)
        }

        // La foto original del outfit puede compartirse entre varios recortes de la misma subida.
        if let outfit = removed.sourceOutfitRelativePath {
            let stillReferenced = pieces.contains { $0.sourceOutfitRelativePath == outfit }
            if !stillReferenced {
                ImageStore.deleteIfExists(outfit)
            }
        }

        if pieces.isEmpty {
            studioBatchInvocationFinished = false
            isGeneratingStudioBatch = false
            generatingPieceIDs.removeAll()
            phase = .idle
            ClosetLocalDraftStore.clear()
        } else {
            persistPiecesForLater()
        }
        ClosetAnalytics.named("closet_draft_piece_removed")
    }

    private func processOneOutfitPhoto(rowID: UUID, image: UIImage) async {
        defer {
            Task { @MainActor in
                activeProcessingCount = max(0, activeProcessingCount - 1)
                if let idx = uploadRows.firstIndex(where: { $0.id == rowID }) {
                    uploadRows[idx].finished = true
                }
            }
        }

        guard let jpeg = image.jpegData(compressionQuality: 0.88) else {
            await MainActor.run { showToast("No pudimos comprimir una de las fotos.") }
            return
        }
        let originalRel = try? ImageStore.save(jpeg, inFolder: "originals", filename: "\(UUID().uuidString.lowercased()).jpg")

        do {
            let detected = try await GeminiService.shared.detectItems(in: image)
            guard !detected.isEmpty else { return }

            var newPieces: [(UUID, ClosetDraftPiece)] = []
            for d in detected {
                let draft = ClosetDraftPiece(
                    id: d.id,
                    originalCropRelativePath: d.originalCropRelativePath,
                    prettifiedRelativePath: nil,
                    multiAngleFilenamesJSON: nil,
                    sourceOutfitRelativePath: originalRel,
                    boundingBox: d.boundingBox,
                    name: d.name,
                    brand: "",
                    skuText: "",
                    sizeText: "",
                    colorLabel: "",
                    productDescription: "",
                    purchasePriceText: "",
                    priceText: "",
                    marketPriceJSON: nil,
                    listingPlatformsRaw: nil,
                    category: d.category,
                    prettifyFailedBadge: false
                )
                newPieces.append((d.id, draft))
            }

            await MainActor.run {
                for (_, p) in newPieces {
                    pieces.append(p)
                }
                if phase == .idle { phase = .review }
            }

            for (pieceID, draft) in newPieces {
                await enrichDraftPiece(
                    pieceID: pieceID,
                    cropPath: draft.originalCropRelativePath,
                    category: draft.category ?? .accessories,
                    name: draft.name
                )
            }
        } catch {
            await MainActor.run {
                showToast(error.localizedDescription)
            }
        }
    }

    /// Botón «Generar ✨»: genera imágenes de catálogo en paralelo con Gemini.
    func generateAllStudio() async {
        guard phase == .review, !pieces.isEmpty, !isGeneratingStudioBatch else { return }
        guard GeminiService.apiKeyConfigured else {
            showToast(
                "Configura GeminiAPIKey en DeveloperSettings.local.xcconfig o Info para generar el catálogo."
            )
            return
        }
        let batch = pieces.compactMap { p -> (id: UUID, cropPath: String, cat: String, name: String)? in
            if p.category == .shoes { return nil }
            return (
                id: p.id,
                cropPath: p.originalCropRelativePath,
                cat: (p.category ?? .accessories).rawValue,
                name: p.name,
            )
        }
        isGeneratingStudioBatch = true
        generatingPieceIDs = Set(batch.map(\.id))
        defer {
            generatingPieceIDs.removeAll()
            isGeneratingStudioBatch = false
            studioBatchInvocationFinished = true
            persistPiecesForLater()
        }

        if batch.isEmpty { return }

        await withTaskGroup(of: (UUID, Result<String, Error>).self) { group in
            for item in batch {
                group.addTask {
                    do {
                        let path = try await Self.runStudioPrettify(
                            cropRelativePath: item.cropPath,
                            category: item.cat,
                            itemName: item.name
                        )
                        return (item.id, .success(path))
                    } catch {
                        return (item.id, .failure(error))
                    }
                }
            }
            for await (pieceID, result) in group {
                await MainActor.run {
                    generatingPieceIDs.remove(pieceID)
                    guard let idx = pieces.firstIndex(where: { $0.id == pieceID }) else { return }
                    switch result {
                    case .success(let path):
                        pieces[idx].prettifiedRelativePath = path
                        pieces[idx].prettifyFailedBadge = false
                    case .failure:
                        pieces[idx].prettifyFailedBadge = true
                    }
                }
            }
        }
        ClosetAnalytics.named("studio_generate_batch", params: "count:\(batch.count)")
    }

    /// Resultado «estudio»: Prettify clásico o vistas `shoe360/` tras el flujo de zapatos (4 vistas; algunos datos legados tienen 5).
    func applyShoe360Catalog(orderedPrettyPaths: [String], pieceID: UUID) {
        guard orderedPrettyPaths.count == ShoeAngle.allCases.count
            || orderedPrettyPaths.count == ShoeAngle.legacyMultiAngleCount,
            let idx = pieces.firstIndex(where: { $0.id == pieceID })
        else { return }

        pieces[idx].multiAngleFilenames = orderedPrettyPaths
        let leftIdx = ShoeAngle.left.rawValue
        pieces[idx].prettifiedRelativePath =
            orderedPrettyPaths.indices.contains(leftIdx)
            ? orderedPrettyPaths[leftIdx]
            : orderedPrettyPaths[0]
        pieces[idx].prettifyFailedBadge = false

        studioBatchInvocationFinished = pieces.allSatisfy(\.isCatalogImageReady)
        persistPiecesForLater()
        ClosetAnalytics.named("draft_shoe360_saved", params: "piece")
    }

    /// Al dejar de ser «Zapatos», borra las vistas 360° y el thumb de catálogo asociado.
    func discardDraftShoeAngles(at idx: Int) {
        guard pieces.indices.contains(idx) else { return }
        for path in pieces[idx].multiAngleFilenames {
            ImageStore.deleteIfExists(path)
        }
        pieces[idx].multiAngleFilenames = []
        pieces[idx].prettifiedRelativePath = nil
        pieces[idx].prettifyFailedBadge = false
        persistPiecesForLater()
    }

    func prettify(pieceID: UUID) async {
        guard let idx = pieces.firstIndex(where: { $0.id == pieceID }) else { return }
        let cat = pieces[idx].category ?? .accessories
        if cat == .shoes {
            showToast("Para zapatos usa «Vista 360°» (4 fotos por ángulo).")
            return
        }
        pieces[idx].prettifyFailedBadge = false
        do {
            let path = try await Self.runStudioPrettify(
                cropRelativePath: pieces[idx].originalCropRelativePath,
                category: cat.rawValue,
                itemName: pieces[idx].name
            )
            pieces[idx].prettifiedRelativePath = path
            ClosetAnalytics.named("prettify_completed")
        } catch {
            pieces[idx].prettifyFailedBadge = true
            showToast("Prettify no disponible. Se mantiene el recorte original.")
        }
    }

    func insertOne(pieceID: UUID, modelContext: ModelContext) throws {
        guard let idx = pieces.firstIndex(where: { $0.id == pieceID }),
              let cat = pieces[idx].category
        else { return }

        guard pieces[idx].isCatalogImageReady else {
            showToast(
                pieces[idx].category == .shoes
                    ? "Completa vista 360° para este par de zapatos."
                    : "Genera primero la imagen de catálogo (✨)."
            )
            return
        }
        try persistPiece(at: idx, category: cat, modelContext: modelContext)
        pieces.remove(at: idx)
        ClosetAnalytics.named("items_saved", params: "single")
        if pieces.isEmpty {
            ClosetLocalDraftStore.clear()
        } else {
            persistPiecesForLater()
        }
    }

    func insertAll(modelContext: ModelContext) throws {
        guard canSaveAll else { return }
        let snapshot = pieces
        for p in snapshot {
            guard let idx = pieces.firstIndex(where: { $0.id == p.id }),
                  let cat = pieces[idx].category
            else { continue }
            try persistPiece(at: idx, category: cat, modelContext: modelContext)
        }
        pieces.removeAll()
        ClosetAnalytics.named("items_saved", params: "all:\(snapshot.count)")
        ClosetLocalDraftStore.clear()
    }

    /// Inserta todas aunque falte categoría: asigna `.accessories` como fallback para no bloquear al usuario.
    func insertAllLenient(modelContext: ModelContext) throws {
        guard phase == .review, !pieces.isEmpty else { return }
        while let idx = pieces.indices.first {
            let cat = pieces[idx].category ?? .accessories
            try persistPiece(at: idx, category: cat, modelContext: modelContext)
            pieces.remove(at: idx)
        }
        ClosetLocalDraftStore.clear()
    }

    /// Prettify de catálogo: solo Gemini (`gemini-2.5-flash-image`).
    private static func runStudioPrettify(cropRelativePath: String, category: String, itemName: String) async throws
        -> String
    {
        try await GeminiService.shared.prettify(
            cropRelativePath: cropRelativePath,
            category: category,
            itemName: itemName
        )
    }

    private func persistPiece(at idx: Int, category: ClothingCategory, modelContext: ModelContext) throws {
        let p = pieces[idx]
        let brandStored = p.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayBrand = brandStored.isEmpty ? "Unknown Brand" : brandStored

        let imageFile: String
        var coverPath: String?
        if category == .shoes, p.shoe360Complete {
            let angles = p.multiAngleFilenames
            let leftIdx = ShoeAngle.left.rawValue
            if angles.indices.contains(leftIdx) {
                imageFile = angles[leftIdx]
                coverPath = angles[leftIdx]
            } else {
                imageFile = p.prettifiedRelativePath ?? p.originalCropRelativePath
            }
        } else {
            imageFile = p.prettifiedRelativePath ?? p.originalCropRelativePath
        }

        var paletteJSON: String?
        if let ui = ImageStore.load(imageFile) {
            let hexes = ColorPaletteExtractor.extract(from: ui, count: 5)
            if let data = try? JSONEncoder().encode(hexes),
               let s = String(data: data, encoding: .utf8) {
                paletteJSON = s
            }
        }

        let shoeMultiJSON =
            category == .shoes && p.shoe360Complete ? p.multiAngleFilenamesJSON : nil

        let priceStored = p.priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let purchaseStored = p.purchasePriceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let skuStored = p.skuText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sizeStored = p.sizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let colorStored = p.colorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let descStored = p.productDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let row = ClosetItem(
            name: p.name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: displayBrand,
            skuText: skuStored.isEmpty ? nil : skuStored.uppercased(),
            purchasePriceText: purchaseStored.isEmpty ? nil : purchaseStored,
            priceText: priceStored.isEmpty ? nil : priceStored,
            sizeText: sizeStored.isEmpty ? nil : sizeStored,
            colorLabel: colorStored.isEmpty ? nil : colorStored,
            productDescription: descStored.isEmpty ? nil : descStored,
            marketPriceJSON: p.marketPriceJSON,
            listingPlatformsRaw: p.listingPlatformsRaw,
            colorPaletteJSON: paletteJSON,
            dressCodesRaw: nil,
            seasonsRaw: nil,
            aiColorsJSON: nil,
            multiAngleFilenamesJSON: shoeMultiJSON,
            galleryCoverRelativePath: coverPath,
            category: category,
            imageFilename: imageFile,
            originalCropFilename: p.originalCropRelativePath,
            sourceOutfitFilename: p.sourceOutfitRelativePath,
            boundingBox: p.boundingBox,
            isDraft: false
        )
        modelContext.insert(row)
        try modelContext.save()
    }

    /// Gemini: marca, talla, color, descripción, precio sugerido + OpenAI mercado.
    private func enrichDraftPiece(pieceID: UUID, cropPath: String, category: ClothingCategory, name: String) async {
        guard GeminiService.apiKeyConfigured else { return }
        do {
            let meta = try await GeminiService.shared.enrichGarmentMetadata(
                cropRelativePath: cropPath,
                category: category,
                provisionalName: name
            )
            await MainActor.run {
                guard let idx = pieces.firstIndex(where: { $0.id == pieceID }) else { return }
                if !meta.brand.isEmpty { pieces[idx].brand = meta.brand }
                if !meta.sku.isEmpty {
                    pieces[idx].skuText = meta.sku.uppercased()
                    let split = SneakerSKU.splitNameAndSKU(from: pieces[idx].name)
                    if split.sku != nil, !split.name.isEmpty {
                        pieces[idx].name = split.name
                    }
                }
                if !meta.sizeText.isEmpty { pieces[idx].sizeText = meta.sizeText }
                if !meta.colorLabel.isEmpty { pieces[idx].colorLabel = meta.colorLabel }
                if !meta.productDescription.isEmpty { pieces[idx].productDescription = meta.productDescription }
                if !meta.priceText.isEmpty { pieces[idx].priceText = meta.priceText }
                if !meta.listingPlatforms.isEmpty {
                    pieces[idx].listingPlatformsRaw = meta.listingPlatforms.joined(separator: ",")
                }
                persistPiecesForLater()
            }
        } catch {
            await MainActor.run {
                showToast("Metadatos: \(error.localizedDescription)")
            }
        }
    }

    func fetchMarketPriceForDraftPiece(pieceID: UUID) async {
        guard let idx = pieces.firstIndex(where: { $0.id == pieceID }) else { return }
        let p = pieces[idx]
        let query: String = {
            let sku = p.skuText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sku.isEmpty { return sku.uppercased() }
            return [p.brand, p.name]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }()
        guard !query.isEmpty else { return }
        do {
            let estimate = try await PieceMarketPrice.fetchFromOpenAI(
                query: query,
                category: (p.category ?? .accessories).displayName
            )
            if let data = try? JSONEncoder().encode(estimate),
               let json = String(data: data, encoding: .utf8) {
                await MainActor.run {
                    guard let i = pieces.firstIndex(where: { $0.id == pieceID }) else { return }
                    pieces[i].marketPriceJSON = json
                    if pieces[i].priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        pieces[i].priceText = PieceMarketPrice.formatUSD(estimate.avg)
                    }
                    persistPiecesForLater()
                }
            }
        } catch {
            // Silencioso: el usuario puede consultar manualmente en revisión.
        }
    }
}

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
                    category: d.category,
                    prettifyFailedBadge: false
                )
                newPieces.append((d.id, draft))
            }

            await MainActor.run {
                for (_, p) in newPieces {
                    pieces.append(p)
                }
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
        pieces[idx].prettifiedRelativePath = orderedPrettyPaths[0]
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
        let imageFile = p.prettifiedRelativePath ?? p.originalCropRelativePath
        let brandStored = p.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayBrand = brandStored.isEmpty ? "Unknown Brand" : brandStored

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

        let row = ClosetItem(
            name: p.name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: displayBrand,
            priceText: nil,
            colorPaletteJSON: paletteJSON,
            dressCodesRaw: nil,
            seasonsRaw: nil,
            aiColorsJSON: nil,
            multiAngleFilenamesJSON: shoeMultiJSON,
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
}

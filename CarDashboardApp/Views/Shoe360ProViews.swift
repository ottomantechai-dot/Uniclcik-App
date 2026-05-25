import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Giro fluido StockX-style (crossfade + fase continua)

enum ShoeFluidSpinMath {
    static func normalizePhase(_ p: CGFloat, frameCount n: Int) -> CGFloat {
        guard n > 1 else { return 0 }
        let nf = CGFloat(n)
        var r = p.truncatingRemainder(dividingBy: nf)
        if r < 0 { r += nf }
        return r
    }

    static func snapPhase(_ p: CGFloat, frameCount n: Int) -> CGFloat {
        guard n > 1 else { return 0 }
        let norm = normalizePhase(p, frameCount: n)
        let nf = CGFloat(n)
        var r = Darwin.round(norm).truncatingRemainder(dividingBy: nf)
        if r < 0 { r += nf }
        return r
    }

    static func nearestFrameIndex(phase: CGFloat, frameCount n: Int) -> Int {
        guard n > 1 else { return 0 }
        let s = snapPhase(phase, frameCount: n)
        let k = Int(floor(Double(s) + 0.5))
        return Swift.min(Swift.max(0, k), n - 1)
    }

    /// 0 cuando la fase cae exactamente en un fotograma; ~0.5 a mitad de mezcla.
    static func fractionalDistanceToSnap(phase: CGFloat, frameCount n: Int) -> CGFloat {
        guard n > 1 else { return 0 }
        let norm = normalizePhase(phase, frameCount: n)
        let f = norm - CGFloat(Int(floor(Double(norm))))
        return min(f, 1 - f)
    }

    /// Posición 0 … trackWidth del knob (sin clamps finales aquí).
    static func sliderKnobOffsetX(phase: CGFloat, frameCount n: Int, trackWidth: CGFloat) -> CGFloat {
        guard n > 1 else { return -5 }
        let norm = normalizePhase(phase, frameCount: n)
        let t = norm / CGFloat(n - 1)
        return t * trackWidth - 5
    }
}

/// Dos fotogramas superpuestos con opacidades cruzadas + caché en RAM (evita stutter desde disco).
struct ShoeFluidSpinPhaseLayer: View {
    let filenames: [String]
    let phase: CGFloat

    @State private var cache: [String: UIImage] = [:]

    var body: some View {
        let n = filenames.count
        ZStack {
            Color.white

            if n == 1,
               let rel = filenames.first,
               let ui = cached(rel)
            {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else if n > 1 {
                let p = ShoeFluidSpinMath.normalizePhase(phase, frameCount: n)
                let baseFloor = CGFloat(floor(Double(p)))
                let iA = ((Int(baseFloor) % n) + n) % n
                let iB = (iA + 1) % n
                let frac = p - baseFloor
                let relA = filenames[iA]
                let relB = filenames[iB]
                let ua = cached(relA)
                let ub = cached(relB)

                ZStack {
                    if let ua {
                        Image(uiImage: ua)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .opacity(ub == nil ? 1 : Double(1 - frac))
                    }
                    if let ub {
                        Image(uiImage: ub)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .opacity(ua == nil ? 1 : Double(frac))
                    }
                }
                .drawingGroup(opaque: false)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: filenamesStableID) { await warmupCacheIfNeeded() }
    }

    private var filenamesStableID: String {
        filenames.joined(separator: "\u{1}")
    }

    private func cached(_ relative: String) -> UIImage? {
        if let ui = cache[relative] {
            return ui
        }
        let ui = ImageStore.load(relative)
        cache[relative] = ui
        return ui
    }

    /// Precarga paralela para que el scrubbing sea fluido.
    private func warmupCacheIfNeeded() async {
        guard !filenames.isEmpty else {
            await MainActor.run { cache = [:] }
            return
        }
        let paths = filenames
        let loaded: [String: UIImage] = await Task.detached(priority: .userInitiated) {
            var result: [String: UIImage] = [:]
            result.reserveCapacity(paths.count)
            await withTaskGroup(of: (String, UIImage?).self) { group in
                for rel in paths {
                    group.addTask {
                        (rel, ImageStore.load(rel))
                    }
                }
                for await (rel, img) in group {
                    if let img {
                        result[rel] = img
                    }
                }
            }
            return result
        }.value
        await MainActor.run {
            cache = loaded
        }
    }
}

// MARK: - UIKit bridge · vídeo (cámara o carrete)

struct ClosetMoviePickerBridge: UIViewControllerRepresentable {
    enum Source {
        case camera
        case photoLibrary
    }

    let source: Source
    @Binding var pickedFileURL: URL?
    @Environment(\.dismiss) private var dismiss

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ClosetMoviePickerBridge

        init(_ parent: ClosetMoviePickerBridge) { self.parent = parent }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { parent.dismiss() }
            guard let url = info[.mediaURL] as? URL else { return }
            do {
                parent.pickedFileURL = try Coordinator.copyToClosetImports(url)
            } catch {
                print("🔴 [360Pro] Copiar vídeo: \(error)")
                parent.pickedFileURL = nil
            }
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            parent.dismiss()
        }

        private static func copyToClosetImports(_ temp: URL) throws -> URL {
            let dir = try ImageStore.ensureNestedDirectory(relativePath: "video_imports")
            let dest = dir.appendingPathComponent("\(UUID().uuidString.lowercased()).mov")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: temp, to: dest)
            return dest
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.delegate = context.coordinator
        p.mediaTypes = [UTType.movie.identifier]
        p.videoQuality = .typeHigh
        if source == .camera {
            p.sourceType = .camera
            p.cameraCaptureMode = .video
            p.videoMaximumDuration = 120
        } else {
            p.sourceType = .photoLibrary
        }
        p.modalPresentationStyle = .fullScreen
        return p
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}
}

// MARK: - Captura · video → fotogramas

struct Shoe360ProCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var item: ClosetItem

    @State private var videoURL: URL?
    @State private var showCameraRecorder = false
    @State private var showLibraryPicker = false

    @State private var isExtracting = false
    @State private var isApplyingStudio = false
    @State private var progress: Double = 0
    @State private var extractedRelativePaths: [String] = []
    @State private var errorText: String?

    /// Progreso 0–1 durante el paso de estudio Gemini (solo informativo dentro del subtítulo si hace falta).
    @State private var studioFractionDone: Double = 0

    private let extractBarWeight = 0.22

    private var processingSubtitle: String {
        if isExtracting {
            let ex = max(extractBarWeight, 0.001)
            return "Paso 1/2 · Fotogramas del vídeo (\(Int((progress / ex * 100).rounded())) %)"
        }
        if isApplyingStudio {
            return "Paso 2/2 · Fondo blanco Gemini (mismo ángulo que el vídeo) — \(Int((studioFractionDone * 100).rounded())) %"
        }
        return ""
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Text(
                    """
                    360° Pro: primero exportamos \(Shoe360VideoFrameExtractor.preferredFrameCount) fotogramas del vídeo en el teléfono. \
                    Luego Gemini los convierte en fotos tipo catálogo — fondo blanco #FFFFFF, luz uniforme tipo StockX — respetando el ángulo de cada fotograma. \
                    Una vuelta son unas \(Shoe360VideoFrameExtractor.preferredFrameCount) generaciones IA (las hacemos de 2 en 2 para evitar errores de cuota). \
                    Sin GeminiAPIKey no se puede hacer el paso de estudio.
                    """
                )
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

                heroPreviewBlock

                if isExtracting || isApplyingStudio {
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .tint(.black)
                            .padding(.horizontal, 28)
                        Text(processingSubtitle)
                            .font(.caption)
                            .foregroundStyle(Color.black.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 4)
                } else if extractedRelativePaths.isEmpty {
                    VStack(spacing: 12) {
                        Button {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showCameraRecorder = true
                            } else {
                                errorText = "La cámara no está disponible en este dispositivo."
                            }
                        } label: {
                            Label("Grabar video", systemImage: "video.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: 26).fill(Color.black))
                        }
                        Button {
                            showLibraryPicker = true
                        } label: {
                            Label("Elegir de la galería", systemImage: "film")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: 26).fill(Color(.secondarySystemBackground)))
                        }
                    }
                    .padding(.horizontal, 20)

                    if videoURL != nil {
                        Button {
                            Task { await runExtractionAndStudio() }
                        } label: {
                            Label(
                                "Extraer y fondo estudio (Gemini)",
                                systemImage: "sparkles"
                            )
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 26).fill(Color.black))
                        }
                        .padding(.horizontal, 20)
                        .disabled(!GeminiService.apiKeyConfigured)
                        .opacity(GeminiService.apiKeyConfigured ? 1 : 0.45)
                    }
                    if videoURL != nil, !GeminiService.apiKeyConfigured {
                        Text("Configura GeminiAPIKey para aplicar fondo blanco tipo estudio a todos los fotogramas.")
                            .font(.caption2)
                            .foregroundStyle(Color.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else {
                    resultsPreviewStrip
                    Button {
                        commitSpin()
                    } label: {
                        Label("Guardar vista 360° Pro", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 26).fill(Color.black))
                    }
                    .padding(.horizontal, 20)

                    Button("Volver a empezar") {
                        purgeExtractedTrialFiles()
                        extractedRelativePaths = []
                        videoURL = nil
                        errorText = nil
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.blue)
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(Color.red.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                }
            }
            .padding(.bottom, 32)
            .padding(.top, 8)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("360° Pro (vídeo + IA)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar") { dismissWithCleanupIfNeeded() }
                    .foregroundStyle(Color.black)
            }
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showCameraRecorder) {
            ClosetMoviePickerBridge(source: .camera, pickedFileURL: $videoURL)
        }
        .fullScreenCover(isPresented: $showLibraryPicker) {
            ClosetMoviePickerBridge(source: .photoLibrary, pickedFileURL: $videoURL)
        }
        .onChange(of: videoURL) { _, newVal in
            if newVal != nil {
                errorText = nil
                extractedRelativePaths = []
            }
        }
    }

    private func dismissWithCleanupIfNeeded() {
        if !extractedRelativePaths.isEmpty, item.spin360Filenames != extractedRelativePaths {
            purgeExtractedTrialFiles()
        }
        dismiss()
    }

    private var heroPreviewBlock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let first = extractedRelativePaths.first,
               let ui = ImageStore.load(first)
            {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
            } else if videoURL != nil {
                VStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.black.opacity(0.28))
                    Text("Vídeo listo para extraer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.62))
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.black.opacity(0.22))
                    Text("Sin vídeo")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
            }
        }
        .frame(height: 240)
        .padding(.horizontal, 16)
    }

    private var resultsPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(extractedRelativePaths, id: \.self) { rel in
                    if let ui = ImageStore.load(rel) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func purgeExtractedTrialFiles() {
        for p in extractedRelativePaths {
            ImageStore.deleteIfExists(p)
        }
    }

    @MainActor
    private func runExtractionAndStudio() async {
        guard let videoURL else { return }
        errorText = nil
        studioFractionDone = 0
        extractedRelativePaths = []
        isExtracting = true
        progress = 0

        let paths: [String]
        do {
            paths = try await Shoe360VideoFrameExtractor.extractSpinFrames(from: videoURL) { p in
                Task { @MainActor in progress = extractBarWeight * p }
            }
        } catch {
            isExtracting = false
            extractedRelativePaths = []
            progress = 0
            errorText = error.localizedDescription
            return
        }

        isExtracting = false
        await applyStudioBackground(rawPaths: paths)
    }

    /// Reemplaza vídeo‑crudos por JPG en `shoe360_pro_studio/` con fondo blanco catálogo.
    private func applyStudioBackground(rawPaths: [String]) async {
        let n = rawPaths.count
        guard n > 0 else {
            extractedRelativePaths = []
            return
        }
        guard GeminiService.apiKeyConfigured else {
            extractedRelativePaths = rawPaths
            errorText =
                "Falta GeminiAPIKey: sin clave no se puede aplicar el fondo blanco tipo estudio a los fotogramas."
            progress = 1
            return
        }

        extractedRelativePaths = rawPaths

        isApplyingStudio = true
        studioFractionDone = 0
        progress = extractBarWeight

        defer {
            isApplyingStudio = false
        }

        let batchSize = 2
        var orderedSlots = Array<String?>(repeating: nil, count: n)

        for batchStart in stride(from: 0, to: n, by: batchSize) {
            let upper = min(batchStart + batchSize, n)

            var batchError: Error?

            await withTaskGroup(of: (Int, Result<String, Error>).self) { group in
                for i in batchStart ..< upper {
                    group.addTask {
                        do {
                            let saved = try await GeminiService.shared.prettifyShoeSpin360Frame(
                                cropRelativePath: rawPaths[i],
                                itemName: item.name,
                                frameOneBasedIndex: i + 1,
                                totalFrames: n
                            )
                            return (i, .success(saved))
                        } catch {
                            return (i, .failure(error))
                        }
                    }
                }

                for await (idx, res) in group {
                    switch res {
                    case .success(let path):
                        orderedSlots[idx] = path
                    case .failure(let err):
                        batchError = err
                        group.cancelAll()
                    }
                }
            }

            if let batchError {
                deletePartialStudioOutputs(orderedSlots)
                extractedRelativePaths = rawPaths
                errorText = batchError.localizedDescription
                progress = extractBarWeight
                studioFractionDone = Double(batchStart) / Double(n)
                return
            }

            studioFractionDone = Double(upper) / Double(n)
            progress = extractBarWeight + (1 - extractBarWeight) * studioFractionDone
        }

        let final = orderedSlots.compactMap { $0 }
        guard final.count == n else {
            deletePartialStudioOutputs(orderedSlots)
            extractedRelativePaths = rawPaths
            errorText = "No se generaron todos los fotogramas de estudio."
            progress = extractBarWeight
            studioFractionDone = 0
            return
        }

        for raw in rawPaths {
            ImageStore.deleteIfExists(raw)
        }
        extractedRelativePaths = final
        progress = 1
        studioFractionDone = 1
        ClosetAnalytics.named("closet_shoe360_pro_studio_done", params: "frames:\(n)")
    }

    private func deletePartialStudioOutputs(_ slots: [String?]) {
        for r in slots.compactMap({ $0 }) {
            ImageStore.deleteIfExists(r)
        }
    }

    private func commitSpin() {
        guard !extractedRelativePaths.isEmpty else { return }
        for old in item.spin360Filenames {
            ImageStore.deleteIfExists(old)
        }
        item.spin360Filenames = extractedRelativePaths
        try? modelContext.save()
        ClosetAnalytics.named("closet_shoe360_pro_saved", params: "frames:\(extractedRelativePaths.count)")
        dismiss()
    }
}

// MARK: - Viewer StockX fluido · crossfade + fase continua

struct Shoe360ProViewer: View {
    let filenames: [String]
    @Binding var toast: String?

    @State private var phase: CGFloat = 0
    @State private var spinGrabAnchor: CGFloat = 0
    @State private var isDraggingSpin = false
    @State private var saving = false

    private var frameCount: Int { filenames.count }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let trackInnerWidth = max(width - 28, 44)
            let distSnap =
                frameCount <= 1
                    ? 0
                    : ShoeFluidSpinMath.fractionalDistanceToSnap(
                        phase: phase,
                        frameCount: frameCount
                    )
            let showSwipeHint = !isDraggingSpin && frameCount > 1 && distSnap < 0.045

            ZStack {
                Color.white

                ShoeFluidSpinPhaseLayer(filenames: filenames, phase: phase)

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            Task { await saveCurrentToPhotos() }
                        } label: {
                            HStack(spacing: 5) {
                                if saving {
                                    ProgressView().scaleEffect(0.75).tint(.black)
                                } else {
                                    Image(systemName: "square.and.arrow.down")
                                }
                                Text("Fotos")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.92)))
                        }
                        .disabled(saving || filenames.isEmpty)
                        .buttonStyle(.plain)
                        .padding(10)
                    }

                    Spacer()

                    shoeSliderTrack(trackWidth: trackInnerWidth)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)

                    Text("Arrastra con continuidad · \(frameCount) fotogramas (mezcla)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.42))
                        .padding(.bottom, 12)
                }

                Image(systemName: "hand.draw")
                    .font(.system(size: 21))
                    .foregroundStyle(Color.black.opacity(showSwipeHint ? 0.26 : 0))
                    .offset(y: 68)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(fluidsDragGesture(surfaceWidth: width))
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: filenames.count) { _, newCount in
            guard newCount > 0 else {
                phase = 0
                spinGrabAnchor = 0
                return
            }
            phase = ShoeFluidSpinMath.normalizePhase(phase, frameCount: newCount)
            spinGrabAnchor = phase
        }
    }

    private func fluidsDragGesture(surfaceWidth width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard frameCount > 0 else { return }
                let nFloat = CGFloat(max(frameCount, 1))
                if !isDraggingSpin {
                    isDraggingSpin = true
                    spinGrabAnchor = ShoeFluidSpinMath.normalizePhase(phase, frameCount: frameCount)
                }
                let deltaFrames = -(value.translation.width / max(width, 1)) * nFloat
                var t = Transaction()
                t.animation = nil
                withTransaction(t) {
                    phase = ShoeFluidSpinMath.normalizePhase(spinGrabAnchor + deltaFrames, frameCount: frameCount)
                }
            }
            .onEnded { _ in
                isDraggingSpin = false
                let snapped = ShoeFluidSpinMath.snapPhase(phase, frameCount: frameCount)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    phase = snapped
                }
                spinGrabAnchor = phase
            }
    }

    private func shoeSliderTrack(trackWidth: CGFloat) -> some View {
        let knobX = ShoeFluidSpinMath.sliderKnobOffsetX(
            phase: phase,
            frameCount: frameCount,
            trackWidth: trackWidth
        )

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.gray.opacity(0.28))
                .frame(height: 3)

            Circle()
                .fill(Color.black)
                .frame(width: 10, height: 10)
                .offset(x: max(0, min(knobX, trackWidth - 10)))
        }
        .frame(width: trackWidth + 10, height: 14)
    }

    @MainActor
    private func saveCurrentToPhotos() async {
        let idx = ShoeFluidSpinMath.nearestFrameIndex(phase: phase, frameCount: frameCount)
        guard filenames.indices.contains(idx) else { return }
        saving = true
        defer { saving = false }
        let rel = filenames[idx]
        do {
            try await ClosetPhotoExports.saveRelativeClosetImageToPhotoAlbum(relativePath: rel)
            toast = "Fotograma guardado en Fotos."
        } catch {
            toast = error.localizedDescription
        }
    }
}

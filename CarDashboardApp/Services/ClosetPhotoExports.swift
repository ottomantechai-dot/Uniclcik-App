import Photos
import UIKit

/// Export de imágenes del clóset a Fotos del sistema y formato vertical TikTok/Reels (9:16 sobre blanco).
enum ClosetPhotoExports {
    enum SaveFailure: LocalizedError {
        case photoLibraryDenied
        case saveDidNotFinish

        var errorDescription: String? {
            switch self {
            case .photoLibraryDenied:
                return "No tienes permiso para guardar en Fotos. Actívalo en Ajustes."
            case .saveDidNotFinish:
                return "No se pudo guardar la imagen en Fotos."
            }
        }
    }

    /// Composición 9:16 (1080×1920 pts, scale 1) con fondo #FFFFFF; escala la imagen con `aspectFit`.
    static func tikTokWhitePortraitComposite(image: UIImage) -> UIImage {
        let canvasW: CGFloat = 1080
        let canvasH: CGFloat = 1920
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasW, height: canvasH), format: format)

        let prepared = horizontallyUpImage(image)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

            let iw = prepared.size.width
            let ih = prepared.size.height
            guard iw > 1, ih > 1 else { return }

            let scale = min(canvasW / iw, canvasH / ih)
            let dw = iw * scale
            let dh = ih * scale
            let ox = (canvasW - dw) / 2
            let oy = (canvasH - dh) / 2
            prepared.draw(in: CGRect(x: ox, y: oy, width: dw, height: dh))
        }
    }

    @MainActor
    static func saveToPhotoAlbum(_ image: UIImage) async throws {
        try await Self.requestAddOnlyAuthorizationIfNeeded()
        try await Self.performCreation(image)
    }

    /// Guarda como está (sin recomponer 9:16), p. ej. lookbook/catálogo.
    @MainActor
    static func saveRelativeClosetImageToPhotoAlbum(relativePath: String) async throws {
        guard let img = ImageStore.load(relativePath) else {
            throw SaveFailure.saveDidNotFinish
        }
        try await saveToPhotoAlbum(img)
    }

    /// Avatar/portada TikTok-friendly: mismo ratio 9:16 sobre blanco antes de guardar.
    @MainActor
    static func saveClosetAvatarForTikTokExport(relativePath: String) async throws {
        guard let img = ImageStore.load(relativePath) else {
            throw SaveFailure.saveDidNotFinish
        }
        let tik = tikTokWhitePortraitComposite(image: img)
        try await saveToPhotoAlbum(tik)
    }

    /// Normaliza orientation para dibujado predecible.
    private static func horizontallyUpImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: fmt)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    @MainActor
    private static func requestAddOnlyAuthorizationIfNeeded() async throws {
        let auth = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch auth {
        case .authorized, .limited:
            return
        case .denied, .restricted:
            throw SaveFailure.photoLibraryDenied
        case .notDetermined:
            let next = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    cont.resume(returning: status)
                }
            }
            guard next == .authorized || next == .limited else {
                throw SaveFailure.photoLibraryDenied
            }
        @unknown default:
            throw SaveFailure.photoLibraryDenied
        }
    }

    private static func performCreation(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { ok, error in
                if let error {
                    cont.resume(throwing: error)
                } else if ok {
                    cont.resume(returning: ())
                } else {
                    cont.resume(throwing: SaveFailure.saveDidNotFinish)
                }
            })
        }
    }
}

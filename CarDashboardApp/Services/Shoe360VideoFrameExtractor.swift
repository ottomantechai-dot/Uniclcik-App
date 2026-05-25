import AVFoundation
import Foundation
import UIKit

enum Shoe360VideoFrameExtractorError: LocalizedError {
    case durationTooShort
    case noFramesExtracted
    case insufficientFrames(saved: Int, minimum: Int)

    var errorDescription: String? {
        switch self {
        case .durationTooShort:
            return "El vídeo es demasiado corto. Graba al menos unos 2–3 segundos rodeando el zapato."
        case .noFramesExtracted:
            return "No se pudieron extraer fotogramas del vídeo."
        case .insufficientFrames(let saved, let minimum):
            return "Solo se guardaron \(saved) fotogramas; hacen falta al menos \(minimum) para una vuelta fluida."
        }
    }
}

/// Extracción local (~36 JPG) desde un vídeo tipo “walk-around” sobre el zapato. Sin llamadas a Gemini.
enum Shoe360VideoFrameExtractor {
    static let preferredFrameCount = 36
    static let minimumUsableSavedFrames = 24

    /// Devuelve rutas relativas `shoe360_pro/<uuid>/imgNN.jpg` ordenadas por ángulo.
    static func extractSpinFrames(from videoURL: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> [String] {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 1 else { throw Shoe360VideoFrameExtractorError.durationTooShort }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1024, height: 1024)

        let safeStart = totalSeconds * 0.05
        let safeEnd = totalSeconds * 0.95
        let step = preferredFrameCount <= 1 ? 0 : (safeEnd - safeStart) / Double(preferredFrameCount - 1)
        let times: [CMTime] = (0 ..< preferredFrameCount).map { i in
            CMTime(seconds: safeStart + Double(i) * step, preferredTimescale: 600)
        }

        let sessionFolder = UUID().uuidString.lowercased()
        let nestedFolder = "shoe360_pro/\(sessionFolder)"
        var saved: [String] = []

        for (i, time) in times.enumerated() {
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let ui = UIImage(cgImage: cgImage)
                guard let jpeg = ui.jpegData(compressionQuality: 0.88) else { continue }
                let name = String(format: "img%02d.jpg", i + 1)
                let rel = try ImageStore.save(jpeg, nestedRelativeFolder: nestedFolder, filename: name)
                saved.append(rel)
            } catch {
                print("🔴 [360Pro] Frame \(i + 1) falló: \(error)")
            }
            progress?(Double(i + 1) / Double(preferredFrameCount))
        }

        guard !saved.isEmpty else { throw Shoe360VideoFrameExtractorError.noFramesExtracted }
        guard saved.count >= minimumUsableSavedFrames else {
            for p in saved { ImageStore.deleteIfExists(p) }
            throw Shoe360VideoFrameExtractorError.insufficientFrames(saved: saved.count, minimum: minimumUsableSavedFrames)
        }

        return saved
    }
}

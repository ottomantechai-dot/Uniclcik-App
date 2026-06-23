import ImageIO
import SwiftUI
import UIKit

/// Reproduce un GIF del bundle con timing por fotograma (fluido y contenido en el layout).
struct GIFAnimatedView: UIViewRepresentable {
    var resourceName: String = "AIAssistantOrb"
    var bundle: Bundle = .main
    /// Subcarpeta opcional dentro del bundle (p. ej. `AccarLogo.imageset`).
    var subdirectory: String?
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GIFPlayerContainerView {
        let container = GIFPlayerContainerView()
        container.playerView.contentMode = contentMode
        context.coordinator.load(
            into: container.playerView,
            resourceName: resourceName,
            bundle: bundle,
            subdirectory: subdirectory
        )
        return container
    }

    func updateUIView(_ uiView: GIFPlayerContainerView, context: Context) {
        uiView.playerView.contentMode = contentMode
        context.coordinator.load(
            into: uiView.playerView,
            resourceName: resourceName,
            bundle: bundle,
            subdirectory: subdirectory
        )
    }

    final class Coordinator {
        private var loadedKey: String?

        func load(
            into view: GIFPlayerUIView,
            resourceName: String,
            bundle: Bundle,
            subdirectory: String?
        ) {
            let key = "\(resourceName)|\(subdirectory ?? "")|\(bundle.bundlePath)"
            guard key != loadedKey else { return }
            loadedKey = key

            guard let url = Self.resolvedGIFURL(
                resourceName: resourceName,
                bundle: bundle,
                subdirectory: subdirectory
            ), let data = try? Data(contentsOf: url) else {
                view.configure(with: Data())
                return
            }
            view.configure(with: data)
        }

        private static func resolvedGIFURL(
            resourceName: String,
            bundle: Bundle,
            subdirectory: String?
        ) -> URL? {
            if let subdirectory,
               let url = bundle.url(
                   forResource: resourceName,
                   withExtension: "gif",
                   subdirectory: subdirectory
               ) {
                return url
            }
            if let url = bundle.url(forResource: resourceName, withExtension: "gif") {
                return url
            }
            let imagesetPath = "Assets.xcassets/AccarLogo.imageset/\(resourceName).gif"
            if let url = bundle.resourceURL?.appendingPathComponent(imagesetPath),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            return nil
        }
    }
}

// MARK: - Container (evita que el UIImageView de 1024px rompa el layout SwiftUI)

final class GIFPlayerContainerView: UIView {
    let playerView = GIFPlayerUIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .clear
        playerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

// MARK: - Player

final class GIFPlayerUIView: UIImageView {
    private var timer: Timer?
    private var frames: [(image: UIImage, delay: TimeInterval)] = []
    private var frameIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.magnificationFilter = .linear
        layer.minificationFilter = .linear
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    deinit {
        stopPlayback()
    }

    func configure(with data: Data) {
        stopPlayback()
        frames = Self.decodeFrames(from: data)
        frameIndex = 0

        guard let first = frames.first else {
            image = nil
            return
        }

        image = first.image
        guard frames.count > 1 else { return }
        scheduleNextFrame(after: first.delay)
    }

    private func scheduleNextFrame(after delay: TimeInterval) {
        timer?.invalidate()
        let interval = max(delay, 1.0 / 60.0)
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.advanceFrame()
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    private func advanceFrame() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        let frame = frames[frameIndex]
        image = frame.image
        scheduleNextFrame(after: frame.delay)
    }

    private func stopPlayback() {
        timer?.invalidate()
        timer = nil
    }

    private static func decodeFrames(from data: Data) -> [(UIImage, TimeInterval)] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return [] }

        var result: [(UIImage, TimeInterval)] = []
        result.reserveCapacity(count)

        for index in 0 ..< count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
            let gifDict = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let rawDelay =
                (gifDict?[kCGImagePropertyGIFUnclampedDelayTime as String] as? TimeInterval)
                ?? (gifDict?[kCGImagePropertyGIFDelayTime as String] as? TimeInterval)
                ?? 0.1
            let delay = rawDelay <= 0 ? 0.1 : max(rawDelay, 1.0 / 60.0)
            result.append((UIImage(cgImage: cgImage), delay))
        }
        return result
    }
}

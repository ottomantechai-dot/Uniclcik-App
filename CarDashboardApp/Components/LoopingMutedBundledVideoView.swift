import AVFoundation
import SwiftUI
import UIKit

/// Vídeo del bundle en bucle, sin sonido (p. ej. orbe IA).
struct LoopingMutedBundledVideoView: UIViewRepresentable {
    var resourceName: String
    var fileExtension: String = "mp4"
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> LoopingBundledVideoUIView {
        let v = LoopingBundledVideoUIView()
        v.videoGravity = videoGravity
        if let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) {
            v.start(url: url)
        }
        return v
    }

    func updateUIView(_ uiView: LoopingBundledVideoUIView, context: Context) {
        uiView.videoGravity = videoGravity
    }

    static func dismantleUIView(_ uiView: LoopingBundledVideoUIView, coordinator: Void) {
        uiView.stop()
    }
}

final class LoopingBundledVideoUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var resumeObserver: NSObjectProtocol?

    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet { playerLayer.videoGravity = videoGravity }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
        backgroundColor = .clear
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        playerLayer.videoGravity = videoGravity
    }

    func start(url: URL) {
        stop()
        let item = AVPlayerItem(url: url)
        let pl = AVPlayer(playerItem: item)
        pl.isMuted = true
        pl.volume = 0
        pl.actionAtItemEnd = .none

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak pl] _ in
            pl?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            pl?.play()
        }

        resumeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak pl] _ in
            pl?.play()
        }

        player = pl
        playerLayer.videoGravity = videoGravity
        playerLayer.player = pl
        pl.play()
    }

    func stop() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        if let resumeObserver {
            NotificationCenter.default.removeObserver(resumeObserver)
        }
        resumeObserver = nil
        player?.pause()
        player = nil
        playerLayer.player = nil
    }

    deinit {
        stop()
    }
}

// MARK: - Vídeo guía 360° (scrub por ángulo, sin bucle)

/// Reproduce un vídeo del bundle y se desplaza suavemente al segundo indicado (pausa al llegar).
struct ShoeGuideAngleVideoView: UIViewRepresentable {
    var resourceName: String
    var fileExtension: String = "mp4"
    var angle: ShoeAngle
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> ScrubbingBundledVideoUIView {
        let view = ScrubbingBundledVideoUIView()
        view.videoGravity = videoGravity
        if let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) {
            view.load(url: url, angle: angle)
        }
        return view
    }

    func updateUIView(_ uiView: ScrubbingBundledVideoUIView, context: Context) {
        uiView.videoGravity = videoGravity
        uiView.moveTo(angle: angle, animated: true)
    }

    static func dismantleUIView(_ uiView: ScrubbingBundledVideoUIView, coordinator: Void) {
        uiView.stop()
    }
}

final class ScrubbingBundledVideoUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var player: AVPlayer?
    private var scrubTimer: Timer?
    private var displayedSeconds: Double = 0
    private var videoDuration: Double = 0
    private var resumeObserver: NSObjectProtocol?

    private static let scrubDuration: TimeInterval = 0.48
    private static let tickInterval: TimeInterval = 1.0 / 60.0

    var videoGravity: AVLayerVideoGravity = .resizeAspect {
        didSet { playerLayer.videoGravity = videoGravity }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
        backgroundColor = .clear
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        playerLayer.videoGravity = videoGravity
    }

    func load(url: URL, angle: ShoeAngle) {
        stopScrubAnimation()
        if let resumeObserver {
            NotificationCenter.default.removeObserver(resumeObserver)
        }
        resumeObserver = nil

        let asset = AVURLAsset(url: url)
        let rawDuration = CMTimeGetSeconds(asset.duration)
        videoDuration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 5

        let item = AVPlayerItem(asset: asset)
        let pl = AVPlayer(playerItem: item)
        pl.isMuted = true
        pl.volume = 0
        pl.actionAtItemEnd = .pause
        pl.automaticallyWaitsToMinimizeStalling = false

        player = pl
        playerLayer.player = pl
        let initial = angle.guideVideoSeconds(duration: videoDuration)
        displayedSeconds = initial
        seekExact(to: initial)
        pl.pause()
    }

    func moveTo(angle: ShoeAngle, animated: Bool) {
        moveTo(seconds: angle.guideVideoSeconds(duration: videoDuration), animated: animated)
    }

    func moveTo(seconds target: Double, animated: Bool) {
        guard player != nil else { return }
        let maxTime = videoDuration > 0 ? videoDuration : target
        let clamped = min(max(0, target), maxTime)
        if !animated {
            stopScrubAnimation()
            displayedSeconds = clamped
            seekExact(to: clamped)
            player?.pause()
            return
        }
        if abs(displayedSeconds - clamped) < 0.02 {
            displayedSeconds = clamped
            seekExact(to: clamped)
            player?.pause()
            return
        }

        stopScrubAnimation()
        let start = displayedSeconds
        let delta = clamped - start
        let startTime = CACurrentMediaTime()
        player?.pause()

        scrubTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(1, elapsed / Self.scrubDuration)
            let eased = Self.easeInOut(progress)
            let t = start + delta * eased
            self.displayedSeconds = t
            self.seekExact(to: t)
            if progress >= 1 {
                self.displayedSeconds = clamped
                self.seekExact(to: clamped)
                self.player?.pause()
                timer.invalidate()
                self.scrubTimer = nil
            }
        }
        if let scrubTimer {
            RunLoop.main.add(scrubTimer, forMode: .common)
        }
    }

    func stop() {
        stopScrubAnimation()
        if let resumeObserver {
            NotificationCenter.default.removeObserver(resumeObserver)
        }
        resumeObserver = nil
        player?.pause()
        player = nil
        playerLayer.player = nil
    }

    deinit {
        stop()
    }

    private func stopScrubAnimation() {
        scrubTimer?.invalidate()
        scrubTimer = nil
    }

    private func seekExact(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private static func easeInOut(_ t: Double) -> Double {
        if t < 0.5 { return 2 * t * t }
        return 1 - pow(-2 * t + 2, 2) / 2
    }
}

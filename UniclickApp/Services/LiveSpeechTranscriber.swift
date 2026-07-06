import AVFoundation
import Combine
import Foundation
import Speech

/// Real-time microphone transcription (en-US). Requires microphone and speech recognition permissions.
final class LiveSpeechTranscriber: NSObject, ObservableObject {
    @Published private(set) var partialText: String = ""
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private weak var waveformMonitor: AudioWaveformMonitor?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    init(waveformMonitor: AudioWaveformMonitor? = nil) {
        self.waveformMonitor = waveformMonitor
        super.init()
    }

    func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    cont.resume(returning: status == .authorized)
                }
            }
        }
    }

    /// Arranca captura y reconocimiento. Llamar en cola principal.
    func startLiveTranscription() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        partialText = ""
        recognitionTask?.cancel()
        recognitionTask = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { throw TranscriptionError.setupFailed }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, _ in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    self.partialText = result.bestTranscription.formattedString
                }
            }
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            recognitionRequest.append(buffer)
            self?.waveformMonitor?.ingestAudioBuffer(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopLiveTranscription() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    enum TranscriptionError: LocalizedError {
        case recognizerUnavailable
        case setupFailed

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "English speech recognition is not available on this device."
            case .setupFailed:
                return "Could not start audio capture."
            }
        }
    }
}

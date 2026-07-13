import Foundation
import AVFoundation
import Speech

/// Streams microphone audio into SFSpeechRecognizer and publishes
/// live transcript text plus an input level for the waveform.
final class SpeechTranscriber: NSObject, ObservableObject {
    @Published var liveText = ""
    @Published var level: Float = 0   // 0...1 smoothed RMS
    /// Rolling window of recent levels (newest last) driving the scrolling
    /// waveform, like Voice Memos.
    @Published var levelHistory: [Float] = []
    static let historyLength = 22

    /// Built fresh per recording and fully released on stop. A long-lived engine
    /// keeps the Bluetooth input device claimed, which pins AirPods/BT headsets
    /// in the low-quality HFP profile (16 kHz mono) even after recording ends —
    /// music stays degraded until the input HAL device is released. Tearing the
    /// engine down and deallocating it lets CoreAudio switch the device back to
    /// high-quality A2DP playback.
    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finalText = ""
    private var completion: ((String) -> Void)?

    static func requestPermissions(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { auth in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async { done(auth == .authorized && mic) }
            }
        }
    }

    func start(locale: Locale, onDeviceOnly: Bool) throws {
        stopEngine()
        liveText = ""
        finalText = ""
        levelHistory = Array(repeating: 0, count: Self.historyLength)

        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "OpenFlow", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if onDeviceOnly, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.updateLevel(buffer)
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let result {
                    self.liveText = result.bestTranscription.formattedString
                    if result.isFinal { self.finish(with: result.bestTranscription.formattedString) }
                }
                if error != nil { self.finish(with: self.liveText) }
            }
        }
    }

    /// Stop listening; the recognizer finalizes and calls back with the full text.
    func stop(_ completion: @escaping (String) -> Void) {
        self.completion = completion
        request?.endAudio()
        stopEngineOnly()
        // Safety net if the recognizer never delivers a final result.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.completion != nil else { return }
            self.finish(with: self.liveText)
        }
    }

    func cancel() {
        completion = nil
        stopEngine()
        liveText = ""
        level = 0
    }

    private func finish(with text: String) {
        let done = completion
        completion = nil
        stopEngine()
        level = 0
        if let done { done(text) }
    }

    /// Stop capture and fully release the input device so Bluetooth headsets
    /// revert from HFP (low quality) back to A2DP (high quality).
    private func stopEngineOnly() {
        guard let engine = audioEngine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()
        audioEngine = nil   // deallocate — releases the HAL input device
    }

    private func stopEngine() {
        stopEngineOnly()
        task?.cancel()
        task = nil
        request = nil
    }

    private func updateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(n))
        // Perceptual scaling: compress the dynamic range so quiet speech still
        // moves the bars and shouting doesn't just pin them at max.
        let scaled = min(1, pow(rms * 9, 0.6))
        DispatchQueue.main.async {
            // Fast attack, slower release — like the system voice meters.
            self.level = scaled > self.level
                ? self.level * 0.3 + scaled * 0.7
                : self.level * 0.8 + scaled * 0.2
            self.levelHistory.append(self.level)
            if self.levelHistory.count > Self.historyLength {
                self.levelHistory.removeFirst(self.levelHistory.count - Self.historyLength)
            }
        }
    }
}

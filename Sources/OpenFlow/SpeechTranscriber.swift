import Foundation
import AVFoundation
import Speech

/// Streams microphone audio into SFSpeechRecognizer and publishes
/// live transcript text plus an input level for the waveform.
final class SpeechTranscriber: NSObject, ObservableObject {
    @Published var liveText = ""
    @Published var level: Float = 0   // 0...1 smoothed RMS

    private let audioEngine = AVAudioEngine()
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

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.updateLevel(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

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

    private func stopEngineOnly() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
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
        let scaled = min(1, rms * 12)
        DispatchQueue.main.async { self.level = self.level * 0.6 + scaled * 0.4 }
    }
}

import Foundation
import AVFoundation
import AudioToolbox
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
    private var loggedFirstBuffer = false
    /// Non-zero while we've overridden the system default input for a recording.
    private var savedDefaultInput: AudioDeviceID = 0

    private func restoreDefaultInput() {
        guard savedDefaultInput != 0 else { return }
        let dev = savedDefaultInput
        savedDefaultInput = 0
        AudioDevices.setDefaultInputDevice(dev)
        Log.line("restored default input to \(AudioDevices.name(dev))")
    }

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

        let authStatus = SFSpeechRecognizer.authorizationStatus()
        Log.line("transcriber.start speechAuth=\(authStatus.rawValue) locale=\(locale.identifier)")
        if authStatus != .authorized {
            SFSpeechRecognizer.requestAuthorization { s in Log.line("speech auth callback = \(s.rawValue)") }
            throw NSError(domain: "OpenFlow", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Speech Recognition permission not granted (status \(authStatus.rawValue))"])
        }

        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        Log.line("recognizer available=\(recognizer?.isAvailable ?? false) onDeviceSupported=\(recognizer?.supportsOnDeviceRecognition ?? false)")
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

        // The Bluetooth headset mic (HFP) delivers no audio buffers to
        // AVAudioEngine on macOS and drops music to call quality. When the
        // system default input is Bluetooth, temporarily switch the default to
        // the built-in mic — AVAudioEngine.inputNode follows the default — and
        // restore it on stop. AVAudioEngine must be created AFTER the switch so
        // it inherits the new device.
        let currentDefault = AudioDevices.defaultInputDevice()
        if AppState.shared.settings.preferBuiltInMic,
           AudioDevices.isBluetooth(currentDefault),
           let builtIn = AudioDevices.builtInInputDevice() {
            savedDefaultInput = currentDefault
            let ok = AudioDevices.setDefaultInputDevice(builtIn)
            Log.line("switched default input \(AudioDevices.name(currentDefault)) -> \(AudioDevices.name(builtIn)) ok=\(ok)")
        }

        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        Log.line("tap format sr=\(format.sampleRate) ch=\(format.channelCount)")
        guard format.sampleRate > 0, format.channelCount > 0 else {
            restoreDefaultInput()
            audioEngine = nil
            throw NSError(domain: "OpenFlow", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "No usable audio input device (format \(format.sampleRate)Hz/\(format.channelCount)ch)"])
        }
        loggedFirstBuffer = false
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            if !self.loggedFirstBuffer {
                self.loggedFirstBuffer = true
                Log.line("first audio buffer: frames=\(buffer.frameLength)")
            }
            self.request?.append(buffer)
            self.updateLevel(buffer)
        }
        engine.prepare()
        try engine.start()
        Log.line("engine running=\(engine.isRunning)")

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let result {
                    self.liveText = result.bestTranscription.formattedString
                    if result.isFinal {
                        Log.line("recog FINAL (\(self.liveText.count) chars)")
                        self.finish(with: result.bestTranscription.formattedString)
                    }
                }
                if let error {
                    Log.line("recog ERROR: \(error.localizedDescription)")
                    // Only abandon the session on error if we have nothing yet;
                    // a mid-stream error after text shouldn't discard the audio.
                    if self.liveText.isEmpty { self.finish(with: "") }
                }
            }
        }
    }

    /// Stop listening; the recognizer finalizes and calls back with the full text.
    func stop(_ completion: @escaping (String) -> Void) {
        Log.line("stop requested, liveText=\(liveText.count) chars")
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
        // Restore the default input device only AFTER the engine (and its audio-
        // unit device-change listener) is fully torn down. Doing it synchronously
        // here races that listener and segfaults in IOUnitPropertyListener.
        let toRestore = savedDefaultInput
        savedDefaultInput = 0
        if toRestore != 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                AudioDevices.setDefaultInputDevice(toRestore)
                Log.line("restored default input to \(AudioDevices.name(toRestore))")
            }
        }
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

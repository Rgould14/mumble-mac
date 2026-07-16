import Foundation
import AVFoundation
import AudioToolbox
import Speech

/// Captures microphone audio with AVCaptureSession (targeting a specific device
/// — the built-in mic by preference) and streams it into SFSpeechRecognizer.
///
/// AVCaptureSession is used instead of AVAudioEngine because AVAudioEngine binds
/// its input to the *system default* device, and steering it toward the built-in
/// mic on macOS (when a Bluetooth headset is default) requires flipping the
/// system default device — which proved fragile: no buffers on repeat, format
/// negotiation errors (-10868), and a device-listener segfault. AVCaptureSession
/// picks the exact device by uniqueID, never touches the system default (so
/// Bluetooth headphones stay in high-quality A2DP), and reliably delivers sample
/// buffers we forward to the recognizer.
final class SpeechTranscriber: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    @Published var liveText = ""
    @Published var level: Float = 0   // 0...1 smoothed RMS
    /// Rolling window of recent levels (newest last) driving the scrolling
    /// waveform, like Voice Memos.
    @Published var levelHistory: [Float] = []
    static let historyLength = 22

    private var session: AVCaptureSession?
    private let sampleQueue = DispatchQueue(label: "com.team.openflow.audio")
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var completion: ((String) -> Void)?
    private var loggedFirstBuffer = false

    /// Retained only for API compatibility with the app delegate; the
    /// AVCaptureSession approach never changes the system default input, so
    /// there is nothing to restore. Kept as a no-op to avoid touching main.swift.
    static var originalDefaultInput: AudioDeviceID = 0
    static func restoreOriginalDefaultInput() { /* no-op: default input is never changed */ }

    static func requestPermissions(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { auth in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async { done(auth == .authorized && mic) }
            }
        }
    }

    func start(locale: Locale, onDeviceOnly: Bool) throws {
        teardownSession()
        liveText = ""
        levelHistory = Array(repeating: 0, count: Self.historyLength)

        let authStatus = SFSpeechRecognizer.authorizationStatus()
        Log.line("transcriber.start speechAuth=\(authStatus.rawValue) locale=\(locale.identifier)")
        if authStatus != .authorized {
            SFSpeechRecognizer.requestAuthorization { s in Log.line("speech auth callback = \(s.rawValue)") }
            throw NSError(domain: "OpenFlow", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Speech Recognition permission not granted (status \(authStatus.rawValue))"])
        }

        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        Log.line("recognizer available=\(recognizer?.isAvailable ?? false)")
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "OpenFlow", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if onDeviceOnly, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        // Pick the capture device explicitly — built-in mic by preference.
        let device = try captureDevice()
        Log.line("capture device = \(device.localizedName) (uid \(device.uniqueID))")

        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "OpenFlow", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Cannot add audio input to capture session"])
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(output) else {
            throw NSError(domain: "OpenFlow", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Cannot add audio output to capture session"])
        }
        session.addOutput(output)

        self.session = session
        loggedFirstBuffer = false
        session.startRunning()
        Log.line("capture session running=\(session.isRunning)")

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
                    if self.liveText.isEmpty { self.finish(with: "") }
                }
            }
        }
    }

    /// The built-in mic (preferred) picked by CoreAudio UID, else the system
    /// default audio device.
    private func captureDevice() throws -> AVCaptureDevice {
        if AppState.shared.settings.preferBuiltInMic,
           let uid = AudioDevices.builtInInputUID(),
           let dev = AVCaptureDevice(uniqueID: uid) {
            return dev
        }
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
        if let def = AVCaptureDevice.default(for: .audio) { return def }
        if let first = discovered.first { return first }
        throw NSError(domain: "OpenFlow", code: 6, userInfo: [
            NSLocalizedDescriptionKey: "No audio capture device available"])
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if !loggedFirstBuffer {
            loggedFirstBuffer = true
            Log.line("first audio sample buffer received")
        }
        request?.appendAudioSampleBuffer(sampleBuffer)
        updateLevel(from: sampleBuffer)
    }

    // MARK: - Lifecycle

    func stop(_ completion: @escaping (String) -> Void) {
        Log.line("stop requested, liveText=\(liveText.count) chars")
        self.completion = completion
        request?.endAudio()
        teardownSession()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.completion != nil else { return }
            self.finish(with: self.liveText)
        }
    }

    func cancel() {
        completion = nil
        teardownSession()
        task?.cancel(); task = nil; request = nil
        liveText = ""
        level = 0
    }

    private func finish(with text: String) {
        let done = completion
        completion = nil
        teardownSession()
        task?.cancel(); task = nil; request = nil
        level = 0
        if let done { done(text) }
    }

    private func teardownSession() {
        guard let session else { return }
        if session.isRunning { session.stopRunning() }
        for i in session.inputs { session.removeInput(i) }
        for o in session.outputs { session.removeOutput(o) }
        self.session = nil
    }

    // MARK: - Level metering

    private func updateLevel(from sampleBuffer: CMSampleBuffer) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var lengthAtOffset = 0, totalLength = 0
        var dataPointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset,
                                          totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let dataPointer, totalLength > 0 else { return }

        // Determine sample format from the buffer's ASBD.
        guard let fmt = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee else { return }
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0

        var rms: Float = 0
        if isFloat {
            let count = totalLength / MemoryLayout<Float>.size
            guard count > 0 else { return }
            dataPointer.withMemoryRebound(to: Float.self, capacity: count) { p in
                var sum: Float = 0
                for i in 0..<count { sum += p[i] * p[i] }
                rms = (sum / Float(count)).squareRoot()
            }
        } else {
            let count = totalLength / MemoryLayout<Int16>.size
            guard count > 0 else { return }
            dataPointer.withMemoryRebound(to: Int16.self, capacity: count) { p in
                var sum: Float = 0
                for i in 0..<count { let v = Float(p[i]) / 32768.0; sum += v * v }
                rms = (sum / Float(count)).squareRoot()
            }
        }

        let scaled = min(1, pow(rms * 9, 0.6))
        DispatchQueue.main.async {
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

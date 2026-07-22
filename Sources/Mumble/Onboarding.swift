import SwiftUI
import AVFoundation
import Speech
import AppKit

/// Permission checklist shown on first launch and in Settings, mirroring
/// Wispr Flow's setup flow (microphone + speech + accessibility).
struct PermissionsStatusView: View {
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var speech = SFSpeechRecognizer.authorizationStatus()
    @State private var ax = HotkeyMonitor.hasAccessibilityPermission
    @State private var inputMon = HotkeyMonitor.hasInputMonitoringPermission
    private let tick = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Microphone", ok: mic == .authorized) {
                AVCaptureDevice.requestAccess(for: .audio) { _ in refresh() }
            }
            row("Speech Recognition", ok: speech == .authorized) {
                SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async { refresh() } }
            }
            row("Accessibility (insert text)", ok: ax) {
                HotkeyMonitor.promptForAccessibility()
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            row("Input Monitoring (fn hotkey)", ok: inputMon) {
                HotkeyMonitor.promptForInputMonitoring()
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }
        }
        .onReceive(tick) { _ in refresh() }
    }

    private func refresh() {
        mic = AVCaptureDevice.authorizationStatus(for: .audio)
        speech = SFSpeechRecognizer.authorizationStatus()
        ax = HotkeyMonitor.hasAccessibilityPermission
        inputMon = HotkeyMonitor.hasInputMonitoringPermission
    }

    @ViewBuilder
    private func row(_ name: String, ok: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? .green : .secondary)
            Text(name)
            Spacer()
            if !ok { Button("Grant…", action: action) }
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Set up Mumble").font(.largeTitle.bold())
            Text("Grant these three permissions, then hold **fn** in any app and start talking. Release the key and your words appear — polished.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            GroupBox { PermissionsStatusView().padding(6) }.frame(maxWidth: 440)

            Button("Start using Mumble") {
                state.settings.hasCompletedOnboarding = true
                DictationController.shared.startMonitoring()
                AppWindows.closeOnboarding()
                AppWindows.showHub()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(36)
        .frame(width: 540, height: 460)
    }
}

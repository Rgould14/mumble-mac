import AppKit
import SwiftUI

/// The recording HUD: floating overlay at the bottom-center of the screen —
/// transcript bubble + recording/processing/clipboard pills, per the Mumble
/// design system. Non-activating so focus stays in the target app.
final class FlowBarPanel {
    static let shared = FlowBarPanel()
    private var panel: NSPanel?

    private static let size = NSSize(width: 460, height: 118)

    func show() {
        if panel == nil { makePanel() }
        position()
        panel?.orderFrontRegardless()
    }

    func hideSoon(after delay: TimeInterval = 0.6) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            if DictationController.shared.state == .idle { self?.panel?.orderOut(nil) }
        }
    }

    private func makePanel() {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: FlowBarView())
        self.panel = panel
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        // 24px above the dock/screen bottom per the design spec.
        panel.setFrame(NSRect(x: f.midX - Self.size.width / 2, y: f.minY + 16,
                              width: Self.size.width, height: Self.size.height),
                       display: true)
    }
}

struct FlowBarView: View {
    @ObservedObject var controller = DictationController.shared
    @ObservedObject var transcriber = DictationController.shared.transcriber

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            // Transcript bubble: last two lines while speaking.
            if controller.isDictating, !transcriber.liveText.isEmpty {
                Text(transcriber.liveText)
                    .font(.system(size: 13, weight: .medium))
                    .lineSpacing(4)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.hudInk))
                    .frame(maxWidth: 430)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            switch controller.state {
            case .recording:
                recordingPill
                    .transition(.opacity)
            case .processing:
                statusPill(text: "Polishing…") { HUDSpinner() }
                    .transition(.opacity)
            case .idle:
                if let notice = controller.notice {
                    statusPill(text: notice) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.pink)
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(width: 460, height: 118)
        .animation(.easeOut(duration: 0.18), value: controller.state)
        .animation(.easeOut(duration: 0.18), value: transcriber.liveText.isEmpty)
    }

    /// Recording pill: HUD Ink, waveform + 40px pink stop control.
    private var recordingPill: some View {
        HStack(spacing: 12) {
            if AppState.shared.settings.secondaryKey != .off, !controller.activeLocale.isEmpty {
                Text(languageCode(controller.activeLocale))
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.18)))
            }
            if controller.promptMode {
                Text("PROMPT")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.pinkTintText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.pinkTint))
            }
            WaveformView(history: transcriber.levelHistory)
            Button { controller.stopAndInsert() } label: {
                ZStack {
                    Circle().fill(Theme.pink)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: 10, height: 10)
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Stop and insert (or press your shortcut)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.hudInk))
        .onTapGesture { if controller.isDictating { controller.stopAndInsert() } }
    }

    private func statusPill(text: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 10) {
            icon()
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(Capsule().fill(Theme.hudInk))
    }
}

/// 14px ring spinner: white arc on 25% white track, 0.8s linear rotation.
private func languageCode(_ id: String) -> String {
    String(id.split(separator: "-").first ?? "").uppercased()
}

struct HUDSpinner: View {
    @State private var spinning = false
    var body: some View {
        Circle()
            .stroke(.white.opacity(0.25), lineWidth: 2.5)
            .overlay(
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(.linear(duration: 0.8).repeatForever(autoreverses: false),
                               value: spinning)
            )
            .frame(width: 14, height: 14)
            .onAppear { spinning = true }
    }
}

/// Live waveform: 26 white bars, 3px wide, 2.5px gap, heights 8–26px driven by
/// real mic level samples (newest on the right) — never faked loops.
struct WaveformView: View {
    var history: [Float]
    private let barCount = SpeechTranscriber.historyLength
    private let maxBar: CGFloat = 18
    private let minBar: CGFloat = 4

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                let idx = history.count - barCount + i
                let sample = idx >= 0 && idx < history.count ? CGFloat(history[idx]) : 0
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5, height: minBar + sample * (maxBar - minBar))
                    .animation(.linear(duration: 0.05), value: sample)
            }
        }
        .frame(height: maxBar)
    }
}

import AppKit
import SwiftUI

/// The floating "Flow Bar": a dark navy pill at the bottom-center of the screen
/// with a live waveform, a pink stop button, and a live transcript preview.
/// Non-activating so focus stays in the target app.
final class FlowBarPanel {
    static let shared = FlowBarPanel()
    private var panel: NSPanel?

    private static let size = NSSize(width: 400, height: 104)

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
        panel.setFrame(NSRect(x: f.midX - Self.size.width / 2, y: f.minY + 12,
                              width: Self.size.width, height: Self.size.height),
                       display: true)
    }
}

private extension Color {
    static let flowNavy = Color(red: 0x23 / 255.0, green: 0x2A / 255.0, blue: 0x42 / 255.0)
    static let flowPink = Color(red: 0xF0 / 255.0, green: 0x6E / 255.0, blue: 0xBC / 255.0)
}

struct FlowBarView: View {
    @ObservedObject var controller = DictationController.shared
    @ObservedObject var transcriber = DictationController.shared.transcriber

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            // Live transcript preview while recording.
            if controller.isDictating, !transcriber.liveText.isEmpty {
                Text(transcriber.liveText)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(Color.flowNavy.opacity(0.92)))
                    .frame(maxWidth: 380)
                    .transition(.opacity)
            }

            switch controller.state {
            case .recording:
                recordingPill
            case .processing:
                statusPill(text: "Polishing…") {
                    ProgressView().controlSize(.small).tint(.white)
                }
            case .idle:
                if let notice = controller.notice {
                    statusPill(text: notice) {
                        Image(systemName: "doc.on.clipboard").foregroundStyle(Color.flowPink)
                    }
                }
            }
        }
        .frame(width: 400, height: 104)
        .animation(.easeOut(duration: 0.15), value: transcriber.liveText.isEmpty)
    }

    /// The Figma pill: navy capsule, white waveform, pink circular stop button
    /// containing a white rounded square. Sized like Wispr Flow's bar.
    private var recordingPill: some View {
        HStack(spacing: 9) {
            WaveformView(history: transcriber.levelHistory)
                .padding(.leading, 15)
            Button { controller.stopAndInsert() } label: {
                ZStack {
                    Circle().fill(Color.flowPink)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: 10, height: 10)
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 5)
            .help("Stop and insert (or press your shortcut)")
        }
        .frame(height: 36)
        .background(Capsule().fill(Color.flowNavy))
        .onTapGesture { if controller.isDictating { controller.stopAndInsert() } }
    }

    private func statusPill(text: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 8) {
            icon()
            Text(text).font(.caption).foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.flowNavy))
    }
}

/// Scrolling waveform driven by real mic levels: each bar is a recent level
/// sample (newest on the right), so the shape follows your voice like the
/// Voice Memos / Wispr Flow meters.
struct WaveformView: View {
    var history: [Float]
    private let barCount = SpeechTranscriber.historyLength
    private let maxBar: CGFloat = 20
    private let minBar: CGFloat = 2.5

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                let idx = history.count - barCount + i
                let sample = idx >= 0 && idx < history.count ? CGFloat(history[idx]) : 0
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5, height: max(minBar, sample * maxBar))
                    .animation(.linear(duration: 0.05), value: sample)
            }
        }
        .frame(height: maxBar)
    }
}

import AppKit
import SwiftUI

/// The floating "Flow Bar": a dark navy pill at the bottom-center of the screen
/// with a live waveform, a pink stop button, and a live transcript preview.
/// Non-activating so focus stays in the target app.
final class FlowBarPanel {
    static let shared = FlowBarPanel()
    private var panel: NSPanel?

    private static let size = NSSize(width: 460, height: 130)

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
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Color.flowNavy.opacity(0.92)))
                    .frame(maxWidth: 440)
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
        .frame(width: 460, height: 130)
        .animation(.easeOut(duration: 0.15), value: transcriber.liveText.isEmpty)
    }

    /// The Figma pill: navy capsule, white waveform, pink circular stop button
    /// containing a white rounded square.
    private var recordingPill: some View {
        HStack(spacing: 14) {
            WaveformView(level: transcriber.level)
                .padding(.leading, 22)
            Button { controller.stopAndInsert() } label: {
                ZStack {
                    Circle().fill(Color.flowPink)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 15, height: 15)
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 7)
            .help("Stop and insert (or press your shortcut)")
        }
        .frame(height: 52)
        .background(Capsule().fill(Color.flowNavy))
        .onTapGesture { if controller.isDictating { controller.stopAndInsert() } }
    }

    private func statusPill(text: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 10) {
            icon()
            Text(text).font(.callout).foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.flowNavy))
    }
}

/// White bars reacting to microphone level, matching the Figma waveform.
struct WaveformView: View {
    var level: Float
    private let barCount = 17

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { i in
                    let wobble = 0.5 + 0.5 * sin(t * 8 + Double(i) * 1.1)
                    let base: CGFloat = i.isMultiple(of: 3) ? 10 : 6
                    let h = base + CGFloat(level) * 22 * CGFloat(wobble)
                    Capsule()
                        .fill(.white)
                        .frame(width: 3.5, height: min(h, 30))
                }
            }
            .frame(height: 30)
        }
    }
}

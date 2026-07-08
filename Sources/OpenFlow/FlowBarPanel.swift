import AppKit
import SwiftUI

/// The floating "Flow Bar": a small pill at the bottom-center of the screen,
/// shown while dictating. Non-activating so focus stays in the target app.
final class FlowBarPanel {
    static let shared = FlowBarPanel()
    private var panel: NSPanel?

    func show() {
        if panel == nil { makePanel() }
        position()
        panel?.orderFrontRegardless()
    }

    func hideSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if DictationController.shared.state == .idle { self?.panel?.orderOut(nil) }
        }
    }

    private func makePanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
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
        panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + 12))
    }
}

struct FlowBarView: View {
    @ObservedObject var controller = DictationController.shared
    @ObservedObject var transcriber = DictationController.shared.transcriber

    var body: some View {
        HStack(spacing: 10) {
            switch controller.state {
            case .recording:
                WaveformView(level: transcriber.level)
                Button {
                    controller.stopAndInsert()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop and insert (or press your shortcut)")
            case .processing:
                ProgressView().controlSize(.small).tint(.white)
                Text("Processing…").font(.caption).foregroundStyle(.white.opacity(0.9))
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .frame(width: 200, height: 44)
        .onTapGesture {
            if controller.isDictating { controller.stopAndInsert() }
        }
    }
}

/// Animated white bars that react to microphone level, like Wispr's Flow Bar.
struct WaveformView: View {
    var level: Float
    @State private var phase = 0.0
    private let barCount = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let wobble = 0.5 + 0.5 * sin(t * 8 + Double(i) * 0.9)
                    let h = 4 + CGFloat(level) * 18 * CGFloat(wobble) + 2
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: 3, height: min(h, 24))
                }
            }
            .frame(height: 24)
        }
    }
}

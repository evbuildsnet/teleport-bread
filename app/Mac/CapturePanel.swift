import AppKit
import InboxCore
import SwiftUI

/// Raycast-shaped quick capture: one field, one button, floating over
/// everything. ⏎ creates the need (due today, last-used list) and closes;
/// ⎋ or losing focus closes.
@MainActor
final class CapturePanelController {
    static let shared = CapturePanelController()
    private var panel: NSPanel?

    func toggle(model: AppModel) {
        if let panel, panel.isVisible { close(); return }
        show(model: model)
    }

    func show(model: AppModel) {
        guard model.phase == .ready else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: CaptureView(model: model, close: { [weak self] in self?.close() }))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let size = NSSize(width: 560, height: 64)
        panel.setContentSize(size)
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.66))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        return panel
    }
}

/// Borderless panels refuse key status by default; we need it for typing.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

struct CaptureView: View {
    let model: AppModel
    let close: () -> Void
    @State private var title = ""
    @FocusState private var focused: Bool

    private var canSend: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField("What needs doing?", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .onSubmit(send)
                .onKeyPress(.escape) { close(); return .handled }
                .accessibilityLabel("Quick capture")
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(canSend ? Theme.accent : Theme.input, in: Circle())
                    .foregroundStyle(canSend ? .white : Theme.muted)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Create need")
        }
        .padding(.horizontal, 16)
        .frame(width: 560, height: 64)
        .background(Theme.overlay.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.border))
        .onAppear {
            title = ""
            focused = true
        }
    }

    private func send() {
        guard canSend else { return }
        var draft = model.newDraft()
        draft.title = title
        title = ""
        close()
        Task { await model.send(draft) }
    }
}

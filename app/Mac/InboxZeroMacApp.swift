import AppKit
import InboxCore
import SwiftUI

@main
struct InboxZeroMacApp: App {
    @State private var model = ProcessInfo.processInfo.environment["INBOXZERO_PREVIEW"] == nil ? AppModel() : AppModel.preview()
    @State private var ui = UIState()

    var body: some Scene {
        WindowGroup("InboxZero") {
            MacRootView()
                .environment(model)
                .environment(ui)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 780)
        Settings { SettingsView() }
        .commands {
            // T3 Code's shortcut set — nothing invented.
            CommandGroup(replacing: .newItem) {
                Button("New Need") { ui.newDraft(model: model) }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.phase != .ready)
                Button("Quick Capture") { CapturePanelController.shared.toggle(model: model) }
                    .disabled(model.phase != .ready)
            }
            CommandMenu("Go") {
                Button("Command Palette") { ui.paletteOpen.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Previous Need") { ui.selectNeighbor(-1, in: model) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Next Need") { ui.selectNeighbor(1, in: model) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Divider()
                ForEach(1...9, id: \.self) { number in
                    Button("Need \(number)") { ui.jump(to: number, in: model) }
                        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                }
            }
            CommandGroup(before: .sidebar) {
                Button(ui.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    withAnimation(.snappy(duration: 0.2)) { ui.sidebarVisible.toggle() }
                }
                .keyboardShortcut("b", modifiers: .command)
            }
        }
    }
}

struct MacRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.phase {
            case .loading, .needsAccess:
                ProgressView()
            case .denied:
                ContentUnavailableView(
                    "No Reminders access",
                    systemImage: "lock",
                    description: Text("InboxZero is a lens over Apple Reminders. Grant full access in System Settings → Privacy & Security → Reminders.")
                )
            case .ready:
                MainWindow()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: Theme.sidebarMinWidth + Theme.mainMinWidth, minHeight: 620)
        .background(Theme.canvas)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .task { installKeyMonitors() }
        .task { HotKeyCenter.shared.onPress = { CapturePanelController.shared.toggle(model: model) } }
        .task { await Snapshotter.run(model: model, ui: ui) }
    }

    /// ⌘-held badges and "type anywhere to focus the composer" (T3 behaviour):
    /// an unmodified printable key outside any text control seeds the composer.
    private func installKeyMonitors() {
        guard !ui.monitorsInstalled else { return }
        ui.monitorsInstalled = true
        // ⌘ released while another app was frontmost never reaches this
        // monitor; re-read the live modifier state whenever we come back.
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let command = NSEvent.modifierFlags.contains(.command)
                    if ui.commandHeld != command { ui.commandHeld = command }
                }
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let isFlagsChange = event.type == .flagsChanged
            let flags = event.modifierFlags
            let characters = event.characters
            let inTextControl = NSApp.keyWindow?.firstResponder is NSTextView
            // Keys for the capture panel (or any panel) are never ours to redirect.
            if event.window is NSPanel { return event }
            let consumed = MainActor.assumeIsolated { () -> Bool in
                let command = flags.contains(.command)
                // Write only on change: every write re-renders observers.
                if ui.commandHeld != command { ui.commandHeld = command }
                guard !isFlagsChange, model.phase == .ready, !ui.paletteOpen,
                      flags.intersection([.command, .control, .option]).isEmpty,
                      let characters, characters.count == 1,
                      let scalar = characters.unicodeScalars.first,
                      !CharacterSet.controlCharacters.contains(scalar),
                      !inTextControl,
                      ui.selection != nil
                else { return false }
                ui.composerSeed = characters
                ui.composerFocusRequest += 1
                return true
            }
            return consumed ? nil : event
        }
    }
}

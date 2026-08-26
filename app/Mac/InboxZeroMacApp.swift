import AppKit
import InboxCore
import SwiftUI

@main
struct InboxZeroMacApp: App {
    @State private var model = ProcessInfo.processInfo.environment["INBOXZERO_PREVIEW"] == nil ? AppModel() : AppModel.preview()
    @State private var ui = UIState()
    @State private var shortcuts = Shortcuts.shared

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
            // Keys are dispatched by KeyBindings (context-aware) before the
            // menu sees them; the menu shows the combos and runs the same
            // commands on click.
            CommandGroup(replacing: .newItem) {
                menuItem("New Need", .action(.newNeed))
                    .disabled(model.phase != .ready)
                Button("Quick Capture") { CapturePanelController.shared.toggle(model: model) }
                    .disabled(model.phase != .ready)
            }
            CommandMenu("Go") {
                menuItem("Command Palette", .action(.palette))
                Divider()
                menuItem("Previous Need", .action(.previousNeed))
                menuItem("Next Need", .action(.nextNeed))
                Divider()
                ForEach(1...9, id: \.self) { number in
                    menuItem("Need \(number)", .jump(number))
                }
            }
            CommandGroup(before: .sidebar) {
                menuItem(ui.sidebarVisible ? "Hide Sidebar" : "Show Sidebar", .action(.toggleSidebar))
            }
        }
    }

    private func menuItem(_ title: String, _ command: KeyCommand) -> some View {
        Button(title) { ui.perform(command, model: model) }
            .keyboardShortcut(KeyBindings.binding(for: command, shortcuts).combo.keyboardShortcut)
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
        // The one reliable source for "is ⌘ down": SwiftUI's modifier-key
        // tracking. Event monitors miss flagsChanged in several focus states.
        .onModifierKeysChanged(mask: .command, initial: true) { _, new in
            let command = new.contains(.command)
            if ui.commandHeld != command { ui.commandHeld = command }
        }
        .task { HotKeyCenter.shared.onPress = { CapturePanelController.shared.toggle(model: model) } }
        .background(WindowReader { window in if ui.window !== window { ui.window = window } })
        .task { await Snapshotter.run(model: model, ui: ui) }
    }

    /// One monitor: ⌘-held badges, key bindings (context-aware, ahead of the
    /// menu bar), and "type anywhere to focus the composer" (T3 behaviour):
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
                guard !isFlagsChange, model.phase == .ready else { return false }
                if event.window === ui.window, KeyBindings.handle(event, ui: ui, model: model) { return true }
                guard !ui.paletteOpen,
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

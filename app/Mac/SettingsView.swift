import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var hotKeys = HotKeyCenter.shared
    @State private var shortcuts = Shortcuts.shared
    @State private var conflict: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Quick capture") {
                LabeledContent("Global shortcut") {
                    HStack(spacing: 8) {
                        ShortcutRecorder(combo: hotKeys.combo, placeholder: "None", onClear: { hotKeys.combo = nil }) { hotKeys.combo = $0 }
                        Button {
                            hotKeys.combo = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .help("Unbind — no global shortcut")
                        .disabled(hotKeys.combo == nil)
                    }
                }
                Text("Opens a single-field capture box over any app. Needs at least one of ⌘ ⌃ ⌥; × (or ⌫ while recording) unbinds it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("In-app shortcuts") {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        HStack(spacing: 8) {
                            ShortcutRecorder(combo: shortcuts.combo(for: action), placeholder: "Record") { combo in
                                if let other = shortcuts.owner(of: combo, besides: action) {
                                    conflict = "\(combo.display) is already \(other.title)."
                                } else {
                                    conflict = nil
                                    shortcuts.set(combo, for: action)
                                }
                            }
                            Button {
                                shortcuts.reset(action)
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .help("Reset to \(action.defaultCombo.display)")
                            .disabled(shortcuts.isDefault(action))
                        }
                    }
                }
                if let conflict {
                    Text(conflict)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Text("⌘1–⌘9 always jump to today's needs; everything else is yours to change.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text("Keep InboxZero running so the capture shortcut is always live, even with the window closed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

/// Click, press a combination, done. ⎋ cancels; ⌫ clears when `onClear` is
/// given. Only one recorder listens at a time (each installs its own monitor
/// while recording).
struct ShortcutRecorder: View {
    let combo: KeyCombo?
    let placeholder: String
    var onClear: (() -> Void)?
    let onRecord: (KeyCombo) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : (combo?.display ?? placeholder))
                .frame(minWidth: 110)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isEscape = event.keyCode == kVK_Escape
            let isDelete = event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete
            let combo = KeyCombo(event: event)
            MainActor.assumeIsolated {
                if isEscape { stop(); return }
                if isDelete, let onClear { stop(); onClear(); return }
                guard let combo else { return }
                stop()
                onRecord(combo)
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

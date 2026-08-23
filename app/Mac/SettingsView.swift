import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var hotKeys = HotKeyCenter.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Quick capture") {
                LabeledContent("Global shortcut") {
                    HStack(spacing: 8) {
                        Button {
                            recording ? stopRecording() : startRecording()
                        } label: {
                            Text(recording ? "Press keys…" : (hotKeys.combo?.display ?? "Record shortcut"))
                                .frame(minWidth: 120)
                        }
                        if hotKeys.combo != nil, !recording {
                            Button("Clear") { hotKeys.combo = nil }
                        }
                    }
                }
                Text("Opens a single-field capture box over any app. Needs at least one of ⌘ ⌃ ⌥.")
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
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isEscape = event.keyCode == 53
            let combo = KeyCombo(event: event)
            MainActor.assumeIsolated {
                if isEscape { stopRecording(); return } // Escape cancels
                guard let combo else { return }
                hotKeys.combo = combo
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

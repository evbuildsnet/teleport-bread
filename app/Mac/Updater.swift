#if DIRECT
import Observation
import Sparkle
import SwiftUI

/// Sparkle, direct-download builds only. Our launch task owns automatic
/// checks so Sparkle never schedules a periodic check or permission prompt.
/// Info.plist carries the feed URL and public key (see app/project.yml).
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController
    private let delegate = UpdaterDelegate()
    private var observation: NSKeyValueObservation?
    private var checkedAtLaunch = false
    private static let automaticChecksKey = "automaticUpdateChecks"

    private(set) var canCheck = false
    var automaticChecks: Bool {
        didSet { UserDefaults.standard.set(automaticChecks, forKey: Self.automaticChecksKey) }
    }

    private init() {
        UserDefaults.standard.register(defaults: [Self.automaticChecksKey: true])
        automaticChecks = UserDefaults.standard.bool(forKey: Self.automaticChecksKey)
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
        // Older builds may have persisted an opt-in to Sparkle's scheduler.
        controller.updater.automaticallyChecksForUpdates = false
        controller.startUpdater()
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            guard let can = change.newValue else { return }
            Task { @MainActor in self?.canCheck = can }
        }
    }

    func check() { controller.updater.checkForUpdates() }

    func checkAtLaunch() {
        guard !checkedAtLaunch else { return }
        checkedAtLaunch = true
        guard automaticChecks else { return }
        controller.updater.checkForUpdatesInBackground()
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    #if DEBUG
    /// Debug builds can point at a local appcast to rehearse an update:
    /// `TELEPORTBREAD_FEED_URL=http://127.0.0.1:8000/appcast.xml`.
    func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["TELEPORTBREAD_FEED_URL"]
    }
    #endif
}

struct CheckForUpdatesMenuItem: View {
    @State private var updater = Updater.shared

    var body: some View {
        Button("Check for Updates…") { updater.check() }
            .disabled(!updater.canCheck)
    }
}

struct UpdatesSettingsSection: View {
    @State private var updater = Updater.shared

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updater.automaticChecks)
            Text("On by default. Teleport Bread checks for updates once when the app launches. Nothing about you or your reminders is sent.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Check Now") { updater.check() }
                .disabled(!updater.canCheck)
        }
    }
}
#endif

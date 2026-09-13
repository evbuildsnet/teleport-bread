#if DIRECT
import Observation
import Sparkle
import SwiftUI

/// Sparkle, direct-download builds only. Automatic checks are on by default:
/// one right at launch, then Sparkle's own scheduler once a day. The toggle
/// in Settings is Sparkle's preference. Info.plist carries the feed URL and
/// public key (see app/project.yml).
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController
    private let delegate = UpdaterDelegate()
    private var observation: NSKeyValueObservation?
    private var checkedAtLaunch = false

    private(set) var canCheck = false
    var automaticChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticChecks }
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            guard let can = change.newValue else { return }
            Task { @MainActor in self?.canCheck = can }
        }
    }

    func check() { controller.updater.checkForUpdates() }

    /// The scheduler only fires at launch once a day has passed; this makes
    /// every launch check, so an urgent release is never a day late.
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
            Text("On by default. Teleport Bread checks for updates when it launches and once a day after that. Nothing about you or your reminders is sent.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Check Now") { updater.check() }
                .disabled(!updater.canCheck)
        }
    }
}
#endif

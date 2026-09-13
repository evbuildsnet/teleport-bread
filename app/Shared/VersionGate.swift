import Foundation
import InboxCore
import Observation
import SwiftUI

@MainActor
@Observable
final class VersionGate {
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    private(set) var requirement: VersionRequirement?
    var bannerDismissed = false
    private var checked = false

    var required: Bool { requirement?.required ?? false }
    var available: Bool { requirement?.available ?? false }

    func checkAtLaunch() async {
        // The app owns one gate, even when multiple root windows run .task.
        guard !checked else { return }
        checked = true
        var address = "https://teleportbread.com/app-version.json"
        #if DEBUG
        address = ProcessInfo.processInfo.environment["TELEPORTBREAD_VERSION_URL"] ?? address
        #endif
        guard let url = URL(string: address) else { return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 10
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { return }
            #if os(iOS)
            let platform = VersionRequirement.Platform.ios
            #else
            let platform = VersionRequirement.Platform.mac
            #endif
            requirement = VersionRequirement(data: data, platform: platform, currentVersion: currentVersion)
        } catch {
            // Offline, timeout, or bad data: keep the app usable this launch.
        }
    }
}

struct VersionLockView: View {
    @Environment(VersionGate.self) private var gate

    var body: some View {
        ContentUnavailableView {
            Label("Update to continue", systemImage: "arrow.down.app")
        } description: {
            VStack(spacing: 12) {
                Text(gate.requirement?.message ?? "This version of Teleport Bread is too old to keep your reminders safe.")
                if let requirement = gate.requirement {
                    Text("\(gate.currentVersion) → \(requirement.minimum)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 380)
        } actions: {
            VersionUpdateButton()
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                #if os(macOS)
                .tint(Theme.accent)
                #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct VersionUpdateButton: View {
    @Environment(VersionGate.self) private var gate
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Update") {
            #if DIRECT
            Updater.shared.check()
            #else
            #if os(iOS)
            let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
            #else
            let isTestFlight = false
            #endif
            if let url = gate.requirement?.updateURL(isTestFlight: isTestFlight) {
                openURL(url)
            }
            #endif
        }
    }
}

#if os(iOS)
struct VersionBanner: View {
    @Environment(VersionGate.self) private var gate

    var body: some View {
        if gate.available, !gate.bannerDismissed, let requirement = gate.requirement {
            HStack(spacing: 12) {
                Text("Version \(requirement.latest) is available")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                VersionUpdateButton()
                Button {
                    gate.bannerDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss update")
            }
            .font(.footnote)
            .padding()
            .background(.bar)
        }
    }
}
#endif

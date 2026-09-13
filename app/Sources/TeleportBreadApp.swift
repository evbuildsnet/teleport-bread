import InboxCore
import SwiftUI

@main
struct TeleportBreadApp: App {
    @State private var model = AppModel()
    @State private var gate = VersionGate()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(gate)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(VersionGate.self) private var gate
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if gate.required {
                VersionLockView()
            } else {
                content
            }
        }
        .task { await gate.checkAtLaunch() }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            // Change events don't arrive while backgrounded; catch up on return.
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading, .needsAccess:
            ProgressView()
        case .denied:
            ContentUnavailableView(
                "No Reminders access",
                systemImage: "lock",
                description: Text("Teleport Bread is a lens over Apple Reminders. Grant full access in Settings → Privacy & Security → Reminders.")
            )
        case .ready:
            InboxView()
        }
    }
}

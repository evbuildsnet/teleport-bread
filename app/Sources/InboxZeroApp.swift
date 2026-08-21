import InboxCore
import SwiftUI

@main
struct InboxZeroApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
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
                    description: Text("InboxZero is a lens over Apple Reminders. Grant full access in Settings → Privacy & Security → Reminders.")
                )
            case .ready:
                InboxView()
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            // Change events don't arrive while backgrounded; catch up on return.
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }
}

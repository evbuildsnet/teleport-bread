import InboxCore
import SwiftUI

/// Menu body shared by the iOS row context menu and the Mac context/title
/// menus: primary verb + Snooze submenu, all rendered from TriageAction so
/// every surface stays in step.
struct TriageMenuItems: View {
    let state: NeedState
    /// iOS inbox rows omit the primary verb: settling is deliberately
    /// swipe-only on mobile, to build the habit.
    var includePrimary = true
    let perform: (TriageAction) -> Void

    var body: some View {
        if includePrimary {
            let primary = TriageAction.primary(for: state)
            Button("\(primary.label) need", systemImage: primary.symbol) {
                perform(primary)
            }
        }
        Menu("Snooze") {
            ForEach(TriageAction.snoozeMenu) { action in
                if action == .snoozePickDate { Divider() }
                Button(action.label, systemImage: action.symbol) { perform(action) }
            }
        }
    }
}

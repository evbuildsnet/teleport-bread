import InboxCore
import SwiftUI

/// 52pt bar: "List / Need title" breadcrumb. Title opens the action menu;
/// the pencil beside it (or Rename… in the menu) edits the title in place.
struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let snapshot: ReminderSnapshot?

    private func editing(_ snapshot: ReminderSnapshot) -> Bool {
        ui.titleEdit == .init(id: snapshot.id, place: .topBar)
    }

    var body: some View {
        HStack(spacing: 8) {
            if !ui.sidebarVisible {
                Spacer().frame(width: 70)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { ui.sidebarVisible = true }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(SidebarIconButtonStyle())
                .tooltip("Show sidebar ⌘B", edge: .bottom)
            }
            if let snapshot {
                if editing(snapshot) {
                    TitleEditor(snapshot: snapshot, place: .topBar)
                        .frame(maxWidth: 480)
                } else {
                    Menu {
                        NeedActionMenu(snapshot: snapshot) { beginEdit(snapshot) }
                    } label: {
                        Text(snapshot.title)
                            .lineLimit(1)
                            .foregroundStyle(Theme.text)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Need actions")
                    .accessibilityIdentifier("threadTitle")
                    .accessibilityValue(snapshot.title)
                    Button {
                        beginEdit(snapshot)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(SidebarIconButtonStyle())
                    .tooltip("Edit title", edge: .bottom)
                    .accessibilityLabel("Edit title")
                }
            }
            Spacer()
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .frame(height: Theme.topBarHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private func beginEdit(_ snapshot: ReminderSnapshot) {
        ui.titleEdit = .init(id: snapshot.id, place: .topBar)
    }
}

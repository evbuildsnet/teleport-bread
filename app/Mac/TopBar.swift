import InboxCore
import SwiftUI

/// 52pt bar: "List / Need title" breadcrumb. Title opens the action menu and
/// supports inline rename (T3: title click → menu, inline rename).
struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let snapshot: ReminderSnapshot?
    @State private var renaming = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

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
                if renaming {
                    TextField("Need title", text: $renameText)
                        .textFieldStyle(.plain)
                        .focused($renameFocused)
                        .onSubmit(commitRename)
                        .onKeyPress(.escape) { renaming = false; return .handled }
                        .onChange(of: renameFocused) { _, focused in if !focused { commitRename() } }
                        .frame(maxWidth: 480)
                } else {
                    Menu {
                        NeedActionMenu(snapshot: snapshot) { beginRename(snapshot) }
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

    private func beginRename(_ snapshot: ReminderSnapshot) {
        renameText = snapshot.title
        renaming = true
        renameFocused = true
    }

    private func commitRename() {
        guard renaming, let snapshot else { return }
        renaming = false
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != snapshot.title else { return }
        Task { await model.update(snapshot, title: title, listID: snapshot.listID) }
    }
}

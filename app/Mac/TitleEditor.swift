import InboxCore
import SwiftUI

/// Inline title field shared by sidebar rows and the top bar. ⏎ or losing
/// focus saves; ⎋ discards. A failed write reopens the editor with the text
/// intact rather than silently reverting the title.
struct TitleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let snapshot: ReminderSnapshot
    let place: UIState.TitleEdit.Place
    @State private var text = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    private var edit: UIState.TitleEdit { .init(id: snapshot.id, place: place) }

    var body: some View {
        TextField("Need title", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit(commit)
            .onKeyPress(.escape) { discard(); return .handled }
            .onExitCommand(perform: discard)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onAppear {
                text = ui.titleEditRestore ?? snapshot.title
                ui.titleEditRestore = nil
            }
            .task {
                // After the first layout pass; an immediate request loses to
                // whatever field held focus before.
                try? await Task.sleep(for: .milliseconds(50))
                focused = true
            }
            .accessibilityLabel("Need title")
    }

    private func discard() {
        guard !finished else { return }
        finished = true
        close()
    }

    private func commit() {
        guard !finished else { return }
        finished = true
        close()
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != snapshot.title else { return }
        let edit = edit
        Task {
            if await !model.update(snapshot, title: title, listID: snapshot.listID), ui.titleEdit == nil {
                ui.titleEditRestore = title
                ui.titleEdit = edit
            }
        }
    }

    private func close() {
        if ui.titleEdit == edit { ui.titleEdit = nil }
    }
}

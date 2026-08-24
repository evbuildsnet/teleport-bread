import Foundation
import InboxCore
import Observation

/// Thread-composer state shared by both platforms: draft text, edit mode,
/// sanitizing, and the send/restore contract. Views own focus and layout.
@MainActor
@Observable
final class MessageComposer {
    var draft = ""
    var editingIndex: Int?

    var isEditing: Bool { editingIndex != nil }

    /// U+2063 is invisible and not in .whitespacesAndNewlines — without
    /// stripping it first, a pasted invisible-only draft would append a
    /// permanently empty message.
    var sanitizedDraft: String {
        draft
            .replacingOccurrences(of: String(NoteCodec.invisibleSeparator), with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func beginEditing(_ index: Int, _ message: String) {
        editingIndex = index
        draft = message
    }

    func cancelEditing() {
        editingIndex = nil
        draft = ""
    }

    /// Append, or save the message being edited. On a failed write the text
    /// is handed back to the (still idle) composer so it is never silently
    /// lost.
    func send(to snapshot: ReminderSnapshot, via model: AppModel) {
        let message = sanitizedDraft
        guard !message.isEmpty else { return }
        if let index = editingIndex {
            editingIndex = nil
            draft = ""
            Task {
                if await !model.replaceMessage(at: index, with: message, in: snapshot),
                   draft.isEmpty, editingIndex == nil {
                    beginEditing(index, message)
                }
            }
            return
        }
        draft = ""
        Task {
            if await !model.append(message, to: snapshot), draft.isEmpty {
                draft = message
            }
        }
    }
}

import Foundation

/// A reminder note is an append-only log of messages. Messages are separated
/// by a blank line carrying U+2063 (INVISIBLE SEPARATOR), which renders as an
/// ordinary paragraph break in the native Reminders app.
public enum NoteCodec {
    public static let invisibleSeparator: Character = "\u{2063}"
    public static let separator = "\n\u{2063}\n"

    /// Lenient parse: a note without markers is a single message. Text is
    /// never repaired, dropped, or rewritten.
    public static func parse(_ note: String?) -> [String] {
        guard let note, !note.isEmpty else { return [] }
        return note.components(separatedBy: separator)
    }

    /// Rebuilds a note from messages (used when the user explicitly edits or
    /// deletes a message). Empty result → nil note.
    public static func join(_ messages: [String]) -> String? {
        let clean = messages.map { $0.replacingOccurrences(of: String(invisibleSeparator), with: "") }
        guard !clean.isEmpty else { return nil }
        return clean.joined(separator: separator)
    }

    /// Appends a message to the log. U+2063 is stripped from the new message
    /// so pasted input can never forge a message boundary; the character is
    /// invisible, so stripping it does not alter what the user sees.
    public static func append(_ message: String, to note: String?) -> String {
        let clean = message.replacingOccurrences(of: String(invisibleSeparator), with: "")
        guard let note, !note.isEmpty else { return clean }
        return note + separator + clean
    }
}

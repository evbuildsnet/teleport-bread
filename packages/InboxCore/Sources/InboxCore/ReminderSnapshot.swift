import Foundation

/// Value-type view of an EKReminder. The UI renders these; live EventKit
/// objects are only touched at write time, on the main actor.
public struct ReminderSnapshot: Identifiable, Hashable, Sendable {
    public let id: String
    public let listID: String
    public let listTitle: String
    public let listColorHex: String?
    public let title: String
    /// Normalized to start of day; nil means the reminder is undated and is
    /// excluded from the app by design.
    public let dueDate: Date?
    public let isCompleted: Bool
    public let completionDate: Date?
    public let creationDate: Date?
    public let note: String?

    public init(
        id: String,
        listID: String,
        listTitle: String,
        listColorHex: String? = nil,
        title: String,
        dueDate: Date?,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        creationDate: Date? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.listID = listID
        self.listTitle = listTitle
        self.listColorHex = listColorHex
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.creationDate = creationDate
        self.note = note
    }

    public var messages: [String] { NoteCodec.parse(note) }
}

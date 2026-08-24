import Foundation

/// Platform-free description of a reminder list for the UI. A source without
/// native lists exposes one synthetic list rather than a capability flag.
public struct ListOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let colorHex: String?

    public init(id: String, title: String, colorHex: String? = nil) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
    }
}

public enum NeedSourceError: Error {
    case notFound
    case noDefaultList
}

/// A place needs come from. One instance per backend; the app drives exactly
/// one. All members are main-actor: EventKit demands it, and it spares every
/// conformer Sendable gymnastics — a network-backed source hops off-main
/// internally.
///
/// List IDs are source-local strings; the source resolves them internally.
/// Writes are `async throws` even where the backend is synchronous, so a
/// future network source doesn't force a breaking protocol change.
@MainActor
public protocol NeedSource: AnyObject {

    // MARK: Authorization

    /// True when access is already granted — the app skips the prompt phase.
    var isAuthorized: Bool { get }
    /// Prompts (TCC dialog, OAuth flow, …). An in-memory source returns true.
    func requestAccess() async -> Bool

    // MARK: Change signaling

    /// Yields whenever the backing store changed underneath us; the app
    /// re-fetches. Day rollover stays an app concern, not a source concern.
    /// Each access returns an independent stream.
    var changes: AsyncStream<Void> { get }

    // MARK: Lists

    var lists: [ListOption] { get }
    var defaultListID: String? { get }

    // MARK: Reads

    /// `nil` list filter means all lists.
    func fetchIncomplete(inLists listIDs: Set<String>?) async -> [ReminderSnapshot]
    func fetchCompleted(after date: Date, inLists listIDs: Set<String>?) async -> [ReminderSnapshot]

    // MARK: Writes

    func settle(id: String) async throws
    /// Snoozing (or waking) always yields an active need on the given day.
    func snooze(id: String, to date: Date) async throws
    func unsettle(id: String) async throws
    func update(id: String, title: String, listID: String?) async throws
    func setNote(id: String, note: String?) async throws
    func appendMessage(id: String, message: String) async throws
    /// Capture always sets a due date — undated needs are invisible by design.
    /// `nil` list falls back to the source's default list.
    @discardableResult
    func create(title: String, note: String?, due: Date, inList listID: String?) async throws -> ReminderSnapshot
}

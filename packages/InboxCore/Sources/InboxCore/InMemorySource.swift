import Foundation

/// In-memory NeedSource. Previews, canvases, and tests run through the same
/// mutation logic users hit — one code path, no preview drift, no EventKit.
@MainActor
public final class InMemorySource: NeedSource {
    public private(set) var lists: [ListOption]
    private var items: [ReminderSnapshot]
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(seed items: [ReminderSnapshot] = [], lists: [ListOption] = []) {
        self.items = items
        self.lists = lists
    }

    // MARK: Authorization

    public var isAuthorized: Bool { true }
    public func requestAccess() async -> Bool { true }

    // MARK: Change signaling

    public var changes: AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.continuations[id] = nil }
            }
        }
    }

    private func notify() {
        for continuation in continuations.values { continuation.yield() }
    }

    // MARK: Lists

    public var defaultListID: String? { lists.first?.id }

    // MARK: Reads

    public func fetchIncomplete(inLists listIDs: Set<String>?) async -> [ReminderSnapshot] {
        items.filter { !$0.isCompleted && included($0, in: listIDs) }
    }

    public func fetchCompleted(after date: Date, inLists listIDs: Set<String>?) async -> [ReminderSnapshot] {
        items.filter {
            $0.isCompleted && ($0.completionDate ?? .distantPast) >= date && included($0, in: listIDs)
        }
    }

    private func included(_ snapshot: ReminderSnapshot, in listIDs: Set<String>?) -> Bool {
        listIDs.map { $0.contains(snapshot.listID) } ?? true
    }

    // MARK: Writes

    public func settle(id: String) async throws {
        try mutate(id) { $0.with(isCompleted: true, completionDate: .now) }
    }

    public func snooze(id: String, to date: Date) async throws {
        let day = Calendar.current.startOfDay(for: date)
        try mutate(id) { $0.with(dueDate: day, isCompleted: false, completionDate: .some(nil)) }
    }

    public func unsettle(id: String) async throws {
        try mutate(id) { $0.with(isCompleted: false, completionDate: .some(nil)) }
    }

    public func update(id: String, title: String, listID: String?) async throws {
        let list = listID.flatMap { target in lists.first { $0.id == target } }
        try mutate(id) { $0.with(listID: list?.id, listTitle: list?.title, title: title) }
    }

    public func setNote(id: String, note: String?) async throws {
        try mutate(id) { $0.with(note: .some(note)) }
    }

    public func appendMessage(id: String, message: String) async throws {
        try mutate(id) { $0.with(note: NoteCodec.append(message, to: $0.note)) }
    }

    @discardableResult
    public func create(
        title: String, note: String?, due: Date, inList listID: String?
    ) async throws -> ReminderSnapshot {
        let target = listID.flatMap { id in lists.first { $0.id == id } }
        guard let list = target ?? lists.first else { throw NeedSourceError.noDefaultList }
        let snapshot = ReminderSnapshot(
            id: UUID().uuidString,
            listID: list.id,
            listTitle: list.title,
            listColorHex: list.colorHex,
            title: title,
            dueDate: Calendar.current.startOfDay(for: due),
            creationDate: .now,
            note: note
        )
        items.append(snapshot)
        notify()
        return snapshot
    }

    private func mutate(_ id: String, _ transform: (ReminderSnapshot) -> ReminderSnapshot) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw NeedSourceError.notFound
        }
        items[index] = transform(items[index])
        notify()
    }
}

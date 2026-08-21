import EventKit
import Foundation

/// Thin wrapper around EKEventStore. All access stays on the main actor;
/// the UI works with `ReminderSnapshot` values, and live EKReminder objects
/// are re-fetched fresh immediately before every write.
@MainActor
public final class ReminderStore {
    public let store = EKEventStore()

    public init() {}

    // MARK: Access

    public func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    public var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    // MARK: Lists

    public var lists: [EKCalendar] {
        store.calendars(for: .reminder)
    }

    public func list(withIdentifier id: String) -> EKCalendar? {
        store.calendar(withIdentifier: id)
    }

    // MARK: Fetching

    public func fetchIncomplete(in calendars: [EKCalendar]? = nil) async -> [ReminderSnapshot] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: calendars
        )
        return await fetchSnapshots(matching: predicate)
    }

    public func fetchCompleted(
        completedAfter: Date,
        in calendars: [EKCalendar]? = nil
    ) async -> [ReminderSnapshot] {
        let predicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: completedAfter, ending: nil, calendars: calendars
        )
        return await fetchSnapshots(matching: predicate)
    }

    private func fetchSnapshots(matching predicate: NSPredicate) async -> [ReminderSnapshot] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let snapshots = (reminders ?? []).map(Self.snapshot(of:))
                continuation.resume(returning: snapshots)
            }
        }
    }

    // MARK: Writing (always against a freshly fetched reminder)

    public func settle(id: String) throws {
        guard let reminder = liveReminder(id) else { throw ReminderStoreError.notFound }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    public func snooze(id: String, to date: Date) throws {
        guard let reminder = liveReminder(id) else { throw ReminderStoreError.notFound }
        reminder.dueDateComponents = Self.dateOnlyComponents(from: date)
        try store.save(reminder, commit: true)
    }

    public func appendMessage(id: String, message: String) throws {
        guard let reminder = liveReminder(id) else { throw ReminderStoreError.notFound }
        reminder.notes = NoteCodec.append(message, to: reminder.notes)
        try store.save(reminder, commit: true)
    }

    /// Capture always sets a due date (today by default) — undated reminders
    /// are invisible in this app by design.
    @discardableResult
    public func createReminder(
        title: String,
        note: String? = nil,
        due: Date = .now,
        in calendar: EKCalendar? = nil
    ) throws -> ReminderSnapshot {
        guard let target = calendar ?? store.defaultCalendarForNewReminders() else {
            throw ReminderStoreError.noDefaultList
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = target
        reminder.title = title
        reminder.notes = note
        reminder.dueDateComponents = Self.dateOnlyComponents(from: due)
        try store.save(reminder, commit: true)
        return Self.snapshot(of: reminder)
    }

    private func liveReminder(_ id: String) -> EKReminder? {
        store.calendarItem(withIdentifier: id) as? EKReminder
    }

    // MARK: Mapping

    nonisolated static func snapshot(of reminder: EKReminder) -> ReminderSnapshot {
        ReminderSnapshot(
            id: reminder.calendarItemIdentifier,
            listID: reminder.calendar?.calendarIdentifier ?? "",
            listTitle: reminder.calendar?.title ?? "",
            listColorHex: reminder.calendar.flatMap(Self.hexColor(of:)),
            title: reminder.title ?? "",
            dueDate: reminder.dueDateComponents.flatMap { components in
                var calendar = components.calendar ?? .current
                calendar.timeZone = components.timeZone ?? calendar.timeZone
                return calendar.date(from: components).map(calendar.startOfDay(for:))
            },
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            creationDate: reminder.creationDate,
            note: reminder.notes
        )
    }

    nonisolated static func dateOnlyComponents(from date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: date)
    }

    nonisolated private static func hexColor(of calendar: EKCalendar) -> String? {
        guard let cgColor = calendar.cgColor,
              let components = cgColor.components, components.count >= 3
        else { return nil }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

public enum ReminderStoreError: Error {
    case notFound
    case noDefaultList
}

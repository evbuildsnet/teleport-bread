import EventKit
import Foundation

/// Apple Reminders as a NeedSource. Thin wrapper around EKEventStore; the UI
/// works with `ReminderSnapshot` values, and live EKReminder objects are
/// re-fetched fresh immediately before every write.
@MainActor
public final class EventKitSource: NeedSource {
    private let store = EKEventStore()

    public init() {}

    // MARK: Authorization

    public var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    public func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        #if targetEnvironment(simulator)
        if granted { seedSampleDataIfNeeded() }
        #endif
        return granted
    }

    // MARK: Change signaling

    public var changes: AsyncStream<Void> {
        AsyncStream { continuation in
            // Token removal is thread-safe; the token itself never crosses
            // isolation in any other way.
            nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: .main
            ) { _ in continuation.yield() }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    // MARK: Lists

    public var lists: [ListOption] {
        store.calendars(for: .reminder).map {
            ListOption(id: $0.calendarIdentifier, title: $0.title, colorHex: Self.hexColor(of: $0))
        }
    }

    public var defaultListID: String? {
        store.defaultCalendarForNewReminders()?.calendarIdentifier
    }

    /// Unknown or stale IDs (a deleted list) fall back to all lists rather
    /// than an empty predicate.
    private func calendars(for listIDs: Set<String>?) -> [EKCalendar]? {
        guard let listIDs else { return nil }
        let matched = store.calendars(for: .reminder).filter { listIDs.contains($0.calendarIdentifier) }
        return matched.isEmpty ? nil : matched
    }

    // MARK: Fetching

    public func fetchIncomplete(inLists listIDs: Set<String>?) async -> [ReminderSnapshot] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: calendars(for: listIDs)
        )
        return await fetchSnapshots(matching: predicate)
    }

    public func fetchCompleted(after date: Date, inLists listIDs: Set<String>?) async -> [ReminderSnapshot] {
        let predicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: date, ending: nil, calendars: calendars(for: listIDs)
        )
        return await fetchSnapshots(matching: predicate)
    }

    private func fetchSnapshots(matching predicate: NSPredicate) async -> [ReminderSnapshot] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                // EKReminder isn't thread-safe; hand the batch to the main
                // thread and read it there.
                let fetched = reminders ?? []
                DispatchQueue.main.async {
                    continuation.resume(returning: fetched.map(Self.snapshot(of:)))
                }
            }
        }
    }

    // MARK: Writing (always against a freshly fetched reminder)

    public func settle(id: String) async throws {
        guard let reminder = liveReminder(id) else { throw NeedSourceError.notFound }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    /// Snoozing (or waking) always yields an active need on the given day.
    public func snooze(id: String, to date: Date) async throws {
        guard let reminder = liveReminder(id) else { throw NeedSourceError.notFound }
        reminder.isCompleted = false
        reminder.dueDateComponents = Self.dateOnlyComponents(from: date)
        // A stale absolute alarm would still fire at the old due time,
        // contradicting the snooze. Alarms belong to the due date.
        reminder.alarms?.forEach(reminder.removeAlarm)
        try store.save(reminder, commit: true)
    }

    public func unsettle(id: String) async throws {
        guard let reminder = liveReminder(id) else { throw NeedSourceError.notFound }
        reminder.isCompleted = false
        try store.save(reminder, commit: true)
    }

    public func update(id: String, title: String, listID: String?) async throws {
        guard let reminder = liveReminder(id) else { throw NeedSourceError.notFound }
        reminder.title = title
        if let listID, let list = store.calendar(withIdentifier: listID), list != reminder.calendar {
            reminder.calendar = list
        }
        try store.save(reminder, commit: true)
    }

    public func setNote(id: String, note: String?) async throws {
        guard let reminder = liveReminder(id) else { throw NeedSourceError.notFound }
        reminder.notes = note
        try store.save(reminder, commit: true)
    }

    public func appendMessage(id: String, message: String) async throws {
        guard let reminder = liveReminder(id) else { throw NeedSourceError.notFound }
        reminder.notes = NoteCodec.append(message, to: reminder.notes)
        try store.save(reminder, commit: true)
    }

    /// Capture always sets a due date (today by default) — undated reminders
    /// are invisible in this app by design.
    @discardableResult
    public func create(
        title: String, note: String?, due: Date, inList listID: String?
    ) async throws -> ReminderSnapshot {
        let calendar = listID.flatMap { store.calendar(withIdentifier: $0) }
        guard let target = calendar ?? store.defaultCalendarForNewReminders() else {
            throw NeedSourceError.noDefaultList
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
            dueDate: reminder.dueDateComponents.flatMap(Self.localDueDate(from:)),
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            creationDate: reminder.creationDate,
            note: reminder.notes
        )
    }

    /// EventKit expects Gregorian due-date components; deriving them from a
    /// non-Gregorian Calendar.current (e.g. Buddhist) would write a due date
    /// centuries off.
    nonisolated public static func dateOnlyComponents(from date: Date) -> DateComponents {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        var components = gregorian.dateComponents([.year, .month, .day], from: date)
        components.calendar = gregorian
        return components
    }

    /// Takes the stored calendar day at face value (date-only semantics) and
    /// anchors it to the local calendar. Flooring an absolute Date in the
    /// components' own time zone and re-flooring locally would shift the day.
    nonisolated static func localDueDate(from components: DateComponents) -> Date? {
        guard let year = components.year, let month = components.month, let day = components.day
        else { return nil }
        var calendar = components.calendar ?? Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        // Noon dodges DST days where local midnight doesn't exist.
        let noon = DateComponents(year: year, month: month, day: day, hour: 12)
        return calendar.date(from: noon).map(Calendar.current.startOfDay(for:))
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

// MARK: - Simulator seed data

#if targetEnvironment(simulator)
extension EventKitSource {
    /// First-launch sample data so the simulator isn't an empty screen.
    /// Touches EKReminder directly because one sample is deliberately
    /// undated, which the neutral `create` can't express.
    func seedSampleDataIfNeeded() {
        let seededKey = "didSeedSimulatorData"
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        UserDefaults.standard.set(true, forKey: seededKey)

        guard let list = store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first else { return }
        let today = Date.now
        let calendar = Calendar.current
        let day: (Int) -> Date = { calendar.date(byAdding: .day, value: $0, to: today)! }

        let samples: [(String, Date?, String?)] = [
            ("Reply to Alisher about admin roles", day(-2),
             NoteCodec.append("He pinged again on Slack.", to: NoteCodec.append("Waiting on the role matrix.", to: nil))),
            ("Update CV after Macy's", day(-1), nil),
            ("Review meal location association order", today, "Check the sort order regression first."),
            ("Book dentist", today, nil),
            ("Prepare tab extension for team", day(2), nil),
            ("Renew passport", day(6), NoteCodec.append("Photos are already done.", to: nil)),
            ("Someday: learn to sail", nil, nil),
        ]
        for (title, due, note) in samples {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = title
            reminder.notes = note
            if let due {
                reminder.dueDateComponents = Self.dateOnlyComponents(from: due)
            }
            try? store.save(reminder, commit: false)
        }
        let settled = EKReminder(eventStore: store)
        settled.calendar = list
        settled.title = "Assess Microsoft Keycloak login"
        settled.dueDateComponents = Self.dateOnlyComponents(from: day(-1))
        settled.isCompleted = true
        try? store.save(settled, commit: false)
        try? store.commit()
    }
}
#endif

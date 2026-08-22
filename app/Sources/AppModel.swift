import EventKit
import Foundation
import InboxCore
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase { case loading, needsAccess, denied, ready }

    private let store = ReminderStore()
    private let engine = InboxEngine()

    var phase: Phase = .loading
    var inbox: [ReminderSnapshot] = []
    var snoozed: [ReminderSnapshot] = []
    var settled: [ReminderSnapshot] = []
    var searchText = ""
    /// Bumped on every successful triage action; drives haptic feedback.
    private(set) var triageCount = 0

    /// nil = all lists. Persisted per device.
    var selectedListIDs: Set<String>? {
        didSet { persistSelection() }
    }

    var lists: [EKCalendar] { store.lists }

    private var observers: [any NSObjectProtocol] = []
    private var started = false

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        switch store.authorizationStatus {
        case .fullAccess:
            phase = .ready
        default:
            phase = .needsAccess
            let granted = (try? await store.requestAccess()) ?? false
            phase = granted ? .ready : .denied
        }
        guard phase == .ready else { return }

        restoreSelection()
        await seedSimulatorDataIfNeeded()
        await refresh()

        // Refresh on store changes and on day rollover (an item due "Today"
        // becomes overdue at midnight without any store change).
        for name in [Notification.Name.EKEventStoreChanged, .NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            })
        }
    }

    // MARK: Data

    func refresh() async {
        guard phase == .ready else { return }
        let calendars = selectedCalendars()
        let sections = engine.sections(from: await store.fetchIncomplete(in: calendars), today: .now)
        inbox = sections.inbox
        snoozed = sections.snoozed

        let recent = Calendar.current.date(byAdding: .day, value: -14, to: .now)!
        settled = await store.fetchCompleted(completedAfter: recent, in: calendars)
            .filter { $0.dueDate != nil }
            .sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
    }

    private func selectedCalendars() -> [EKCalendar]? {
        guard let selectedListIDs else { return nil }
        let calendars = lists.filter { selectedListIDs.contains($0.calendarIdentifier) }
        return calendars.isEmpty ? nil : calendars
    }

    func matchesSearch(_ snapshot: ReminderSnapshot) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return snapshot.title.localizedCaseInsensitiveContains(query)
            || (snapshot.note?.localizedCaseInsensitiveContains(query) ?? false)
    }

    func snapshot(id: String) -> ReminderSnapshot? {
        inbox.first { $0.id == id }
            ?? snoozed.first { $0.id == id }
            ?? settled.first { $0.id == id }
    }

    // MARK: Actions

    func settle(_ snapshot: ReminderSnapshot) async {
        guard (try? store.settle(id: snapshot.id)) != nil else { return }
        triageCount += 1
        await refresh()
    }

    func snooze(_ snapshot: ReminderSnapshot, _ preset: SnoozePreset) async {
        guard (try? store.snooze(id: snapshot.id, to: engine.snoozeDate(preset, from: .now))) != nil else { return }
        triageCount += 1
        await refresh()
    }

    /// Returns false when the write failed so the UI can hand the text back —
    /// a user's message must never be silently lost.
    func append(_ message: String, to snapshot: ReminderSnapshot) async -> Bool {
        do {
            try store.appendMessage(id: snapshot.id, message: message)
        } catch {
            return false
        }
        await refresh()
        return true
    }

    func capture(title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Capture into a list the active filter can actually show.
        let target = selectedCalendars()?.first
        try? store.createReminder(title: trimmed, due: .now, in: target)
        await refresh()
    }

    // MARK: List selection persistence

    private static let selectionKey = "selectedListIDs"

    private func persistSelection() {
        if let selectedListIDs {
            UserDefaults.standard.set(Array(selectedListIDs), forKey: Self.selectionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectionKey)
        }
    }

    private func restoreSelection() {
        guard let stored = UserDefaults.standard.stringArray(forKey: Self.selectionKey) else { return }
        selectedListIDs = Set(stored)
    }

    // MARK: Simulator seed data

    private func seedSimulatorDataIfNeeded() async {
        #if targetEnvironment(simulator)
        let seededKey = "didSeedSimulatorData"
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        UserDefaults.standard.set(true, forKey: seededKey)

        guard let list = store.store.defaultCalendarForNewReminders() ?? lists.first else { return }
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
            let reminder = EKReminder(eventStore: store.store)
            reminder.calendar = list
            reminder.title = title
            reminder.notes = note
            if let due {
                reminder.dueDateComponents = ReminderStore.dateOnlyComponents(from: due)
            }
            try? store.store.save(reminder, commit: false)
        }
        let settled = EKReminder(eventStore: store.store)
        settled.calendar = list
        settled.title = "Assess Microsoft Keycloak login"
        settled.dueDateComponents = ReminderStore.dateOnlyComponents(from: day(-1))
        settled.isCompleted = true
        try? store.store.save(settled, commit: false)
        try? store.store.commit()
        #endif
    }
}

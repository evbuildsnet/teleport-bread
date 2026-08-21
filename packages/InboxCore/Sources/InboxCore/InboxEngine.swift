import Foundation

public enum SnoozePreset: String, CaseIterable, Sendable {
    case tomorrow
    case weekend
    case nextWeek

    public var label: String {
        switch self {
        case .tomorrow: "Tomorrow"
        case .weekend: "Weekend"
        case .nextWeek: "Next week"
        }
    }
}

/// Pure date math and classification. Undated reminders never enter the app.
public struct InboxEngine: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public struct Sections: Sendable {
        public var inbox: [ReminderSnapshot] = []
        public var snoozed: [ReminderSnapshot] = []
    }

    /// Inbox = due today or overdue. Snoozed = any future due date.
    /// Undated and completed reminders are dropped.
    public func sections(from snapshots: [ReminderSnapshot], today: Date) -> Sections {
        let startOfToday = calendar.startOfDay(for: today)
        var result = Sections()
        for snapshot in snapshots {
            guard !snapshot.isCompleted, let due = snapshot.dueDate else { continue }
            if calendar.startOfDay(for: due) > startOfToday {
                result.snoozed.append(snapshot)
            } else {
                result.inbox.append(snapshot)
            }
        }
        result.inbox.sort(by: dueThenCreation)
        result.snoozed.sort(by: dueThenCreation)
        return result
    }

    private func dueThenCreation(_ a: ReminderSnapshot, _ b: ReminderSnapshot) -> Bool {
        let dueA = a.dueDate ?? .distantFuture
        let dueB = b.dueDate ?? .distantFuture
        if dueA != dueB { return dueA < dueB }
        let createdA = a.creationDate ?? .distantPast
        let createdB = b.creationDate ?? .distantPast
        if createdA != createdB { return createdA < createdB }
        return a.id < b.id
    }

    /// Snooze targets are date-only and always strictly after today:
    /// tomorrow, the upcoming Saturday, or the upcoming Monday. On a Saturday,
    /// "weekend" means the following Saturday; likewise Monday for "next week".
    public func snoozeDate(_ preset: SnoozePreset, from today: Date) -> Date {
        let start = calendar.startOfDay(for: today)
        switch preset {
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: start)!
        case .weekend:
            return next(weekday: 7, strictlyAfter: start)
        case .nextWeek:
            return next(weekday: 2, strictlyAfter: start)
        }
    }

    private func next(weekday: Int, strictlyAfter day: Date) -> Date {
        var components = DateComponents()
        components.weekday = weekday
        return calendar.nextDate(
            after: day,
            matching: components,
            matchingPolicy: .nextTime,
            direction: .forward
        )!
    }
}

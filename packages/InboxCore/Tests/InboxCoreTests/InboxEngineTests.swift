import Foundation
import Testing
@testable import InboxCore

@Suite struct InboxEngineTests {
    let engine: InboxEngine
    let calendar: Calendar

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        self.calendar = calendar
        self.engine = InboxEngine(calendar: calendar)
    }

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func snapshot(_ id: String, due: Date?, completed: Bool = false, created: Date? = nil) -> ReminderSnapshot {
        ReminderSnapshot(
            id: id, listID: "L", listTitle: "List", title: id,
            dueDate: due, isCompleted: completed, creationDate: created
        )
    }

    // 2026-08-21 is a Friday.
    var friday: Date { date(2026, 8, 21) }

    @Test func classificationSplitsByDay() {
        let sections = engine.sections(from: [
            snapshot("overdue", due: date(2026, 8, 19)),
            snapshot("today", due: friday),
            snapshot("todayLateFetch", due: friday, created: date(2026, 8, 20)),
            snapshot("future", due: date(2026, 8, 25)),
            snapshot("undated", due: nil),
            snapshot("done", due: friday, completed: true),
        ], today: date(2026, 8, 21, hour: 17))

        // Newest-created first; items without a creation date sink to the bottom.
        #expect(sections.inbox.map(\.id) == ["todayLateFetch", "overdue", "today"])
        #expect(sections.snoozed.map(\.id) == ["future"])
    }

    @Test func undatedIsAlwaysExcluded() {
        let sections = engine.sections(
            from: [snapshot("undated", due: nil)],
            today: friday
        )
        #expect(sections.inbox.isEmpty)
        #expect(sections.snoozed.isEmpty)
    }

    @Test func inboxSortsNewestCreatedFirst() {
        let sections = engine.sections(from: [
            snapshot("b", due: friday, created: date(2026, 8, 20)),
            snapshot("a", due: friday, created: date(2026, 8, 18)),
            snapshot("oldDueNewest", due: date(2026, 8, 10), created: date(2026, 8, 21)),
        ], today: friday)
        #expect(sections.inbox.map(\.id) == ["oldDueNewest", "b", "a"])
    }

    @Test func snoozedSortsBySoonestDueThenNewest() {
        let sections = engine.sections(from: [
            snapshot("later", due: date(2026, 8, 30), created: date(2026, 8, 21)),
            snapshot("soonOld", due: date(2026, 8, 25), created: date(2026, 8, 18)),
            snapshot("soonNew", due: date(2026, 8, 25), created: date(2026, 8, 20)),
        ], today: friday)
        #expect(sections.snoozed.map(\.id) == ["soonNew", "soonOld", "later"])
    }

    @Test func snoozeTomorrow() {
        #expect(engine.snoozeDate(.tomorrow, from: date(2026, 8, 21, hour: 23)) == date(2026, 8, 22))
    }

    @Test func snoozeWeekendFromFridayIsNextDay() {
        #expect(engine.snoozeDate(.weekend, from: friday) == date(2026, 8, 22))
    }

    @Test func snoozeWeekendFromSaturdaySkipsAWeek() {
        #expect(engine.snoozeDate(.weekend, from: date(2026, 8, 22)) == date(2026, 8, 29))
    }

    @Test func snoozeNextWeekIsUpcomingMonday() {
        #expect(engine.snoozeDate(.nextWeek, from: friday) == date(2026, 8, 24))
    }

    @Test func snoozeNextWeekFromMondaySkipsAWeek() {
        #expect(engine.snoozeDate(.nextWeek, from: date(2026, 8, 24)) == date(2026, 8, 31))
    }

    @Test func snoozeIsAlwaysStrictlyInTheFuture() {
        let today = date(2026, 8, 21, hour: 23)
        for preset in SnoozePreset.allCases {
            #expect(engine.snoozeDate(preset, from: today) > calendar.startOfDay(for: today))
        }
    }
}

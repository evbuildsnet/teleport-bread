import Foundation
import Testing
@testable import InboxCore

@Suite struct DateMappingTests {
    @Test func dateOnlyComponentsAreAlwaysGregorian() {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let date = gregorian.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 15))!

        let components = ReminderStore.dateOnlyComponents(from: date)
        #expect(components.calendar?.identifier == .gregorian)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 21)
        #expect(components.hour == nil)
    }

    @Test func localDueDateTakesStoredDayAtFaceValue() {
        // A timed reminder stored with a Tokyo calendar: the visible calendar
        // day must not shift when the components are re-floored locally.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var components = DateComponents(year: 2026, month: 8, day: 21, hour: 23)
        components.calendar = tokyo
        components.timeZone = tokyo.timeZone

        let due = ReminderStore.localDueDate(from: components)
        let local = Calendar.current.dateComponents([.year, .month, .day], from: due!)
        #expect(local.year == 2026)
        #expect(local.month == 8)
        #expect(local.day == 21)
        #expect(due == Calendar.current.startOfDay(for: due!))
    }

    @Test func localDueDateWithoutCalendarDefaultsToGregorian() {
        let due = ReminderStore.localDueDate(
            from: DateComponents(year: 2026, month: 12, day: 31)
        )
        let local = Calendar.current.dateComponents([.year, .month, .day], from: due!)
        #expect(local.year == 2026)
        #expect(local.month == 12)
        #expect(local.day == 31)
    }

    @Test func localDueDateWithMissingDayIsNil() {
        #expect(ReminderStore.localDueDate(from: DateComponents(year: 2026)) == nil)
    }
}

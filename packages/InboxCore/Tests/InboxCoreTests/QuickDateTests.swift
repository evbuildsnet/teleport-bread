import Foundation
import Testing
@testable import InboxCore

@Suite struct QuickDateTests {
    // Wednesday 26 Aug 2026, en_US, UTC — everything below is relative to it.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private var today: Date { day(2026, 8, 26) }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func parse(_ text: String) -> Date? {
        QuickDate.parse(text, today: today, calendar: calendar)
    }

    @Test(arguments: [
        ("tomorrow", (2026, 8, 27)), ("tom", (2026, 8, 27)), ("today", (2026, 8, 26)),
        ("3d", (2026, 8, 29)), ("2w", (2026, 9, 9)), ("1m", (2026, 9, 26)), ("2 weeks", (2026, 9, 9)),
        ("next week", (2026, 9, 2)), ("next month", (2026, 9, 26)),
        ("fri", (2026, 8, 28)), ("Friday", (2026, 8, 28)), ("next fri", (2026, 8, 28)),
        ("14", (2026, 9, 14)), ("30", (2026, 8, 30)),
        ("sep 14", (2026, 9, 14)), ("14 sep", (2026, 9, 14)), ("september 14", (2026, 9, 14)),
        ("9/14", (2026, 9, 14)), ("14/9", (2026, 9, 14)), ("14.9", (2026, 9, 14)),
        ("2026-12-25", (2026, 12, 25)),
    ])
    func resolves(_ text: String, expected: (Int, Int, Int)) {
        #expect(parse(text) == day(expected.0, expected.1, expected.2))
    }

    @Test func sameWeekdayMeansNextWeek() {
        #expect(parse("wed") == day(2026, 9, 2))
    }

    @Test func todaysDayNumberMeansNextMonth() {
        #expect(parse("26") == day(2026, 9, 26))
    }

    @Test func monthDayAlreadyPassedRollsToNextYear() {
        #expect(parse("aug 1") == day(2027, 8, 1))
    }

    @Test(arguments: ["", "  ", "t", "xyz", "2020-01-01", "0", "32", "feb 30"])
    func rejects(_ text: String) {
        #expect(parse(text) == nil)
    }
}

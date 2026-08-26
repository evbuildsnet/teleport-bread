import Foundation

/// Turns a short typed token into a day — the keyboard half of the snooze
/// calendar. Accepts: `today` / `tomorrow`, a weekday by prefix (`fri`,
/// `mon`), `3d` / `2w` / `1m`, a bare day of month (`14`), month + day
/// (`sep 14`, `14 sep`), `14/9` (order per locale), `next week/month`, and
/// ISO `2026-09-14`. Never yields a day before today; nil = no idea yet.
public enum QuickDate {
    public static func parse(_ input: String, today: Date, calendar: Calendar = .current) -> Date? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        let day = calendar.startOfDay(for: today)
        func future(_ date: Date?) -> Date? {
            guard let date else { return nil }
            let start = calendar.startOfDay(for: date)
            return start >= day ? start : nil
        }
        func add(_ component: Calendar.Component, _ value: Int) -> Date? {
            future(calendar.date(byAdding: component, value: value, to: day))
        }

        switch text {
        case "today", "tod": return day
        case "tomorrow", "tom", "tmr", "tmrw": return add(.day, 1)
        case "next week": return add(.day, 7)
        case "next month": return add(.month, 1)
        default: break
        }

        if let match = text.wholeMatch(of: /(\d+)\s*(d|days?|w|weeks?|m|months?)/) {
            let count = Int(match.1)!
            switch match.2.first! {
            case "d": return add(.day, count)
            case "w": return add(.day, count * 7)
            default: return add(.month, count)
            }
        }

        if let match = text.wholeMatch(of: /(\d{4})-(\d{1,2})-(\d{1,2})/) {
            return future(calendar.date(from: DateComponents(year: Int(match.1), month: Int(match.2), day: Int(match.3))))
        }

        var words = text.split(separator: " ").map(String.init)
        if words.first == "next" { words.removeFirst() }

        if words.count == 1, let word = words.first {
            if let dayOfMonth = Int(word), (1...31).contains(dayOfMonth) {
                return calendar.nextDate(after: day, matching: DateComponents(day: dayOfMonth), matchingPolicy: .strict)
            }
            if word.count >= 2, let weekday = index(of: word, in: calendar.weekdaySymbols) {
                var delta = (weekday + 1 - calendar.component(.weekday, from: day) + 7) % 7
                if delta == 0 { delta = 7 } // "fri" on a Friday means next Friday
                return add(.day, delta)
            }
            if let match = word.wholeMatch(of: /(\d{1,2})[.\/-](\d{1,2})/) {
                let (a, b) = (Int(match.1)!, Int(match.2)!)
                // Locale order first; the other order when that can't be a month.
                let dayFirst = dayComesFirst(in: calendar)
                return monthDay(month: dayFirst ? b : a, day: dayFirst ? a : b, after: day, calendar: calendar)
                    ?? monthDay(month: dayFirst ? a : b, day: dayFirst ? b : a, after: day, calendar: calendar)
            }
            return nil
        }

        if words.count == 2 {
            let (first, second) = (words[0], words[1])
            if let dayOfMonth = Int(second), let month = monthIndex(first, calendar) {
                return monthDay(month: month + 1, day: dayOfMonth, after: day, calendar: calendar)
            }
            if let dayOfMonth = Int(first), let month = monthIndex(second, calendar) {
                return monthDay(month: month + 1, day: dayOfMonth, after: day, calendar: calendar)
            }
        }
        return nil
    }

    private static func monthDay(month: Int, day: Int, after date: Date, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return calendar.nextDate(after: date, matching: DateComponents(month: month, day: day), matchingPolicy: .strict)
    }

    private static func monthIndex(_ word: String, _ calendar: Calendar) -> Int? {
        guard word.count >= 3 else { return nil }
        return index(of: word, in: calendar.monthSymbols) ?? index(of: word, in: calendar.shortMonthSymbols)
    }

    /// Unique prefix match; ambiguous prefixes ("t" for tue/thu) yield nil.
    private static func index(of prefix: String, in symbols: [String]) -> Int? {
        let hits = symbols.indices.filter { symbols[$0].lowercased().hasPrefix(prefix) }
        return hits.count == 1 ? hits[0] : nil
    }

    private static func dayComesFirst(in calendar: Calendar) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "dM", options: 0, locale: calendar.locale) ?? "d/M"
        guard let d = format.firstIndex(of: "d"), let m = format.firstIndex(of: "M") else { return true }
        return d < m
    }
}

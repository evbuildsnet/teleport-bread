import SwiftUI

enum RelativeLabel {
    /// "3d over" / "Today" / "Tomorrow" / "in 5d" — date-only semantics.
    static func due(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case ..<0: return "\(-days)d over"
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return "in \(days)d"
        }
    }

    /// "9m" / "3h" / "2d" ago, for settled items.
    static func since(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 3600 { return "\(max(1, Int(seconds / 60)))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }
}

extension Color {
    init?(hexString: String?) {
        guard let hexString,
              hexString.hasPrefix("#"), hexString.count == 7,
              let value = UInt32(hexString.dropFirst(), radix: 16)
        else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

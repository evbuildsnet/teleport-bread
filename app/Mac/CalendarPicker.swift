import InboxCore
import SwiftUI

/// Keyboard-first day picker: type a quick date (`fri`, `3d`, `sep 14`) or
/// walk the month grid — ← → day, ↑ ↓ week, ⇞ ⇟ or ⌘← ⌘→ month, ⏎ picks.
/// Clicking a day picks it outright. Days before today can't be picked.
struct CalendarPicker: View {
    @Binding var date: Date
    let confirm: () -> Void
    let cancel: () -> Void
    @State private var query = ""
    @State private var month: Date
    @FocusState private var focused: Bool

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private var unparsed: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty && QuickDate.parse(query, today: .now, calendar: calendar) == nil
    }

    init(date: Binding<Date>, confirm: @escaping () -> Void, cancel: @escaping () -> Void) {
        _date = date
        self.confirm = confirm
        self.cancel = cancel
        _month = State(initialValue: Self.startOfMonth(date.wrappedValue, Calendar.current))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            field
            header
            grid
            footer
        }
        .frame(width: 7 * cellWidth + 6 * cellSpacing)
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
        }
    }

    // MARK: Pieces

    private let cellWidth: CGFloat = 32
    private let cellHeight: CGFloat = 26
    private let cellSpacing: CGFloat = 2

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .foregroundStyle(Theme.muted)
            TextField("fri · 3d · sep 14 · 2w", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(confirm)
                .onKeyPress(.escape) { cancel(); return .handled }
                .onKeyPress(.leftArrow, phases: .down) { press in step(press.modifiers.contains(.command) ? .month(-1) : .day(-1)) }
                .onKeyPress(.rightArrow, phases: .down) { press in step(press.modifiers.contains(.command) ? .month(1) : .day(1)) }
                .onKeyPress(.upArrow) { step(.day(-7)) }
                .onKeyPress(.downArrow) { step(.day(7)) }
                .onKeyPress(.pageUp) { step(.month(-1)) }
                .onKeyPress(.pageDown) { step(.month(1)) }
                .onChange(of: query) { _, text in
                    if let parsed = QuickDate.parse(text, today: .now, calendar: calendar) { select(parsed) }
                }
                .accessibilityLabel("Quick date")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Theme.sidebarHover, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(unparsed ? Color.red.opacity(0.5) : .clear))
    }

    private var header: some View {
        HStack(spacing: 2) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            Button { _ = step(.month(-1)) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(SidebarIconButtonStyle())
                .disabled(month <= Self.startOfMonth(today, calendar))
                .accessibilityLabel("Previous month")
            Button { _ = step(.month(1)) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(SidebarIconButtonStyle())
                .accessibilityLabel("Next month")
        }
        .padding(.leading, 4)
    }

    private var grid: some View {
        VStack(spacing: cellSpacing) {
            HStack(spacing: cellSpacing) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(width: cellWidth, height: 16)
                }
            }
            // Always six rows so the popover never changes height.
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: cellSpacing) {
                    ForEach(0..<7, id: \.self) { column in
                        if let day = cells[row * 7 + column] {
                            DayCell(
                                number: calendar.component(.day, from: day),
                                selected: day == calendar.startOfDay(for: date),
                                isToday: day == today,
                                past: day < today,
                                size: CGSize(width: cellWidth, height: cellHeight)
                            ) {
                                select(day)
                                confirm()
                            }
                        } else {
                            Color.clear.frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
            Spacer()
            Text("↑↓←→ move · ⇞⇟ month · ⏎ snooze")
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Model

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    /// 42 slots: leading blanks up to the first weekday, then each day.
    private var cells: [Date?] {
        let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)!.count
        var slots = [Date?](repeating: nil, count: 42)
        for day in 0..<count {
            slots[offset + day] = calendar.date(byAdding: .day, value: day, to: month)
        }
        return slots
    }

    private enum Step { case day(Int), month(Int) }

    private func step(_ step: Step) -> KeyPress.Result {
        let target: Date? = switch step {
        case .day(let days): calendar.date(byAdding: .day, value: days, to: date)
        case .month(let months): calendar.date(byAdding: .month, value: months, to: date)
        }
        guard let target else { return .handled }
        select(max(target, today))
        return .handled
    }

    private func select(_ day: Date) {
        date = calendar.startOfDay(for: day)
        month = Self.startOfMonth(date, calendar)
    }

    private static func startOfMonth(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }
}

private struct DayCell: View {
    let number: Int
    let selected: Bool
    let isToday: Bool
    let past: Bool
    let size: CGSize
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 12, weight: selected || isToday ? .semibold : .regular))
                .foregroundStyle(selected ? .white : isToday ? Theme.accent : past ? Theme.muted.opacity(0.45) : Theme.text)
                .frame(width: size.width, height: size.height)
                .background(
                    selected ? Theme.accent : hovering && !past ? Theme.sidebarHover : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(past)
        .onHover { hovering = $0 }
        .accessibilityLabel("Day \(number)")
    }
}

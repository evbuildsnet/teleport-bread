import Foundation

/// Which shelf a need currently sits on. Derived from live section
/// membership (a row can outlive a refresh), not snapshot flags.
public enum NeedState: Sendable {
    case inbox, snoozed, settled
}

/// The triage verbs, described once: every surface (swipe actions, context
/// menus, hover buttons, palette) renders label + symbol from here instead
/// of hand-wiring its own switch.
public enum TriageAction: Hashable, Identifiable, Sendable {
    case settle
    case wake
    case unsettle
    case snooze(SnoozePreset)
    /// Entry point only; each surface owns its date-picking UI.
    case snoozePickDate

    public var id: Self { self }

    public var label: String {
        switch self {
        case .settle: "Settle"
        case .wake: "Wake"
        case .unsettle: "Un-settle"
        case .snooze(let preset): preset.label
        case .snoozePickDate: "Pick date…"
        }
    }

    public var symbol: String {
        switch self {
        case .settle: "checkmark"
        case .wake: "sun.max"
        case .unsettle: "arrow.uturn.backward"
        case .snooze: "clock"
        case .snoozePickDate: "calendar"
        }
    }

    /// The one-tap verb for a row in this state.
    public static func primary(for state: NeedState) -> TriageAction {
        switch state {
        case .inbox: .settle
        case .snoozed: .wake
        case .settled: .unsettle
        }
    }

    /// Snooze applies in every state: reschedules snoozed, reopens settled.
    public static let snoozeMenu: [TriageAction] =
        SnoozePreset.allCases.map(TriageAction.snooze) + [.snoozePickDate]
}

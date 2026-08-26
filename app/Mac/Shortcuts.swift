import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import SwiftUI

/// In-app commands whose keys the user can change in Settings. ⌘1…⌘9 jumps
/// are deliberately not here — they are the numbers themselves.
enum ShortcutAction: String, CaseIterable, Codable {
    case newNeed, palette, previousNeed, nextNeed, toggleSidebar

    var title: String {
        switch self {
        case .newNeed: "New need"
        case .palette: "Search (command palette)"
        case .previousNeed: "Previous need"
        case .nextNeed: "Next need"
        case .toggleSidebar: "Toggle sidebar"
        }
    }

    /// Where the key is inert. Technical, not a setting.
    var blockedIn: KeyContext {
        switch self {
        case .newNeed, .previousNeed, .nextNeed: .palette
        case .palette, .toggleSidebar: []
        }
    }

    var defaultCombo: KeyCombo {
        switch self {
        case .newNeed: KeyCombo(keyCode: kVK_ANSI_N, modifiers: .command)
        case .palette: KeyCombo(keyCode: kVK_ANSI_K, modifiers: .command)
        case .previousNeed: KeyCombo(keyCode: kVK_ANSI_LeftBracket, modifiers: [.command, .shift])
        case .nextNeed: KeyCombo(keyCode: kVK_ANSI_RightBracket, modifiers: [.command, .shift])
        case .toggleSidebar: KeyCombo(keyCode: kVK_ANSI_B, modifiers: .command)
        }
    }
}

/// The user's bindings; anything unset falls back to the default. Menu items
/// read `combo(for:)`, so the menu bar and every hint stay in step.
@MainActor
@Observable
final class Shortcuts {
    static let shared = Shortcuts()
    private static let defaultsKey = "shortcuts"

    private(set) var custom: [ShortcutAction: KeyCombo] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(custom), forKey: Self.defaultsKey) }
    }

    private init() {
        custom = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([ShortcutAction: KeyCombo].self, from: $0) } ?? [:]
    }

    func combo(for action: ShortcutAction) -> KeyCombo {
        custom[action] ?? action.defaultCombo
    }

    func display(_ action: ShortcutAction) -> String {
        combo(for: action).display
    }

    func isDefault(_ action: ShortcutAction) -> Bool {
        custom[action] == nil
    }

    /// Which other action already uses this combo, if any.
    func owner(of combo: KeyCombo, besides action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != action && self.combo(for: $0) == combo }
    }

    func set(_ combo: KeyCombo, for action: ShortcutAction) {
        custom[action] = combo == action.defaultCombo ? nil : combo
    }

    func reset(_ action: ShortcutAction) {
        custom[action] = nil
    }
}

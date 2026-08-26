import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Where a binding is live. Purely technical — derived from UI state at
/// key-down time — never something the user configures.
struct KeyContext: OptionSet, Hashable {
    let rawValue: UInt8
    static let search = KeyContext(rawValue: 1 << 0)
    static let titleEdit = KeyContext(rawValue: 1 << 1)
    static let noteEdit = KeyContext(rawValue: 1 << 2)
    static let palette = KeyContext(rawValue: 1 << 3)
    /// Every modal text entry. A draft is deliberately not one: its text is
    /// stashed when you leave, so hopping between needs is fine there.
    static let textEntry: KeyContext = [.search, .titleEdit, .noteEdit, .palette]
}

enum KeyCommand: Hashable {
    case action(ShortcutAction)
    case jump(Int)
}

struct KeyBinding {
    let command: KeyCommand
    let combo: KeyCombo
    /// Contexts in which the key does nothing. The event is still swallowed
    /// so the menu bar can't fire it either.
    let blockedIn: KeyContext
}

/// Single dispatch point for in-app keys: the local event monitor asks here
/// before anything else sees the key; menu items show the same combos and
/// run the same commands on click.
@MainActor
enum KeyBindings {
    static func all(_ shortcuts: Shortcuts) -> [KeyBinding] {
        ShortcutAction.allCases.map {
            KeyBinding(command: .action($0), combo: shortcuts.combo(for: $0), blockedIn: $0.blockedIn)
        } + (1...9).map {
            KeyBinding(command: .jump($0), combo: jumpCombo($0), blockedIn: .textEntry)
        }
    }

    static func binding(for command: KeyCommand, _ shortcuts: Shortcuts) -> KeyBinding {
        all(shortcuts).first { $0.command == command }!
    }

    /// ⌘1…⌘9: the number is the badge on the row, never rebindable.
    private static func jumpCombo(_ number: Int) -> KeyCombo {
        let keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        return KeyCombo(keyCode: keyCodes[number - 1], modifiers: .command)
    }

    /// True when the key belongs to a binding — performed, or ignored because
    /// of the context — and must not propagate.
    static func handle(_ event: NSEvent, ui: UIState, model: AppModel) -> Bool {
        guard let combo = KeyCombo(event: event),
              let binding = all(Shortcuts.shared).first(where: { $0.combo == combo })
        else { return false }
        ui.perform(binding.command, model: model)
        return true
    }
}

/// Hands the hosting NSWindow to whoever needs to tell "our" key events from
/// the Settings window's.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}

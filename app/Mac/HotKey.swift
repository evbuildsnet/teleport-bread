import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import SwiftUI

/// A recorded key combination. Stored as keyCode + Carbon modifier mask.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // A bare key would swallow normal typing; require a real modifier.
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        self.init(keyCode: Int(event.keyCode), modifiers: flags)
    }

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = UInt32(keyCode)
        var mods: UInt32 = 0
        if modifiers.contains(.command) { mods |= UInt32(cmdKey) }
        if modifiers.contains(.control) { mods |= UInt32(controlKey) }
        if modifiers.contains(.option) { mods |= UInt32(optionKey) }
        if modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
        carbonModifiers = mods
    }

    /// The same combo as a SwiftUI menu shortcut; nil for keys SwiftUI has
    /// no equivalent for (function keys and the like).
    var keyboardShortcut: KeyboardShortcut? {
        guard let key = keyEquivalent else { return nil }
        var modifiers: SwiftUI.EventModifiers = []
        if carbonModifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        if carbonModifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }

    private var keyEquivalent: KeyEquivalent? {
        let special: [UInt32: KeyEquivalent] = [
            UInt32(kVK_Space): .space, UInt32(kVK_Return): .return, UInt32(kVK_Tab): .tab,
            UInt32(kVK_Escape): .escape, UInt32(kVK_Delete): .delete, UInt32(kVK_UpArrow): .upArrow,
            UInt32(kVK_DownArrow): .downArrow, UInt32(kVK_LeftArrow): .leftArrow, UInt32(kVK_RightArrow): .rightArrow,
        ]
        if let key = special[keyCode] { return key }
        let name = Self.keyName(keyCode).lowercased()
        guard name.count == 1, let character = name.first else { return nil }
        return KeyEquivalent(character)
    }

    var display: String {
        var parts = ""
        if carbonModifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + Self.keyName(keyCode)
    }

    private static func keyName(_ keyCode: UInt32) -> String {
        let special: [UInt32: String] = [
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Escape): "⎋", UInt32(kVK_Delete): "⌫", UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓", UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        ]
        if let name = special[keyCode] { return name }
        // Translate through the current keyboard layout.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }
        let layout = unsafeBitCast(CFDataGetBytePtr(unsafeBitCast(data, to: CFData.self)), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKeys, 4, &length, &chars)
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// System-wide hotkey via Carbon's RegisterEventHotKey — public API, no
/// Accessibility permission, works while the app is in the background.
@MainActor
@Observable
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private static let defaultsKey = "captureHotKey"

    var combo: KeyCombo? {
        didSet {
            if let combo { UserDefaults.standard.set(try? JSONEncoder().encode(combo), forKey: Self.defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.defaultsKey) }
            register()
        }
    }
    var onPress: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey) {
            combo = try? JSONDecoder().decode(KeyCombo.self, from: data)
        }
        installHandler()
        register()
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in HotKeyCenter.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    private func register() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        guard let combo else { return }
        let id = EventHotKeyID(signature: OSType(0x495A_4B59), id: 1) // "IZKY"
        RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

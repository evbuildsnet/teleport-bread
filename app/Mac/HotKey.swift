import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

/// A recorded key combination. Stored as keyCode + Carbon modifier mask.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // A bare key would swallow normal typing system-wide; require a modifier.
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        carbonModifiers = mods
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

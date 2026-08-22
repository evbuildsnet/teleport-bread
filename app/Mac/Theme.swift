import AppKit
import SwiftUI

/// Colour and geometry tokens lifted from T3 Code's stock palette, so the
/// Mac surface reads as a sibling of that UI. Light/dark resolved by AppKit.
enum Theme {
    static let canvas = dynamic(light: 0xFCFCFC, dark: 0x0A0A0A)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x111111)
    static let raised = dynamic(light: 0xFCFCFC, dark: 0x141414)
    static let overlay = dynamic(light: 0xFFFFFF, dark: 0x191919)
    static let text = dynamic(light: 0x27272A, dark: 0xF5F5F5)
    static let muted = dynamic(light: 0x71717B, dark: 0x818181)
    static let border = dynamic(light: 0xE4E4E7, dark: 0x262626)
    static let input = dynamic(light: 0xD4D4D8, dark: 0x1E1E1E)
    static let accent = dynamic(light: 0x1B4ED8, dark: 0x346BF1)
    static let bubble = dynamic(light: 0xF4F4F5, dark: 0x1C1C1C)

    static let sidebar = dynamic(light: 0xFAFAFA, dark: 0x000000)
    static let sidebarText = dynamic(light: 0x27272A, dark: 0xF1F3F7)
    static let sidebarMuted = dynamic(light: 0x71717B, dark: 0xA3A3A3)
    static let sidebarHover = dynamic(light: 0xF1F1F3, dark: 0x131313)
    static let sidebarSelected = dynamic(light: 0xFFFFFF, dark: 0x1A1B1B)
    static let sidebarBorder = dynamic(light: 0xE4E4E7, dark: 0x141414)

    static let sidebarDefaultWidth: CGFloat = 256
    static let sidebarMinWidth: CGFloat = 208
    static let mainMinWidth: CGFloat = 640
    static let topBarHeight: CGFloat = 52
    static let cardHeight: CGFloat = 78
    static let rowHeight: CGFloat = 36
    static let columnMaxWidth: CGFloat = 768
    static let controlRadius: CGFloat = 8
    static let radius: CGFloat = 10

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(rgb: Int) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

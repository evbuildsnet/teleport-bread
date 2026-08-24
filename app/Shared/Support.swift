import SwiftUI

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

import AppKit
import SwiftUI

/// Note text with native selection and clickable links/phone numbers. On
/// macOS, SwiftUI Text selection is solid and link attributes are clickable,
/// so no AppKit bridge is needed (unlike the iOS bubble).
struct SelectableText: View {
    let text: String

    var body: some View {
        Text(attributed)
            .font(.system(size: 14))
            .textSelection(.enabled)
            .tint(Theme.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return result }
        let nsText = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let url = match.url ?? match.phoneNumber.flatMap({ URL(string: "tel:\($0.filter { !$0.isWhitespace })") }),
                  let range = Range(match.range, in: result)
            else { continue }
            result[range].link = url
            result[range].underlineStyle = .single
        }
        return result
    }
}

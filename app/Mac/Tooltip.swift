import SwiftUI

/// Styled tooltip for icon-only controls: appears below the control after a
/// short hover, never while `suppressed` (e.g. a popover is open).
struct Tooltip: ViewModifier {
    let text: String
    var suppressed = false
    @State private var hovering = false
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                if !inside { visible = false }
            }
            .task(id: hovering) {
                guard hovering else { return }
                try? await Task.sleep(for: .milliseconds(350))
                if hovering { visible = true }
            }
            .overlay(alignment: .bottom) {
                if visible && !suppressed {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                        .fixedSize()
                        .alignmentGuide(.bottom) { $0[.top] - 6 }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .onChange(of: suppressed) { _, on in if on { visible = false } }
    }
}

extension View {
    func tooltip(_ text: String, suppressed: Bool = false) -> some View {
        modifier(Tooltip(text: text, suppressed: suppressed))
    }
}

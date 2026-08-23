import SwiftUI

/// Styled tooltip for icon-only controls. Sits above the control by default
/// (never covering what it labels); `.bottom` for controls at the window top.
/// Appears after a short hover, never while `suppressed` (e.g. popover open).
struct Tooltip: ViewModifier {
    let text: String
    var edge: VerticalEdge = .top
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
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if visible && !suppressed {
                    label
                        .alignmentGuide(.top) { $0[.bottom] + 6 }
                        .alignmentGuide(.bottom) { $0[.top] - 6 }
                }
            }
            .onChange(of: suppressed) { _, on in if on { visible = false } }
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .fixedSize()
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

extension View {
    func tooltip(_ text: String, edge: VerticalEdge = .top, suppressed: Bool = false) -> some View {
        modifier(Tooltip(text: text, edge: edge, suppressed: suppressed))
    }
}

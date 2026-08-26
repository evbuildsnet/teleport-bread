import SwiftUI

/// What the window-level tooltip layer shows: one label, anchored to the
/// control's frame in window coordinates.
struct TooltipState: Equatable {
    let owner: UUID
    var text: String
    var anchor: CGRect
    var edge: VerticalEdge
}

/// Window-root coordinate space shared by every in-window floating layer.
enum WindowSpace {
    static let name = "window"
}

/// Styled tooltip for icon-only controls. The label is rendered by
/// `TooltipLayer` at the window root, so it floats above every row and never
/// gets covered or clipped by the control's own container. Sits above the
/// control by default; `.bottom` for controls at the window top. Appears
/// after a short hover, never while `suppressed` (e.g. popover open).
struct Tooltip: ViewModifier {
    @Environment(UIState.self) private var ui
    let text: String
    var edge: VerticalEdge = .top
    var suppressed = false
    @State private var owner = UUID()
    @State private var hovering = false
    @State private var anchor = CGRect.zero

    private var shown: Bool { ui.tooltip?.owner == owner }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(WindowSpace.name)) } action: { frame in
                anchor = frame
                if shown { ui.tooltip?.anchor = frame }
            }
            .onHover { inside in
                hovering = inside
                if !inside { hide() }
            }
            .task(id: hovering) {
                guard hovering, !suppressed else { return }
                try? await Task.sleep(for: .milliseconds(350))
                if hovering, !suppressed { ui.tooltip = TooltipState(owner: owner, text: text, anchor: anchor, edge: edge) }
            }
            .onChange(of: suppressed) { _, on in if on { hide() } }
            .onDisappear(perform: hide)
    }

    private func hide() {
        if shown { ui.tooltip = nil }
    }
}

/// Draws the active tooltip. Mount once at the window root, together with
/// `.coordinateSpace(name: WindowSpace.name)` on the same view.
struct TooltipLayer: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let tip = ui.tooltip {
                Text(tip.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    .fixedSize()
                    // Centre over the control; 6pt gap on the chosen side.
                    .alignmentGuide(.leading) { $0[HorizontalAlignment.center] - tip.anchor.midX }
                    .alignmentGuide(.top) { d in
                        tip.edge == .top ? d[.bottom] - tip.anchor.minY + 6 : -(tip.anchor.maxY + 6)
                    }
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func tooltip(_ text: String, edge: VerticalEdge = .top, suppressed: Bool = false) -> some View {
        modifier(Tooltip(text: text, edge: edge, suppressed: suppressed))
    }
}

import InboxCore
import SwiftUI

/// Sidebar + main pane with a draggable rail; double-click resets the width.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        @Bindable var ui = ui
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if ui.sidebarVisible {
                    Sidebar()
                        .frame(width: ui.sidebarWidth)
                        .background(Theme.sidebar)
                        .transition(.move(edge: .leading))
                    rail(maxWidth: geometry.size.width - Theme.mainMinWidth)
                }
                MainPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.canvas)
            }
        }
        .ignoresSafeArea()
        .overlay { if ui.paletteOpen { CommandPalette() } }
        .onChange(of: model.inbox.isEmpty, initial: true) { _, _ in
            guard ui.selection == nil, let first = model.inbox.first else { return }
            ui.selection = .need(first.id)
        }
    }

    private func rail(maxWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Theme.sidebarBorder)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStartWidth ?? ui.sidebarWidth
                                dragStartWidth = start
                                let proposed = start + value.translation.width
                                ui.sidebarWidth = min(max(proposed, Theme.sidebarMinWidth), max(Theme.sidebarMinWidth, maxWidth))
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        ui.sidebarWidth = Theme.sidebarDefaultWidth
                    })
            }
    }
}

/// Right side: a need's thread, the draft hero, or the empty state.
struct MainPane: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        switch ui.selection {
        case .need(let id):
            if let snapshot = model.snapshot(id: id) {
                MacThreadView(snapshot: snapshot)
                    .id(id)
            } else {
                empty("This need is no longer here.")
            }
        case .draft:
            DraftHero()
        case nil:
            empty(model.inbox.isEmpty ? "Inbox Zero. Nothing due." : "Select a need, or press ⌘N.")
        }
    }

    private func empty(_ text: String) -> some View {
        VStack(spacing: 0) {
            TopBar(snapshot: nil)
            Spacer()
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
    }
}

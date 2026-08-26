import InboxCore
import SwiftUI

/// Every place an action can be taken (hover buttons, context menu, title
/// menu, palette) funnels through here so the rules stay in one spot:
/// mobile's semantics, untouched — snooze reopens, wake = due today.
@MainActor
struct NeedActions {
    let model: AppModel
    let ui: UIState

    func settle(_ snapshot: ReminderSnapshot) {
        advanceIfSelected(snapshot)
        Task { await model.settle(snapshot) }
    }

    func snooze(_ snapshot: ReminderSnapshot, _ preset: SnoozePreset) {
        advanceIfSelected(snapshot)
        Task { await model.snooze(snapshot, preset) }
    }

    func snooze(_ snapshot: ReminderSnapshot, until date: Date) {
        advanceIfSelected(snapshot)
        Task { await model.snooze(snapshot, until: date) }
    }

    func wake(_ snapshot: ReminderSnapshot) {
        Task { await model.wake(snapshot) }
    }

    func unsettle(_ snapshot: ReminderSnapshot) {
        Task { await model.unsettle(snapshot) }
    }

    /// Single entry point: surfaces hand a TriageAction here instead of
    /// hand-wiring their own switch.
    func perform(_ action: TriageAction, on snapshot: ReminderSnapshot) {
        switch action {
        case .settle: settle(snapshot)
        case .wake: wake(snapshot)
        case .unsettle: unsettle(snapshot)
        case .snooze(let preset): snooze(snapshot, preset)
        case .snoozePickDate: SnoozeDatePicker.present(for: snapshot, model: model, ui: ui)
        }
    }

    /// Settling/snoozing the open need moves selection to the next inbox need.
    private func advanceIfSelected(_ snapshot: ReminderSnapshot) {
        guard ui.selection == .need(snapshot.id) else { return }
        ui.selection = ui.selectionAfterRemoving(snapshot.id, in: model)
    }
}

/// Shared menu body: row context menu and the title menu in the top bar.
struct NeedActionMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let snapshot: ReminderSnapshot
    var onRename: (() -> Void)?

    var body: some View {
        let actions = NeedActions(model: model, ui: ui)
        TriageMenuItems(state: model.state(of: snapshot.id) ?? .inbox) {
            actions.perform($0, on: snapshot)
        }
        Divider()
        if let onRename {
            Button("Rename…") { onRename() }
        }
        Menu("Move to list") {
            ForEach(model.listOptions) { list in
                Button {
                    Task { await model.update(snapshot, title: snapshot.title, listID: list.id) }
                } label: {
                    if list.id == snapshot.listID { Label(list.title, systemImage: "checkmark") } else { Text(list.title) }
                }
            }
        }
    }
}

/// Hover buttons at the trailing edge of a row (T3: clock + check on cards,
/// wake / un-settle on compact rows), as a small floating toolbar: it reads
/// as a control sitting over the row rather than a smear across the title.
struct HoverActions: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let snapshot: ReminderSnapshot
    let placement: NeedState
    @State private var snoozeOpen = false

    var body: some View {
        let actions = NeedActions(model: model, ui: ui)
        let primary = TriageAction.primary(for: placement)
        HStack(spacing: 2) {
            if placement == .inbox { snoozeButton }
            iconButton(primary.symbol, help: primary.label) { actions.perform(primary, on: snapshot) }
            if placement == .settled { snoozeButton }
        }
        .padding(2)
        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.14), radius: 4, y: 1)
    }

    private var snoozeButton: some View {
        Button { snoozeOpen = true } label: { Image(systemName: "clock") }
            .buttonStyle(SidebarIconButtonStyle())
            .accessibilityLabel("Snooze need")
            .tooltip("Snooze", suppressed: snoozeOpen)
            .popover(isPresented: $snoozeOpen, arrowEdge: .trailing) {
                SnoozePopover(snapshot: snapshot)
            }
            .onChange(of: snoozeOpen) { _, open in
                // The cursor leaves the row to reach the popover; keep the
                // row hovered (and this button mounted) until it closes.
                ui.hoverLockID = open ? snapshot.id : nil
                if !open { ui.hoveredID = nil }
            }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(SidebarIconButtonStyle())
        .tooltip(help)
        .accessibilityLabel("\(help) need")
    }
}

/// Presets + Pick date… (mobile's "Snooze until" dialog, as a popover).
struct SnoozePopover: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    let snapshot: ReminderSnapshot
    @State private var picking = false
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now)!

    var body: some View {
        let actions = NeedActions(model: model, ui: ui)
        VStack(alignment: .leading, spacing: 4) {
            Text("Snooze until")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            if picking {
                CalendarPicker(date: $date) {
                    actions.snooze(snapshot, until: date)
                    dismiss()
                } cancel: { picking = false }
            } else {
                ForEach(TriageAction.snoozeMenu) { action in
                    if action == .snoozePickDate {
                        Divider().padding(.vertical, 2)
                        // Popovers can host the field inline; no panel needed.
                        menuRow(action.label) { picking = true }
                    } else {
                        menuRow(action.label) {
                            actions.perform(action, on: snapshot)
                            dismiss()
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(width: picking ? nil : 180)
    }

    private func menuRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PaletteRowStyle())
    }
}

/// Context menus can't host a calendar; "Pick date…" from a menu opens a
/// small panel instead.
@MainActor
enum SnoozeDatePicker {
    static func present(for snapshot: ReminderSnapshot, model: AppModel, ui: UIState) {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.title = "Snooze until"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(
            rootView: SnoozePanelBody(snapshot: snapshot) { panel.close() }.environment(model).environment(ui)
        )
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct SnoozePanelBody: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let snapshot: ReminderSnapshot
    let close: () -> Void
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now)!

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            CalendarPicker(date: $date) {
                NeedActions(model: model, ui: ui).snooze(snapshot, until: date)
                close()
            } cancel: { close() }
        }
        .padding(12)
        .padding(.top, 16)
        .background(Theme.overlay)
    }
}

struct PaletteRowStyle: ButtonStyle {
    @State private var hovering = false
    var highlighted = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.text)
            .background(
                highlighted || hovering || configuration.isPressed ? Theme.sidebarHover : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .onHover { hovering = $0 }
    }
}

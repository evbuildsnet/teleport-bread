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
        let isSettled = snapshot.isCompleted
        let isSnoozed = !isSettled && model.snoozed.contains { $0.id == snapshot.id }

        if isSettled {
            Button("Un-settle need") { actions.unsettle(snapshot) }
        } else if isSnoozed {
            Button("Wake need") { actions.wake(snapshot) }
        } else {
            Button("Settle need") { actions.settle(snapshot) }
        }
        Menu("Snooze") {
            ForEach(SnoozePreset.allCases, id: \.self) { preset in
                Button(preset.label) { actions.snooze(snapshot, preset) }
            }
            Divider()
            Button("Pick date…") { SnoozeDatePicker.present(for: snapshot, model: model, ui: ui) }
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
/// wake / un-settle on compact rows).
struct HoverActions: View {
    enum Placement { case inbox, snoozed, settled }

    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let snapshot: ReminderSnapshot
    let placement: Placement
    @State private var snoozeOpen = false

    var body: some View {
        let actions = NeedActions(model: model, ui: ui)
        HStack(spacing: 2) {
            switch placement {
            case .inbox:
                snoozeButton
                iconButton("checkmark", help: "Settle") { actions.settle(snapshot) }
            case .snoozed:
                iconButton("sun.max", help: "Wake") { actions.wake(snapshot) }
            case .settled:
                iconButton("arrow.uturn.backward", help: "Un-settle") { actions.unsettle(snapshot) }
                snoozeButton
            }
        }
    }

    private var snoozeButton: some View {
        iconButton("clock", help: "Snooze") { snoozeOpen = true }
            .popover(isPresented: $snoozeOpen, arrowEdge: .trailing) {
                SnoozePopover(snapshot: snapshot)
            }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(SidebarIconButtonStyle())
        .help(help)
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
                DatePicker("Snooze until", selection: $date, in: Date.now..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    Spacer()
                    Button("Cancel") { picking = false }
                    Button("Snooze") {
                        actions.snooze(snapshot, until: date)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            } else {
                ForEach(SnoozePreset.allCases, id: \.self) { preset in
                    menuRow(preset.label) {
                        actions.snooze(snapshot, preset)
                        dismiss()
                    }
                }
                Divider().padding(.vertical, 2)
                menuRow("Pick date…") { picking = true }
            }
        }
        .padding(8)
        .frame(width: picking ? 280 : 180)
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
        panel.contentView = NSHostingView(
            rootView: SnoozePanelBody(snapshot: snapshot) { panel.close() }.environment(model).environment(ui)
        )
        panel.setContentSize(NSSize(width: 296, height: 360))
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
        VStack(spacing: 8) {
            DatePicker("Snooze until", selection: $date, in: Date.now..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                Button("Snooze") {
                    NeedActions(model: model, ui: ui).snooze(snapshot, until: date)
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .padding(.top, 16)
        .frame(width: 296)
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

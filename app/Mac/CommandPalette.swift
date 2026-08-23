import InboxCore
import SwiftUI

/// ⌘K: search needs by title/notes and run actions. `>` prefix = actions
/// only (T3 convention). ↑↓ move, ⏎ runs, Esc closes.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let symbol: String
        let run: @MainActor () -> Void
    }

    private var current: ReminderSnapshot? { ui.selection?.needID.flatMap { model.snapshot(id: $0) } }

    private var actions: [Entry] {
        let actions = NeedActions(model: model, ui: ui)
        var list: [Entry] = [
            Entry(id: "new", title: "New need", subtitle: "⌘N", symbol: "square.and.pencil") { ui.newDraft(model: model) },
        ]
        if let need = current {
            let isSettled = need.isCompleted
            let isSnoozed = !isSettled && model.snoozed.contains { $0.id == need.id }
            if isSettled {
                list.append(Entry(id: "unsettle", title: "Un-settle need", subtitle: need.title, symbol: "arrow.uturn.backward") { actions.unsettle(need) })
            } else if isSnoozed {
                list.append(Entry(id: "wake", title: "Wake need", subtitle: need.title, symbol: "sun.max") { actions.wake(need) })
            } else {
                list.append(Entry(id: "settle", title: "Settle need", subtitle: need.title, symbol: "checkmark") { actions.settle(need) })
            }
            for preset in SnoozePreset.allCases {
                list.append(Entry(id: "snooze-\(preset.rawValue)", title: "Snooze until \(preset.label.lowercased())", subtitle: need.title, symbol: "clock") { actions.snooze(need, preset) })
            }
            list.append(Entry(id: "snooze-pick", title: "Snooze until a date…", subtitle: need.title, symbol: "calendar") {
                SnoozeDatePicker.present(for: need, model: model, ui: ui)
            })
        }
        list.append(Entry(id: "sidebar", title: ui.sidebarVisible ? "Hide sidebar" : "Show sidebar", subtitle: "⌘B", symbol: "sidebar.left") {
            ui.sidebarVisible.toggle()
        })
        list.append(Entry(id: "all-lists", title: "Show all lists", subtitle: nil, symbol: "tray.2") {
            model.selectedListIDs = nil
            Task { await model.refresh() }
        })
        return list
    }

    private var results: (actions: [Entry], needs: [ReminderSnapshot]) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(">") {
            let q = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            return (actions.filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) }, [])
        }
        let all = model.inbox + model.snoozed + model.settled
        if trimmed.isEmpty {
            return (actions, Array(all.prefix(12)))
        }
        let needs = all.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || ($0.note?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
        return (actions.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }, needs)
    }

    private var rowCount: Int { results.actions.count + results.needs.count }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { ui.paletteOpen = false }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search needs and actions…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($focused)
                        .onSubmit(runHighlighted)
                        .onKeyPress(.escape) { ui.paletteOpen = false; return .handled }
                        .onKeyPress(.upArrow) { move(-1); return .handled }
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onChange(of: query) { _, _ in highlighted = 0 }
                        .accessibilityLabel("Palette search")
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                Rectangle().fill(Theme.border).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            let (actions, needs) = results
                            if !actions.isEmpty {
                                sectionLabel("Actions")
                                ForEach(Array(actions.enumerated()), id: \.element.id) { index, entry in
                                    row(index: index, symbol: entry.symbol, title: entry.title, subtitle: entry.subtitle) {
                                        ui.paletteOpen = false
                                        entry.run()
                                    }
                                }
                            }
                            if !needs.isEmpty {
                                sectionLabel(query.trimmingCharacters(in: .whitespaces).isEmpty ? "Needs" : "Matching needs")
                                ForEach(Array(needs.enumerated()), id: \.element.id) { offset, need in
                                    row(index: actions.count + offset, symbol: "circle", title: need.title, subtitle: need.listTitle) {
                                        ui.paletteOpen = false
                                        ui.open(.need(need.id), model: model)
                                    }
                                }
                            }
                            if rowCount == 0 {
                                Text("No matching needs or actions.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
                }
                .frame(maxHeight: 380)
            }
            .frame(width: 560)
            .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
            .padding(.top, 90)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(120))
            focused = true
        }
        .onExitCommand { ui.paletteOpen = false }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func row(index: Int, symbol: String, title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .frame(maxWidth: 220, alignment: .trailing)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaletteRowStyle(highlighted: highlighted == index))
        .id(index)
    }

    private func move(_ offset: Int) {
        guard rowCount > 0 else { return }
        highlighted = (highlighted + offset + rowCount) % rowCount
    }

    private func runHighlighted() {
        let (actions, needs) = results
        if highlighted < actions.count {
            ui.paletteOpen = false
            actions[highlighted].run()
        } else if needs.indices.contains(highlighted - actions.count) {
            ui.paletteOpen = false
            ui.open(.need(needs[highlighted - actions.count].id), model: model)
        }
    }
}

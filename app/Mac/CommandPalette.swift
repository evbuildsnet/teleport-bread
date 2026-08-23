import InboxCore
import SwiftUI

/// ⌘K: search, nothing else. Empty query is just the field; typing lists
/// matching needs (title or notes). ↑↓ move, ⏎ opens, Esc closes.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @FocusState private var focused: Bool
    private var query: String { ui.paletteQuery }
    private var highlighted: Int { ui.paletteHighlighted }

    private var results: [ReminderSnapshot] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let all = model.inbox + model.snoozed + model.settled
        return Array(all.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.note?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }.prefix(50))
    }

    var body: some View {
        @Bindable var ui = ui
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { ui.paletteOpen = false }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search needs…", text: $ui.paletteQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($focused)
                        .onSubmit(openHighlighted)
                        .onKeyPress(.escape) { ui.paletteOpen = false; return .handled }
                        .onKeyPress(.upArrow) { move(-1); return .handled }
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onChange(of: ui.paletteQuery) { _, _ in ui.paletteHighlighted = 0 }
                        .accessibilityLabel("Palette search")
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                let needs = results
                if !needs.isEmpty {
                    Rectangle().fill(Theme.border).frame(height: 1)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(needs.enumerated()), id: \.element.id) { index, need in
                                    row(need, index: index)
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: min(CGFloat(needs.count) * 34 + 16, 380))
                        .onChange(of: highlighted) { _, index in
                            if needs.indices.contains(index) { proxy.scrollTo(needs[index].id) }
                        }
                    }
                } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Rectangle().fill(Theme.border).frame(height: 1)
                    Text("No matching needs.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
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

    private func row(_ need: ReminderSnapshot, index: Int) -> some View {
        Button {
            ui.paletteOpen = false
            ui.open(.need(need.id), model: model)
        } label: {
            HStack(spacing: 10) {
                Text(need.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaletteRowStyle(highlighted: highlighted == index))
        .id(need.id)
    }

    private func move(_ offset: Int) {
        let count = results.count
        guard count > 0 else { return }
        ui.paletteHighlighted = (highlighted + offset + count) % count
    }

    private func openHighlighted() {
        let needs = results
        guard needs.indices.contains(highlighted) else { return }
        ui.paletteOpen = false
        ui.open(.need(needs[highlighted].id), model: model)
    }
}

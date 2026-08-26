import InboxCore
import SwiftUI

/// T3-style flat lifecycle list: Drafts · Inbox cards · Snoozed shelf ·
/// Settled shelf · Show N more. Search and list filter live in the header.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @FocusState private var searchFocused: Bool

    private var drafts: [NeedDraft] {
        var rows = model.visibleDrafts
        if let active = ui.activeDraft, !model.drafts.contains(where: { $0.id == active.id }) {
            rows.insert(active, at: 0)
        }
        return rows
    }
    private var inbox: [ReminderSnapshot] { model.visibleInbox }
    private var snoozed: [ReminderSnapshot] { model.visibleSnoozed }
    private var settled: [ReminderSnapshot] { model.visibleSettled }
    private var selectedID: String? { ui.selection?.needID }

    var body: some View {
        @Bindable var model = model
        @Bindable var ui = ui
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    // Plain VStack on purpose: tens of rows at most, and lazy
                    // placement loops forever on variable-height rows (100% CPU).
                    VStack(spacing: 0) {
                        ForEach(drafts) { DraftRow(draft: $0) }
                        if !drafts.isEmpty { divider }
                        inboxRows
                        shelf("Snoozed", items: snoozed, isExpanded: $ui.snoozedExpanded, tint: Theme.accent) { item in
                            NeedRow(snapshot: item, placement: .snoozed).id("snoozed-\(item.id)")
                        }
                        shelf("Settled", items: settled, isExpanded: $ui.settledExpanded, tint: Theme.sidebarMuted) { item in
                            NeedRow(snapshot: item, placement: .settled).id("settled-\(item.id)")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                }
                .onChange(of: ui.selection) { _, selection in
                    guard let id = selection?.needID else { return }
                    proxy.scrollTo(rowID(id), anchor: nil)
                }
                .onChange(of: model.inbox.count + model.snoozed.count + model.settled.count) { _, _ in
                    ui.hoveredID = nil
                }
                .onChange(of: ui.snoozedExpanded || ui.settledExpanded) { _, _ in ui.hoveredID = nil }
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.sidebarBorder).frame(width: 1)
        }
    }

    // MARK: Header

    private var header: some View {
        @Bindable var model = model
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Spacer().frame(width: 70) // traffic lights
                Button {
                    withAnimation(.snappy(duration: 0.2)) { ui.sidebarVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(SidebarIconButtonStyle())
                .tooltip("Hide sidebar ⌘B", edge: .bottom)
                Text("InboxZero")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.sidebarText)
                Spacer()
            }
            .frame(height: Theme.topBarHeight)
            .padding(.horizontal, 8)
            .gesture(WindowDragGesture())

            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.sidebarMuted)
                    TextField("Search", text: $model.searchText)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onKeyPress(.escape) {
                            model.searchText = ""
                            searchFocused = false
                            return .handled
                        }
                        .accessibilityLabel("Search needs")
                }
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Theme.sidebarHover, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                Button {
                    ui.newDraft(model: model)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(SidebarIconButtonStyle())
                .tooltip("New need ⌘N", edge: .bottom)
                .accessibilityLabel("New need")
            }
            .padding(.horizontal, 10)

            ListFilterMenu()
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
        }
    }

    // MARK: Sections

    private var divider: some View {
        Rectangle().fill(Theme.sidebarBorder).frame(height: 1).padding(.vertical, 6)
    }

    @ViewBuilder private var inboxRows: some View {
        if inbox.isEmpty {
            if model.isSearching {
                if drafts.isEmpty && snoozed.isEmpty && settled.isEmpty {
                    emptyLabel("No results")
                }
            } else if drafts.isEmpty {
                emptyLabel("Inbox Zero")
            }
        } else {
            ForEach(inbox) { item in
                NeedCard(snapshot: item, number: number(of: item))
                    .id("inbox-\(item.id)")
            }
        }
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.sidebarMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    /// Collapsed header shows "(n)"; expanded shows the bare title. A
    /// collapsed shelf still renders the selected row so selection never hides.
    @ViewBuilder
    private func shelf<Content: View>(
        _ title: String,
        items: [ReminderSnapshot],
        isExpanded: Binding<Bool>,
        tint: Color,
        @ViewBuilder row: @escaping (ReminderSnapshot) -> Content
    ) -> some View {
        if !items.isEmpty {
            let open = isExpanded.wrappedValue || model.isSearching
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(open ? title : "\(title) (\(items.count))")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityLabel("\(title) section")

            let visible = title == "Settled" ? Array(items.prefix(ui.settledShown)) : items
            if open {
                ForEach(visible) { item in row(item) }
                if title == "Settled", items.count > visible.count {
                    Button {
                        ui.settledShown += UIState.settledPageCount
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                            Text("Show \(min(items.count - visible.count, UIState.settledPageCount)) more")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.sidebarMuted)
                        .padding(.horizontal, 10)
                        .frame(height: Theme.rowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else if let selectedID, let kept = items.first(where: { $0.id == selectedID }) {
                row(kept)
            }
        }
    }

    /// 1-based jump number among today's needs, first nine only.
    private func number(of item: ReminderSnapshot) -> Int? {
        guard ui.commandHeld else { return nil }
        guard let index = inbox.firstIndex(where: { $0.id == item.id }), index < 9 else { return nil }
        return index + 1
    }

    /// Row ids are namespaced per shelf: the same need id in two shelves
    /// would make the lazy stack reuse the old row after a move.
    private func rowID(_ id: String) -> String {
        if model.inbox.contains(where: { $0.id == id }) { return "inbox-\(id)" }
        if model.snoozed.contains(where: { $0.id == id }) { return "snoozed-\(id)" }
        return "settled-\(id)"
    }
}

// MARK: - Rows

/// Inbox card: just the title. Nothing competes for attention; actions
/// appear on hover at the trailing edge.
struct NeedCard: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let snapshot: ReminderSnapshot
    let number: Int?

    private var isSelected: Bool { ui.selection == .need(snapshot.id) }
    private var hovering: Bool { ui.hoveredID == snapshot.id }
    private var editing: Bool { ui.titleEdit == .init(id: snapshot.id, place: .sidebar) }

    var body: some View {
        // Fixed height fitting the 2-line title cap: hover must never
        // change a row's height (the list would jump under the cursor).
        if editing {
            TitleEditor(snapshot: snapshot, place: .sidebar)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 54)
                .background(rowBackground(isSelected: isSelected, hovering: false), in: RoundedRectangle(cornerRadius: Theme.radius))
        } else {
            Text(snapshot.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.sidebarText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 54)
                .background(rowBackground(isSelected: isSelected, hovering: hovering), in: RoundedRectangle(cornerRadius: Theme.radius))
                // Actions float over the title instead of squeezing it (the
                // row never changes height or reflows under the cursor).
                .overlay(alignment: .trailing) {
                    if hovering {
                        HoverActions(snapshot: snapshot, placement: .inbox)
                            .padding(.trailing, 4)
                    }
                }
                .zIndex(hovering ? 1 : 0)
                .modifier(RowInteraction(snapshot: snapshot))
                .overlay(alignment: .trailing) { JumpBadge(number: number) }
        }
    }
}

/// 36pt compact row for snoozed/settled needs: title only, hover actions.
struct NeedRow: View {
    enum Placement { case snoozed, settled }

    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let snapshot: ReminderSnapshot
    let placement: Placement

    private var isSelected: Bool { ui.selection == .need(snapshot.id) }
    private var hovering: Bool { ui.hoveredID == snapshot.id }
    private var editing: Bool { ui.titleEdit == .init(id: snapshot.id, place: .sidebar) }

    var body: some View {
        if editing {
            TitleEditor(snapshot: snapshot, place: .sidebar)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(height: Theme.rowHeight)
                .background(rowBackground(isSelected: isSelected, hovering: false), in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        } else {
            Text(snapshot.title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.sidebarMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: Theme.rowHeight)
                .background(rowBackground(isSelected: isSelected, hovering: hovering), in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(alignment: .trailing) {
                    if hovering {
                        HoverActions(snapshot: snapshot, placement: placement == .snoozed ? .snoozed : .settled)
                            .padding(.trailing, 4)
                    }
                }
                .zIndex(hovering ? 1 : 0)
                .modifier(RowInteraction(snapshot: snapshot))
        }
    }
}

/// Click opens, double-click edits the title in place, right-click menus.
private struct RowInteraction: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let snapshot: ReminderSnapshot

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { ui.titleEdit = .init(id: snapshot.id, place: .sidebar) }
            .onTapGesture { ui.open(.need(snapshot.id), model: model) }
            .onHover { ui.setHover(snapshot.id, $0) }
            .contextMenu { NeedActionMenu(snapshot: snapshot) { ui.titleEdit = .init(id: snapshot.id, place: .sidebar) } }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(snapshot.title)
            .accessibilityAddTraits(.isButton)
    }
}

struct DraftRow: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let draft: NeedDraft

    private var isSelected: Bool { ui.selection == .draft(draft.id) }
    private var hovering: Bool { ui.hoveredID == draft.id.uuidString }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.line")
                .font(.system(size: 11))
                .foregroundStyle(Theme.sidebarMuted)
            Text(draft.title.isEmpty ? "New need" : draft.title)
                .font(.system(size: 13))
                .italic()
                .foregroundStyle(Theme.sidebarMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering {
                Button {
                    if ui.activeDraft?.id == draft.id { ui.activeDraft = nil }
                    model.discard(draft)
                    if isSelected { ui.selection = nil }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(SidebarIconButtonStyle())
                .tooltip("Discard draft")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.rowHeight)
        .background(rowBackground(isSelected: isSelected, hovering: hovering), in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .contentShape(Rectangle())
        .onTapGesture { ui.open(.draft(draft.id), model: model) }
        .onHover { ui.setHover(draft.id.uuidString, $0) }
    }
}

private func rowBackground(isSelected: Bool, hovering: Bool) -> Color {
    isSelected ? Theme.sidebarSelected : hovering ? Theme.sidebarHover : .clear
}

struct JumpBadge: View {
    let number: Int?
    var body: some View {
        if let number {
            Text("⌘\(number)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.sidebarText)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.sidebarHover, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border))
                .padding(.trailing, 8)
        }
    }
}

struct SidebarIconButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Theme.sidebarText : Theme.sidebarMuted)
            .frame(width: 26, height: 26)
            .background(hovering ? Theme.sidebarHover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// "All lists ▾" — checkmark menu over Reminders lists (T3's project filter).
struct ListFilterMenu: View {
    @Environment(AppModel.self) private var model

    private var label: String {
        guard let selected = model.selectedListIDs else { return "All lists" }
        let titles = model.listOptions.filter { selected.contains($0.id) }.map(\.title)
        return titles.count == 1 ? titles[0] : "\(titles.count) lists"
    }

    var body: some View {
        Menu {
            Button {
                model.selectedListIDs = nil
            } label: {
                if model.selectedListIDs == nil { Label("All lists", systemImage: "checkmark") } else { Text("All lists") }
            }
            Divider()
            ForEach(model.listOptions) { list in
                Button {
                    model.toggleList(list.id)
                } label: {
                    if model.selectedListIDs?.contains(list.id) == true {
                        Label(list.title, systemImage: "checkmark")
                    } else {
                        Text(list.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tray.2")
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Theme.sidebarMuted)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Filter lists")
    }
}

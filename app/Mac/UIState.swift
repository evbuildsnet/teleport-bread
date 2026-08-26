import AppKit
import Foundation
import InboxCore
import Observation
import SwiftUI

/// What the main pane shows.
enum Selection: Hashable {
    case need(String)
    case draft(UUID)

    var needID: String? {
        if case .need(let id) = self { return id }
        return nil
    }
}

/// Window-level UI state: selection, sidebar, shelves, palette. Persisted
/// bits mirror T3 Code (sidebar width, shelf expansion).
@MainActor
@Observable
final class UIState {
    var selection: Selection?
    /// Draft currently open in the hero composer. Lives here until it is
    /// sent (→ need) or abandoned (→ model.stash / discard).
    var activeDraft: NeedDraft?

    var sidebarVisible = true
    var sidebarWidth: CGFloat {
        didSet { UserDefaults.standard.set(sidebarWidth, forKey: "sidebarWidth") }
    }
    /// Deliberately not persisted: a triage surface starts each session
    /// with the snoozed shelf out of sight (matches mobile).
    var snoozedExpanded = false
    var settledExpanded: Bool {
        didSet { UserDefaults.standard.set(settledExpanded, forKey: "settledExpanded") }
    }
    var settledShown = UIState.settledInitialCount
    var paletteOpen = false {
        didSet {
            guard paletteOpen else { return }
            paletteQuery = ""
            paletteHighlighted = 0
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
    var paletteQuery = ""
    var paletteHighlighted = 0
    /// ⌘ held: rows show their jump numbers.
    var commandHeld = false
    /// Event monitors are process-wide; never install twice.
    var monitorsInstalled = false
    /// Exactly one sidebar row can be hovered; cleared whenever the list
    /// shifts under a stationary cursor (onHover doesn't fire then).
    var hoveredID: String?
    /// Bumped to ask the thread composer to take focus (printable-key typing).
    var composerFocusRequest = 0
    var composerSeed = ""

    /// While a row's popover is open the cursor leaves the row; keep its
    /// hover (and the button the popover hangs off) alive until it closes.
    var hoverLockID: String?
    /// The one tooltip on screen, drawn by `TooltipLayer` at the window root.
    var tooltip: TooltipState?

    /// Row snooze menu, drawn in-window by `SnoozeMenuLayer` beside its
    /// button — no popover window to spin up, no animation. While open the
    /// row stays hovered (the cursor leaves it to reach the menu).
    struct SnoozeMenu: Equatable {
        var id: String
        var anchor: CGRect
    }
    var snoozeMenu: SnoozeMenu? {
        didSet {
            hoverLockID = snoozeMenu?.id
            if snoozeMenu != nil { NSApp.keyWindow?.makeFirstResponder(nil) } else { hoveredID = nil }
        }
    }

    // MARK: Modes that change what keys mean

    /// A need title being edited inline — in its sidebar row or the top bar.
    struct TitleEdit: Equatable {
        enum Place { case sidebar, topBar }
        var id: String
        var place: Place
    }
    var titleEdit: TitleEdit? {
        didSet { if titleEdit != nil { NSApp.keyWindow?.makeFirstResponder(nil) } }
    }
    /// Text handed back to the next editor after a failed save.
    var titleEditRestore: String?
    /// Sidebar search field has keyboard focus.
    var searchFocused = false
    /// The thread composer is editing an existing note.
    var noteEditing = false

    /// The main window, so key events from Settings are never dispatched.
    weak var window: NSWindow?

    /// What the keyboard is currently "in". SwiftUI focus state plus AppKit's
    /// own view of it: a single-line field holding the field editor that is
    /// not the title editor or the palette can only be the search field.
    func keyContext(in model: AppModel) -> KeyContext {
        var context: KeyContext = []
        if paletteOpen { context.insert(.palette) }
        if titleEdit != nil { context.insert(.titleEdit) }
        if noteEditing { context.insert(.noteEdit) }
        if model.isSearching || searchFocused || (context.isEmpty && textFieldFocused) { context.insert(.search) }
        return context
    }

    private var textFieldFocused: Bool {
        (window?.firstResponder as? NSTextView)?.delegate is NSTextField
    }

    func isAvailable(_ command: KeyCommand, in model: AppModel) -> Bool {
        KeyBindings.binding(for: command, Shortcuts.shared).blockedIn.isDisjoint(with: keyContext(in: model))
    }

    /// Every command runs through here — from a key or a menu click — so the
    /// context rules apply to both.
    func perform(_ command: KeyCommand, model: AppModel) {
        guard isAvailable(command, in: model) else { return }
        switch command {
        case .action(.newNeed): newDraft(model: model)
        case .action(.palette): paletteOpen.toggle()
        case .action(.previousNeed): selectNeighbor(-1, in: model)
        case .action(.nextNeed): selectNeighbor(1, in: model)
        case .action(.toggleSidebar): withAnimation(.snappy(duration: 0.2)) { sidebarVisible.toggle() }
        case .jump(let number): jump(to: number, in: model)
        }
    }

    func setHover(_ id: String, _ inside: Bool) {
        if inside { hoveredID = id } else if hoveredID == id, hoverLockID != id { hoveredID = nil }
    }

    /// Deliberately taller first page than iOS's 5 — desktop screen.
    static let settledInitialCount = 10
    static let settledPageCount = 25

    init() {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: "sidebarWidth")
        sidebarWidth = width >= Theme.sidebarMinWidth ? width : Theme.sidebarDefaultWidth
        settledExpanded = defaults.object(forKey: "settledExpanded") as? Bool ?? true
    }

    // MARK: Navigation over the rendered order

    /// Needs currently rendered in the sidebar, top to bottom. Collapsed
    /// shelves and unpaged settled rows don't participate (T3 behaviour).
    func renderedNeeds(_ model: AppModel) -> [ReminderSnapshot] {
        var rows = model.visibleInbox
        if snoozedExpanded || model.isSearching {
            rows += model.visibleSnoozed
        }
        if settledExpanded || model.isSearching {
            rows += model.visibleSettled.prefix(settledShown)
        }
        return rows
    }

    func selectNeighbor(_ offset: Int, in model: AppModel) {
        let rows = renderedNeeds(model)
        guard !rows.isEmpty else { return }
        guard let current = selection?.needID, let index = rows.firstIndex(where: { $0.id == current }) else {
            open(.need(offset > 0 ? rows[0].id : rows[rows.count - 1].id), model: model)
            return
        }
        let next = index + offset
        guard rows.indices.contains(next) else { return }
        open(.need(rows[next].id), model: model)
    }

    /// ⌘1…⌘9 index today's needs only (the inbox), never the shelves.
    func jump(to number: Int, in model: AppModel) {
        let rows = model.inbox
        guard rows.indices.contains(number - 1) else { return }
        open(.need(rows[number - 1].id), model: model)
    }

    /// After settling/snoozing the open need, land on the next remaining
    /// inbox need (T3: "navigates to the next remaining active card").
    func selectionAfterRemoving(_ id: String, in model: AppModel) -> Selection? {
        let inbox = model.visibleInbox
        guard let index = inbox.firstIndex(where: { $0.id == id }) else { return selection }
        let remaining = inbox.filter { $0.id != id }
        guard !remaining.isEmpty else { return nil }
        return .need(remaining[min(index, remaining.count - 1)].id)
    }

    // MARK: Selection changes keep drafts honest

    func open(_ target: Selection?, model: AppModel) {
        if hoverLockID == nil { hoveredID = nil }
        if target != selection, let draft = activeDraft, case .draft(draft.id) = selection {
            // Leaving the hero: keep non-empty work as a sidebar draft.
            model.stash(draft)
            activeDraft = nil
        }
        if case .draft(let id)? = target, activeDraft?.id != id,
           let stashed = model.drafts.first(where: { $0.id == id }) {
            activeDraft = stashed
        }
        selection = target
    }

    func newDraft(model: AppModel) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        if let draft = activeDraft, case .draft(draft.id) = selection, draft.title.isEmpty {
            return // already on an empty hero
        }
        let draft = model.newDraft()
        open(.draft(draft.id), model: model)
        activeDraft = draft
    }
}

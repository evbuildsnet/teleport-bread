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
    var snoozedExpanded: Bool {
        didSet { UserDefaults.standard.set(snoozedExpanded, forKey: "snoozedExpanded") }
    }
    var settledExpanded: Bool {
        didSet { UserDefaults.standard.set(settledExpanded, forKey: "settledExpanded") }
    }
    var settledShown = UIState.settledInitialCount
    var paletteOpen = false
    /// ⌘ held: rows show their jump numbers.
    var commandHeld = false
    /// Bumped to ask the thread composer to take focus (printable-key typing).
    var composerFocusRequest = 0
    var composerSeed = ""

    static let settledInitialCount = 10
    static let settledPageCount = 25

    init() {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: "sidebarWidth")
        sidebarWidth = width >= Theme.sidebarMinWidth ? width : Theme.sidebarDefaultWidth
        snoozedExpanded = defaults.object(forKey: "snoozedExpanded") as? Bool ?? false
        settledExpanded = defaults.object(forKey: "settledExpanded") as? Bool ?? true
    }

    // MARK: Navigation over the rendered order

    /// Needs currently rendered in the sidebar, top to bottom. Collapsed
    /// shelves and unpaged settled rows don't participate (T3 behaviour).
    func renderedNeeds(_ model: AppModel) -> [ReminderSnapshot] {
        var rows = model.inbox.filter(model.matchesSearch)
        if snoozedExpanded || model.isSearching {
            rows += model.snoozed.filter(model.matchesSearch)
        }
        if settledExpanded || model.isSearching {
            rows += model.settled.filter(model.matchesSearch).prefix(settledShown)
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

    func jump(to number: Int, in model: AppModel) {
        let rows = renderedNeeds(model)
        guard rows.indices.contains(number - 1) else { return }
        open(.need(rows[number - 1].id), model: model)
    }

    /// After settling/snoozing the open need, land on the next remaining
    /// inbox need (T3: "navigates to the next remaining active card").
    func selectionAfterRemoving(_ id: String, in model: AppModel) -> Selection? {
        let inbox = model.inbox.filter(model.matchesSearch)
        guard let index = inbox.firstIndex(where: { $0.id == id }) else { return selection }
        let remaining = inbox.filter { $0.id != id }
        guard !remaining.isEmpty else { return nil }
        return .need(remaining[min(index, remaining.count - 1)].id)
    }

    // MARK: Selection changes keep drafts honest

    func open(_ target: Selection?, model: AppModel) {
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
        if let draft = activeDraft, case .draft(draft.id) = selection, draft.title.isEmpty {
            return // already on an empty hero
        }
        let draft = model.newDraft()
        open(.draft(draft.id), model: model)
        activeDraft = draft
    }
}

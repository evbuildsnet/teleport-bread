import Foundation
import InboxCore
import Observation

/// A need being composed. Lives only in memory; no reminder exists until sent.
struct NeedDraft: Identifiable, Hashable {
    let id: UUID
    var title: String
    var listID: String?
}

@MainActor
@Observable
final class AppModel {
    enum Phase { case loading, needsAccess, denied, ready }

    private let source: any NeedSource
    private let engine = InboxEngine()

    init(source: any NeedSource = EventKitSource()) {
        self.source = source
    }

    var phase: Phase = .loading
    var inbox: [ReminderSnapshot] = []
    var snoozed: [ReminderSnapshot] = []
    var settled: [ReminderSnapshot] = []
    var drafts: [NeedDraft] = []
    var searchText = ""
    /// Bumped on every successful triage action; drives haptic feedback.
    private(set) var triageCount = 0

    /// nil = all lists. Persisted per device.
    var selectedListIDs: Set<String>? {
        didSet { persistSelection() }
    }

    var listOptions: [ListOption] { source.lists }

    var defaultListID: String? { source.defaultListID }

    private var changeTask: Task<Void, Never>?
    private var dayObserver: (any NSObjectProtocol)?
    private var started = false

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        if source.isAuthorized {
            phase = .ready
        } else {
            phase = .needsAccess
            phase = await source.requestAccess() ? .ready : .denied
        }
        guard phase == .ready else { return }

        restoreSelection()
        await refresh()

        // Refresh when the source changes underneath us, and on day rollover
        // (an item due "Today" becomes overdue at midnight without any store
        // change).
        changeTask = Task { [weak self] in
            guard let changes = self?.source.changes else { return }
            for await _ in changes {
                await self?.refresh()
            }
        }
        dayObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    // MARK: Data

    private var activeRefresh: Task<Void, Never>?
    private var refreshQueued = false

    /// Coalesced: one fetch pass in flight at a time. A request arriving
    /// mid-run (our own post-write refresh racing a source change signal)
    /// queues exactly one follow-up pass instead of interleaving, so a stale
    /// fetch can never overwrite a fresher one.
    func refresh() async {
        guard phase == .ready else { return }
        if let activeRefresh {
            refreshQueued = true
            await activeRefresh.value
            return
        }
        let task = Task { await performRefresh() }
        activeRefresh = task
        await task.value
        activeRefresh = nil
        if refreshQueued {
            refreshQueued = false
            await refresh()
        }
    }

    private func performRefresh() async {
        let filter = activeListFilter()
        let sections = engine.sections(from: await source.fetchIncomplete(inLists: filter), today: .now)
        inbox = sections.inbox
        snoozed = sections.snoozed

        let recent = Calendar.current.date(byAdding: .day, value: -14, to: .now)!
        settled = await source.fetchCompleted(after: recent, inLists: filter)
            .filter { $0.dueDate != nil }
            .sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
    }

    /// nil = all lists. Stale persisted IDs (deleted lists) fall back to all.
    private func activeListFilter() -> Set<String>? {
        guard let selectedListIDs else { return nil }
        let known = selectedListIDs.intersection(source.lists.map(\.id))
        return known.isEmpty ? nil : known
    }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    func matchesSearch(_ snapshot: ReminderSnapshot) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return snapshot.title.localizedCaseInsensitiveContains(query)
            || (snapshot.note?.localizedCaseInsensitiveContains(query) ?? false)
    }

    func matchesSearch(_ draft: NeedDraft) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || draft.title.localizedCaseInsensitiveContains(query)
    }

    func snapshot(id: String) -> ReminderSnapshot? {
        inbox.first { $0.id == id }
            ?? snoozed.first { $0.id == id }
            ?? settled.first { $0.id == id }
    }

    // MARK: Triage

    func settle(_ snapshot: ReminderSnapshot) async {
        guard (try? await source.settle(id: snapshot.id)) != nil else { return }
        triageCount += 1
        await refresh()
    }

    func snooze(_ snapshot: ReminderSnapshot, _ preset: SnoozePreset) async {
        await snooze(snapshot, until: engine.snoozeDate(preset, from: .now))
    }

    /// Moves the need to the given day and makes it active (reopens settled).
    func snooze(_ snapshot: ReminderSnapshot, until date: Date) async {
        let day = Calendar.current.startOfDay(for: date)
        guard (try? await source.snooze(id: snapshot.id, to: day)) != nil else { return }
        triageCount += 1
        await refresh()
    }

    /// Wake = bring a snoozed need back to today.
    func wake(_ snapshot: ReminderSnapshot) async {
        await snooze(snapshot, until: .now)
    }

    func unsettle(_ snapshot: ReminderSnapshot) async {
        guard (try? await source.unsettle(id: snapshot.id)) != nil else { return }
        triageCount += 1
        await refresh()
    }

    /// Returns false when the write failed so the UI can hand the text back —
    /// a user's message must never be silently lost.
    func append(_ message: String, to snapshot: ReminderSnapshot) async -> Bool {
        do {
            try await source.appendMessage(id: snapshot.id, message: message)
        } catch {
            return false
        }
        await refresh()
        return true
    }

    /// Edit title and/or list from the compose sheet in edit mode.
    /// Returns false when the write failed so the edit isn't silently dropped.
    @discardableResult
    func update(_ snapshot: ReminderSnapshot, title: String, listID: String?) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try await source.update(id: snapshot.id, title: trimmed, listID: listID)
        } catch {
            return false
        }
        await refresh()
        return true
    }

    /// Explicit history edits, requested by the user via long-press.
    func replaceMessage(at index: Int, with text: String, in snapshot: ReminderSnapshot) async {
        var messages = snapshot.messages
        guard messages.indices.contains(index) else { return }
        messages[index] = text
        await setMessages(messages, in: snapshot)
    }

    func deleteMessage(at index: Int, in snapshot: ReminderSnapshot) async {
        var messages = snapshot.messages
        guard messages.indices.contains(index) else { return }
        messages.remove(at: index)
        await setMessages(messages, in: snapshot)
    }

    private func setMessages(_ messages: [String], in snapshot: ReminderSnapshot) async {
        try? await source.setNote(id: snapshot.id, note: NoteCodec.join(messages))
        await refresh()
    }

    // MARK: Drafts & capture

    /// New drafts go to the last list used on this device, falling back to
    /// the default (or first) list if that one no longer exists.
    func newDraft() -> NeedDraft {
        let options = listOptions
        let remembered = UserDefaults.standard.string(forKey: Self.lastListKey)
        let listID = options.first { $0.id == remembered }?.id
            ?? options.first { $0.id == defaultListID }?.id
            ?? options.first?.id
        return NeedDraft(id: UUID(), title: "", listID: listID)
    }

    private static let lastListKey = "lastListID"

    /// Called when the compose sheet is swiped away: keep the work in memory.
    func stash(_ draft: NeedDraft) {
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            discard(draft)
            return
        }
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.insert(draft, at: 0)
        }
    }

    func discard(_ draft: NeedDraft) {
        drafts.removeAll { $0.id == draft.id }
    }

    /// Creates the need. Capture always sets a due date (today) so it is
    /// immediately visible; undated needs are invisible by design.
    /// The draft is only discarded once the write succeeds — on failure it is
    /// stashed into Drafts, so the user's text is never silently lost.
    @discardableResult
    func send(_ draft: NeedDraft) async -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        UserDefaults.standard.set(draft.listID, forKey: Self.lastListKey)
        // Fall back to a list the active filter can actually show.
        let known = Set(source.lists.map(\.id))
        let target = draft.listID.flatMap { known.contains($0) ? $0 : nil }
            ?? activeListFilter()?.first
        do {
            try await source.create(title: title, note: nil, due: .now, inList: target)
        } catch {
            stash(draft)
            return false
        }
        discard(draft)
        await refresh()
        return true
    }

    // MARK: List selection persistence

    private static let selectionKey = "selectedListIDs"

    private func persistSelection() {
        if let selectedListIDs {
            UserDefaults.standard.set(Array(selectedListIDs), forKey: Self.selectionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectionKey)
        }
    }

    private func restoreSelection() {
        guard let stored = UserDefaults.standard.stringArray(forKey: Self.selectionKey) else { return }
        selectedListIDs = Set(stored)
    }

    // MARK: Preview support

    static func preview() -> AppModel {
        let day: (Int) -> Date = { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: .now))! }
        let lists = [
            ListOption(id: "reminders", title: "Reminders", colorHex: "#3B82F6"),
            ListOption(id: "tripleseat", title: "tripleseat", colorHex: "#EC4899"),
            ListOption(id: "t3", title: "T3", colorHex: "#6366F1"),
        ]
        func item(_ id: String, _ title: String, list: ListOption = lists[0],
                  due: Int, note: String? = nil, done: Bool = false) -> ReminderSnapshot {
            ReminderSnapshot(
                id: id, listID: list.id, listTitle: list.title, listColorHex: list.colorHex, title: title,
                dueDate: day(due), isCompleted: done, completionDate: done ? day(0) : nil,
                creationDate: day(-5), note: note
            )
        }
        let source = InMemorySource(seed: [
            item("1", "Reply to Alisher about admin roles", due: -2,
                 note: NoteCodec.append("He pinged again on Slack.", to: NoteCodec.append("Waiting on the role matrix.", to: nil))),
            item("2", "Update CV after Macy's", due: -1),
            item("3", "Review meal location association order", list: lists[1], due: 0,
                 note: "Check the sort order regression first."),
            item("4", "Book dentist", due: 0),
            item("5", "Prepare tab extension for team", list: lists[2], due: 2),
            item("6", "Renew passport", due: 6, note: "Photos are already done."),
            item("7", "Assess Microsoft Keycloak login", due: -1, done: true),
            item("8", "Use Tailscale alias in artifacts", due: 0, done: true),
        ], lists: lists)
        let model = AppModel(source: source)
        model.drafts = [NeedDraft(id: UUID(), title: "Ask about the Keycloak migration window", listID: "reminders")]
        // Canvases don't go through start(): mark ready and load synchronously
        // soon after; mutations then run the same code path as production.
        model.phase = .ready
        Task { @MainActor in await model.refresh() }
        return model
    }
}

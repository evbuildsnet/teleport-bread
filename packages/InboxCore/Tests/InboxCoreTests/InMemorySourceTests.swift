import Foundation
import Testing
@testable import InboxCore

@MainActor
struct InMemorySourceTests {
    static let lists = [
        ListOption(id: "a", title: "A", colorHex: "#112233"),
        ListOption(id: "b", title: "B"),
    ]

    static func item(
        _ id: String, list: ListOption = lists[0], due: Date? = .now,
        done: Bool = false, note: String? = nil
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            id: id, listID: list.id, listTitle: list.title, listColorHex: list.colorHex,
            title: "Need \(id)", dueDate: due, isCompleted: done,
            completionDate: done ? .now : nil, note: note
        )
    }

    @Test func settleSetsCompletionDate() async throws {
        let source = InMemorySource(seed: [Self.item("1")], lists: Self.lists)
        try await source.settle(id: "1")
        let settled = await source.fetchCompleted(after: .distantPast, inLists: nil)
        #expect(settled.count == 1)
        #expect(settled[0].isCompleted)
        #expect(settled[0].completionDate != nil)
        #expect(await source.fetchIncomplete(inLists: nil).isEmpty)
    }

    @Test func snoozeNormalizesToStartOfDayAndReactivates() async throws {
        let source = InMemorySource(seed: [Self.item("1", done: true)], lists: Self.lists)
        let target = Calendar.current.date(byAdding: .day, value: 3, to: .now)!
        try await source.snooze(id: "1", to: target)
        let active = await source.fetchIncomplete(inLists: nil)
        #expect(active.count == 1)
        #expect(active[0].dueDate == Calendar.current.startOfDay(for: target))
        #expect(!active[0].isCompleted)
        #expect(active[0].completionDate == nil)
    }

    @Test func appendStripsSeparatorAndBuildsLog() async throws {
        let source = InMemorySource(seed: [Self.item("1", note: "first")], lists: Self.lists)
        try await source.appendMessage(id: "1", message: "sec\u{2063}ond")
        let item = await source.fetchIncomplete(inLists: nil)[0]
        #expect(item.messages == ["first", "second"])
    }

    @Test func createUsesDefaultListAndStartOfDay() async throws {
        let source = InMemorySource(lists: Self.lists)
        let made = try await source.create(title: "New", note: nil, due: .now, inList: nil)
        #expect(made.listID == "a")
        #expect(made.dueDate == Calendar.current.startOfDay(for: .now))
        #expect(await source.fetchIncomplete(inLists: nil).count == 1)
    }

    @Test func createWithoutListsThrows() async {
        let source = InMemorySource()
        await #expect(throws: NeedSourceError.self) {
            try await source.create(title: "New", note: nil, due: .now, inList: nil)
        }
    }

    @Test func fetchFiltersByList() async throws {
        let source = InMemorySource(
            seed: [Self.item("1"), Self.item("2", list: Self.lists[1])],
            lists: Self.lists
        )
        let onlyB = await source.fetchIncomplete(inLists: ["b"])
        #expect(onlyB.map(\.id) == ["2"])
    }

    @Test func updateMovesBetweenLists() async throws {
        let source = InMemorySource(seed: [Self.item("1")], lists: Self.lists)
        try await source.update(id: "1", title: "Renamed", listID: "b")
        let item = await source.fetchIncomplete(inLists: nil)[0]
        #expect(item.title == "Renamed")
        #expect(item.listID == "b")
        #expect(item.listTitle == "B")
    }

    @Test func mutatingMissingIDThrowsNotFound() async {
        let source = InMemorySource(lists: Self.lists)
        await #expect(throws: NeedSourceError.self) {
            try await source.settle(id: "ghost")
        }
    }
}

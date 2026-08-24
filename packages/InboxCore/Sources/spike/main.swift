import EventKit
import Foundation
import InboxCore

// Phase 0 spike. Verifies against the real Reminders store:
//   1. Full-access request works from a CLI binary.
//   2. A date-only due date roundtrips cleanly.
//   3. A NoteCodec log (U+2063 separators) roundtrips through EventKit.
// Leaves a "InboxZero Spike" list behind for manual iCloud/iPhone checks.

let spikeListName = "InboxZero Spike"
let logPath = "/tmp/inboxzero-spike.log"

func print(_ message: String) {
    Swift.print(message)
    let line = message + "\n"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

/// Read-only mode: parse every reminder in the spike list and make the
/// separator visible, without creating anything.
@MainActor
func check() async {
    let source = EventKitSource()
    guard await source.requestAccess() else {
        print("FAIL access: not granted")
        exit(1)
    }
    guard let list = source.lists.first(where: { $0.title == spikeListName }) else {
        print("FAIL check: list '\(spikeListName)' not found")
        exit(1)
    }
    let reminders = await source.fetchIncomplete(inLists: [list.id])
    for reminder in reminders {
        print("reminder: \(reminder.title)")
        let messages = reminder.messages
        print("messages: \(messages.count)")
        for (index, message) in messages.enumerated() {
            print("  [\(index)] \(message.replacingOccurrences(of: "\n", with: "\\n"))")
        }
        let visible = (reminder.note ?? "")
            .replacingOccurrences(of: String(NoteCodec.invisibleSeparator), with: "<SEP>")
            .replacingOccurrences(of: "\n", with: "\\n")
        print("raw: \(visible)")
    }
    print("CHECK DONE (\(reminders.count) reminders)")
    exit(0)
}

/// List creation is raw-EventKit setup tooling, deliberately outside the
/// NeedSource surface. Runs before the EventKitSource under test is made so
/// the fresh instance sees the list.
@MainActor
func ensureSpikeList() async -> String {
    let store = EKEventStore()
    do {
        guard try await store.requestFullAccessToReminders() else {
            print("FAIL access: not granted")
            exit(1)
        }
        print("OK access granted")
    } catch {
        print("FAIL access: \(error)")
        exit(1)
    }

    if let existing = store.calendars(for: .reminder).first(where: { $0.title == spikeListName }) {
        print("OK reusing list \(spikeListName)")
        return existing.calendarIdentifier
    }
    let calendar = EKCalendar(for: .reminder, eventStore: store)
    calendar.title = spikeListName
    guard let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first
    else {
        print("FAIL no reminder source available")
        exit(1)
    }
    calendar.source = source
    do {
        try store.saveCalendar(calendar, commit: true)
        print("OK created list \(spikeListName) in source \(source.title)")
    } catch {
        print("FAIL creating list: \(error)")
        exit(1)
    }
    return calendar.calendarIdentifier
}

@MainActor
func run() async {
    if CommandLine.arguments.contains("--check") {
        await check()
        return
    }
    let spikeListID = await ensureSpikeList()

    let source = EventKitSource()
    print("Lists visible: \(source.lists.map(\.title).joined(separator: ", "))")

    // Create a reminder with a date-only due date and a two-message log.
    let stamp = ISO8601DateFormatter().string(from: .now)
    let note = NoteCodec.append(
        "Second message appended at \(stamp).",
        to: NoteCodec.append("First message. Should read as its own paragraph.", to: nil)
    )
    let snapshot: ReminderSnapshot
    do {
        snapshot = try await source.create(
            title: "Spike \(stamp)",
            note: note,
            due: .now,
            inList: spikeListID
        )
        print("OK created reminder \(snapshot.id)")
    } catch {
        print("FAIL creating reminder: \(error)")
        exit(1)
    }

    // Read back through a fresh fetch and verify.
    let fetched = await source.fetchIncomplete(inLists: [spikeListID])
    guard let roundtrip = fetched.first(where: { $0.id == snapshot.id }) else {
        print("FAIL roundtrip: created reminder not returned by incomplete fetch")
        exit(1)
    }

    let messages = roundtrip.messages
    if messages.count == 2 {
        print("OK note log roundtrip: \(messages.count) messages")
    } else {
        print("FAIL note log roundtrip: expected 2 messages, got \(messages.count)")
        print("raw note: \(roundtrip.note ?? "<nil>")")
        exit(1)
    }

    if let due = roundtrip.dueDate {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: due)
        print("OK due date roundtrip: \(due) (h=\(comps.hour ?? -1) m=\(comps.minute ?? -1))")
    } else {
        print("FAIL due date roundtrip: nil")
        exit(1)
    }

    print("SPIKE PASSED — check '\(spikeListName)' in the native Reminders app")
    exit(0)
}

Task { await run() }
RunLoop.main.run()

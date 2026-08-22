import Foundation
import Testing
@testable import InboxCore

@Suite struct NoteCodecTests {
    @Test func emptyAndNilNotesParseToNoMessages() {
        #expect(NoteCodec.parse(nil).isEmpty)
        #expect(NoteCodec.parse("").isEmpty)
    }

    @Test func plainNoteIsSingleMessage() {
        #expect(NoteCodec.parse("buy milk") == ["buy milk"])
    }

    @Test func userTypedBlankLinesDoNotSplit() {
        let note = "first paragraph\n\nsecond paragraph\n\n\nthird"
        #expect(NoteCodec.parse(note) == [note])
    }

    @Test func appendToEmptyNoteHasNoSeparator() {
        let note = NoteCodec.append("hello", to: nil)
        #expect(note == "hello")
        #expect(NoteCodec.parse(note) == ["hello"])
    }

    @Test func appendRoundtrips() {
        var note: String? = nil
        for message in ["one", "two\nwith a newline", "three\n\nwith a blank line"] {
            note = NoteCodec.append(message, to: note)
        }
        #expect(NoteCodec.parse(note) == ["one", "two\nwith a newline", "three\n\nwith a blank line"])
    }

    @Test func appendedMessageCannotForgeBoundary() {
        let hostile = "before\(NoteCodec.separator)after"
        let note = NoteCodec.append(hostile, to: "existing")
        let messages = NoteCodec.parse(note)
        #expect(messages.count == 2)
        #expect(messages[0] == "existing")
        // The invisible character is stripped; the visible text survives.
        #expect(messages[1] == "before\n\nafter")
    }

    @Test func joinRoundtripsAndStripsForgedMarkers() {
        let messages = ["one", "two\nlines", "three\(NoteCodec.separator)forged"]
        let note = NoteCodec.join(messages)
        #expect(NoteCodec.parse(note) == ["one", "two\nlines", "three\n\nforged"])
        #expect(NoteCodec.join([]) == nil)
    }

    @Test func separatorRendersAsBlankLineWithoutMarker() {
        // What the native app shows if U+2063 were stripped: still a paragraph break.
        let note = NoteCodec.append("b", to: "a")
        let degraded = note.replacingOccurrences(
            of: String(NoteCodec.invisibleSeparator), with: ""
        )
        #expect(degraded == "a\n\nb")
        // Lenient parse of degraded content: one message, nothing lost.
        #expect(NoteCodec.parse(degraded) == [degraded])
    }
}

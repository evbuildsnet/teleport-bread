import Testing
@testable import InboxCore

struct TriageActionTests {
    @Test func primaryVerbPerState() {
        #expect(TriageAction.primary(for: .inbox) == .settle)
        #expect(TriageAction.primary(for: .snoozed) == .wake)
        #expect(TriageAction.primary(for: .settled) == .unsettle)
    }

    @Test func snoozeMenuListsAllPresetsThenPickDate() {
        #expect(TriageAction.snoozeMenu == SnoozePreset.allCases.map(TriageAction.snooze) + [.snoozePickDate])
        #expect(TriageAction.snoozeMenu.last == .snoozePickDate)
    }

    @Test func snoozeLabelsComeFromPresets() {
        for preset in SnoozePreset.allCases {
            #expect(TriageAction.snooze(preset).label == preset.label)
        }
    }
}

import InboxCore
import SwiftUI

/// New need: centered hero composer (T3's fresh-draft state). ⏎ creates the
/// need due today in the chosen list; list defaults to the last one used.
struct DraftHero: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var title = ""
    @FocusState private var focused: Bool

    private var selectedList: ListOption? {
        model.listOptions.first { $0.id == ui.activeDraft?.listID } ?? model.listOptions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(snapshot: nil)
            Spacer()
            VStack(spacing: 18) {
                Text("What needs doing?")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Composer(
                    text: $title,
                    placeholder: "A need, due today.",
                    focused: $focused,
                    footer: { listPicker },
                    sendSymbol: "paperplane.fill",
                    canSend: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onSend: send
                )
            }
            .frame(maxWidth: Theme.columnMaxWidth)
            .padding(.horizontal, 20)
            Spacer()
            Spacer()
        }
        .onAppear { title = ui.activeDraft?.title ?? "" }
        .task {
            // Focus after the first layout pass; an immediate request loses
            // to whatever field (e.g. sidebar search) held focus before.
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
        .onChange(of: title) { _, value in
            ui.activeDraft?.title = value.replacingOccurrences(of: "\n", with: " ")
        }
        .onChange(of: ui.composerFocusRequest) { _, _ in
            guard case .draft = ui.selection else { return }
            title += ui.composerSeed
            ui.composerSeed = ""
            focused = true
        }
    }

    @ViewBuilder private var listPicker: some View {
        if !model.listOptions.isEmpty {
            Menu {
                ForEach(model.listOptions) { option in
                    Button {
                        ui.activeDraft?.listID = option.id
                    } label: {
                        if option.id == selectedList?.id { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hexString: selectedList?.colorHex) ?? Theme.accent)
                        .frame(width: 7, height: 7)
                    Text(selectedList?.title ?? "")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Save to list")
        }
    }

    private func send() {
        guard var draft = ui.activeDraft else { return }
        draft.title = title.replacingOccurrences(of: "\n", with: " ")
        ui.activeDraft = nil
        ui.selection = nil
        Task {
            await model.send(draft)
            // Land on the new need: it's the newest in the inbox.
            if let created = model.inbox.first(where: { $0.title == draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                ui.selection = .need(created.id)
            }
        }
    }
}

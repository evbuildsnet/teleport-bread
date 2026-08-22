import InboxCore
import SwiftUI

/// The main surface: the need's note rendered as an append-only log.
/// History is read-only here; editing past messages happens in the native app.
struct ThreadView: View {
    @Environment(AppModel.self) private var model
    let reminderID: String

    @State private var draft = ""
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool
    @FocusState private var inputFocused: Bool

    private var snapshot: ReminderSnapshot? { model.snapshot(id: reminderID) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        titleField
                            .padding(.bottom, 8)

                        let messages = snapshot?.messages ?? []
                        if messages.isEmpty {
                            Text("No notes yet. Leave a thought for your future self.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            Text(message)
                                .textSelection(.enabled)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .onChange(of: snapshot?.messages.count ?? 0) { _, count in
                    guard count > 0 else { return }
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
                .onAppear {
                    titleDraft = snapshot?.title ?? ""
                    let count = snapshot?.messages.count ?? 0
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }

            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // Deliberately no Settle here: completing a need is only ever the
        // swipe gesture in the list, to build the habit.
    }

    /// The need's title, editable in place. Commits on return or when focus leaves.
    private var titleField: some View {
        TextField("Title", text: $titleDraft, axis: .vertical)
            .font(.title2.weight(.semibold))
            .lineLimit(1...3)
            .focused($titleFocused)
            .submitLabel(.done)
            .onSubmit(commitTitle)
            .onChange(of: titleFocused) { _, focused in
                if !focused { commitTitle() }
            }
            .onChange(of: snapshot?.title ?? "") { _, title in
                if !titleFocused { titleDraft = title }
            }
            .accessibilityLabel("Need title")
    }

    private func commitTitle() {
        guard let snapshot else { return }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            titleDraft = snapshot.title
            return
        }
        Task { await model.rename(snapshot, to: trimmed) }
    }

    /// Multiline composer with the send control anchored to the bottom edge.
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Message to your future self", text: $draft, axis: .vertical)
                .lineLimit(1...8)
                .focused($inputFocused)
            HStack {
                Spacer()
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(sanitizedDraft.isEmpty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint), in: Circle())
                        .foregroundStyle(sanitizedDraft.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                }
                .buttonStyle(.plain)
                .disabled(sanitizedDraft.isEmpty)
                .accessibilityLabel("Append message")
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// U+2063 is invisible and not in .whitespacesAndNewlines — without
    /// stripping it first, a pasted invisible-only draft would append a
    /// permanently empty message.
    private var sanitizedDraft: String {
        draft
            .replacingOccurrences(of: String(NoteCodec.invisibleSeparator), with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        guard let snapshot else { return }
        let message = sanitizedDraft
        guard !message.isEmpty else { return }
        draft = ""
        Task {
            if await !model.append(message, to: snapshot), draft.isEmpty {
                draft = message
            }
        }
    }
}

#Preview("Thread") {
    NavigationStack {
        ThreadView(reminderID: "1")
    }
    .environment(AppModel.preview())
}

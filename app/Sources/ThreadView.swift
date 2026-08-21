import InboxCore
import SwiftUI

/// The main surface: the reminder's note rendered as an append-only log.
/// History is read-only here; editing past messages happens in the native app.
struct ThreadView: View {
    @Environment(AppModel.self) private var model
    let reminderID: String

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var snapshot: ReminderSnapshot? { model.snapshot(id: reminderID) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
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
                    let count = snapshot?.messages.count ?? 0
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }

            inputBar
        }
        .navigationTitle(snapshot?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let snapshot, !snapshot.isCompleted {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.settle(snapshot) }
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityLabel("Settle")
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message to your future self", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(sanitizedDraft.isEmpty)
            .accessibilityLabel("Append message")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
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

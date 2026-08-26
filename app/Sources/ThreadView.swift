import InboxCore
import SwiftUI

/// The main surface: the need's note rendered as a log of messages.
/// Appending is the primary action; editing or deleting a past message is
/// available on long-press, by explicit user request.
struct ThreadView: View {
    @Environment(AppModel.self) private var model
    let reminderID: String

    @State private var composer = MessageComposer()
    @FocusState private var inputFocused: Bool

    // Title/list edit sheet (reuses the compose sheet in edit mode).
    @State private var editing = false
    @State private var editDraft = NeedDraft(id: UUID(), title: "", listID: nil)
    @State private var editOutcome: ComposeOutcome = .dismissed

    private var snapshot: ReminderSnapshot? { model.snapshot(id: reminderID) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Text(snapshot?.title ?? "")
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)

                        let messages = snapshot?.messages ?? []
                        if messages.isEmpty {
                            Text("Leave a thought for your future self.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            VStack(alignment: .trailing, spacing: 2) {
                                SelectableText(text: message)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        composer.editingIndex == index ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                Menu {
                                    Button {
                                        composer.beginEditing(index, message)
                                        inputFocused = true
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button {
                                        UIPasteboard.general.string = message
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    Button(role: .destructive) {
                                        guard let snapshot else { return }
                                        Task { await model.deleteMessage(at: index, in: snapshot) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    // Small glyph, generous target: the hit
                                    // area grows leftwards so the dots stay
                                    // tucked under the bubble's corner.
                                    Image(systemName: "ellipsis")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.quaternary)
                                        .frame(width: 28, height: 22)
                                        .padding(.leading, 20)
                                        .padding(.vertical, 5)
                                        .contentShape(Rectangle())
                                }
                                .tint(.primary)
                                .accessibilityLabel("Message actions")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                // Tap anywhere outside the composer to put the keyboard away.
                .simultaneousGesture(TapGesture().onEnded { inputFocused = false })
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

            banner
            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // Deliberately no Settle here: completing a need is only ever the
        // swipe gesture in the list, to build the habit.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard let snapshot else { return }
                    editDraft = NeedDraft(id: UUID(), title: snapshot.title, listID: snapshot.listID)
                    editOutcome = .dismissed
                    editing = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit need")
            }
        }
        .sheet(isPresented: $editing, onDismiss: finishEdit) {
            CaptureSheet(draft: $editDraft, outcome: $editOutcome, mode: .edit)
        }
    }

    private func finishEdit() {
        guard editOutcome == .sent, let snapshot else { return }
        Task {
            // A failed write re-opens the sheet with the edit intact rather
            // than silently reverting the title.
            if await !model.update(snapshot, title: editDraft.title, listID: editDraft.listID) {
                editOutcome = .dismissed
                editing = true
            }
        }
    }

    // MARK: Banner (parity with Mac: appending to a snoozed/settled need
    // shouldn't be a surprise)

    @ViewBuilder private var banner: some View {
        if let snapshot {
            if model.state(of: snapshot.id) == .settled || snapshot.isCompleted {
                bannerRow("This need is settled.", button: "Un-settle") {
                    Task { await model.unsettle(snapshot) }
                }
            } else if model.state(of: snapshot.id) == .snoozed, let due = snapshot.dueDate {
                bannerRow("Snoozed until \(due.formatted(.dateTime.weekday(.wide).month().day())).", button: "Wake") {
                    Task { await model.wake(snapshot) }
                }
            }
        }
    }

    private func bannerRow(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
            Button(button, action: action)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: Composer

    /// Multiline composer with the send control anchored to the bottom edge.
    private var inputBar: some View {
        @Bindable var composer = composer
        return VStack(alignment: .leading, spacing: 8) {
            if composer.isEditing {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                    Text("Editing note")
                    Spacer()
                    Button {
                        composer.cancelEditing()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel editing")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            TextField("Message to your future self", text: $composer.draft, axis: .vertical)
                .lineLimit(1...8)
                .focused($inputFocused)
            HStack {
                Spacer()
                Button(action: send) {
                    Image(systemName: composer.isEditing ? "checkmark" : "arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(composer.sanitizedDraft.isEmpty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint), in: Circle())
                        .foregroundStyle(composer.sanitizedDraft.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                }
                .buttonStyle(.plain)
                .disabled(composer.sanitizedDraft.isEmpty)
                .accessibilityLabel(composer.isEditing ? "Save message" : "Append message")
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func send() {
        guard let snapshot else { return }
        composer.send(to: snapshot, via: model)
    }
}

#Preview("Thread") {
    NavigationStack {
        ThreadView(reminderID: "1")
    }
    .environment(AppModel.preview())
}

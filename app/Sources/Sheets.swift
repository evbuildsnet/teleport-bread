import InboxCore
import SwiftUI

/// Half-height sheet used both to create a need and to edit its title/list.
/// Create mode: Discard clears the draft; send creates; swipe-down stashes the
/// draft (see InboxView). Edit mode: Cancel and swipe-down both leave the
/// need untouched.
struct CaptureSheet: View {
    enum Mode { case create, edit }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: NeedDraft
    @Binding var outcome: ComposeOutcome
    let mode: Mode
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedList: ListOption? {
        model.listOptions.first { $0.id == draft.listID } ?? model.listOptions.first
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // Wraps long titles; Enter still submits (a vertical-axis field
                // would otherwise insert a newline).
                TextField("What do you need?", text: $draft.title, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.title3)
                    .focused($focused)
                    .submitLabel(mode == .create ? .send : .done)
                    .onSubmit(send)
                    .onChange(of: draft.title) { _, value in
                        guard value.contains("\n") else { return }
                        draft.title = value.replacingOccurrences(of: "\n", with: " ")
                        send()
                    }
                    .accessibilityLabel("Need title")
                    .accessibilityIdentifier("needTitleField")

                if !model.listOptions.isEmpty {
                    Menu {
                        ForEach(model.listOptions) { option in
                            Button {
                                draft.listID = option.id
                            } label: {
                                if option.id == selectedList?.id {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Save to list:")
                                .foregroundStyle(.secondary)
                            Text(selectedList?.title ?? "")
                                .fontWeight(.medium)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    }
                    .tint(.primary)
                    .accessibilityLabel("Save to list")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == .create ? "Discard" : "Cancel", role: .destructive) {
                        outcome = .discarded
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: send) {
                        Image(systemName: mode == .create ? "paperplane.fill" : "checkmark")
                    }
                    .disabled(!canSend)
                    .accessibilityLabel(mode == .create ? "Create need" : "Save need")
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func send() {
        guard canSend else { return }
        outcome = .sent
        dismiss()
    }
}

struct FilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    model.selectedListIDs = nil
                } label: {
                    HStack {
                        Text("All lists").foregroundStyle(.primary)
                        Spacer()
                        if model.selectedListIDs == nil {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                ForEach(model.listOptions) { list in
                    Button {
                        model.toggleList(list.id)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hexString: list.colorHex) ?? .accentColor)
                                .frame(width: 10, height: 10)
                            Text(list.title).foregroundStyle(.primary)
                            Spacer()
                            if model.selectedListIDs?.contains(list.id) == true {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

import InboxCore
import SwiftUI

/// Half-height compose sheet. Discard clears the draft; send creates the
/// need; swiping the sheet away keeps the draft in memory (see InboxView).
struct CaptureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: NeedDraft
    @Binding var outcome: ComposeOutcome
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                TextField("What do you need?", text: $draft.title, axis: .vertical)
                    .font(.title3)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)

                if !model.listOptions.isEmpty {
                    Picker("List", selection: $draft.listID) {
                        ForEach(model.listOptions) { option in
                            Text(option.title).tag(Optional(option.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) {
                        outcome = .discarded
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: send) {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Create need")
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
                    Task { await model.refresh() }
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
                        toggle(list.id)
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

    private func toggle(_ id: String) {
        var selection = model.selectedListIDs ?? []
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        model.selectedListIDs = selection.isEmpty ? nil : selection
        Task { await model.refresh() }
    }
}

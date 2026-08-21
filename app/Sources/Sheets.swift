import EventKit
import InboxCore
import SwiftUI

struct CaptureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("What needs doing?", text: $title)
                    .focused($focused)
                    .onSubmit(add)
            }
            .navigationTitle("New reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(180)])
    }

    private func add() {
        let value = title
        dismiss()
        Task { await model.capture(title: value) }
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
                ForEach(model.lists, id: \.calendarIdentifier) { list in
                    Button {
                        toggle(list.calendarIdentifier)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(list.cgColor.map { Color(cgColor: $0) } ?? .accentColor)
                                .frame(width: 10, height: 10)
                            Text(list.title).foregroundStyle(.primary)
                            Spacer()
                            if model.selectedListIDs?.contains(list.calendarIdentifier) == true {
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

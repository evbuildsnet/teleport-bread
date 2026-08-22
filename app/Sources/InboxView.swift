import InboxCore
import SwiftUI

struct InboxView: View {
    @Environment(AppModel.self) private var model

    @State private var path: [String] = []
    @State private var snoozeTarget: ReminderSnapshot?
    @State private var showFilter = false
    @State private var snoozedExpanded = false
    @State private var settledExpanded = false
    @State private var settledShown = 5

    // Compose sheet state. `composeOutcome` distinguishes an explicit
    // send/discard from a swipe-down, which stashes the draft.
    @State private var composing = false
    @State private var draft = NeedDraft(id: UUID(), title: "", listID: nil)
    @State private var composeOutcome: ComposeOutcome = .dismissed

    private var inbox: [ReminderSnapshot] { model.inbox.filter(model.matchesSearch) }
    private var snoozed: [ReminderSnapshot] { model.snoozed.filter(model.matchesSearch) }
    private var settled: [ReminderSnapshot] { model.settled.filter(model.matchesSearch) }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            List {
                ForEach(model.drafts) { draft in
                    draftRow(draft)
                }
                inboxSection
                if !snoozed.isEmpty {
                    collapsible("Snoozed (\(snoozed.count))", isExpanded: $snoozedExpanded, tint: .accentColor) {
                        ForEach(snoozed) { row($0, triageable: true) }
                    }
                }
                if !settled.isEmpty {
                    collapsible("Settled", isExpanded: $settledExpanded, tint: .secondary) {
                        ForEach(settled.prefix(settledShown)) { row($0, triageable: false) }
                        if settled.count > settledShown {
                            showMore
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden, edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .searchable(text: $model.searchText, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showFilter = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    .accessibilityLabel("Filter lists")
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        compose(model.newDraft())
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New need")
                }
            }
            .navigationDestination(for: String.self) { id in
                ThreadView(reminderID: id)
            }
        }
        .confirmationDialog(
            "Snooze until",
            isPresented: Binding(
                get: { snoozeTarget != nil },
                set: { if !$0 { snoozeTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(SnoozePreset.allCases, id: \.self) { preset in
                Button(preset.label) {
                    guard let target = snoozeTarget else { return }
                    Task { await model.snooze(target, preset) }
                }
            }
        }
        .sheet(isPresented: $composing, onDismiss: finishCompose) {
            CaptureSheet(draft: $draft, outcome: $composeOutcome)
        }
        .sheet(isPresented: $showFilter) { FilterSheet() }
        .refreshable { await model.refresh() }
        .sensoryFeedback(.success, trigger: model.triageCount)
    }

    // MARK: Compose lifecycle

    private func compose(_ target: NeedDraft) {
        draft = target
        composeOutcome = .dismissed
        composing = true
    }

    private func finishCompose() {
        switch composeOutcome {
        case .dismissed: model.stash(draft)
        case .discarded: model.discard(draft)
        case .sent: Task { await model.send(draft) }
        }
    }

    // MARK: Rows

    @ViewBuilder private var inboxSection: some View {
        if inbox.isEmpty && model.drafts.isEmpty {
            Group {
                if model.searchText.isEmpty {
                    ContentUnavailableView(
                        "Inbox Zero",
                        systemImage: "checkmark.circle",
                        description: Text("Nothing due. Enjoy the quiet.")
                    )
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
            .listRowSeparator(.hidden)
        } else {
            ForEach(inbox) { row($0, triageable: true) }
        }
    }

    private func row(_ snapshot: ReminderSnapshot, triageable: Bool) -> some View {
        Button {
            path.append(snapshot.id)
        } label: {
            Text(snapshot.title)
                .lineLimit(2)
                .foregroundStyle(snapshot.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: triageable) {
            if triageable {
                Button {
                    Task { await model.settle(snapshot) }
                } label: {
                    Label("Settle", systemImage: "checkmark")
                }
                .tint(.blue)
                Button {
                    snoozeTarget = snapshot
                } label: {
                    Label("Snooze", systemImage: "clock")
                }
                .tint(.indigo)
            }
        }
    }

    private func draftRow(_ draft: NeedDraft) -> some View {
        Button {
            compose(draft)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "pencil.line")
                    .foregroundStyle(.secondary)
                Text(draft.title)
                    .italic()
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Draft")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(.quaternary))
            }
            .padding(.vertical, 6)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                model.discard(draft)
            } label: {
                Label("Discard", systemImage: "trash")
            }
        }
    }

    private func collapsible<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            Button {
                withAnimation(.snappy) { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Rectangle()
                        .fill(tint.opacity(0.35))
                        .frame(height: 1)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(tint)
                .padding(.vertical, 8)
            }
            .listRowSeparator(.hidden)
            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    private var showMore: some View {
        Button {
            settledShown += 25
        } label: {
            Text("Show more (\(settled.count - settledShown) hidden)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.quaternary)
                )
        }
        .listRowSeparator(.hidden)
    }
}

enum ComposeOutcome { case dismissed, discarded, sent }

#Preview("Inbox") {
    InboxView().environment(AppModel.preview())
}

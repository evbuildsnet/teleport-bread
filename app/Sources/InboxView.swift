import InboxCore
import SwiftUI

struct InboxView: View {
    @Environment(AppModel.self) private var model

    @State private var snoozeTarget: ReminderSnapshot?
    @State private var showCapture = false
    @State private var showFilter = false
    @State private var snoozedExpanded = false
    @State private var settledExpanded = false
    @State private var settledShown = 5

    private var inbox: [ReminderSnapshot] { model.inbox.filter(model.matchesSearch) }
    private var snoozed: [ReminderSnapshot] { model.snoozed.filter(model.matchesSearch) }
    private var settled: [ReminderSnapshot] { model.settled.filter(model.matchesSearch) }

    var body: some View {
        NavigationStack {
            List {
                inboxSection
                if !snoozed.isEmpty { snoozedSection }
                if !settled.isEmpty { settledSection }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Inbox")
            .navigationDestination(for: ReminderSnapshot.self) { snapshot in
                ThreadView(reminderID: snapshot.id)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
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
        .sheet(isPresented: $showCapture) { CaptureSheet() }
        .sheet(isPresented: $showFilter) { FilterSheet() }
        .refreshable { await model.refresh() }
        .sensoryFeedback(.success, trigger: model.triageCount)
    }

    // MARK: Sections

    @ViewBuilder private var inboxSection: some View {
        if inbox.isEmpty {
            if model.searchText.isEmpty {
                ContentUnavailableView(
                    "Inbox Zero",
                    systemImage: "checkmark.circle",
                    description: Text("Nothing due. Enjoy the quiet.")
                )
                .listRowBackground(Color.clear)
            } else {
                ContentUnavailableView.search(text: model.searchText)
                    .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(inbox) { snapshot in
                    row(snapshot, triageable: true)
                }
            }
        }
    }

    private var snoozedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $snoozedExpanded) {
                ForEach(snoozed) { snapshot in
                    row(snapshot, triageable: true)
                }
            } label: {
                Text("Snoozed (\(snoozed.count))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
            }
        }
    }

    private var settledSection: some View {
        Section {
            DisclosureGroup(isExpanded: $settledExpanded) {
                ForEach(settled.prefix(settledShown)) { snapshot in
                    row(snapshot, triageable: false)
                }
                if settled.count > settledShown {
                    Button("Show more (\(settled.count - settledShown) hidden)") {
                        settledShown += 25
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            } label: {
                Text("Settled")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ snapshot: ReminderSnapshot, triageable: Bool) -> some View {
        NavigationLink(value: snapshot) {
            ReminderRow(snapshot: snapshot)
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

    // MARK: Bottom bar

    private var bottomBar: some View {
        @Bindable var model = model
        return HStack(spacing: 12) {
            Button {
                showFilter = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Filter lists")

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $model.searchText)
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.regularMaterial, in: Capsule())

            Button {
                showCapture = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("New reminder")
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
}

struct ReminderRow: View {
    let snapshot: ReminderSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hexString: snapshot.listColorHex) ?? .accentColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .lineLimit(1)
                    .foregroundStyle(snapshot.isCompleted ? .secondary : .primary)
                Text(snapshot.listTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(timeLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(timeColor)
        }
        .padding(.vertical, 2)
    }

    private var timeLabel: String {
        if snapshot.isCompleted {
            return snapshot.completionDate.map { RelativeLabel.since($0) } ?? ""
        }
        return snapshot.dueDate.map { RelativeLabel.due($0) } ?? ""
    }

    private var timeColor: Color {
        guard !snapshot.isCompleted, let due = snapshot.dueDate else { return .secondary }
        return due < Calendar.current.startOfDay(for: .now) ? .red : .secondary
    }
}

#Preview("Inbox") {
    InboxView().environment(AppModel.preview())
}

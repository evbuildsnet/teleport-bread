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

    // Pull-down-to-add: overscroll distance drives the hint; releasing past
    // the threshold opens the compose sheet.
    @State private var pullProgress: Double = 0
    @State private var pullArmed = false
    private let pullThreshold: CGFloat = 96

    private var drafts: [NeedDraft] { model.drafts.filter(model.matchesSearch) }
    private var inbox: [ReminderSnapshot] { model.inbox.filter(model.matchesSearch) }
    private var snoozed: [ReminderSnapshot] { model.snoozed.filter(model.matchesSearch) }
    private var settled: [ReminderSnapshot] { model.settled.filter(model.matchesSearch) }
    private var nothingMatches: Bool {
        drafts.isEmpty && inbox.isEmpty && snoozed.isEmpty && settled.isEmpty
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            List {
                ForEach(drafts) { draftRow($0) }
                inboxSection
                if !snoozed.isEmpty {
                    collapsible("Snoozed (\(snoozed.count))", isExpanded: $snoozedExpanded, tint: .accentColor) {
                        ForEach(snoozed) { row($0, in: .snoozed) }
                    }
                }
                if !settled.isEmpty {
                    collapsible("Settled", isExpanded: $settledExpanded, tint: .secondary) {
                        ForEach(settled.prefix(settledShown)) { row($0, in: .settled) }
                        if settled.count > settledShown {
                            showMore
                        }
                    }
                }
            }
            .listStyle(.plain)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, overscroll in
                pullProgress = min(1, overscroll / pullThreshold)
                pullArmed = overscroll >= pullThreshold
            }
            .onScrollPhaseChange { previous, next in
                guard previous == .interacting, next != .interacting, pullArmed else { return }
                pullArmed = false
                compose(model.newDraft())
            }
            .overlay(alignment: .top) { pullHint }
            .sensoryFeedback(.impact(weight: .light), trigger: pullArmed) { _, armed in armed }
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
        .sheet(isPresented: $composing, onDismiss: finishCompose) {
            CaptureSheet(draft: $draft, outcome: $composeOutcome, mode: .create)
        }
        .sheet(isPresented: $showFilter) { FilterSheet() }
        .sensoryFeedback(.success, trigger: model.triageCount)
    }

    /// Rides in the overscroll area: fades in with the pull, flips copy when armed.
    private var pullHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .rotationEffect(.degrees(pullArmed ? 0 : -90 * (1 - pullProgress)))
            Text(pullArmed ? "Release to add a need" : "Keep pulling to add a need")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(pullArmed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .padding(.top, 8)
        .opacity(pullProgress)
        .scaleEffect(0.9 + 0.1 * pullProgress)
        .animation(.snappy(duration: 0.2), value: pullArmed)
        .allowsHitTesting(false)
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

    // MARK: Sections

    @ViewBuilder private var inboxSection: some View {
        if model.isSearching {
            if nothingMatches {
                ContentUnavailableView.search(text: model.searchText)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(inbox) { row($0, in: .inbox) }
            }
        } else if inbox.isEmpty && drafts.isEmpty {
            ContentUnavailableView(
                "Inbox Zero",
                systemImage: "checkmark.circle",
                description: Text("Nothing due. Enjoy the quiet.")
            )
            .listRowSeparator(.hidden)
        } else {
            ForEach(inbox) { row($0, in: .inbox) }
        }
    }

    private enum Placement { case inbox, snoozed, settled }

    private func row(_ snapshot: ReminderSnapshot, in placement: Placement) -> some View {
        let compact = placement != .inbox
        return Button {
            path.append(snapshot.id)
        } label: {
            Text(snapshot.title)
                .font(compact ? .subheadline : .body)
                .lineLimit(2)
                .foregroundStyle(compact ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, compact ? 2 : 6)
        }
        .listRowSeparator(.hidden, edges: .top)
        .listRowSeparator(compact ? .hidden : .visible, edges: .bottom)
        .listRowSeparatorTint(.primary.opacity(0.08))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            switch placement {
            case .inbox:
                settleButton(snapshot)
                snoozeButton(snapshot)
            case .snoozed:
                Button {
                    Task { await model.wake(snapshot) }
                } label: {
                    Label("Wake", systemImage: "sun.max")
                }
                .tint(.blue)
            case .settled:
                Button {
                    Task { await model.unsettle(snapshot) }
                } label: {
                    Label("Un-settle", systemImage: "arrow.uturn.backward")
                }
                .tint(.orange)
                snoozeButton(snapshot)
            }
        }
        .popover(
            isPresented: Binding(
                get: { snoozeTarget?.id == snapshot.id },
                set: { if !$0 { snoozeTarget = nil } }
            ),
            arrowEdge: .top
        ) {
            SnoozePicker(title: "Snooze until") { date in
                snoozeTarget = nil
                Task { await model.snooze(snapshot, until: date) }
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private func settleButton(_ snapshot: ReminderSnapshot) -> some View {
        Button {
            Task { await model.settle(snapshot) }
        } label: {
            Label("Settle", systemImage: "checkmark")
        }
        .tint(.blue)
    }

    private func snoozeButton(_ snapshot: ReminderSnapshot) -> some View {
        Button {
            snoozeTarget = snapshot
        } label: {
            Label("Snooze", systemImage: "clock")
        }
        .tint(.indigo)
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
            }
            .padding(.vertical, 6)
        }
        .listRowSeparator(.hidden, edges: .top)
        .listRowSeparatorTint(.primary.opacity(0.08))
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                model.discard(draft)
            } label: {
                Label("Discard", systemImage: "trash")
            }
        }
    }

    /// Text-only section control. Sections are forced open while searching
    /// so matches are never hidden behind a collapsed header.
    private func collapsible<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let open = isExpanded.wrappedValue || model.isSearching
        return Group {
            Button {
                withAnimation(.snappy) { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Rectangle()
                        .fill(tint.opacity(0.35))
                        .frame(height: 1)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(tint)
                .padding(.vertical, 8)
            }
            .listRowSeparator(.hidden)
            if open {
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

/// Glass popover: presets plus a calendar for an arbitrary day.
struct SnoozePicker: View {
    let title: String
    let onPick: (Date) -> Void

    @State private var pickingDate = false
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
    private let engine = InboxEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
            if pickingDate {
                DatePicker("Day", selection: $date, in: Date.now..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal, 8)
                Button {
                    onPick(date)
                } label: {
                    Text("Snooze")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding([.horizontal, .bottom], 12)
            } else {
                ForEach(SnoozePreset.allCases, id: \.self) { preset in
                    option(preset.label) { onPick(engine.snoozeDate(preset, from: .now)) }
                }
                Divider().padding(.horizontal, 12)
                option("Pick date…", systemImage: "calendar") {
                    withAnimation { pickingDate = true }
                }
            }
        }
        .frame(minWidth: 240)
        .padding(.bottom, pickingDate ? 0 : 6)
    }

    private func option(_ label: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
                if let systemImage { Image(systemName: systemImage).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum ComposeOutcome { case dismissed, discarded, sent }

#Preview("Inbox") {
    InboxView().environment(AppModel.preview())
}

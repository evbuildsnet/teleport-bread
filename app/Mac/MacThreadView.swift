import AppKit
import InboxCore
import SwiftUI

/// One-sided log of the user's own notes, T3 thread geometry: 768pt column,
/// floating composer, banner for snoozed/settled needs.
struct MacThreadView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let snapshot: ReminderSnapshot

    @State private var draft = ""
    @State private var editingIndex: Int?
    @FocusState private var composerFocused: Bool

    private var live: ReminderSnapshot { model.snapshot(id: snapshot.id) ?? snapshot }
    private var isSnoozed: Bool { model.snoozed.contains { $0.id == snapshot.id } }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(snapshot: live)
            ZStack(alignment: .bottom) {
                log
                composer
            }
        }
        .onChange(of: ui.composerFocusRequest) { _, _ in
            guard ui.selection == .need(snapshot.id) else { return }
            draft += ui.composerSeed
            ui.composerSeed = ""
            composerFocused = true
        }
    }

    // MARK: Log

    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    let messages = live.messages
                    if messages.isEmpty {
                        Text("Leave a thought for your future self.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                    ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                        NoteBubble(
                            message: message,
                            highlighted: editingIndex == index,
                            onEdit: { beginEditing(index, message) },
                            onDelete: { Task { await model.deleteMessage(at: index, in: live) } }
                        )
                        .id(index)
                    }
                    Color.clear.frame(height: 140) // room for the floating composer
                }
                .frame(maxWidth: Theme.columnMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .onChange(of: live.messages.count) { _, count in
                guard count > 0 else { return }
                withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
            .onAppear {
                let count = live.messages.count
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 8) {
            banner
            Composer(
                text: $draft,
                placeholder: "Leave a thought for your future self.",
                focused: $composerFocused,
                accessory: { editingAccessory },
                sendSymbol: editingIndex == nil ? "arrow.up" : "checkmark",
                canSend: !sanitizedDraft.isEmpty,
                onSend: send
            )
        }
        .frame(maxWidth: Theme.columnMaxWidth)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    @ViewBuilder private var banner: some View {
        let actions = NeedActions(model: model, ui: ui)
        if live.isCompleted {
            bannerRow("This need is settled.", button: "Un-settle") { actions.unsettle(live) }
        } else if isSnoozed, let due = live.dueDate {
            bannerRow("Snoozed until \(due.formatted(.dateTime.weekday(.wide).month().day())).", button: "Wake now") { actions.wake(live) }
        }
    }

    private func bannerRow(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(text)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button(button, action: action)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    @ViewBuilder private var editingAccessory: some View {
        if editingIndex != nil {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                Text("Editing note")
                Spacer()
                Button {
                    cancelEditing()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel editing")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
        }
    }

    private var sanitizedDraft: String {
        draft
            .replacingOccurrences(of: String(NoteCodec.invisibleSeparator), with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginEditing(_ index: Int, _ message: String) {
        editingIndex = index
        draft = message
        composerFocused = true
    }

    private func cancelEditing() {
        editingIndex = nil
        draft = ""
    }

    private func send() {
        let message = sanitizedDraft
        guard !message.isEmpty else { return }
        let target = live
        if let index = editingIndex {
            editingIndex = nil
            draft = ""
            Task { await model.replaceMessage(at: index, with: message, in: target) }
            return
        }
        draft = ""
        Task {
            if await !model.append(message, to: target), draft.isEmpty {
                draft = message
            }
        }
    }
}

/// A note in the log; "…" appears on hover → Edit · Copy · Delete.
struct NoteBubble: View {
    let message: String
    let highlighted: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            SelectableText(text: message)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(highlighted ? Theme.accent.opacity(0.18) : Theme.bubble, in: RoundedRectangle(cornerRadius: 14))
            Menu {
                Button("Edit", action: onEdit)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                }
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
            .accessibilityLabel("Note actions")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovering = $0 }
    }
}

/// Floating glass composer (T3 geometry: radius 22/20, send bottom-right).
/// ⏎ sends, ⇧⏎ inserts a newline.
struct Composer<Accessory: View, Footer: View>: View {
    @Binding var text: String
    let placeholder: String
    var focused: FocusState<Bool>.Binding
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var footer: Footer
    var sendSymbol = "arrow.up"
    let canSend: Bool
    let onSend: () -> Void
    @State private var editorHeight: CGFloat = 20

    init(
        text: Binding<String>,
        placeholder: String,
        focused: FocusState<Bool>.Binding,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder footer: () -> Footer = { EmptyView() },
        sendSymbol: String = "arrow.up",
        canSend: Bool,
        onSend: @escaping () -> Void
    ) {
        _text = text
        self.placeholder = placeholder
        self.focused = focused
        self.accessory = accessory()
        self.footer = footer()
        self.sendSymbol = sendSymbol
        self.canSend = canSend
        self.onSend = onSend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            accessory
            ZStack(alignment: .topLeading) {
                // Mirror text sizes the editor; TextEditor itself won't grow.
                Text(text.isEmpty ? " " : text + "\u{200B}")
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .opacity(0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { editorHeight = $0 }
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .focused(focused)
                    .padding(.horizontal, -5)
                    .frame(height: min(editorHeight + 4, 200))
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        if canSend { onSend() }
                        return .handled
                    }
                    .accessibilityLabel("Composer")
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .allowsHitTesting(false)
                }
            }
            HStack(alignment: .center) {
                footer
                Spacer()
                Button(action: onSend) {
                    Image(systemName: sendSymbol)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(canSend ? Theme.accent : Theme.input, in: Circle())
                        .foregroundStyle(canSend ? .white : Theme.muted)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel(sendSymbol == "arrow.up" ? "Send" : "Save")
            }
        }
        .padding(14)
        .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
    }
}

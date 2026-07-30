import AppKit
import SwiftUI

struct ChangesView: View {
    @EnvironmentObject private var store: RepositoryStore
    @Binding var showingStashSheet: Bool
    @Binding var stashScope: StashScope
    @State private var showingCommitSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Working Tree")
                        .font(.headline)
                    Text(changeCountLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button {
                        showStashSheet(for: .staged)
                    } label: {
                        Label("Staged Changes", systemImage: "checkmark.circle")
                    }
                    .disabled(
                        store.stagedChanges.isEmpty
                            || hasPartiallyStagedFiles
                    )

                    Button {
                        showStashSheet(for: .unstaged)
                    } label: {
                        Label("Unstaged Changes", systemImage: "pencil.circle")
                    }
                    .disabled(store.unstagedChanges.isEmpty)

                    Divider()

                    Button {
                        showStashSheet(for: .all)
                    } label: {
                        Label("All Changes", systemImage: "tray.full")
                    }
                } label: {
                    Label("Stash Changes", systemImage: "archivebox")
                }
                .menuStyle(.borderedButton)
                .controlSize(.regular)
                .help("Choose which changes to save to a stash")
                .disabled(store.changes.isEmpty || store.isLoading)

                Button {
                    showingCommitSheet = true
                } label: {
                    Label(
                        "Commit",
                        systemImage: store.signCommit ? "checkmark.seal.fill" : "checkmark.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Write a commit message for the staged changes")
                .disabled(store.isLoading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ChangeList()
                .frame(maxHeight: .infinity)
        }
        .sheet(isPresented: $showingCommitSheet) {
            CommitSheet(isPresented: $showingCommitSheet)
        }
    }

    private var changeCountLabel: String {
        let count = store.changes.count
        return "\(count) changed file\(count == 1 ? "" : "s")"
    }

    private var hasPartiallyStagedFiles: Bool {
        store.changes.contains { $0.isStaged && $0.isUnstaged }
    }

    private func showStashSheet(for scope: StashScope) {
        stashScope = scope
        showingStashSheet = true
    }
}

private struct ChangeList: View {
    @EnvironmentObject private var store: RepositoryStore
    @Environment(\.openWindow) private var openWindow
    @State private var pendingDiscard: [ChangeEntry] = []
    @FocusState private var isListFocused: Bool

    var body: some View {
        let entries = store.changeEntries
        let stagedEntries = entries.stagedSide
        let unstagedEntries = entries.unstagedSide
        VStack(spacing: 0) {
            if store.changeSelection.count > 1 {
                SelectionActionBar(
                    entries: store.selectedChangeEntries,
                    requestDiscard: requestDiscard
                )
                Divider()
            }

            List(selection: primarySelection) {
                if !store.changes.isEmpty {
                    Section {
                        if stagedEntries.isEmpty {
                            EmptyChangeRow(title: "No staged changes")
                        } else {
                            ForEach(stagedEntries) { entry in
                                ChangeRow(
                                    entry: entry,
                                    requestDiscard: requestDiscard,
                                    focusList: focusList
                                )
                                .tag(entry.id)
                            }
                        }
                    } header: {
                        ChangeSectionHeader(
                            title: "Staged Changes",
                            count: stagedEntries.count,
                            systemImage: "checkmark.circle.fill",
                            tint: GitForkTheme.green,
                            actionTitle: "Unstage All",
                            action: store.unstageAll
                        )
                    }

                    Section {
                        if unstagedEntries.isEmpty {
                            EmptyChangeRow(title: "No unstaged changes")
                        } else {
                            ForEach(unstagedEntries) { entry in
                                ChangeRow(
                                    entry: entry,
                                    requestDiscard: requestDiscard,
                                    focusList: focusList
                                )
                                .tag(entry.id)
                            }
                        }
                    } header: {
                        ChangeSectionHeader(
                            title: "Unstaged Changes",
                            count: unstagedEntries.count,
                            systemImage: "pencil.circle.fill",
                            tint: GitForkTheme.accent,
                            actionTitle: "Stage All",
                            action: store.stageAll
                        )
                    }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 30)
            .focused($isListFocused)
            .onKeyPress(.return) {
                performKeyboardAction(for: .returnKey)
            }
            .onKeyPress(.space) {
                openSideBySideDiff()
            }
            .onDeleteCommand {
                _ = performKeyboardAction(for: .deleteKey)
            }
            .overlay {
                if store.changes.isEmpty {
                    ContentUnavailableView(
                        "Working Tree Clean",
                        systemImage: "checkmark.circle",
                        description: Text("There are no staged or unstaged changes.")
                    )
                }
            }
        }
        .alert(
            DiscardPrompt.title(for: pendingDiscard),
            isPresented: Binding(
                get: { !pendingDiscard.isEmpty },
                set: { if !$0 { pendingDiscard = [] } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingDiscard = []
            }
            Button("Discard", role: .destructive) {
                store.discard(pendingDiscard)
                pendingDiscard = []
            }
        } message: {
            Text(DiscardPrompt.message(for: pendingDiscard))
        }
    }

    private var primarySelection: Binding<ChangeEntryID?> {
        Binding(
            get: { store.changeSelection.primary },
            set: store.selectChangeEntry
        )
    }

    private func requestDiscard(_ entries: [ChangeEntry]) {
        let targets = entries.unstagedSide
        guard !targets.isEmpty else { return }
        pendingDiscard = targets
    }

    private func focusList() {
        isListFocused = true
    }

    private func openSideBySideDiff() -> KeyPress.Result {
        guard let repositoryURL = store.repositoryURL,
              let change = store.selectedChange,
              !store.diff.isEmpty else {
            return .ignored
        }
        openWindow(
            id: GitForkApp.sideBySideDiffWindowID,
            value: SideBySideDiffWindowState(
                repositoryURL: repositoryURL,
                change: change,
                staged: store.selectedChangeIsStaged,
                diff: store.diff
            )
        )
        return .handled
    }

    private func performKeyboardAction(
        for key: ChangeSelectionKey
    ) -> KeyPress.Result {
        guard let action = store.changeSelection.keyboardAction(for: key) else {
            return .ignored
        }
        guard !store.isLoading else { return .handled }

        switch action {
        case .stage:
            store.stage(store.selectedChangeEntries)
        case .unstage:
            store.unstage(store.selectedChangeEntries)
        }
        return .handled
    }
}

/// Batch actions for the current multi-selection, shown above the list so the
/// selection has a visible destination beyond the context menu.
private struct SelectionActionBar: View {
    @EnvironmentObject private var store: RepositoryStore
    let entries: [ChangeEntry]
    let requestDiscard: ([ChangeEntry]) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.caption)
                .foregroundStyle(GitForkTheme.accent)
            Text("\(entries.count) selected")
                .font(.caption.weight(.medium))

            Spacer()

            if !entries.unstagedSide.isEmpty {
                Button {
                    store.stage(entries)
                } label: {
                    Label("Stage", systemImage: "plus")
                }
                .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
                .font(.callout)
                .help("Stage \(ChangeActionTitle.fileCount(entries.unstagedSide.count))")
                .disabled(store.isLoading)
            }

            if !entries.stagedSide.isEmpty {
                Button {
                    store.unstage(entries)
                } label: {
                    Label("Unstage", systemImage: "minus")
                }
                .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
                .font(.callout)
                .help("Unstage \(ChangeActionTitle.fileCount(entries.stagedSide.count))")
                .disabled(store.isLoading)
            }

            if !entries.unstagedSide.isEmpty {
                Button(role: .destructive) {
                    requestDiscard(entries)
                } label: {
                    Label("Discard…", systemImage: "trash")
                }
                .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
                .font(.callout)
                .foregroundStyle(GitForkTheme.red)
                .help(
                    "Permanently discard the working-tree changes in "
                        + ChangeActionTitle.fileCount(entries.unstagedSide.count)
                        + " after confirmation"
                )
                .disabled(store.isLoading)
            }

            Button {
                store.clearChangeSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(GitForkHoverButtonStyle(.icon))
            .help("Clear the selection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(GitForkTheme.accent.opacity(0.08))
    }
}

private struct ChangeSectionHeader: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(tint)
            Text(title)
                .font(.body.weight(.semibold))
            Text("\(count)")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(tint.opacity(0.13), in: Capsule())
            Spacer()
            Button(actionTitle, action: action)
                .font(.callout.weight(.semibold))
                .textCase(nil)
                .buttonStyle(GitForkHoverButtonStyle(.text))
                .foregroundStyle(tint)
                .help(actionTitle)
                .disabled(count == 0)
        }
        .textCase(nil)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(tint.opacity(0.18))
        }
    }
}

private struct EmptyChangeRow: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "tray")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 3)
            .listRowInsets(EdgeInsets(top: 1, leading: 7, bottom: 1, trailing: 7))
            .listRowBackground(Color.clear)
    }
}

private struct ChangeRow: View {
    @EnvironmentObject private var store: RepositoryStore
    let entry: ChangeEntry
    let requestDiscard: ([ChangeEntry]) -> Void
    let focusList: () -> Void

    private var change: WorkingChange { entry.change }
    private var staged: Bool { entry.staged }
    private var isSelected: Bool { store.isSelected(entry) }

    /// A menu opened on a selected row acts on the whole selection; one opened
    /// on an unselected row acts on that row alone.
    private var actionTargets: [ChangeEntry] {
        isSelected ? store.selectedChangeEntries : [entry]
    }

    var body: some View {
        let statusSymbol = change.statusSymbol(staged: staged)
        Button(action: handleClick) {
            HStack(spacing: 7) {
                Text(statusSymbol)
                    .font(.callout.monospaced().weight(.bold))
                    .foregroundStyle(Color.statusColor(statusSymbol))
                    .frame(width: 22, height: 22)
                    .background(Color.statusColor(statusSymbol).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

                Text(change.path)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                Spacer()

                Button {
                    staged ? store.unstage(change) : store.stage(change)
                } label: {
                    Image(systemName: staged ? "minus" : "plus")
                        .font(.body.weight(.medium))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GitForkHoverButtonStyle(.icon))
                .help(staged ? "Unstage" : "Stage")
                .disabled(store.isLoading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GitForkHoverButtonStyle(.compactRow(isSelected: isSelected)))
        .help(
            "View \(staged ? "staged" : "working tree") diff for \(change.path)"
                + " · Space for side by side"
                + " · Shift-click for a range, Command-click to add or remove"
        )
        .contextMenu {
            ChangeActionsMenu(entries: actionTargets, requestDiscard: requestDiscard)
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 7, bottom: 1, trailing: 7))
        .listRowBackground(Color.clear)
    }

    /// Standard macOS list behavior: Shift extends from the anchor, Command
    /// toggles one row, a plain click replaces the selection.
    private func handleClick() {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            store.extendSelection(to: entry)
        } else if modifiers.contains(.command) {
            store.toggleSelection(of: entry)
        } else {
            store.selectChange(change, staged: staged)
        }
        // The full-row button otherwise keeps keyboard focus, preventing the
        // enclosing List from handling arrows, Return, Space, and Delete.
        focusList()
    }
}

private struct ChangeActionsMenu: View {
    @EnvironmentObject private var store: RepositoryStore
    let entries: [ChangeEntry]
    let requestDiscard: ([ChangeEntry]) -> Void

    var body: some View {
        let stageable = entries.unstagedSide
        let unstageable = entries.stagedSide

        if !stageable.isEmpty {
            Button {
                store.stage(entries)
            } label: {
                Label(ChangeActionTitle.stage(stageable.count), systemImage: "plus")
            }
            .disabled(store.isLoading)
        }

        if !unstageable.isEmpty {
            Button {
                store.unstage(entries)
            } label: {
                Label(ChangeActionTitle.unstage(unstageable.count), systemImage: "minus")
            }
            .disabled(store.isLoading)
        }

        if !stageable.isEmpty {
            Divider()

            Button(role: .destructive) {
                requestDiscard(entries)
            } label: {
                Label(ChangeActionTitle.discard(stageable.count), systemImage: "trash")
            }
            .disabled(store.isLoading)
        }
    }
}

private enum ChangeActionTitle {
    static func fileCount(_ count: Int) -> String {
        "\(count) file\(count == 1 ? "" : "s")"
    }

    static func stage(_ count: Int) -> String {
        count == 1 ? "Stage File" : "Stage \(count) Files"
    }

    static func unstage(_ count: Int) -> String {
        count == 1 ? "Unstage File" : "Unstage \(count) Files"
    }

    static func discard(_ count: Int) -> String {
        count == 1 ? "Discard Changes…" : "Discard Changes in \(count) Files…"
    }
}

/// Confirmation copy for discarding working-tree changes. Untracked files are
/// deleted rather than reverted, so the prompt names them separately.
private enum DiscardPrompt {
    static func title(for entries: [ChangeEntry]) -> String {
        entries.count == 1
            ? "Discard All Changes in This File?"
            : "Discard Changes in \(entries.count) Files?"
    }

    static func message(for entries: [ChangeEntry]) -> String {
        let untracked = entries.filter(\.change.isUntracked).count
        if entries.count == 1, let only = entries.first {
            return only.change.isUntracked
                ? "\(only.change.path) is untracked and will be permanently deleted. "
                    + "This cannot be undone."
                : "All unstaged changes in \(only.change.path) will be permanently discarded. "
                    + "This cannot be undone."
        }

        var message = "All unstaged changes in \(entries.count) files will be "
            + "permanently discarded."
        if untracked > 0 {
            message += " \(untracked) untracked file\(untracked == 1 ? " is" : "s are") "
                + "among them and will be permanently deleted."
        }
        return message + " This cannot be undone."
    }
}

private struct CommitSheet: View {
    @EnvironmentObject private var store: RepositoryStore
    @Binding var isPresented: Bool
    @State private var isConfirmingAmend = false
    @FocusState private var isMessageFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: store.signCommit ? "checkmark.seal" : "checkmark.circle")
                    .font(.title)
                    .foregroundStyle(store.signCommit ? GitForkTheme.green : GitForkTheme.accent)
                VStack(alignment: .leading) {
                    Text("Commit Changes")
                        .font(.title2.weight(.semibold))
                    Text(stagedSummary)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 5) {
                    Toggle(isOn: $store.signCommit) {
                        Label("Sign", systemImage: "checkmark.seal")
                    }
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(store.signCommit ? GitForkTheme.green : .primary)
                    .help("Sign commits with the configured OpenPGP key")

                    Toggle("Amend", isOn: $store.amend)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .help("Replace the latest commit")
                        .disabled(store.isLoading)
                }
            }

            TextEditor(text: $store.commitMessage)
                .font(.body)
                .scrollContentBackground(.hidden)
                .focused($isMessageFocused)
                .frame(minHeight: 170)
                .padding(7)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.separator.opacity(0.7))
                )
                .overlay(alignment: .topLeading) {
                    if store.commitMessage.isEmpty {
                        Text("Commit message")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .help("Close without committing; the message is kept")

                Button {
                    if store.amend {
                        isConfirmingAmend = true
                    } else {
                        commit()
                    }
                } label: {
                    Label(
                        commitButtonTitle,
                        systemImage: store.signCommit ? "checkmark.seal.fill" : "checkmark.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help(commitButtonHelp)
                .disabled(
                    (!store.amend && store.stagedChanges.isEmpty)
                        || store.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || store.isLoading
                )
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear { isMessageFocused = true }
        .alert("Amend the Latest Commit?", isPresented: $isConfirmingAmend) {
            Button("Cancel", role: .cancel) {}
            Button("Amend Commit", role: .destructive) {
                commit()
            }
        } message: {
            Text(
                "This replaces the latest commit and rewrites local history. "
                    + "If that commit was already pushed, the remote will no longer match."
            )
        }
    }

    private func commit() {
        store.createCommit()
        isPresented = false
    }

    private var stagedSummary: String {
        let count = store.stagedChanges.count
        return "\(count) staged file\(count == 1 ? "" : "s") on \(store.branch)"
    }

    private var commitButtonTitle: String {
        if store.amend {
            return store.signCommit ? "Amend & Sign" : "Amend Commit"
        }
        return store.signCommit ? "Sign & Commit" : "Commit"
    }

    private var commitButtonHelp: String {
        if store.signCommit {
            return store.amend
                ? "Replace and OpenPGP-sign the latest commit"
                : "Create an OpenPGP-signed commit using Git's configured key"
        }
        return store.amend ? "Replace the latest commit" : "Commit the staged changes"
    }
}

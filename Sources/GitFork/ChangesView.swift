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
                        .font(.caption)
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
                .controlSize(.small)
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
                .controlSize(.small)
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

    var body: some View {
        List(selection: changeSelection) {
            if !store.changes.isEmpty {
                Section {
                    if stagedChanges.isEmpty {
                        EmptyChangeRow(title: "No staged changes")
                    } else {
                        ForEach(stagedChanges) { item in
                            ChangeRow(change: item.change, staged: item.staged)
                                .tag(item)
                        }
                    }
                } header: {
                    ChangeSectionHeader(
                        title: "Staged Changes",
                        count: store.stagedChanges.count,
                        systemImage: "checkmark.circle.fill",
                        tint: GitForkTheme.green,
                        actionTitle: "Unstage All",
                        action: store.unstageAll
                    )
                }

                Section {
                    if unstagedChanges.isEmpty {
                        EmptyChangeRow(title: "No unstaged changes")
                    } else {
                        ForEach(unstagedChanges) { item in
                            ChangeRow(change: item.change, staged: item.staged)
                                .tag(item)
                        }
                    }
                } header: {
                    ChangeSectionHeader(
                        title: "Unstaged Changes",
                        count: store.unstagedChanges.count,
                        systemImage: "pencil.circle.fill",
                        tint: GitForkTheme.accent,
                        actionTitle: "Stage All",
                        action: store.stageAll
                    )
                }
            }
        }
        .listStyle(.inset)
        .environment(\.defaultMinListRowHeight, 26)
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

    private var stagedChanges: [PresentedChange] {
        store.stagedChanges.map { PresentedChange($0, staged: true) }
    }

    private var unstagedChanges: [PresentedChange] {
        store.unstagedChanges.map { PresentedChange($0, staged: false) }
    }

    private var changes: [PresentedChange] {
        stagedChanges + unstagedChanges
    }

    private var changeSelection: Binding<PresentedChange?> {
        Binding(
            get: {
                changes.first {
                    $0.change == store.selectedChange
                        && $0.staged == store.selectedChangeIsStaged
                }
            },
            set: { item in
                store.selectChange(item?.change, staged: item?.staged ?? false)
            }
        )
    }
}

private struct PresentedChange: Hashable, Identifiable {
    let change: WorkingChange
    let staged: Bool

    init(_ change: WorkingChange, staged: Bool) {
        self.change = change
        self.staged = staged
    }

    var id: String {
        "\(staged ? "staged" : "unstaged")|\(change.id)"
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
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(tint.opacity(0.13), in: Capsule())
            Spacer()
            Button(actionTitle, action: action)
                .font(.caption2)
                .textCase(nil)
                .buttonStyle(GitForkHoverButtonStyle(.text))
                .foregroundStyle(tint)
                .help(actionTitle)
                .disabled(count == 0)
        }
        .textCase(nil)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
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
    let change: WorkingChange
    let staged: Bool

    var body: some View {
        let statusSymbol = change.statusSymbol(staged: staged)
        Button {
            store.selectChange(change, staged: staged)
        } label: {
            HStack(spacing: 7) {
                Text(statusSymbol)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(Color.statusColor(statusSymbol))
                    .frame(width: 18, height: 18)
                    .background(Color.statusColor(statusSymbol).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                Text(change.path)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                Spacer()

                Button {
                    staged ? store.unstage(change) : store.stage(change)
                } label: {
                    Image(systemName: staged ? "minus" : "plus")
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GitForkHoverButtonStyle(.icon))
                .help(staged ? "Unstage" : "Stage")
                .disabled(store.isLoading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(
            GitForkHoverButtonStyle(
                .compactRow(
                    isSelected: store.selectedChange == change
                        && store.selectedChangeIsStaged == staged
                )
            )
        )
        .help("View \(staged ? "staged" : "working tree") diff for \(change.path)")
        .listRowInsets(EdgeInsets(top: 1, leading: 7, bottom: 1, trailing: 7))
        .listRowBackground(Color.clear)
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

import SwiftUI

struct ChangesView: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            ChangeList()
                .frame(maxHeight: .infinity)

            Divider()

            CommitComposer()
                .frame(minHeight: 190, idealHeight: 220, maxHeight: 270)
        }
    }
}

private struct ChangeList: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        List {
            if !store.changes.isEmpty {
                Section {
                    if store.stagedChanges.isEmpty {
                        EmptyChangeRow(title: "No staged changes")
                    } else {
                        ForEach(store.stagedChanges.map { PresentedChange($0, staged: true) }) { item in
                            ChangeRow(change: item.change, staged: item.staged)
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
                    if store.unstagedChanges.isEmpty {
                        EmptyChangeRow(title: "No unstaged changes")
                    } else {
                        ForEach(store.unstagedChanges.map { PresentedChange($0, staged: false) }) { item in
                            ChangeRow(change: item.change, staged: item.staged)
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
}

private struct PresentedChange: Identifiable {
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

private struct CommitComposer: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Commit", systemImage: "checkmark.circle")
                    .font(.headline)
                Spacer()

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
            }

            TextEditor(text: $store.commitMessage)
                .font(.body)
                .scrollContentBackground(.hidden)
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
                Text("\(store.stagedChanges.count) staged file\(store.stagedChanges.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.createCommit()
                } label: {
                    Label(
                        commitButtonTitle,
                        systemImage: store.signCommit ? "checkmark.seal.fill" : "checkmark.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .help(commitButtonHelp)
                .disabled(
                    (!store.amend && store.stagedChanges.isEmpty)
                        || store.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || store.isLoading
                )
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var commitButtonTitle: String {
        if store.amend {
            return store.signCommit ? "Amend & Sign" : "Amend Commit"
        }
        return store.signCommit ? "Sign & Commit \(store.branch)" : "Commit \(store.branch)"
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

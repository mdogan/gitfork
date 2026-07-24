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
            if !store.stagedChanges.isEmpty {
                Section {
                    ForEach(store.stagedChanges) { change in
                        ChangeRow(change: change, staged: true)
                    }
                } header: {
                    ChangeSectionHeader(
                        title: "Staged Changes",
                        count: store.stagedChanges.count,
                        actionTitle: "Unstage All",
                        action: store.unstageAll
                    )
                }
            }

            if !store.unstagedChanges.isEmpty {
                Section {
                    ForEach(store.unstagedChanges) { change in
                        ChangeRow(change: change, staged: false)
                    }
                } header: {
                    ChangeSectionHeader(
                        title: "Changes",
                        count: store.unstagedChanges.count,
                        actionTitle: "Stage All",
                        action: store.stageAll
                    )
                }
            }
        }
        .listStyle(.inset)
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

private struct ChangeSectionHeader: View {
    let title: String
    let count: Int
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Text("\(count)")
                .foregroundStyle(.secondary)
            Spacer()
            Button(actionTitle, action: action)
                .font(.caption)
                .textCase(nil)
                .buttonStyle(.plain)
                .foregroundStyle(GitForkTheme.accent)
                .help(actionTitle)
        }
    }
}

private struct ChangeRow: View {
    @EnvironmentObject private var store: RepositoryStore
    let change: WorkingChange
    let staged: Bool

    var body: some View {
        Button {
            store.selectChange(change, staged: staged)
        } label: {
            HStack(spacing: 9) {
                Text(change.statusSymbol)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(Color.statusColor(change.statusSymbol))
                    .frame(width: 20, height: 20)
                    .background(Color.statusColor(change.statusSymbol).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: change.path).lastPathComponent)
                        .lineLimit(1)
                    let directory = URL(fileURLWithPath: change.path).deletingLastPathComponent().path
                    if directory != "." && directory != "/" {
                        Text(directory)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    staged ? store.unstage(change) : store.stage(change)
                } label: {
                    Image(systemName: staged ? "minus" : "plus")
                        .frame(width: 19, height: 19)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(staged ? "Unstage" : "Stage")
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .help("View \(staged ? "staged" : "working tree") diff for \(change.path)")
        .listRowBackground(
            store.selectedChange == change && store.selectedChangeIsStaged == staged
                ? GitForkTheme.accent.opacity(0.12)
                : Color.clear
        )
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
                Toggle("Amend", isOn: $store.amend)
                    .toggleStyle(.checkbox)
                    .font(.caption)
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
                Button(store.amend ? "Amend Commit" : "Commit \(store.branch)") {
                    store.createCommit()
                }
                .buttonStyle(.borderedProminent)
                .help(store.amend ? "Replace the latest commit" : "Commit the staged changes")
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
}

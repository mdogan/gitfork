import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            if let commit = store.selectedCommit, store.selectedSection == .history {
                CommitHeader(commit: commit)
                Divider()
                DiffTextView(text: store.diff)
            } else if let change = store.selectedChange, store.selectedSection == .changes {
                ChangeHeader(change: change, staged: store.selectedChangeIsStaged)
                Divider()
                DiffTextView(text: store.diff)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a commit or changed file to inspect it.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CommitHeader: View {
    let commit: GitCommit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(commit.subject)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)

            HStack(spacing: 16) {
                Label(commit.authorName, systemImage: "person.crop.circle")
                Label {
                    Text(commit.date, format: .dateTime.year().month().day().hour().minute())
                } icon: {
                    Image(systemName: "calendar")
                }
                CommitSignatureBadge(signature: commit.signature)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                CopyableValue(label: "COMMIT", value: commit.hash, display: commit.shortHash)
                if let parent = commit.parents.first {
                    CopyableValue(label: "PARENT", value: parent, display: String(parent.prefix(8)))
                }
                if commit.parents.count > 1 {
                    Text("MERGE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GitForkTheme.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(GitForkTheme.purple.opacity(0.12), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.bar)
    }
}

private struct ChangeHeader: View {
    @EnvironmentObject private var store: RepositoryStore
    let change: WorkingChange
    let staged: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(change.statusSymbol)
                .font(.headline.monospaced())
                .foregroundStyle(Color.statusColor(change.statusSymbol))
                .frame(width: 32, height: 32)
                .background(Color.statusColor(change.statusSymbol).opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(change.path)
                    .font(.headline)
                    .textSelection(.enabled)
                Text("\(change.displayStatus) · \(staged ? "Staged" : "Working tree")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                staged ? store.unstage(change) : store.stage(change)
            } label: {
                Label(staged ? "Unstage" : "Stage", systemImage: staged ? "minus" : "plus")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help(staged ? "Move this file back to working changes" : "Stage this file for commit")
        }
        .padding(14)
        .background(.bar)
    }
}

private struct CopyableValue: View {
    let label: String
    let value: String
    let display: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
            Text(display)
                .font(.caption.monospaced())
        }
        .contextMenu {
            Button("Copy \(label.capitalized)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
        }
    }
}

private struct DiffTextView: View {
    let text: String

    var body: some View {
        if text.isEmpty {
            VStack {
                ProgressView()
                Text("Loading diff…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { viewport in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            DiffLine(line: line)
                        }
                    }
                    .padding(.bottom, 8)
                    .frame(
                        minWidth: viewport.size.width,
                        minHeight: viewport.size.height,
                        alignment: .topLeading
                    )
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}

private struct DiffLine: View {
    let line: String

    private var foreground: Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color(red: 0.10, green: 0.55, blue: 0.25) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color(red: 0.78, green: 0.18, blue: 0.18) }
        if line.hasPrefix("@@") { return GitForkTheme.blue }
        if line.hasPrefix("diff ") || line.hasPrefix("commit ") { return GitForkTheme.purple }
        return .primary
    }

    private var background: Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return GitForkTheme.green.opacity(0.10) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return GitForkTheme.red.opacity(0.09) }
        if line.hasPrefix("@@") { return GitForkTheme.blue.opacity(0.08) }
        return .clear
    }

    var body: some View {
        Text(line.isEmpty ? " " : line)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(foreground)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
    }
}

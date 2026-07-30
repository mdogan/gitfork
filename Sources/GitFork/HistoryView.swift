import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        let commits = store.filteredCommits
        let graph = store.searchText.isEmpty
            ? CommitGraphLayout(commits: commits)
            : CommitGraphLayout(
                commits: commits,
                connectingThrough: store.commits
            )
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedReference?.name ?? "All Commits")
                        .font(.headline)
                    Text("\(commits.count) commits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if commits.isEmpty {
                ContentUnavailableView(
                    "No Commits",
                    systemImage: "clock",
                    description: Text(store.searchText.isEmpty ? "This repository has no commits yet." : "No commits match your search.")
                )
            } else {
                List(selection: commitSelection) {
                    ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                        CommitRow(
                            commit: commit,
                            graphRow: graph.rows[index],
                            graphColumnCount: graph.columnCount
                        )
                        .tag(commit)
                        .listRowInsets(
                            EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 10)
                        )
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search commits")
    }

    private var commitSelection: Binding<GitCommit?> {
        Binding(
            get: { store.selectedCommit },
            set: { store.selectCommit($0) }
        )
    }
}

private struct CommitRow: View {
    let commit: GitCommit
    let graphRow: CommitGraphRow
    let graphColumnCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: graphWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(commit.subject)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)

                    CommitSignatureBadge(signature: commit.signature, compact: true)

                    ForEach(commit.decorations.prefix(2), id: \.self) { decoration in
                        HStack(spacing: 3) {
                            Image(systemName: labelIcon(decoration))
                                .font(.system(size: 8, weight: .bold))
                            Text(cleanDecoration(decoration))
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(labelColor(decoration))
                        .background(labelColor(decoration).opacity(0.14), in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(labelColor(decoration).opacity(0.22), lineWidth: 0.5)
                        )
                        .lineLimit(1)
                    }
                }

                HStack(spacing: 7) {
                    IdentityAvatar(name: commit.authorName, initials: commit.initials)
                    Text(commit.authorName)
                        .lineLimit(1)
                    Text("·")
                    Text(commit.date, format: .relative(presentation: .named))
                    if commit.parents.count > 1 {
                        Label(
                            "\(commit.parents.count) parents",
                            systemImage: "arrow.triangle.merge"
                        )
                        .foregroundStyle(GitForkTheme.purple)
                    }
                    Spacer()
                    Text(commit.shortHash)
                        .font(.caption.monospaced())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 7)
        }
        .overlay(alignment: .leading) {
            CommitGraph(
                row: graphRow,
                columnCount: graphColumnCount
            )
            .frame(width: graphWidth)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .help(parentDescription)
        .accessibilityElement(children: .combine)
        .accessibilityValue(parentDescription)
    }

    private var graphWidth: CGFloat {
        min(
            max(28, CGFloat(graphColumnCount - 1) * 14 + 14),
            140
        )
    }

    private var parentDescription: String {
        guard !commit.parents.isEmpty else {
            return "Root commit · no parents"
        }
        let hashes = commit.parents
            .map { String($0.prefix(8)) }
            .joined(separator: ", ")
        let label = commit.parents.count == 1 ? "Parent" : "Parents"
        return "\(label): \(hashes)"
    }

    private func cleanDecoration(_ value: String) -> String {
        value
            .replacingOccurrences(of: "HEAD -> ", with: "")
            .replacingOccurrences(of: "tag: ", with: "")
    }

    private func labelColor(_ value: String) -> Color {
        if value.contains("tag:") { return GitForkTheme.purple }
        if value.contains("HEAD") { return GitForkTheme.accent }
        if value.contains("/") { return GitForkTheme.blue }
        return GitForkTheme.green
    }

    private func labelIcon(_ value: String) -> String {
        if value.contains("tag:") { return "tag.fill" }
        if value.contains("HEAD") { return "smallcircle.filled.circle" }
        if value.contains("/") { return "cloud" }
        return "arrow.triangle.branch"
    }
}

private struct CommitGraph: View {
    let row: CommitGraphRow
    let columnCount: Int

    private let colors: [Color] = [
        GitForkTheme.accent,
        GitForkTheme.purple,
        GitForkTheme.green,
        GitForkTheme.orange,
        Color(red: 0.20, green: 0.68, blue: 0.66),
        Color(red: 0.90, green: 0.42, blue: 0.68),
        Color(red: 0.42, green: 0.48, blue: 0.90),
        Color(red: 0.89, green: 0.68, blue: 0.24)
    ]

    var body: some View {
        Canvas { context, size in
            for segment in row.segments {
                let start = point(for: segment.start, in: size)
                let end = point(for: segment.end, in: size)
                var path = Path()
                path.move(to: start)

                if start.x == end.x {
                    path.addLine(to: end)
                } else {
                    let middleY = (start.y + end.y) / 2
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: start.x, y: middleY),
                        control2: CGPoint(x: end.x, y: middleY)
                    )
                }

                context.stroke(
                    path,
                    with: .color(color(segment.color).opacity(0.82)),
                    style: StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            let nodePoint = point(
                for: .node(row.nodeColumn),
                in: size
            )
            let node = Path(
                ellipseIn: CGRect(
                    x: nodePoint.x - 5,
                    y: nodePoint.y - 5,
                    width: 10,
                    height: 10
                )
            )
            context.fill(node, with: .color(color(row.nodeColor)))
            context.stroke(
                node,
                with: .color(.white.opacity(0.72)),
                lineWidth: 1
            )
        }
    }

    private func point(
        for anchor: CommitGraphAnchor,
        in size: CGSize
    ) -> CGPoint {
        let horizontalInset: CGFloat = 7
        let availableWidth = max(0, size.width - horizontalInset * 2)
        let spacing = columnCount > 1
            ? availableWidth / CGFloat(columnCount - 1)
            : 0
        let x = columnCount > 1
            ? horizontalInset + CGFloat(anchor.column) * spacing
            : size.width / 2
        let y: CGFloat
        switch anchor {
        case .top:
            y = 0
        case .node:
            y = size.height / 2
        case .bottom:
            y = size.height
        }
        return CGPoint(x: x, y: y)
    }

    private func color(_ index: Int) -> Color {
        colors[index % colors.count]
    }
}

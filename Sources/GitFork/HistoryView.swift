import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedReference?.name ?? "All Commits")
                        .font(.headline)
                    Text("\(store.filteredCommits.count) commits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if store.filteredCommits.isEmpty {
                ContentUnavailableView(
                    "No Commits",
                    systemImage: "clock",
                    description: Text(store.searchText.isEmpty ? "This repository has no commits yet." : "No commits match your search.")
                )
            } else {
                List(store.filteredCommits, selection: commitSelection) { commit in
                    CommitRow(commit: commit)
                        .tag(commit)
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 10))
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

    var body: some View {
        HStack(spacing: 10) {
            CommitGraphGlyph(isMerge: commit.parents.count > 1)
                .frame(width: 24, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(commit.subject)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)

                    ForEach(commit.decorations.prefix(2), id: \.self) { decoration in
                        Text(cleanDecoration(decoration))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .foregroundStyle(labelColor(decoration))
                            .background(labelColor(decoration).opacity(0.13), in: Capsule())
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 7) {
                    AvatarView(initials: commit.initials)
                    Text(commit.authorName)
                        .lineLimit(1)
                    Text("·")
                    Text(commit.date, format: .relative(presentation: .named))
                    Spacer()
                    Text(commit.shortHash)
                        .font(.caption.monospaced())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
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
}

private struct CommitGraphGlyph: View {
    let isMerge: Bool

    var body: some View {
        Canvas { context, size in
            let centerX = size.width / 2
            var main = Path()
            main.move(to: CGPoint(x: centerX, y: 0))
            main.addLine(to: CGPoint(x: centerX, y: size.height))
            context.stroke(main, with: .color(GitForkTheme.accent.opacity(0.7)), lineWidth: 2)

            if isMerge {
                var branch = Path()
                branch.move(to: CGPoint(x: centerX, y: size.height * 0.5))
                branch.addCurve(
                    to: CGPoint(x: size.width, y: 0),
                    control1: CGPoint(x: size.width, y: size.height * 0.45),
                    control2: CGPoint(x: size.width, y: size.height * 0.25)
                )
                context.stroke(branch, with: .color(GitForkTheme.purple.opacity(0.75)), lineWidth: 2)
            }

            let circle = Path(
                ellipseIn: CGRect(x: centerX - 5, y: size.height / 2 - 5, width: 10, height: 10)
            )
            context.fill(circle, with: .color(GitForkTheme.accent))
            context.stroke(circle, with: .color(.white), lineWidth: 1.5)
        }
    }
}

private struct AvatarView: View {
    let initials: String

    var body: some View {
        Circle()
            .fill(GitForkTheme.blue.opacity(0.15))
            .frame(width: 18, height: 18)
            .overlay {
                Text(initials)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(GitForkTheme.blue)
            }
    }
}

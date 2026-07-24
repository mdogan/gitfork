import SwiftUI

struct RepositorySwitcherMenu: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        Menu {
            Section("Recent Repositories") {
                ForEach(store.recentRepositories, id: \.path) { repository in
                    Button {
                        guard !isCurrent(repository) else { return }
                        store.openRepository(repository)
                    } label: {
                        Label {
                            Text(repositoryLabel(repository))
                        } icon: {
                            Image(systemName: isCurrent(repository) ? "checkmark" : "shippingbox")
                        }
                    }
                }
            }

            Divider()

            Button {
                store.chooseRepository()
            } label: {
                Label("Open Other Repository…", systemImage: "folder.badge.plus")
            }
        } label: {
            RepositorySwitcherLabel(repositoryName: store.repositoryName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("Switch repository")
        .accessibilityLabel("Switch repository")
    }

    private func isCurrent(_ repository: URL) -> Bool {
        repository.standardizedFileURL == store.repositoryURL?.standardizedFileURL
    }

    private func repositoryLabel(_ repository: URL) -> String {
        let parent = repository.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty
            ? repository.lastPathComponent
            : "\(repository.lastPathComponent) — \(parent)"
    }
}

private struct RepositorySwitcherLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    let repositoryName: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(GitForkTheme.accent)
            Text(repositoryName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isHovering ? GitForkTheme.accent : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isHovering
                        ? GitForkTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.12)
                        : .clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isHovering ? GitForkTheme.accent.opacity(0.38) : .clear,
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

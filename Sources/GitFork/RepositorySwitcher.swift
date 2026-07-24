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
            HStack(spacing: 7) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(GitForkTheme.accent)
                Text(store.repositoryName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 220)
        }
        .menuStyle(.button)
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

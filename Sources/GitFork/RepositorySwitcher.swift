import SwiftUI

enum RepositorySwitcherSearch {
    static func filter(_ repositories: [URL], query: String) -> [URL] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return repositories }

        return repositories.filter { repository in
            repository.lastPathComponent.localizedCaseInsensitiveContains(query)
                || repository.path.localizedCaseInsensitiveContains(query)
        }
    }
}

enum RepositorySwitcherNavigation {
    static func reconcile(
        selection: URL?,
        repositories: [URL],
        currentRepository: URL?
    ) -> URL? {
        if let selection,
           let repository = repositories.first(where: {
               isSameRepository($0, selection)
           }) {
            return repository
        }

        return repositories.first {
            !isSameRepository($0, currentRepository)
        } ?? repositories.first
    }

    static func move(
        selection: URL?,
        offset: Int,
        repositories: [URL]
    ) -> URL? {
        guard !repositories.isEmpty else { return nil }
        guard let selection,
              let index = repositories.firstIndex(where: {
                  isSameRepository($0, selection)
              }) else {
            return offset < 0 ? repositories.last : repositories.first
        }

        let count = repositories.count
        let nextIndex = (index + offset % count + count) % count
        return repositories[nextIndex]
    }

    private static func isSameRepository(_ lhs: URL, _ rhs: URL?) -> Bool {
        lhs.standardizedFileURL == rhs?.standardizedFileURL
    }
}

struct RepositorySwitcherMenu: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        Menu {
            Section("Recent Repositories") {
                ForEach(store.recentRepositories, id: \.path) { repository in
                    Button {
                        guard !isCurrent(repository) else { return }
                        store.requestOpenRepository(repository)
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

struct RepositorySwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: RepositoryStore
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""
    @State private var selectedRepository: URL?

    private var repositories: [URL] {
        RepositorySwitcherSearch.filter(
            store.recentRepositories,
            query: searchText
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .font(.title2)
                        .foregroundStyle(GitForkTheme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Switch Repository")
                            .font(.title2.weight(.semibold))
                        Text("Choose a recent repository or open another folder.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Search repositories", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let repository = selectedRepository {
                            open(repository)
                        }
                    }
                    .onKeyPress(
                        keys: [.escape, .upArrow, .downArrow]
                    ) { press in
                        if press.key == .escape {
                            dismiss()
                        } else if press.key == .upArrow {
                            moveSelection(by: -1)
                        } else {
                            moveSelection(by: 1)
                        }
                        return .handled
                    }
            }
            .padding(20)

            Divider()

            Group {
                if repositories.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(repositories, id: \.path) { repository in
                                    let isSelected = isSelected(repository)

                                    Button {
                                        open(repository)
                                    } label: {
                                        RepositorySwitcherRow(
                                            repository: repository,
                                            isCurrent: isCurrent(repository),
                                            isSelected: isSelected
                                        )
                                    }
                                    .buttonStyle(
                                        GitForkHoverButtonStyle(
                                            .row(isSelected: isSelected)
                                        )
                                    )
                                    .help(
                                        isCurrent(repository)
                                            ? "\(repository.path) is currently open"
                                            : "Open \(repository.path)"
                                    )
                                    .accessibilityAddTraits(
                                        isSelected ? .isSelected : []
                                    )
                                    .id(repository.path)
                                }
                            }
                            .padding(12)
                        }
                        .onChange(of: selectedRepository) { _, repository in
                            guard let repository else { return }
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(repository.path)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button {
                    openOtherRepository()
                } label: {
                    Label("Open Other Repository…", systemImage: "folder.badge.plus")
                }
                .help("Choose a repository that is not in the recent list")

                Spacer()

                HStack(spacing: 12) {
                    Text("↑↓ Navigate")
                    Text("↩ Open")
                    Text("esc Close")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 430)
        .onAppear {
            reconcileSelection()
            isSearchFocused = true
        }
        .onChange(of: searchText) {
            reconcileSelection()
        }
    }

    private func isCurrent(_ repository: URL) -> Bool {
        repository.standardizedFileURL == store.repositoryURL?.standardizedFileURL
    }

    private func isSelected(_ repository: URL) -> Bool {
        repository.standardizedFileURL == selectedRepository?.standardizedFileURL
    }

    private func reconcileSelection() {
        selectedRepository = RepositorySwitcherNavigation.reconcile(
            selection: selectedRepository,
            repositories: repositories,
            currentRepository: store.repositoryURL
        )
    }

    private func moveSelection(by offset: Int) {
        selectedRepository = RepositorySwitcherNavigation.move(
            selection: selectedRepository,
            offset: offset,
            repositories: repositories
        )
    }

    private func open(_ repository: URL) {
        dismiss()
        guard !isCurrent(repository) else { return }
        store.requestOpenRepository(repository)
    }

    private func openOtherRepository() {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            store.chooseRepository()
        }
    }
}

private struct RepositorySwitcherRow: View {
    let repository: URL
    let isCurrent: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCurrent ? "checkmark.circle.fill" : "shippingbox")
                .font(.title3)
                .foregroundStyle(isCurrent ? GitForkTheme.green : GitForkTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(repository.lastPathComponent)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(repository.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isCurrent {
                Text("Current")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if isSelected {
                Image(systemName: "return")
                    .font(.caption)
                    .foregroundStyle(GitForkTheme.accent)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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

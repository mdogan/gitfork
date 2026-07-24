import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: RepositoryStore
    @State private var branchesExpanded = true
    @State private var remotesExpanded = false
    @State private var tagsExpanded = false
    @State private var stashesExpanded = false
    @State private var worktreesExpanded = false

    private var currentBranch: GitReference? {
        store.references.first { $0.kind == .localBranch && $0.isCurrent }
    }

    private var remainingLocalBranches: [GitReference] {
        store.references.filter { $0.kind == .localBranch && !$0.isCurrent }
    }

    private func references(of kind: ReferenceKind) -> [GitReference] {
        store.references.filter { $0.kind == kind }
    }

    var body: some View {
        List {
            Section {
                SidebarRow(
                    title: WorkspaceSection.changes.rawValue,
                    icon: WorkspaceSection.changes.icon,
                    isSelected: store.selectedSection == .changes,
                    size: .regular
                ) {
                    store.selectedSection = .changes
                    store.selectedReference = nil
                    if let change = store.changes.first {
                        store.selectChange(change, staged: change.isStaged)
                    }
                } badge: {
                    if !store.changes.isEmpty {
                        Text("\(store.changes.count)")
                    }
                }

                SidebarRow(
                    title: WorkspaceSection.history.rawValue,
                    icon: WorkspaceSection.history.icon,
                    isSelected: store.selectedSection == .history && store.selectedReference == nil,
                    size: .regular
                ) {
                    store.selectReference(nil)
                } badge: {
                    EmptyView()
                }
            }

            Section("Branches", isExpanded: $branchesExpanded) {
                if let currentBranch {
                    ReferenceSidebarRow(
                        reference: currentBranch,
                        title: currentBranch.name,
                        icon: "checkmark"
                    )
                    .fontWeight(.semibold)
                }

                ReferenceTreeRows(references: remainingLocalBranches)

                if currentBranch == nil && remainingLocalBranches.isEmpty {
                    EmptySidebarRow(title: "No Branches")
                }
            }

            Section("Remotes", isExpanded: $remotesExpanded) {
                if references(of: .remoteBranch).isEmpty {
                    EmptySidebarRow(title: "No Remotes")
                } else {
                    ReferenceTreeRows(references: references(of: .remoteBranch))
                }
            }

            Section("Tags", isExpanded: $tagsExpanded) {
                if references(of: .tag).isEmpty {
                    EmptySidebarRow(title: "No Tags")
                } else {
                    ReferenceTreeRows(references: references(of: .tag))
                }
            }

            Section("Stashes", isExpanded: $stashesExpanded) {
                if store.stashes.isEmpty {
                    EmptySidebarRow(title: "No Stashes")
                } else {
                    ForEach(store.stashes) { stash in
                        SidebarRow(
                            title: stash.displayName,
                            icon: "archivebox",
                            isSelected: store.selectedStash == stash
                        ) {
                            store.selectStash(stash)
                        } badge: {
                            EmptyView()
                        }
                        .contextMenu {
                            Button("Show Stash") {
                                store.selectStash(stash)
                            }
                        }
                    }
                }
            }

            Section("Worktrees", isExpanded: $worktreesExpanded) {
                if store.worktrees.isEmpty {
                    EmptySidebarRow(title: "No Worktrees")
                } else {
                    ForEach(store.worktrees) { worktree in
                        SidebarRow(
                            title: worktree.displayName,
                            icon: worktree.isCurrent
                                ? "checkmark.circle.fill"
                                : "rectangle.stack",
                            isSelected: false
                        ) {
                            guard !worktree.isCurrent else { return }
                            store.openRepository(
                                URL(fileURLWithPath: worktree.path, isDirectory: true)
                            )
                        } badge: {
                            Text(worktree.branchName ?? (worktree.isDetached ? "Detached" : ""))
                                .lineLimit(1)
                        }
                        .help(worktree.path)
                        .contextMenu {
                            Button(worktree.isCurrent ? "Current Worktree" : "Open Worktree") {
                                guard !worktree.isCurrent else { return }
                                store.openRepository(
                                    URL(fileURLWithPath: worktree.path, isDirectory: true)
                                )
                            }
                            .disabled(worktree.isCurrent || worktree.isPrunable)
                        }
                        .disabled(worktree.isPrunable)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            RepositoryIdentityView()
        }
    }
}

private struct ReferenceTreeRows: View {
    let references: [GitReference]

    var body: some View {
        OutlineGroup(
            ReferenceTreeNode.build(from: references),
            children: \.outlineChildren
        ) { node in
            if let reference = node.reference {
                ReferenceSidebarRow(
                    reference: reference,
                    title: node.name,
                    icon: node.children.isEmpty ? reference.kind.icon : "folder"
                )
            } else {
                Label(node.name, systemImage: "folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(node.path)
            }
        }
    }
}

private struct ReferenceSidebarRow: View {
    @EnvironmentObject private var store: RepositoryStore

    let reference: GitReference
    let title: String
    let icon: String

    var body: some View {
        SidebarRow(
            title: title,
            icon: icon,
            isSelected: store.selectedReference == reference
        ) {
            store.selectReference(reference)
        } badge: {
            EmptyView()
        }
        .help(reference.name)
        .contextMenu {
            Button("Show History") {
                store.selectReference(reference)
            }
            Divider()
            Button(reference.kind == .tag ? "Checkout Detached" : "Checkout") {
                store.checkout(reference)
            }
        }
    }
}

private struct EmptySidebarRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.leading, 26)
    }
}

private enum SidebarRowSize {
    case regular
    case compact
}

private struct SidebarRow<Badge: View>: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let size: SidebarRowSize
    let action: () -> Void
    @ViewBuilder let badge: () -> Badge

    init(
        title: String,
        icon: String,
        isSelected: Bool,
        size: SidebarRowSize = .compact,
        action: @escaping () -> Void,
        @ViewBuilder badge: @escaping () -> Badge
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.size = size
        self.action = action
        self.badge = badge
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: size == .regular ? 9 : 7) {
                Image(systemName: icon)
                    .frame(width: size == .regular ? 18 : 15)
                    .foregroundStyle(isSelected ? GitForkTheme.accent : .secondary)
                Text(title)
                    .lineLimit(1)
                Spacer()
                badge()
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(size == .regular ? .body : .callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            GitForkHoverButtonStyle(
                size == .regular
                    ? .row(isSelected: isSelected)
                    : .compactRow(isSelected: isSelected)
            )
        )
        .help("Show \(title)")
        .listRowBackground(Color.clear)
    }
}

private struct RepositoryIdentityView: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(GitForkTheme.accent.gradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.repositoryName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(store.repositoryURL?.deletingLastPathComponent().path ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                Button {
                    store.chooseRepository()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(GitForkHoverButtonStyle(.icon))
                .help("Open another repository")
            }
            .padding(10)
            .background(.bar)
        }
    }
}

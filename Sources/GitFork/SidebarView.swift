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

            Section(isExpanded: $branchesExpanded) {
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
            } header: {
                SidebarSectionHeader(title: "Branches", isExpanded: $branchesExpanded)
            }

            Section(isExpanded: $remotesExpanded) {
                if references(of: .remoteBranch).isEmpty {
                    EmptySidebarRow(title: "No Remotes")
                } else {
                    ReferenceTreeRows(references: references(of: .remoteBranch))
                }
            } header: {
                SidebarSectionHeader(title: "Remotes", isExpanded: $remotesExpanded)
            }

            Section(isExpanded: $tagsExpanded) {
                if references(of: .tag).isEmpty {
                    EmptySidebarRow(title: "No Tags")
                } else {
                    ReferenceTreeRows(references: references(of: .tag))
                }
            } header: {
                SidebarSectionHeader(title: "Tags", isExpanded: $tagsExpanded)
            }

            Section(isExpanded: $stashesExpanded) {
                if store.stashes.isEmpty {
                    EmptySidebarRow(title: "No Stashes")
                } else {
                    ForEach(store.stashes) { stash in
                        StashSidebarRow(stash: stash)
                    }
                }
            } header: {
                SidebarSectionHeader(title: "Stashes", isExpanded: $stashesExpanded)
            }

            Section(isExpanded: $worktreesExpanded) {
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
            } header: {
                SidebarSectionHeader(title: "Worktrees", isExpanded: $worktreesExpanded)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            RepositoryIdentityView()
        }
    }
}

private struct StashSidebarRow: View {
    private enum Action: Equatable {
        case apply
        case drop
    }

    @EnvironmentObject private var store: RepositoryStore
    @State private var pendingAction: Action?
    @State private var isConfirmingAction = false

    let stash: GitStash

    var body: some View {
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

            Divider()

            Button {
                confirm(.apply)
            } label: {
                Label("Apply Stash", systemImage: "arrow.uturn.backward")
            }
            .disabled(store.isLoading)

            Button(role: .destructive) {
                confirm(.drop)
            } label: {
                Label("Drop Stash", systemImage: "trash")
            }
            .disabled(store.isLoading)
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $isConfirmingAction,
            titleVisibility: .visible
        ) {
            if pendingAction == .apply {
                Button("Apply Stash") {
                    store.apply(stash)
                }
            } else if pendingAction == .drop {
                Button("Drop Stash", role: .destructive) {
                    store.drop(stash)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationTitle: String {
        switch pendingAction {
        case .apply:
            "Apply “\(stash.displayName)”?"
        case .drop:
            "Drop “\(stash.displayName)”?"
        case nil:
            "Confirm Stash Action"
        }
    }

    private var confirmationMessage: String {
        switch pendingAction {
        case .apply:
            """
            This applies the stashed changes and restores their staged state. \
            The stash will remain available. Existing changes may cause conflicts.
            """
        case .drop:
            """
            This permanently removes the stash without applying its changes. \
            This action cannot be undone.
            """
        case nil:
            ""
        }
    }

    private func confirm(_ action: Action) {
        pendingAction = action
        isConfirmingAction = true
    }
}

private struct SidebarSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse \(title)" : "Expand \(title)")
    }
}

/// A tree node paired with the depth it is rendered at. The tree is flattened
/// so every row — folder or reference — is an ordinary, fully clickable row.
private struct ReferenceTreeRow: Identifiable {
    let node: ReferenceTreeNode
    let depth: Int

    var id: String { node.id }
}

private struct ReferenceTreeRows: View {
    private static let indentStep: CGFloat = 13

    @State private var expandedPaths: Set<String> = []

    let references: [GitReference]

    var body: some View {
        ForEach(rows(for: ReferenceTreeNode.build(from: references), depth: 0)) { row in
            if row.node.children.isEmpty, let reference = row.node.reference {
                ReferenceSidebarRow(
                    reference: reference,
                    title: row.node.name,
                    icon: reference.kind.icon,
                    indent: indent(for: row.depth)
                )
            } else {
                ReferenceFolderRow(
                    node: row.node,
                    indent: indent(for: row.depth),
                    isExpanded: expandedPaths.contains(row.node.id)
                ) {
                    toggle(row.node)
                }
            }
        }
    }

    private func rows(for nodes: [ReferenceTreeNode], depth: Int) -> [ReferenceTreeRow] {
        nodes.flatMap { node -> [ReferenceTreeRow] in
            let row = ReferenceTreeRow(node: node, depth: depth)
            guard !node.children.isEmpty, expandedPaths.contains(node.id) else {
                return [row]
            }
            return [row] + rows(for: node.children, depth: depth + 1)
        }
    }

    private func indent(for depth: Int) -> CGFloat {
        CGFloat(depth) * Self.indentStep
    }

    private func toggle(_ node: ReferenceTreeNode) {
        if expandedPaths.contains(node.id) {
            expandedPaths.remove(node.id)
        } else {
            expandedPaths.insert(node.id)
        }
    }
}

/// A grouping row such as `origin` or `feature`. The whole row is the
/// disclosure control, so clicking the name toggles it like the chevron does.
private struct ReferenceFolderRow: View {
    let node: ReferenceTreeNode
    let indent: CGFloat
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeOut(duration: 0.15), value: isExpanded)
                    .frame(width: 16)
                Text(node.name)
                    .lineLimit(1)
                Spacer()
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.leading, indent)
            .contentShape(Rectangle())
        }
        .buttonStyle(GitForkHoverButtonStyle(.compactRow(isSelected: false)))
        .help(isExpanded ? "Collapse \(node.path)" : "Expand \(node.path)")
        .listRowBackground(Color.clear)
    }
}

private struct ReferenceSidebarRow: View {
    @EnvironmentObject private var store: RepositoryStore
    @State private var isConfirmingDelete = false

    let reference: GitReference
    let title: String
    let icon: String
    var indent: CGFloat = 0

    var body: some View {
        SidebarRow(
            title: title,
            icon: icon,
            isSelected: store.selectedReference == reference,
            indent: indent
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
            .disabled(store.isLoading)

            if reference.kind != .remoteBranch {
                Divider()
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label(deleteActionTitle, systemImage: "trash")
                }
                .disabled(reference.isCurrent || store.isLoading)
            }
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            if isConfirmingForceDelete {
                Button("Force Delete Branch", role: .destructive) {
                    store.forceDelete(reference)
                }
                .disabled(store.isLoading)
            } else {
                Button(deleteActionTitle, role: .destructive) {
                    store.delete(reference)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var deleteActionTitle: String {
        reference.kind == .tag ? "Delete Tag" : "Delete Branch"
    }

    private var isConfirmingForceDelete: Bool {
        store.branchPendingForceDelete == reference
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { isConfirmingDelete || isConfirmingForceDelete },
            set: { isPresented in
                guard !isPresented else { return }
                isConfirmingDelete = false
                if isConfirmingForceDelete {
                    store.cancelForceDelete()
                }
            }
        )
    }

    private var deleteConfirmationTitle: String {
        if isConfirmingForceDelete {
            return "Force Delete Branch “\(reference.name)”?"
        }
        return "\(deleteActionTitle) “\(reference.name)”?"
    }

    private var deleteConfirmationMessage: String {
        if isConfirmingForceDelete {
            return """
            Git reports that this branch contains commits that are not fully merged. \
            Force deleting it runs git branch -D and may permanently discard those commits.
            """
        }
        if reference.kind == .tag {
            return "This deletes the local tag. It does not delete the tag from any remote."
        }
        return "This deletes the local branch. Git will refuse if it contains unmerged commits."
    }
}

private struct EmptySidebarRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.callout)
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
    let indent: CGFloat
    let action: () -> Void
    @ViewBuilder let badge: () -> Badge

    init(
        title: String,
        icon: String,
        isSelected: Bool,
        size: SidebarRowSize = .compact,
        indent: CGFloat = 0,
        action: @escaping () -> Void,
        @ViewBuilder badge: @escaping () -> Badge
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.size = size
        self.indent = indent
        self.action = action
        self.badge = badge
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: size == .regular ? 9 : 7) {
                Image(systemName: icon)
                    .frame(width: size == .regular ? 20 : 16)
                    .foregroundStyle(isSelected ? GitForkTheme.accent : .secondary)
                Text(title)
                    .lineLimit(1)
                Spacer()
                badge()
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(size == .regular ? .title3 : .body)
            .padding(.leading, indent)
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
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(store.repositoryURL?.deletingLastPathComponent().path ?? "")
                        .font(.caption)
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

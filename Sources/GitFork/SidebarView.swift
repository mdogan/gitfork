import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: RepositoryStore
    @State private var branchesExpanded = true
    @State private var remotesExpanded = false
    @State private var tagsExpanded = false
    @State private var stashesExpanded = false
    @State private var worktreesExpanded = false

    private var primaryBranch: GitReference? {
        GitReference.primaryLocalBranch(in: store.references)
    }

    private var currentBranch: GitReference? {
        store.references.first {
            $0.kind == .localBranch && $0.isCurrent && $0 != primaryBranch
        }
    }

    private var remainingLocalBranches: [GitReference] {
        store.references.filter {
            $0.kind == .localBranch && !$0.isCurrent && $0 != primaryBranch
        }
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
                    store.selectChanges()
                } badge: {
                    if !store.changes.isEmpty {
                        Text("\(store.changes.count)")
                    }
                }

                SidebarRow(
                    title: WorkspaceSection.history.rawValue,
                    icon: WorkspaceSection.history.icon,
                    isSelected: store.selectedSection == .history
                        && store.selectedReference == nil
                        && store.selectedStash == nil
                        && store.historyScope == .all,
                    size: .regular
                ) {
                    store.selectReference(nil)
                } badge: {
                    EmptyView()
                }

                SidebarRow(
                    title: "Unreachable Commits",
                    icon: "lifepreserver",
                    isSelected: store.selectedSection == .history
                        && store.selectedStash == nil
                        && store.historyScope == .lostAndDangling,
                    indent: 29
                ) {
                    store.selectLostAndDanglingCommits()
                } badge: {
                    EmptyView()
                }
            }

            Section(isExpanded: $branchesExpanded) {
                if let primaryBranch {
                    ReferenceSidebarRow(
                        reference: primaryBranch,
                        title: primaryBranch.name,
                        icon: primaryBranch.isCurrent
                            ? "checkmark.circle.fill"
                            : primaryBranch.kind.icon
                    )
                    .fontWeight(.bold)
                }

                if let currentBranch {
                    ReferenceSidebarRow(
                        reference: currentBranch,
                        title: currentBranch.name,
                        icon: "checkmark.circle.fill"
                    )
                    .fontWeight(.semibold)
                }

                ReferenceTreeRows(references: remainingLocalBranches)

                if primaryBranch == nil && currentBranch == nil && remainingLocalBranches.isEmpty {
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
                        WorktreeSidebarRow(worktree: worktree)
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

private struct WorktreeSidebarRow: View {
    private enum Action {
        case delete
        case prune
    }

    @EnvironmentObject private var store: RepositoryStore
    @State private var pendingAction: Action?
    @State private var isConfirmingAction = false

    let worktree: GitWorktree

    var body: some View {
        SidebarRow(
            title: worktree.displayName,
            icon: worktree.isCurrent
                ? "checkmark.circle.fill"
                : "rectangle.stack",
            isSelected: false,
            isEnabled: !worktree.isPrunable
        ) {
            open()
        } badge: {
            Text(worktree.branchName ?? (worktree.isDetached ? "Detached" : ""))
                .lineLimit(1)
        }
        .help(worktree.path)
        .contextMenu {
            Button(worktree.isCurrent ? "Current Worktree" : "Open Worktree") {
                open()
            }
            .disabled(worktree.isCurrent || worktree.isPrunable)

            if worktree.isPrunable {
                Divider()
                Button(role: .destructive) {
                    confirm(.prune)
                } label: {
                    Label("Prune Stale Worktrees", systemImage: "trash")
                }
                .disabled(store.isLoading)
            } else if worktree.isDetached && !worktree.isCurrent {
                Divider()
                Button(role: .destructive) {
                    confirm(.delete)
                } label: {
                    Label("Delete Worktree", systemImage: "trash")
                }
                .disabled(
                    worktree.isBare
                        || worktree.isLocked
                        || store.isLoading
                )
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $isConfirmingAction,
            titleVisibility: .visible
        ) {
            if pendingAction == .delete {
                Button("Delete Worktree", role: .destructive) {
                    store.delete(worktree)
                }
                .disabled(store.isLoading)
            } else if pendingAction == .prune {
                Button("Prune Stale Worktrees", role: .destructive) {
                    store.pruneStaleWorktrees()
                }
                .disabled(store.isLoading)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationTitle: String {
        switch pendingAction {
        case .delete:
            "Delete Worktree “\(worktree.displayName)”?"
        case .prune:
            "Prune Stale Worktrees?"
        case nil:
            "Confirm Worktree Action"
        }
    }

    private var confirmationMessage: String {
        switch pendingAction {
        case .delete:
            """
            This removes the worktree directory and its Git registration. Git will refuse \
            if it contains uncommitted changes. Detached commits not referenced by a branch \
            or tag may become unreachable.
            """
        case .prune:
            """
            This removes the Git registration for every stale worktree in this repository. \
            It does not delete existing worktree directories, and Git preserves locked worktrees.
            """
        case nil:
            ""
        }
    }

    private func confirm(_ action: Action) {
        pendingAction = action
        isConfirmingAction = true
    }

    private func open() {
        guard !worktree.isCurrent, !worktree.isPrunable else { return }
        store.openRepository(
            URL(fileURLWithPath: worktree.path, isDirectory: true)
        )
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
    @State private var isRenaming = false

    let reference: GitReference
    let title: String
    let icon: String
    var indent: CGFloat = 0

    var body: some View {
        SidebarRow(
            title: title,
            icon: icon,
            isSelected: store.selectedReference == reference,
            isProminent: reference.isCurrent,
            indent: indent
        ) {
            store.selectReference(reference)
        } badge: {
            if reference.isCurrent {
                Text("CURRENT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(GitForkTheme.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(GitForkTheme.green.opacity(0.13), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(GitForkTheme.green.opacity(0.35), lineWidth: 1)
                    }
            }
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

            if reference.kind == .localBranch {
                Button {
                    isRenaming = true
                } label: {
                    Label("Rename Branch…", systemImage: "pencil")
                }
                .disabled(store.isLoading)
            }

            if reference.kind != .remoteBranch || remoteBranchTarget != nil {
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
            if let remoteBranchTarget {
                Button("Delete from \(remoteBranchTarget.remote)", role: .destructive) {
                    store.deleteRemoteBranch(reference)
                }
                .disabled(store.isLoading)
            } else if isConfirmingForceDelete {
                if let remoteBranch {
                    Button(
                        "Force Delete Branch and \(remoteBranch.shortName)",
                        role: .destructive
                    ) {
                        store.forceDelete(reference, includingRemote: true)
                    }
                    .disabled(store.isLoading)
                }
                Button(forceDeleteActionTitle, role: .destructive) {
                    store.forceDelete(reference)
                }
                .disabled(store.isLoading)
            } else {
                if let remoteBranch {
                    Button(
                        "Delete Branch and \(remoteBranch.shortName)",
                        role: .destructive
                    ) {
                        store.delete(reference, includingRemote: true)
                    }
                }
                Button(localOnlyDeleteActionTitle, role: .destructive) {
                    store.delete(reference)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
        .sheet(isPresented: $isRenaming) {
            RenameBranchSheet(reference: reference, isPresented: $isRenaming)
        }
    }

    /// The remote-tracking branch this row can offer to delete alongside the
    /// local branch, when one still exists.
    private var remoteBranch: GitUpstream? {
        store.deletableRemoteBranch(for: reference)
    }

    /// Set only on `Remotes` rows, where deletion targets the branch on the
    /// remote itself rather than anything local.
    private var remoteBranchTarget: GitUpstream? {
        reference.remoteBranchTarget
    }

    private var deleteActionTitle: String {
        switch reference.kind {
        case .tag: "Delete Tag"
        case .remoteBranch: "Delete Remote Branch"
        case .localBranch: "Delete Branch"
        }
    }

    private var localOnlyDeleteActionTitle: String {
        remoteBranch == nil ? deleteActionTitle : "Delete Local Branch Only"
    }

    private var forceDeleteActionTitle: String {
        remoteBranch == nil ? "Force Delete Branch" : "Force Delete Local Branch Only"
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
        if let remoteBranchTarget {
            return """
            This deletes the branch from \(remoteBranchTarget.remote) for everyone \
            using that remote.\(trackingBranchMessageSuffix)
            """
        }
        if isConfirmingForceDelete {
            return """
            Git reports that this branch contains commits that are not fully merged. \
            Force deleting it runs git branch -D and may permanently discard those commits.\
            \(remoteBranchMessageSuffix)
            """
        }
        if reference.kind == .tag {
            return "This deletes the local tag. It does not delete the tag from any remote."
        }
        return """
        This deletes the local branch. Git will refuse if it contains unmerged commits.\
        \(remoteBranchMessageSuffix)
        """
    }

    private var remoteBranchMessageSuffix: String {
        guard let remoteBranch else { return "" }
        return " " + """
        This branch tracks \(remoteBranch.shortName), which can be deleted from \
        \(remoteBranch.remote) at the same time.
        """
    }

    /// Names the local branches left with an upstream that no longer resolves
    /// once the remote branch is gone.
    private var trackingBranchMessageSuffix: String {
        let tracking = store.localBranchesTracking(reference).map(\.name)
        guard !tracking.isEmpty else { return "" }
        let names = tracking.map { "“\($0)”" }.formatted(.list(type: .and))
        if tracking.count == 1 {
            return " The local branch \(names) keeps its commits but loses its upstream."
        }
        return " The local branches \(names) keep their commits but lose their upstream."
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
    let isEnabled: Bool
    let isProminent: Bool
    let size: SidebarRowSize
    let indent: CGFloat
    let action: () -> Void
    @ViewBuilder let badge: () -> Badge

    init(
        title: String,
        icon: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        isProminent: Bool = false,
        size: SidebarRowSize = .compact,
        indent: CGFloat = 0,
        action: @escaping () -> Void,
        @ViewBuilder badge: @escaping () -> Badge
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isProminent = isProminent
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
                    .foregroundStyle(
                        isProminent
                            ? GitForkTheme.green
                            : isSelected ? GitForkTheme.accent : .secondary
                    )
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
        .disabled(!isEnabled)
        .buttonStyle(
            GitForkHoverButtonStyle(
                size == .regular
                    ? .row(isSelected: isSelected)
                    : .compactRow(isSelected: isSelected)
            )
        )
        .background {
            if isProminent && !isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(GitForkTheme.green.opacity(0.10))
            }
        }
        .overlay {
            if isProminent && !isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(GitForkTheme.green.opacity(0.32), lineWidth: 1)
            }
        }
        .overlay(alignment: .leading) {
            if isProminent {
                Capsule()
                    .fill(GitForkTheme.green)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
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

import AppKit
import Combine
import Foundation

@MainActor
final class RepositoryStore: ObservableObject {
    @Published private(set) var repositoryURL: URL?
    @Published private(set) var branch = ""
    @Published private(set) var upstream: String?
    @Published private(set) var pushTarget: GitPushTarget?
    @Published private(set) var ahead = 0
    @Published private(set) var behind = 0
    @Published private(set) var changes: [WorkingChange] = []
    @Published private(set) var references: [GitReference] = []
    @Published private(set) var stashes: [GitStash] = []
    @Published private(set) var worktrees: [GitWorktree] = []
    @Published private(set) var commits: [GitCommit] = []
    @Published private(set) var diff = ""
    @Published private(set) var isLoading = false
    @Published private(set) var operationLabel: String?
    @Published var selectedSection: WorkspaceSection = .history
    @Published var selectedCommit: GitCommit?
    @Published private(set) var selectedChange: WorkingChange?
    @Published private(set) var selectedChangeIsStaged = false
    @Published private(set) var changeSelection = ChangeSelectionModel()
    @Published var selectedReference: GitReference?
    @Published var selectedStash: GitStash?
    @Published var searchText = ""
    @Published var commitMessage = ""
    @Published var amend = false
    @Published var signCommit = false {
        didSet {
            UserDefaults.standard.set(signCommit, forKey: Self.signCommitKey)
        }
    }
    @Published var errorMessage: String?
    @Published private(set) var branchPendingForceDelete: GitReference?
    @Published var isConfirmingPush = false
    @Published var isShowingCLIInstaller = false
    @Published var isShowingRepositorySwitcher = false
    @Published private(set) var recentRepositories: [URL] = []

    private let client = GitClient()
    private var loadGeneration = 0
    private var monitorTask: Task<Void, Never>?
    private var monitoredState: RepositoryStateToken?
    private var activeOperationID: UUID?
    private let recentKey = "recentRepositories"
    private static let signCommitKey = "signCommitsWithGPG"
    private static let monitorInterval: Duration = .seconds(2)

    init() {
        signCommit = UserDefaults.standard.bool(forKey: Self.signCommitKey)
        recentRepositories = (UserDefaults.standard.stringArray(forKey: recentKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var repositoryName: String {
        repositoryURL?.lastPathComponent ?? "GitFork"
    }

    var stagedChanges: [WorkingChange] {
        changes.filter(\.isStaged)
    }

    var unstagedChanges: [WorkingChange] {
        changes.filter(\.isUnstaged)
    }

    /// Every change-list row in the order the list draws them: staged first,
    /// then working tree. Shift-click ranges follow this order.
    var changeEntries: [ChangeEntry] {
        stagedChanges.map { ChangeEntry($0, staged: true) }
            + unstagedChanges.map { ChangeEntry($0, staged: false) }
    }

    var selectedChangeEntries: [ChangeEntry] {
        changeEntries.filter { changeSelection.contains($0.id) }
    }

    private var changeOrder: [ChangeEntryID] {
        changeEntries.map(\.id)
    }

    var filteredCommits: [GitCommit] {
        guard !searchText.isEmpty else { return commits }
        return commits.filter {
            $0.subject.localizedCaseInsensitiveContains(searchText)
                || $0.authorName.localizedCaseInsensitiveContains(searchText)
                || $0.hash.localizedCaseInsensitiveContains(searchText)
                || $0.decorations.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Open Git Repository"
        panel.message = "Choose a folder containing a Git repository."
        panel.prompt = "Open Repository"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openRepository(url)
    }

    func openRepository(_ url: URL) {
        _ = startOperation("Opening repository") {
            let root = try await self.client.repositoryRoot(from: url)
            try Task.checkCancellation()
            self.stopMonitoring()
            self.repositoryURL = root
            self.remember(root)
            self.prepareForRepositorySwitch()
            try await self.reload(root: root)
            try Task.checkCancellation()
            guard self.isCurrentRepository(root) else { return }
            self.startMonitoring(root: root)
        }
    }

    func openExternalURL(_ url: URL) {
        guard let path = GitForkExternalURL.repositoryPath(from: url) else {
            errorMessage = "GitFork received an invalid repository URL."
            return
        }
        openRepository(URL(fileURLWithPath: path, isDirectory: true))
    }

    func refresh() {
        guard let root = repositoryURL else { return }
        _ = startOperation("Refreshing") {
            try await self.reload(root: root, revision: self.selectedReference?.fullName)
        }
    }

    func selectCommit(_ commit: GitCommit?) {
        selectedStash = nil
        showCommit(commit)
    }

    private func showCommit(_ commit: GitCommit?) {
        selectedCommit = commit
        selectedChange = nil
        guard let root = repositoryURL, let commit else {
            diff = ""
            return
        }
        diff = ""
        loadGeneration += 1
        let generation = loadGeneration
        Task {
            do {
                async let detailsResult = client.commitDetails(at: root, hash: commit.hash)
                async let verifiedCommitResult = client.commit(
                    at: root,
                    revision: commit.hash
                )
                let details = try await detailsResult
                if generation == loadGeneration {
                    diff = details
                }
                let verifiedCommit = try await verifiedCommitResult
                if generation == loadGeneration,
                   selectedCommit?.hash == verifiedCommit.hash {
                    if let index = commits.firstIndex(where: {
                        $0.hash == verifiedCommit.hash
                    }) {
                        commits[index] = verifiedCommit
                    }
                    selectedCommit = verifiedCommit
                }
            } catch {
                show(error)
            }
        }
    }

    /// Selects a single row, replacing any multi-selection: a plain click.
    func selectChange(_ change: WorkingChange?, staged: Bool) {
        changeSelection.select(change.map { ChangeEntryID(path: $0.path, staged: staged) })
        showPrimaryChange()
    }

    /// Adds or removes one row without disturbing the rest: a Command-click.
    func toggleSelection(of entry: ChangeEntry) {
        changeSelection.toggle(entry.id, in: changeOrder)
        showPrimaryChange()
    }

    /// Selects every row between the anchor and `entry`: a Shift-click.
    func extendSelection(to entry: ChangeEntry) {
        changeSelection.extend(to: entry.id, in: changeOrder)
        showPrimaryChange()
    }

    func clearChangeSelection() {
        changeSelection.clear()
        showPrimaryChange()
    }

    func isSelected(_ entry: ChangeEntry) -> Bool {
        changeSelection.contains(entry.id)
    }

    /// Loads the diff for the row that drives the detail pane. Clicks skip the
    /// reload while the same row stays primary; a refresh always reloads,
    /// because the file may have changed underneath an unchanged row.
    private func showPrimaryChange(alwaysReloadDiff: Bool = false) {
        let entry = changeSelection.primary.flatMap { id in
            changeEntries.first { $0.id == id }
        }
        guard let entry else {
            if selectedChange != nil {
                showChange(nil, staged: false)
            }
            return
        }
        guard alwaysReloadDiff
                || entry.change != selectedChange
                || entry.staged != selectedChangeIsStaged else {
            return
        }
        showChange(entry.change, staged: entry.staged)
    }

    private func showChange(_ change: WorkingChange?, staged: Bool) {
        selectedStash = nil
        selectedChange = change
        selectedChangeIsStaged = staged
        selectedCommit = nil
        guard let root = repositoryURL, let change else {
            diff = ""
            return
        }
        diff = ""
        loadGeneration += 1
        let generation = loadGeneration
        Task {
            do {
                let patch = try await client.diff(at: root, change: change, staged: staged)
                if generation == loadGeneration {
                    diff = patch
                }
            } catch {
                show(error)
            }
        }
    }

    func selectReference(_ reference: GitReference?) {
        guard let root = repositoryURL else { return }
        _ = startOperation("Loading \(reference?.name ?? "history")") {
            self.selectedStash = nil
            self.selectedReference = reference
            self.selectedSection = .history
            try await self.reload(root: root, revision: reference?.fullName)
        }
    }

    func selectStash(_ stash: GitStash) {
        guard let root = repositoryURL else { return }
        _ = startOperation("Loading \(stash.displayName)") {
            self.selectedStash = stash
            self.selectedReference = nil
            self.selectedSection = .history
            let commit = try await self.client.commit(
                at: root,
                revision: stash.selector
            )
            guard self.selectedStash?.id == stash.id else { return }
            self.showCommit(commit)
        }
    }

    func stage(_ change: WorkingChange) {
        stage([ChangeEntry(change, staged: false)])
    }

    func unstage(_ change: WorkingChange) {
        unstage([ChangeEntry(change, staged: true)])
    }

    /// Stages every row of `entries` that sits on the working-tree side; rows
    /// already in the index are ignored, so a selection spanning both sections
    /// still does the expected thing.
    func stage(_ entries: [ChangeEntry]) {
        let paths = entries.unstagedSide.paths
        guard !paths.isEmpty else { return }
        mutate(Self.operationLabel("Staging", paths: paths)) { root in
            try await self.client.stage(at: root, paths: paths)
        }
    }

    /// Unstages every row of `entries` that sits on the staged side.
    func unstage(_ entries: [ChangeEntry]) {
        let paths = entries.stagedSide.paths
        guard !paths.isEmpty else { return }
        mutate(Self.operationLabel("Unstaging", paths: paths)) { root in
            try await self.client.unstage(at: root, paths: paths)
        }
    }

    func stage(_ patch: String, in change: WorkingChange) {
        mutate("Staging selected lines in \(change.path)") { root in
            try await self.client.stage(at: root, patch: patch)
        }
    }

    func unstage(_ patch: String, in change: WorkingChange) {
        mutate("Unstaging selected lines in \(change.path)") { root in
            try await self.client.unstage(at: root, patch: patch)
        }
    }

    func discard(_ patch: String, in change: WorkingChange) {
        mutate("Discarding selected lines in \(change.path)") { root in
            try await self.client.discard(at: root, patch: patch)
        }
    }

    func discard(_ change: WorkingChange) {
        discard([ChangeEntry(change, staged: false)])
    }

    /// Discards the working-tree changes of every row of `entries` on the
    /// unstaged side. Staged rows are left alone: the index is never rewritten
    /// by a discard.
    func discard(_ entries: [ChangeEntry]) {
        let targets = entries.unstagedSide.map(\.change)
        guard !targets.isEmpty else { return }
        mutate(Self.operationLabel("Discarding changes in", paths: targets.map(\.path))) { root in
            try await self.client.discard(at: root, changes: targets)
        }
    }

    func stageAll() {
        mutate("Staging all changes") { root in
            try await self.client.stage(at: root, paths: self.unstagedChanges.map(\.path))
        }
    }

    func unstageAll() {
        mutate("Unstaging all changes") { root in
            try await self.client.unstage(at: root, paths: self.stagedChanges.map(\.path))
        }
    }

    private static func operationLabel(_ verb: String, paths: [String]) -> String {
        paths.count == 1 ? "\(verb) \(paths[0])" : "\(verb) \(paths.count) files"
    }

    func createCommit() {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            errorMessage = "Enter a commit message first."
            return
        }
        let shouldAmend = amend
        let shouldSign = signCommit
        let operation: String
        if shouldAmend {
            operation = shouldSign ? "Amending with GPG signature" : "Amending commit"
        } else {
            operation = shouldSign ? "Creating GPG-signed commit" : "Creating commit"
        }

        mutate(operation) { root in
            try await self.client.commit(
                at: root,
                message: message,
                amend: shouldAmend,
                signWithGPG: shouldSign
            )
            self.commitMessage = ""
            self.amend = false
            self.selectedSection = .history
        }
    }

    func fetch() {
        mutate("Fetching all remotes") { root in
            try await self.client.fetch(at: root)
        }
    }

    func pull() {
        mutate("Pulling \(upstream ?? "upstream")") { root in
            try await self.client.pull(at: root)
        }
    }

    func push() {
        let target = pushTarget
        mutate("Pushing \(branch)") { root in
            try await self.client.push(at: root, target: target)
        }
    }

    func requestPushConfirmation() {
        guard !isLoading else {
            showBusyError()
            return
        }
        guard pushTarget != nil else {
            if branch.hasPrefix("Detached at ") {
                errorMessage = "Create or check out a branch before pushing a detached HEAD."
            } else {
                errorMessage = """
                This branch has no safe push target. Add a remote or repair its \
                upstream configuration.
                """
            }
            return
        }
        isConfirmingPush = true
    }

    func checkout(_ reference: GitReference) {
        mutate("Checking out \(reference.name)") { root in
            try await self.client.checkout(at: root, reference: reference)
            self.selectedReference = nil
        }
    }

    func createBranch(named name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        mutate("Creating \(cleanName)") { root in
            try await self.client.createBranch(at: root, name: cleanName)
            self.selectedReference = nil
        }
    }

    func delete(_ reference: GitReference) {
        let kind = reference.kind == .tag ? "tag" : "branch"
        mutate("Deleting \(kind) \(reference.name)") { root in
            do {
                try await self.client.delete(at: root, reference: reference)
            } catch let error as UnmergedBranchDeletionError {
                guard error.branch == reference.name else {
                    throw error
                }
                self.branchPendingForceDelete = reference
                return
            }
            if self.selectedReference == reference {
                self.selectedReference = nil
            }
        }
    }

    func forceDelete(_ reference: GitReference) {
        guard branchPendingForceDelete == reference, !isLoading else { return }
        branchPendingForceDelete = nil
        mutate("Force deleting branch \(reference.name)") { root in
            try await self.client.forceDelete(at: root, reference: reference)
            if self.selectedReference == reference {
                self.selectedReference = nil
            }
        }
    }

    func cancelForceDelete() {
        branchPendingForceDelete = nil
    }

    func stash(message: String, scope: StashScope = .all) {
        mutate("Stashing \(scope.title.lowercased())") { root in
            let resolved = message.trimmingCharacters(in: .whitespacesAndNewlines)
            try await self.client.stash(
                at: root,
                message: resolved.isEmpty ? "GitFork stash" : resolved,
                scope: scope
            )
        }
    }

    func apply(_ stash: GitStash) {
        mutate("Applying \(stash.displayName)") { root in
            try await self.client.applyStash(at: root, stash: stash)
        }
    }

    func drop(_ stash: GitStash) {
        mutate("Dropping \(stash.displayName)") { root in
            try await self.client.dropStash(at: root, stash: stash)
            if self.selectedStash == stash {
                self.selectedStash = nil
            }
        }
    }

    private func mutate(
        _ label: String,
        action: @escaping @MainActor (URL) async throws -> Void
    ) {
        guard let root = repositoryURL else { return }
        _ = startOperation(label) {
            do {
                try await action(root)
            } catch {
                try? await self.reload(
                    root: root,
                    revision: self.selectedReference?.fullName
                )
                throw error
            }
            try await self.reload(
                root: root,
                revision: self.selectedReference?.fullName
            )
        }
    }

    private func startMonitoring(root: URL) {
        stopMonitoring()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.monitorInterval)
                } catch {
                    return
                }
                guard let self else { return }
                await self.refreshIfRepositoryChanged(root: root)
            }
        }
    }

    private func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        monitoredState = nil
    }

    private func refreshIfRepositoryChanged(root: URL) async {
        guard repositoryURL?.standardizedFileURL == root.standardizedFileURL,
              !isLoading else {
            return
        }

        do {
            let state = try await client.stateToken(at: root)
            guard !Task.isCancelled,
                  repositoryURL?.standardizedFileURL == root.standardizedFileURL,
                  !isLoading,
                  monitoredState != state else {
                return
            }

            isLoading = true
            defer { isLoading = false }
            try await reload(root: root, revision: selectedReference?.fullName)
            monitoredState = state
        } catch {
            // External Git operations can leave short-lived lock or ref states.
            // The next polling pass retries without interrupting the user.
        }
    }

    private func reload(root: URL, revision: String? = nil) async throws {
        let snapshot = try await client.snapshot(at: root, revision: revision)
        try Task.checkCancellation()
        guard isCurrentRepository(root) else { return }
        branch = snapshot.branch
        upstream = snapshot.upstream
        pushTarget = snapshot.pushTarget
        ahead = snapshot.ahead
        behind = snapshot.behind
        changes = snapshot.changes
        references = snapshot.references
        stashes = snapshot.stashes
        worktrees = snapshot.worktrees
        commits = snapshot.commits

        if let selectedStash,
           let replacement = stashes.first(where: { $0.id == selectedStash.id }) {
            self.selectedStash = replacement
            self.selectedCommit = try await client.commit(
                at: root,
                revision: replacement.selector
            )
        } else {
            selectedStash = nil
            if let selectedCommit,
               let replacement = commits.first(where: { $0.hash == selectedCommit.hash }) {
                self.selectedCommit = replacement
            } else {
                selectedCommit = commits.first
            }
        }

        if selectedSection == .history {
            showCommit(selectedCommit)
        } else {
            reconcileChangeSelection()
        }
    }

    /// Carries the change selection across a refresh. Rows whose file moved
    /// between the index and the working tree follow the file to its new side;
    /// rows whose file no longer has changes drop out.
    private func reconcileChangeSelection() {
        changeSelection.reconcile(order: changeOrder) { id in
            guard let change = self.changes.first(where: { $0.path == id.path }) else {
                return nil
            }
            if id.staged ? change.isStaged : change.isUnstaged {
                return id
            }
            if change.isStaged {
                return ChangeEntryID(path: id.path, staged: true)
            }
            if change.isUnstaged {
                return ChangeEntryID(path: id.path, staged: false)
            }
            return nil
        }
        guard changeSelection.primary != nil || selectedChange != nil else { return }
        showPrimaryChange(alwaysReloadDiff: true)
    }

    @discardableResult
    private func startOperation(
        _ label: String,
        operation: @escaping @MainActor () async throws -> Void
    ) -> Task<Void, Never>? {
        guard activeOperationID == nil, !isLoading else {
            showBusyError()
            return nil
        }

        let operationID = UUID()
        activeOperationID = operationID
        isLoading = true
        operationLabel = label
        return Task {
            await self.perform(operationID: operationID, operation: operation)
        }
    }

    private func perform(
        operationID: UUID,
        operation: @escaping @MainActor () async throws -> Void
    ) async {
        defer {
            if activeOperationID == operationID {
                activeOperationID = nil
                isLoading = false
                operationLabel = nil
            }
        }
        do {
            try await operation()
        } catch is CancellationError {
            // A newer repository switch superseded this operation.
        } catch {
            show(error)
        }
    }

    private func showBusyError() {
        let currentOperation = operationLabel ?? "the current repository operation"
        errorMessage = "Wait for \(currentOperation) to finish."
    }

    private func prepareForRepositorySwitch() {
        loadGeneration += 1
        branch = ""
        upstream = nil
        pushTarget = nil
        ahead = 0
        behind = 0
        changes = []
        references = []
        stashes = []
        worktrees = []
        commits = []
        diff = ""
        selectedReference = nil
        selectedStash = nil
        selectedCommit = nil
        selectedChange = nil
        changeSelection.clear()
        selectedSection = .history
        commitMessage = ""
        amend = false
        branchPendingForceDelete = nil
        isConfirmingPush = false
    }

    private func isCurrentRepository(_ root: URL) -> Bool {
        repositoryURL?.standardizedFileURL == root.standardizedFileURL
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func remember(_ url: URL) {
        recentRepositories.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentRepositories.insert(url, at: 0)
        recentRepositories = Array(recentRepositories.prefix(8))
        UserDefaults.standard.set(recentRepositories.map(\.path), forKey: recentKey)
    }
}

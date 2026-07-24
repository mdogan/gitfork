import AppKit
import Combine
import Foundation

@MainActor
final class RepositoryStore: ObservableObject {
    @Published private(set) var repositoryURL: URL?
    @Published private(set) var branch = ""
    @Published private(set) var upstream: String?
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
    @Published var selectedChange: WorkingChange?
    @Published var selectedChangeIsStaged = false
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
    @Published var isShowingCLIInstaller = false
    @Published var isShowingRepositorySwitcher = false
    @Published private(set) var recentRepositories: [URL] = []

    private let client = GitClient()
    private var loadGeneration = 0
    private var openTask: Task<Void, Never>?
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
        openTask?.cancel()
        openTask = Task {
            await perform("Opening repository") {
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
        Task {
            await perform("Refreshing") {
                try await self.reload(root: root, revision: self.selectedReference?.fullName)
            }
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

    func selectChange(_ change: WorkingChange?, staged: Bool) {
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
        selectedStash = nil
        selectedReference = reference
        selectedSection = .history
        guard let root = repositoryURL else { return }
        Task {
            await perform("Loading \(reference?.name ?? "history")") {
                try await self.reload(root: root, revision: reference?.fullName)
            }
        }
    }

    func selectStash(_ stash: GitStash) {
        selectedStash = stash
        selectedReference = nil
        selectedSection = .history
        guard let root = repositoryURL else { return }
        Task {
            await perform("Loading \(stash.displayName)") {
                let commit = try await self.client.commit(
                    at: root,
                    revision: stash.selector
                )
                guard self.selectedStash?.id == stash.id else { return }
                self.showCommit(commit)
            }
        }
    }

    func stage(_ change: WorkingChange) {
        mutate("Staging \(change.path)") { root in
            try await self.client.stage(at: root, paths: [change.path])
        }
    }

    func unstage(_ change: WorkingChange) {
        mutate("Unstaging \(change.path)") { root in
            try await self.client.unstage(at: root, paths: [change.path])
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
        mutate("Discarding changes in \(change.path)") { root in
            try await self.client.discard(at: root, change: change)
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
        mutate("Pushing \(branch)") { root in
            try await self.client.push(
                at: root,
                branch: self.branch,
                upstream: self.upstream
            )
        }
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

    func stash(message: String) {
        mutate("Stashing changes") { root in
            let resolved = message.trimmingCharacters(in: .whitespacesAndNewlines)
            try await self.client.stash(
                at: root,
                message: resolved.isEmpty ? "GitFork stash" : resolved
            )
        }
    }

    private func mutate(
        _ label: String,
        action: @escaping @MainActor (URL) async throws -> Void
    ) {
        guard let root = repositoryURL else { return }
        Task {
            await perform(label) {
                try await action(root)
                try await self.reload(root: root, revision: self.selectedReference?.fullName)
            }
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
        } else if let selectedChange {
            let replacement = changes.first(where: { $0.path == selectedChange.path })
            if selectedChangeIsStaged, replacement?.isStaged == true {
                selectChange(replacement, staged: true)
            } else if !selectedChangeIsStaged, replacement?.isUnstaged == true {
                selectChange(replacement, staged: false)
            } else if let replacement {
                selectChange(replacement, staged: replacement.isStaged)
            } else {
                selectChange(nil, staged: false)
            }
        }
    }

    private func perform(
        _ label: String,
        operation: @escaping @MainActor () async throws -> Void
    ) async {
        let operationID = UUID()
        activeOperationID = operationID
        isLoading = true
        operationLabel = label
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

    private func prepareForRepositorySwitch() {
        loadGeneration += 1
        branch = ""
        upstream = nil
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
        selectedSection = .history
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

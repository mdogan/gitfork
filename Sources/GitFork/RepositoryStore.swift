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
    @Published private(set) var commits: [GitCommit] = []
    @Published private(set) var diff = ""
    @Published private(set) var isLoading = false
    @Published private(set) var operationLabel: String?
    @Published var selectedSection: WorkspaceSection = .history
    @Published var selectedCommit: GitCommit?
    @Published var selectedChange: WorkingChange?
    @Published var selectedChangeIsStaged = false
    @Published var selectedReference: GitReference?
    @Published var searchText = ""
    @Published var commitMessage = ""
    @Published var amend = false
    @Published var errorMessage: String?
    @Published var isShowingCLIInstaller = false
    @Published private(set) var recentRepositories: [URL] = []

    private let client = GitClient()
    private var loadGeneration = 0
    private let recentKey = "recentRepositories"

    init() {
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

    var groupedReferences: [(ReferenceKind, [GitReference])] {
        ReferenceKind.allCasesCompat.map { kind in
            (kind, references.filter { $0.kind == kind })
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
        Task {
            await perform("Opening repository") {
                let root = try await self.client.repositoryRoot(from: url)
                self.repositoryURL = root
                self.remember(root)
                self.selectedReference = nil
                self.selectedSection = .history
                try await self.reload(root: root)
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
                let details = try await client.commitDetails(at: root, hash: commit.hash)
                if generation == loadGeneration {
                    diff = details
                }
            } catch {
                show(error)
            }
        }
    }

    func selectChange(_ change: WorkingChange?, staged: Bool) {
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
        selectedReference = reference
        selectedSection = .history
        guard let root = repositoryURL else { return }
        Task {
            await perform("Loading \(reference?.name ?? "history")") {
                try await self.reload(root: root, revision: reference?.fullName)
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
        mutate(amend ? "Amending commit" : "Creating commit") { root in
            try await self.client.commit(at: root, message: message, amend: self.amend)
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

    private func reload(root: URL, revision: String? = nil) async throws {
        let snapshot = try await client.snapshot(at: root, revision: revision)
        branch = snapshot.branch
        upstream = snapshot.upstream
        ahead = snapshot.ahead
        behind = snapshot.behind
        changes = snapshot.changes
        references = snapshot.references
        commits = snapshot.commits

        if let selectedCommit,
           let replacement = commits.first(where: { $0.hash == selectedCommit.hash }) {
            self.selectedCommit = replacement
        } else {
            selectedCommit = commits.first
        }

        if selectedSection == .history {
            selectCommit(selectedCommit)
        } else if let selectedChange {
            let replacement = changes.first(where: { $0.path == selectedChange.path })
            selectChange(replacement, staged: selectedChangeIsStaged)
        }
    }

    private func perform(
        _ label: String,
        operation: @escaping @MainActor () async throws -> Void
    ) async {
        isLoading = true
        operationLabel = label
        defer {
            isLoading = false
            operationLabel = nil
        }
        do {
            try await operation()
        } catch {
            show(error)
        }
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

private extension ReferenceKind {
    static let allCasesCompat: [ReferenceKind] = [.localBranch, .remoteBranch, .tag]
}

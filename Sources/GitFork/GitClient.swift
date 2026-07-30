import Foundation

struct RepositoryStateToken: Equatable, Sendable {
    let status: String
    let stagedDiff: String
    let references: String
    let stashes: String
    let worktrees: String
    let workingTreeMetadata: String
}

struct GitClient: Sendable {
    private let gitURL = URL(fileURLWithPath: "/usr/bin/git")
    private static let verifiedCommitFormat =
        "%H%x1f%P%x1f%an%x1f%ae%x1f%ad%x1f%D%x1f%G?%x1f%GK%x1f%GS%x1f%GG%x1f%s%x1e"
    private static let unverifiedCommitFormat =
        "%H%x1f%P%x1f%an%x1f%ae%x1f%ad%x1f%D%x1fN%x1f%x1f%x1f%x1f%s%x1e"

    func repositoryRoot(from directory: URL) async throws -> URL {
        let result = try await run(["rev-parse", "--show-toplevel"], in: directory)
        return URL(fileURLWithPath: result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            .standardizedFileURL
    }

    func snapshot(at root: URL, revision: String? = nil) async throws -> RepositorySnapshot {
        async let branchResult = runAllowingFailure(["symbolic-ref", "--quiet", "--short", "HEAD"], in: root)
        async let statusResult = run(["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: root)
        async let refsResult = run([
            "for-each-ref",
            "--format=%(refname)%1f%(objectname:short)%1f%(objectname)",
            "refs/heads", "refs/remotes", "refs/tags"
        ], in: root)
        async let stashResult = run([
            "stash",
            "list",
            "--format=%gd%x1f%H%x1f%gs%x1e"
        ], in: root)
        async let worktreeResult = run([
            "worktree",
            "list",
            "--porcelain",
            "-z"
        ], in: root)
        async let history = commits(at: root, revision: revision)

        let branchCommand = try await branchResult
        let branch: String
        if branchCommand.exitCode == 0 {
            branch = branchCommand.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let detached = try await run(["rev-parse", "--short", "HEAD"], in: root)
            branch = "Detached at \(detached.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }

        async let upstreamResult = runAllowingFailure(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            in: root
        )
        async let countsResult = runAllowingFailure(
            ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"],
            in: root
        )

        let status = try await statusResult
        let refs = try await refsResult
        let stashes = try await stashResult
        let worktrees = try await worktreeResult
        let commits = try await history
        let upstreamCommand = try await upstreamResult
        let countsCommand = try await countsResult
        let upstream = upstreamCommand.exitCode == 0
            ? upstreamCommand.output.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let pushTarget = try await resolvePushTarget(
            at: root,
            branch: branch,
            hasUpstream: upstream != nil
        )

        let counts = countsCommand.output.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }

        return RepositorySnapshot(
            root: root,
            branch: branch,
            upstream: upstream,
            pushTarget: pushTarget,
            ahead: counts.first ?? 0,
            behind: counts.dropFirst().first ?? 0,
            changes: GitParser.parseStatus(Data(status.output.utf8)),
            references: GitParser.parseReferences(refs.output, currentBranch: branch),
            stashes: GitParser.parseStashes(stashes.output),
            worktrees: GitParser.parseWorktrees(worktrees.output, currentRoot: root),
            commits: commits
        )
    }

    private func commits(at root: URL, revision: String? = nil) async throws -> [GitCommit] {
        let result = try await run(
            Self.historyArguments(revision: revision),
            in: root
        )
        return GitParser.parseCommits(result.output)
    }

    static func historyArguments(revision: String?) -> [String] {
        [
            "log",
            "--max-count=300",
            "--date=iso-strict",
            "--pretty=format:\(unverifiedCommitFormat)",
            revision ?? "--all"
        ]
    }

    func stateToken(at root: URL) async throws -> RepositoryStateToken {
        async let statusResult = run([
            "--no-optional-locks",
            "status",
            "--porcelain=v1",
            "--branch",
            "-z",
            "--untracked-files=all"
        ], in: root)
        async let stagedDiffResult = run([
            "diff",
            "--cached",
            "--raw",
            "--no-renames",
            "--no-ext-diff"
        ], in: root)
        async let referencesResult = run([
            "for-each-ref",
            "--format=%(refname)%00%(objectname)%00%(upstream)%00%(upstream:track)",
            "refs/heads", "refs/remotes", "refs/tags"
        ], in: root)
        async let stashResult = run([
            "stash",
            "list",
            "--format=%gd%x00%H%x00%gs%x1e"
        ], in: root)
        async let worktreeResult = run([
            "worktree",
            "list",
            "--porcelain",
            "-z"
        ], in: root)

        let status = try await statusResult
        let stagedDiff = try await stagedDiffResult
        let references = try await referencesResult
        let stashes = try await stashResult
        let worktrees = try await worktreeResult

        return RepositoryStateToken(
            status: status.output,
            stagedDiff: stagedDiff.output,
            references: references.output,
            stashes: stashes.output,
            worktrees: worktrees.output,
            workingTreeMetadata: workingTreeMetadata(from: status.output, at: root)
        )
    }

    func diff(
        at root: URL,
        change: WorkingChange,
        staged: Bool,
        fullFile: Bool = false
    ) async throws -> String {
        var arguments = ["diff", "--no-ext-diff", "--no-color"]
        if fullFile {
            arguments.append("--unified=\(Int32.max)")
        }
        if staged {
            arguments.append("--cached")
        }
        arguments += ["--", change.path]

        let result = try await run(arguments, in: root)
        if result.output.isEmpty && change.isUntracked {
            let untrackedDiff = try await runAllowingFailure([
                "diff",
                "--no-index",
                "--no-ext-diff",
                "--no-color",
                fullFile ? "--unified=\(Int32.max)" : "--unified=3",
                "--",
                "/dev/null",
                change.path
            ], in: root)
            guard untrackedDiff.exitCode <= 1 else {
                throw GitOperationError(
                    command: "git diff --no-index -- /dev/null \(change.path)",
                    message: untrackedDiff.error.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return untrackedDiff.output.isEmpty
                ? "No textual changes."
                : untrackedDiff.output
        }
        return result.output.isEmpty ? "No textual changes." : result.output
    }

    private func workingTreeMetadata(from status: String, at root: URL) -> String {
        let changes = GitParser.parseStatus(Data(status.utf8))
            .filter { $0.indexStatus != "#" }
        let fileManager = FileManager.default

        return changes.map { change in
            let attributes = try? fileManager.attributesOfItem(
                atPath: root.appendingPathComponent(change.path).path
            )
            let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
            let modificationDate = attributes?[.modificationDate] as? Date
            let modificationBits = modificationDate?
                .timeIntervalSinceReferenceDate.bitPattern ?? 0
            let fileIdentifier = (attributes?[.systemFileNumber] as? NSNumber)?
                .uint64Value ?? 0
            return "\(change.path)\u{1f}\(size)\u{1f}\(modificationBits)\u{1f}\(fileIdentifier)"
        }
        .joined(separator: "\u{1e}")
    }

    func commitDetails(at root: URL, hash: String) async throws -> String {
        let result = try await run([
            "show",
            "--no-ext-diff",
            "--no-color",
            "--format=fuller",
            "--stat",
            "--patch",
            "--find-renames",
            hash
        ], in: root)
        return result.output
    }

    func commit(at root: URL, revision: String) async throws -> GitCommit {
        let result = try await run([
            "log",
            "--max-count=1",
            "--date=iso-strict",
            "--pretty=format:\(Self.verifiedCommitFormat)",
            revision
        ], in: root)
        guard let commit = GitParser.parseCommits(result.output).first else {
            throw GitOperationError(
                command: "git log --max-count=1 \(revision)",
                message: "Git did not return the selected stash commit."
            )
        }
        return commit
    }

    func stage(at root: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await run(["add", "--"] + paths, in: root)
    }

    func unstage(at root: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let restore = try await runAllowingFailure(["restore", "--staged", "--"] + paths, in: root)
        if restore.exitCode != 0 {
            _ = try await run(["rm", "--cached", "--ignore-unmatch", "--"] + paths, in: root)
        }
    }

    func stage(at root: URL, patch: String) async throws {
        try await apply(patch, at: root, cached: true, reverse: false)
    }

    func unstage(at root: URL, patch: String) async throws {
        try await apply(patch, at: root, cached: true, reverse: true)
    }

    func discard(at root: URL, patch: String) async throws {
        try await apply(patch, at: root, cached: false, reverse: true)
    }

    func discard(at root: URL, changes: [WorkingChange]) async throws {
        let tracked = changes.filter { !$0.isUntracked }.map(\.path)
        let untracked = changes.filter(\.isUntracked).map(\.path)
        if !tracked.isEmpty {
            _ = try await run(["restore", "--worktree", "--"] + tracked, in: root)
        }
        if !untracked.isEmpty {
            _ = try await run(["clean", "-f", "--"] + untracked, in: root)
        }
    }

    func commit(
        at root: URL,
        message: String,
        amend: Bool,
        signWithGPG: Bool
    ) async throws {
        let gpgProgram = signWithGPG
            ? try await resolvedGPGProgram(at: root).path
            : nil
        let arguments = Self.commitArguments(
            message: message,
            amend: amend,
            signWithGPG: signWithGPG,
            gpgProgram: gpgProgram
        )
        _ = try await run(arguments, in: root)
    }

    static func commitArguments(
        message: String,
        amend: Bool,
        signWithGPG: Bool,
        gpgProgram: String? = nil
    ) -> [String] {
        var arguments: [String] = []
        if signWithGPG {
            arguments += ["-c", "gpg.format=openpgp"]
            if let gpgProgram {
                arguments += ["-c", "gpg.openpgp.program=\(gpgProgram)"]
            }
        }

        arguments += [
            "commit",
            signWithGPG ? "--gpg-sign" : "--no-gpg-sign"
        ]
        if amend {
            arguments.append("--amend")
        }
        arguments += ["-m", message]
        return arguments
    }

    static func commandSearchPath(
        inheritedPath: String?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        var directories = (inheritedPath ?? "")
            .split(separator: ":")
            .map(String.init)
        directories += [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            homeDirectory.appendingPathComponent(".local/bin").path,
            homeDirectory.appendingPathComponent("bin").path,
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        var seen = Set<String>()
        return directories
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }

    static func executableURL(
        named program: String,
        searchPath: String,
        workingDirectory: URL
    ) -> URL? {
        let expanded = NSString(string: program).expandingTildeInPath
        if expanded.contains("/") {
            let candidate = expanded.hasPrefix("/")
                ? URL(fileURLWithPath: expanded)
                : workingDirectory.appendingPathComponent(expanded)
            return FileManager.default.isExecutableFile(atPath: candidate.path)
                ? candidate.standardizedFileURL
                : nil
        }

        for directory in searchPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(expanded)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

    private func resolvedGPGProgram(at root: URL) async throws -> URL {
        let configuredProgram = try await configuredGPGProgram(at: root)
        let searchPath = Self.commandSearchPath(
            inheritedPath: ProcessInfo.processInfo.environment["PATH"]
        )

        if let configuredProgram {
            if let executable = Self.executableURL(
                named: configuredProgram,
                searchPath: searchPath,
                workingDirectory: root
            ) {
                return executable
            }

            throw GitOperationError(
                command: "git commit --gpg-sign",
                message: """
                Git's configured GPG program '\(configuredProgram)' could not be found. \
                Install GnuPG or update it with:
                git config --global gpg.program /absolute/path/to/gpg
                """
            )
        }

        for candidate in ["gpg", "gpg2"] {
            if let executable = Self.executableURL(
                named: candidate,
                searchPath: searchPath,
                workingDirectory: root
            ) {
                return executable
            }
        }

        throw GitOperationError(
            command: "git commit --gpg-sign",
            message: """
            GPG was not found. Install GnuPG (for example, `brew install gnupg`) \
            or configure its absolute path with:
            git config --global gpg.program /absolute/path/to/gpg
            """
        )
    }

    private func configuredGPGProgram(at root: URL) async throws -> String? {
        for key in ["gpg.openpgp.program", "gpg.program"] {
            let result = try await runAllowingFailure(
                ["config", "--get", key],
                in: root
            )
            let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 0, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func fetch(at root: URL) async throws {
        _ = try await run(Self.fetchArguments(), in: root)
    }

    static func fetchArguments() -> [String] {
        ["fetch", "--all"]
    }

    func pull(at root: URL) async throws {
        _ = try await run(["pull", "--ff-only"], in: root)
    }

    func push(at root: URL, target: GitPushTarget?) async throws {
        guard let target else {
            throw GitOperationError(
                command: "git push",
                message: "GitFork could not resolve a safe push target for the current branch."
            )
        }

        _ = try await run(Self.pushArguments(for: target), in: root)
    }

    static func pushArguments(for target: GitPushTarget) -> [String] {
        var arguments = [
            "-c",
            "remote.\(target.remote).mirror=false",
            "push",
            "--no-force",
            "--no-follow-tags"
        ]
        if target.establishesUpstream {
            arguments.append("--set-upstream")
        }
        arguments += ["--", target.remote, "HEAD:\(target.remoteRef)"]
        return arguments
    }

    func checkout(at root: URL, reference: GitReference) async throws {
        if reference.kind == .remoteBranch {
            let localName = reference.name.split(separator: "/").dropFirst().joined(separator: "/")
            let localRef = "refs/heads/\(localName)"
            let existing = try await runAllowingFailure(
                ["show-ref", "--verify", "--quiet", localRef],
                in: root
            )
            if existing.exitCode == 0 {
                let upstream = try await runAllowingFailure(
                    ["for-each-ref", "--format=%(upstream)", localRef],
                    in: root
                )
                let configuredUpstream = upstream.output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard configuredUpstream == reference.fullName else {
                    throw GitOperationError(
                        command: "git switch \(localName)",
                        message: """
                        Local branch '\(localName)' already exists but does not track \
                        \(reference.name). Rename or remove it before checking out this remote branch.
                        """
                    )
                }
                _ = try await run(["switch", "--", localName], in: root)
            } else {
                _ = try await run(
                    ["switch", "--track", "-c", localName, "--", reference.fullName],
                    in: root
                )
            }
        } else if reference.kind == .localBranch {
            _ = try await run(["switch", "--", reference.name], in: root)
        } else {
            _ = try await run(["switch", "--detach", "--", reference.fullName], in: root)
        }
    }

    func createBranch(at root: URL, name: String) async throws {
        _ = try await run(["switch", "-c", name], in: root)
    }

    func delete(at root: URL, reference: GitReference) async throws {
        do {
            _ = try await run(
                Self.deleteArguments(for: reference),
                in: root
            )
        } catch let error as GitOperationError {
            guard reference.kind == .localBranch,
                  error.message.contains("is not fully merged") else {
                throw error
            }
            throw UnmergedBranchDeletionError(
                branch: reference.name,
                message: error.message
            )
        }
    }

    func forceDelete(at root: URL, reference: GitReference) async throws {
        _ = try await run(
            Self.forceDeleteArguments(for: reference),
            in: root
        )
    }

    static func deleteArguments(for reference: GitReference) throws -> [String] {
        switch reference.kind {
        case .localBranch:
            guard !reference.isCurrent else {
                throw GitOperationError(
                    command: "git branch --delete",
                    message: "Check out another branch before deleting \(reference.name)."
                )
            }
            return ["branch", "--delete", "--", reference.name]
        case .tag:
            return ["tag", "--delete", "--", reference.name]
        case .remoteBranch:
            throw GitOperationError(
                command: "git branch --delete",
                message: "Deleting remote branches is not supported."
            )
        }
    }

    static func forceDeleteArguments(for reference: GitReference) throws -> [String] {
        guard reference.kind == .localBranch else {
            throw GitOperationError(
                command: "git branch -D",
                message: "Only local branches can be force deleted."
            )
        }
        guard !reference.isCurrent else {
            throw GitOperationError(
                command: "git branch -D",
                message: "Check out another branch before deleting \(reference.name)."
            )
        }
        return ["branch", "-D", "--", reference.name]
    }

    func removeWorktree(at root: URL, worktree: GitWorktree) async throws {
        _ = try await run(
            Self.removeWorktreeArguments(for: worktree),
            in: root
        )
    }

    static func removeWorktreeArguments(for worktree: GitWorktree) throws -> [String] {
        guard worktree.isDetached else {
            throw GitOperationError(
                command: "git worktree remove",
                message: "Only detached worktrees can be deleted from GitFork."
            )
        }
        guard !worktree.isCurrent else {
            throw GitOperationError(
                command: "git worktree remove",
                message: "The current worktree cannot be deleted."
            )
        }
        guard !worktree.isBare else {
            throw GitOperationError(
                command: "git worktree remove",
                message: "Bare worktrees cannot be deleted from GitFork."
            )
        }
        guard !worktree.isLocked else {
            throw GitOperationError(
                command: "git worktree remove",
                message: "Unlock this worktree before deleting it."
            )
        }
        guard !worktree.isPrunable else {
            throw GitOperationError(
                command: "git worktree remove",
                message: "Prune this missing worktree instead of deleting it."
            )
        }
        return ["worktree", "remove", "--", worktree.path]
    }

    func pruneStaleWorktrees(at root: URL) async throws {
        _ = try await run(Self.pruneStaleWorktreeArguments, in: root)
    }

    static let pruneStaleWorktreeArguments = [
        "worktree",
        "prune",
        "--expire",
        "now"
    ]

    func stash(
        at root: URL,
        message: String,
        scope: StashScope = .all
    ) async throws {
        if scope == .staged {
            let status = try await run(
                ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
                in: root
            )
            let hasPartiallyStagedFile = GitParser.parseStatus(Data(status.output.utf8))
                .contains { $0.isStaged && $0.isUnstaged }
            guard !hasPartiallyStagedFile else {
                throw GitOperationError(
                    command: "git stash push --staged",
                    message: """
                    Staged-only stash is unavailable while a file has both staged and \
                    unstaged changes. Separate those hunks first so Git cannot create \
                    a stash and then fail while cleaning the working tree.
                    """
                )
            }
        }

        _ = try await run(
            Self.stashArguments(message: message, scope: scope),
            in: root
        )
    }

    static func stashArguments(message: String, scope: StashScope) -> [String] {
        var arguments = ["stash", "push"]
        switch scope {
        case .staged:
            arguments.append("--staged")
        case .unstaged:
            arguments += ["--keep-index", "--include-untracked"]
        case .all:
            arguments.append("--include-untracked")
        }
        arguments += ["-m", message]
        return arguments
    }

    func applyStash(at root: URL, stash: GitStash) async throws {
        _ = try await run(
            Self.applyStashArguments(selector: stash.selector),
            in: root
        )
    }

    static func applyStashArguments(selector: String) -> [String] {
        ["stash", "apply", "--index", selector]
    }

    func dropStash(at root: URL, stash: GitStash) async throws {
        _ = try await run(
            Self.dropStashArguments(selector: stash.selector),
            in: root
        )
    }

    static func dropStashArguments(selector: String) -> [String] {
        ["stash", "drop", selector]
    }

    private func resolvePushTarget(
        at root: URL,
        branch: String,
        hasUpstream: Bool
    ) async throws -> GitPushTarget? {
        guard !branch.hasPrefix("Detached at ") else { return nil }

        if hasUpstream {
            async let remoteResult = runAllowingFailure(
                ["config", "--get", "branch.\(branch).remote"],
                in: root
            )
            async let mergeResult = runAllowingFailure(
                ["config", "--get", "branch.\(branch).merge"],
                in: root
            )
            let remoteCommand = try await remoteResult
            let mergeCommand = try await mergeResult
            let remote = remoteCommand.output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteRef = mergeCommand.output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard remoteCommand.exitCode == 0,
                  mergeCommand.exitCode == 0,
                  !remote.isEmpty,
                  remote != ".",
                  remoteRef.hasPrefix("refs/heads/") else {
                return nil
            }
            return GitPushTarget(
                remote: remote,
                remoteRef: remoteRef,
                establishesUpstream: false
            )
        }

        let remotes = try await run(["remote"], in: root).output
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let remote = remotes.first else { return nil }
        return GitPushTarget(
            remote: remote,
            remoteRef: "refs/heads/\(branch)",
            establishesUpstream: true
        )
    }

    private func apply(
        _ patch: String,
        at root: URL,
        cached: Bool,
        reverse: Bool
    ) async throws {
        let patchData = Data(patch.utf8)
        var arguments = ["apply", "--recount"]
        if cached {
            arguments.append("--cached")
        }
        if reverse {
            arguments.append("--reverse")
        }

        _ = try await run(arguments + ["--check", "-"], in: root, input: patchData)
        _ = try await run(arguments + ["-"], in: root, input: patchData)
    }

    private func run(
        _ arguments: [String],
        in directory: URL,
        input: Data? = nil
    ) async throws -> GitCommandResult {
        let result = try await execute(arguments, in: directory, input: input)
        guard result.exitCode == 0 else {
            throw GitOperationError(
                command: "git \(arguments.joined(separator: " "))",
                message: result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }

    private func runAllowingFailure(
        _ arguments: [String],
        in directory: URL
    ) async throws -> GitCommandResult {
        try await execute(arguments, in: directory, input: nil)
    }

    private func execute(
        _ arguments: [String],
        in directory: URL,
        input: Data?
    ) async throws -> GitCommandResult {
        let gitURL = self.gitURL
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let inputPipe = input == nil ? nil : Pipe()
            process.executableURL = gitURL
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.standardInput = inputPipe

            var environment = ProcessInfo.processInfo.environment
            environment["LC_ALL"] = "C"
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["PATH"] = Self.commandSearchPath(
                inheritedPath: environment["PATH"]
            )
            process.environment = environment

            try process.run()

            if let input, let inputPipe {
                inputPipe.fileHandleForWriting.write(input)
                try inputPipe.fileHandleForWriting.close()
            }

            let outputTask = Task.detached {
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            }
            let errorTask = Task.detached {
                errorPipe.fileHandleForReading.readDataToEndOfFile()
            }

            process.waitUntilExit()
            let outputData = await outputTask.value
            let errorData = await errorTask.value

            return GitCommandResult(
                output: String(decoding: outputData, as: UTF8.self),
                error: String(decoding: errorData, as: UTF8.self),
                exitCode: process.terminationStatus
            )
        }.value
    }
}

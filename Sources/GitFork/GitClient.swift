import Foundation

struct GitClient: Sendable {
    private let gitURL = URL(fileURLWithPath: "/usr/bin/git")

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
        async let logResult = run([
            "log",
            "--max-count=300",
            "--date=iso-strict",
            "--pretty=format:%H%x1f%P%x1f%an%x1f%ae%x1f%ad%x1f%D%x1f%s%x1e",
            revision ?? "--all"
        ], in: root)

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
        let log = try await logResult
        let upstreamCommand = try await upstreamResult
        let countsCommand = try await countsResult

        let counts = countsCommand.output.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }

        return RepositorySnapshot(
            root: root,
            branch: branch,
            upstream: upstreamCommand.exitCode == 0
                ? upstreamCommand.output.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            ahead: counts.first ?? 0,
            behind: counts.dropFirst().first ?? 0,
            changes: GitParser.parseStatus(Data(status.output.utf8)),
            references: GitParser.parseReferences(refs.output, currentBranch: branch),
            commits: GitParser.parseCommits(log.output)
        )
    }

    func diff(at root: URL, change: WorkingChange, staged: Bool) async throws -> String {
        var arguments = ["diff", "--no-ext-diff", "--no-color"]
        if staged {
            arguments.append("--cached")
        }
        arguments += ["--", change.path]

        let result = try await run(arguments, in: root)
        if result.output.isEmpty && change.isUntracked {
            let fileURL = root.appendingPathComponent(change.path)
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return "Binary or unreadable untracked file."
            }
            return contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .map { "+\($0.offset + 1)  \($0.element)" }
                .joined(separator: "\n")
        }
        return result.output.isEmpty ? "No textual changes." : result.output
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

    func commit(at root: URL, message: String, amend: Bool) async throws {
        var arguments = ["commit"]
        if amend {
            arguments.append("--amend")
        }
        arguments += ["-m", message]
        _ = try await run(arguments, in: root)
    }

    func fetch(at root: URL) async throws {
        _ = try await run(["fetch", "--all", "--prune"], in: root)
    }

    func pull(at root: URL) async throws {
        _ = try await run(["pull", "--ff-only"], in: root)
    }

    func push(at root: URL, branch: String, upstream: String?) async throws {
        if upstream != nil {
            _ = try await run(["push"], in: root)
            return
        }

        let remotes = try await run(["remote"], in: root).output
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let remote = remotes.first else {
            throw GitOperationError(
                command: "git push",
                message: "This repository has no remotes. Add a remote before pushing."
            )
        }
        guard !branch.hasPrefix("Detached at ") else {
            throw GitOperationError(
                command: "git push",
                message: "Create or check out a branch before pushing a detached HEAD."
            )
        }

        _ = try await run(["push", "--set-upstream", remote, branch], in: root)
    }

    func checkout(at root: URL, reference: GitReference) async throws {
        if reference.kind == .remoteBranch {
            let localName = reference.name.split(separator: "/").dropFirst().joined(separator: "/")
            let attempt = try await runAllowingFailure(["switch", localName], in: root)
            if attempt.exitCode != 0 {
                _ = try await run(["switch", "--track", "-c", localName, reference.name], in: root)
            }
        } else if reference.kind == .localBranch {
            _ = try await run(["switch", reference.name], in: root)
        } else {
            _ = try await run(["switch", "--detach", reference.name], in: root)
        }
    }

    func createBranch(at root: URL, name: String) async throws {
        _ = try await run(["switch", "-c", name], in: root)
    }

    func stash(at root: URL, message: String) async throws {
        _ = try await run(["stash", "push", "--include-untracked", "-m", message], in: root)
    }

    private func run(
        _ arguments: [String],
        in directory: URL
    ) async throws -> GitCommandResult {
        let result = try await execute(arguments, in: directory)
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
        try await execute(arguments, in: directory)
    }

    private func execute(
        _ arguments: [String],
        in directory: URL
    ) async throws -> GitCommandResult {
        let gitURL = self.gitURL
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = gitURL
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            var environment = ProcessInfo.processInfo.environment
            environment["LC_ALL"] = "C"
            environment["GIT_TERMINAL_PROMPT"] = "0"
            process.environment = environment

            try process.run()

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

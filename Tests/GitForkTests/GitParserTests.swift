import Foundation
import Testing
@testable import GitFork

struct GitParserTests {
    @Test
    func parsesPorcelainStatusIncludingRenameAndUntracked() {
        let input = "M  staged.swift\u{0} M working.swift\u{0}?? new file.md\u{0}R  renamed.swift\u{0}old.swift\u{0}"
        let changes = GitParser.parseStatus(Data(input.utf8))

        #expect(changes.count == 4)
        #expect(changes.first { $0.path == "staged.swift" }?.isStaged == true)
        #expect(changes.first { $0.path == "working.swift" }?.isUnstaged == true)
        #expect(changes.first { $0.path == "new file.md" }?.isUntracked == true)
        #expect(changes.first { $0.path == "renamed.swift" }?.originalPath == "old.swift")
    }

    @Test
    func parsesCommitRecords() {
        let input = "abcdef123456\u{1f}111111 222222\u{1f}Ada Lovelace\u{1f}ada@example.com\u{1f}2026-07-23T10:30:00+03:00\u{1f}HEAD -> main, tag: v1.0\u{1f}G\u{1f}ABCDEF1234567890\u{1f}Ada Lovelace\u{1f}Good signature\u{1f}Ship native client\u{1e}"
        let commits = GitParser.parseCommits(input)

        #expect(commits.count == 1)
        #expect(commits[0].shortHash == "abcdef12")
        #expect(commits[0].parents.count == 2)
        #expect(commits[0].decorations == ["HEAD -> main", "tag: v1.0"])
        #expect(commits[0].signature.status == .good)
        #expect(commits[0].signature.keyID == "ABCDEF1234567890")
        #expect(commits[0].signature.signer == "Ada Lovelace")
        #expect(commits[0].subject == "Ship native client")
    }

    @Test
    func detectsSignatureWhenTrustVerificationCannotComplete() {
        let verification = """
        gpg: Signature made Fri Jul 24 09:27:31 2026 +03
        gpg:                using RSA key ABCDEF1234567890
        gpg: Fatal: trust database unavailable
        """
        let input = "abcdef123456\u{1f}\u{1f}Ada Lovelace\u{1f}ada@example.com\u{1f}2026-07-24T09:27:31+03:00\u{1f}\u{1f}N\u{1f}\u{1f}\u{1f}\(verification)\u{1f}Signed commit\u{1e}"
        let commits = GitParser.parseCommits(input)

        #expect(commits.count == 1)
        #expect(commits[0].signature.status == .cannotCheck)
        #expect(commits[0].signature.keyID == "ABCDEF1234567890")
        #expect(commits[0].subject == "Signed commit")
    }

    @Test
    func parsesAndGroupsReferences() {
        let input = """
        refs/heads/main\u{1f}abc\u{1f}abcdef
        refs/remotes/origin/HEAD\u{1f}abc\u{1f}abcdef
        refs/remotes/origin/main\u{1f}abc\u{1f}abcdef
        refs/tags/v1.0\u{1f}def\u{1f}defdef
        """
        let references = GitParser.parseReferences(input, currentBranch: "main")

        #expect(references.count == 3)
        #expect(references.first { $0.name == "main" }?.isCurrent == true)
        #expect(references.contains { $0.name == "origin/main" })
        #expect(!references.contains { $0.name == "origin/HEAD" })
    }

    @Test
    func loadsARealRepositorySnapshotAndDiff() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)

        let readme = root.appendingPathComponent("README.md")
        try "# Demo\n".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)
        try "# Demo\n\nChanged\n".write(to: readme, atomically: true, encoding: .utf8)
        let nestedDirectory = root.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

        let client = GitClient()
        let discoveredRoot = try await client.repositoryRoot(from: nestedDirectory)
        let snapshot = try await client.snapshot(at: discoveredRoot)

        #expect(discoveredRoot == root.standardizedFileURL)
        #expect(snapshot.branch == "main")
        #expect(snapshot.commits.first?.subject == "Initial commit")
        #expect(snapshot.commits.first?.signature.status == GitSignatureStatus.none)
        #expect(snapshot.changes.first?.path == "README.md")
        #expect(snapshot.changes.first?.isUnstaged == true)

        let diff = try await client.diff(
            at: root,
            change: snapshot.changes[0],
            staged: false
        )
        #expect(diff.contains("+Changed"))
    }

    @Test
    func parsesRepositoryOpenURL() throws {
        let url = try #require(
            URL(string: "gitfork://open?path=%2Ftmp%2FA%20Repository")
        )

        #expect(
            GitForkExternalURL.repositoryPath(from: url)
                == "/tmp/A Repository"
        )
        #expect(
            GitForkExternalURL.repositoryPath(
                from: try #require(URL(string: "https://example.com"))
            ) == nil
        )
    }

    @Test
    func buildsUnsignedAndGPGSignedCommitArguments() {
        #expect(
            GitClient.commitArguments(
                message: "Regular commit",
                amend: false,
                signWithGPG: false
            ) == [
                "commit",
                "--no-gpg-sign",
                "-m",
                "Regular commit"
            ]
        )

        #expect(
            GitClient.commitArguments(
                message: "Signed amendment",
                amend: true,
                signWithGPG: true,
                gpgProgram: "/opt/homebrew/bin/gpg"
            ) == [
                "-c",
                "gpg.format=openpgp",
                "-c",
                "gpg.openpgp.program=/opt/homebrew/bin/gpg",
                "commit",
                "--gpg-sign",
                "--amend",
                "-m",
                "Signed amendment"
            ]
        )
    }

    @Test
    func resolvesExecutablesFromAugmentedGUIPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkGPGTests-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin")
        let fakeGPG = bin.appendingPathComponent("gpg")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: fakeGPG)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeGPG.path
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let searchPath = GitClient.commandSearchPath(
            inheritedPath: bin.path,
            homeDirectory: root
        )
        let resolved = GitClient.executableURL(
            named: "gpg",
            searchPath: searchPath,
            workingDirectory: root
        )

        #expect(resolved == fakeGPG.standardizedFileURL)
        #expect(searchPath.contains("/opt/homebrew/bin"))
        #expect(searchPath.contains("/usr/local/bin"))
    }

    @Test
    func installsBundledCLIIntoWritableDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkInstallerTests-\(UUID().uuidString)")
        let sourceDirectory = root.appendingPathComponent("Source")
        let destinationDirectory = root.appendingPathComponent("bin")
        let helper = sourceDirectory.appendingPathComponent("fork")
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: helper)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helper.path
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = CLIInstallerService(helperURL: helper)
        let installed = try await installer.install(
            in: destinationDirectory.path,
            replacing: false
        )

        #expect(installed == destinationDirectory.appendingPathComponent("fork"))
        #expect(FileManager.default.isExecutableFile(atPath: installed.path))
        #expect(installer.status(in: destinationDirectory.path) == .installed)

        try Data("#!/bin/sh\necho other\n".utf8).write(to: installed)
        #expect(installer.status(in: destinationDirectory.path) == .differentExecutable)

        var rejectedReplacement = false
        do {
            _ = try await installer.install(
                in: destinationDirectory.path,
                replacing: false
            )
        } catch {
            rejectedReplacement = true
        }
        #expect(rejectedReplacement)

        _ = try await installer.install(
            in: destinationDirectory.path,
            replacing: true
        )
        #expect(installer.status(in: destinationDirectory.path) == .installed)
    }

    private func runGit(_ arguments: [String], at root: URL) throws {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw GitOperationError(command: "git \(arguments.joined(separator: " "))", message: message)
        }
    }
}

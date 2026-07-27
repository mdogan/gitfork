import AppKit
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
    func presentsDualStateChangeAccordingToItsSection() {
        let change = WorkingChange(
            path: "dual-state.swift",
            originalPath: nil,
            indexStatus: "A",
            workTreeStatus: "M"
        )

        #expect(change.statusSymbol(staged: true) == "A")
        #expect(change.displayStatus(staged: true) == "Added")
        #expect(change.statusSymbol(staged: false) == "M")
        #expect(change.displayStatus(staged: false) == "Modified")
    }

    @Test
    func groupsDisplayHunksAndTracksOldAndNewLineNumbers() throws {
        let diff = """
        diff --git a/file.swift b/file.swift
        index 1111111..2222222 100644
        --- a/file.swift
        +++ b/file.swift
        @@ -10,3 +10,4 @@
         context before
        -old value
        +new value
        +extra value
         context after
        """
        let document = UnifiedDiff(diff)
        let hunk = try #require(document.displayHunks.first)

        #expect(document.displayHunks.count == 1)
        #expect(hunk.header.text == "@@ -10,3 +10,4 @@")
        #expect(hunk.lines.map(\.text) == [
            " context before",
            "-old value",
            "+new value",
            "+extra value",
            " context after"
        ])
        #expect(hunk.lines.map(\.oldLineNumber) == [10, 11, nil, nil, 12])
        #expect(hunk.lines.map(\.newLineNumber) == [10, nil, 11, 12, 13])
        #expect(hunk.selectableLineIDs.count == 3)
    }

    @Test
    func pairsReplacedLinesIntoSideBySideRows() throws {
        let diff = """
        diff --git a/file.swift b/file.swift
        index 1111111..2222222 100644
        --- a/file.swift
        +++ b/file.swift
        @@ -10,4 +10,5 @@
         context before
        -old value
        -dropped value
        +new value
        +extra value
        +another value
         context after
        """
        let sideBySide = SideBySideDiff(UnifiedDiff(diff))
        let hunk = try #require(sideBySide.hunks.first)

        #expect(hunk.header.text == "@@ -10,4 +10,5 @@")
        #expect(hunk.rows.map { $0.old?.displayText } == [
            "context before",
            "old value",
            "dropped value",
            nil,
            "context after"
        ])
        #expect(hunk.rows.map { $0.new?.displayText } == [
            "context before",
            "new value",
            "extra value",
            "another value",
            "context after"
        ])
        #expect(hunk.rows.map { $0.old?.oldLineNumber } == [10, 11, 12, nil, 13])
        #expect(hunk.rows.map { $0.new?.newLineNumber } == [10, 11, 12, 13, 14])
        #expect(hunk.selectableLineIDs.count == 5)
        // Column width covers context lines too, not just the changed ones.
        #expect(sideBySide.oldColumnCharacters == "context before".count)
        #expect(sideBySide.newColumnCharacters == "context before".count)
    }

    @Test
    func startsANewSideBySideBlockWhenDeletionsFollowAdditions() throws {
        let diff = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,4 +1,4 @@
        -first old
        +first new
        -second old
        +second new
        """
        let sideBySide = SideBySideDiff(UnifiedDiff(diff))
        let hunk = try #require(sideBySide.hunks.first)

        #expect(hunk.rows.count == 2)
        #expect(hunk.rows.map { $0.old?.displayText } == ["first old", "second old"])
        #expect(hunk.rows.map { $0.new?.displayText } == ["first new", "second new"])
    }

    @Test
    func keepsMissingNewlineMarkerOnTheVersionThatOwnsIt() throws {
        let diff = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1 +1 @@
        -old value
        +new value
        \\ No newline at end of file
        """
        let sideBySide = SideBySideDiff(UnifiedDiff(diff))
        let hunk = try #require(sideBySide.hunks.first)

        #expect(hunk.rows.count == 2)
        #expect(hunk.rows[1].old == nil)
        #expect(hunk.rows[1].new?.kind == .noNewline)
    }

    @Test
    func separatesCommitDiffIntoFiles() {
        let diff = """
        commit abcdef123456
        Author: Ada Lovelace

         2 files changed, 2 insertions(+), 1 deletion(-)

        diff --git a/Sources/First File.swift b/Sources/First File.swift
        index 1111111..2222222 100644
        --- a/Sources/First File.swift
        +++ b/Sources/First File.swift
        @@ -1 +1 @@
        -old
        +new
        diff --git a/removed.swift b/removed.swift
        deleted file mode 100644
        --- a/removed.swift
        +++ /dev/null
        @@ -1 +0,0 @@
        -removed
        diff --git a/old name.swift b/new name.swift
        similarity index 100%
        rename from old name.swift
        rename to new name.swift
        diff --git a/Assets/icon image.png b/Assets/icon image.png
        index 3333333..4444444 100644
        Binary files a/Assets/icon image.png and b/Assets/icon image.png differ
        """
        let document = UnifiedDiff(diff)

        #expect(document.preambleLines.first?.text == "commit abcdef123456")
        #expect(document.preambleLines.last?.text == "")
        #expect(document.files.count == 4)
        #expect(document.files[0].path == "Sources/First File.swift")
        #expect(document.files[0].lines.first?.text.hasPrefix("diff --git ") == true)
        #expect(document.files[1].path == "removed.swift")
        #expect(document.files[1].lines.last?.text == "-removed")
        #expect(document.files[2].path == "new name.swift")
        #expect(document.files[3].path == "Assets/icon image.png")
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
    func buildsSlashDelimitedReferenceTree() throws {
        let references = [
            GitReference(
                name: "feature/blob-store",
                fullName: "refs/heads/feature/blob-store",
                kind: .localBranch,
                target: "111111",
                isCurrent: false
            ),
            GitReference(
                name: "feature/proxy/quic",
                fullName: "refs/heads/feature/proxy/quic",
                kind: .localBranch,
                target: "222222",
                isCurrent: false
            ),
            GitReference(
                name: "fix",
                fullName: "refs/heads/fix",
                kind: .localBranch,
                target: "333333",
                isCurrent: false
            )
        ]

        let tree = ReferenceTreeNode.build(from: references)
        #expect(tree.map(\.name) == ["feature", "fix"])

        let feature = try #require(tree.first { $0.name == "feature" })
        #expect(feature.reference == nil)
        #expect(feature.children.map(\.name) == ["blob-store", "proxy"])
        #expect(feature.children.first?.reference?.name == "feature/blob-store")
        #expect(feature.children.last?.children.first?.reference?.name == "feature/proxy/quic")

        let fix = try #require(tree.first { $0.name == "fix" })
        #expect(fix.reference?.name == "fix")
        #expect(fix.children.isEmpty)
    }

    @Test
    func parsesStashAndNulDelimitedWorktreeRecords() {
        let stashes = GitParser.parseStashes(
            "stash@{0}\u{1f}abcdef\u{1f}On main: sidebar work\u{1e}\n"
                + "stash@{1}\u{1f}123456\u{1f}WIP on main: 111111 Initial\u{1e}\n"
        )
        #expect(stashes.map(\.selector) == ["stash@{0}", "stash@{1}"])
        #expect(stashes[0].id == "abcdef")
        #expect(stashes[0].displayName == "sidebar work")
        #expect(stashes[1].displayName == "WIP on main: 111111 Initial")

        let root = URL(fileURLWithPath: "/tmp/main repository")
        let worktreeOutput = """
        worktree /tmp/main repository\0HEAD abcdef\0branch refs/heads/main\0\0worktree /tmp/linked\0HEAD 123456\0detached\0locked in use\0\0
        """
        let worktrees = GitParser.parseWorktrees(worktreeOutput, currentRoot: root)

        #expect(worktrees.count == 2)
        #expect(worktrees[0].isCurrent)
        #expect(worktrees[0].branchName == "main")
        #expect(worktrees[1].displayName == "linked")
        #expect(worktrees[1].isDetached)
        #expect(worktrees[1].isLocked)
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
        #expect(snapshot.stashes.isEmpty)
        #expect(snapshot.worktrees.count == 1)
        #expect(snapshot.worktrees[0].isCurrent)

        let diff = try await client.diff(
            at: root,
            change: snapshot.changes[0],
            staged: false
        )
        #expect(diff.contains("+Changed"))
    }

    @Test
    func discardsTrackedAndUntrackedFilesInOneOperation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkDiscardTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)

        let tracked = root.appendingPathComponent("tracked.txt")
        let alsoTracked = root.appendingPathComponent("also tracked.txt")
        let kept = root.appendingPathComponent("kept.txt")
        try "one\n".write(to: tracked, atomically: true, encoding: .utf8)
        try "one\n".write(to: alsoTracked, atomically: true, encoding: .utf8)
        try "one\n".write(to: kept, atomically: true, encoding: .utf8)
        try runGit(["add", "."], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)

        try "changed\n".write(to: tracked, atomically: true, encoding: .utf8)
        try "changed\n".write(to: alsoTracked, atomically: true, encoding: .utf8)
        try "changed\n".write(to: kept, atomically: true, encoding: .utf8)
        let untracked = root.appendingPathComponent("untracked.txt")
        try "new\n".write(to: untracked, atomically: true, encoding: .utf8)

        let client = GitClient()
        let changes = try await client.snapshot(at: root).changes
        let discarded = changes.filter { $0.path != "kept.txt" }
        #expect(discarded.count == 3)

        try await client.discard(at: root, changes: discarded)

        #expect(try String(contentsOf: tracked, encoding: .utf8) == "one\n")
        #expect(try String(contentsOf: alsoTracked, encoding: .utf8) == "one\n")
        #expect(FileManager.default.fileExists(atPath: untracked.path) == false)
        // Files outside the selection keep their working-tree changes.
        #expect(try String(contentsOf: kept, encoding: .utf8) == "changed\n")
    }

    @Test
    func loadsStashesAndLinkedWorktreesInRepositorySnapshot() async throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkSidebarTests-\(UUID().uuidString)")
        let root = container.appendingPathComponent("repository")
        let linked = container.appendingPathComponent("linked-worktree")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)

        let readme = root.appendingPathComponent("README.md")
        try "one\n".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)
        try "two\n".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["stash", "push", "-m", "sidebar stash"], at: root)
        try runGit(["worktree", "add", "-b", "feature/linked", linked.path], at: root)

        let client = GitClient()
        let snapshot = try await client.snapshot(at: root)
        #expect(snapshot.stashes.count == 1)
        #expect(snapshot.stashes[0].displayName == "sidebar stash")
        #expect(snapshot.worktrees.count == 2)
        #expect(snapshot.worktrees.first(where: \.isCurrent) != nil)
        #expect(
            snapshot.worktrees.first {
                URL(fileURLWithPath: $0.path).resolvingSymlinksInPath()
                    == linked.resolvingSymlinksInPath()
            }?.branchName == "feature/linked"
        )
        let stashCommit = try await client.commit(
            at: root,
            revision: snapshot.stashes[0].selector
        )
        #expect(stashCommit.hash == snapshot.stashes[0].hash)

        let state = try await client.stateToken(at: root)
        #expect(state.stashes.contains("sidebar stash"))
        #expect(state.worktrees.contains("linked-worktree"))
    }

    @Test
    func removesCleanDetachedWorktreeWithoutForce() async throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkRemoveWorktreeTests-\(UUID().uuidString)")
        let root = container.appendingPathComponent("repository")
        let linked = container.appendingPathComponent("detached worktree")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)
        try runGit(["commit", "--allow-empty", "-m", "Initial commit"], at: root)
        try runGit(["worktree", "add", "--detach", linked.path, "HEAD"], at: root)

        let client = GitClient()
        let worktree = try #require(
            try await client.snapshot(at: root).worktrees.first {
                URL(fileURLWithPath: $0.path).standardizedFileURL
                    == linked.standardizedFileURL
            }
        )
        #expect(worktree.isDetached)
        #expect(
            try GitClient.removeWorktreeArguments(for: worktree)
                == ["worktree", "remove", "--", worktree.path]
        )

        try await client.removeWorktree(at: root, worktree: worktree)

        #expect(!FileManager.default.fileExists(atPath: linked.path))
        #expect(try await client.snapshot(at: root).worktrees.count == 1)
    }

    @Test
    func refusesToForceRemoveDirtyDetachedWorktree() async throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkDirtyWorktreeTests-\(UUID().uuidString)")
        let root = container.appendingPathComponent("repository")
        let linked = container.appendingPathComponent("detached-worktree")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)
        try runGit(["commit", "--allow-empty", "-m", "Initial commit"], at: root)
        try runGit(["worktree", "add", "--detach", linked.path, "HEAD"], at: root)
        try "keep me\n".write(
            to: linked.appendingPathComponent("untracked.txt"),
            atomically: true,
            encoding: .utf8
        )

        let client = GitClient()
        let worktree = try #require(
            try await client.snapshot(at: root).worktrees.first {
                URL(fileURLWithPath: $0.path).standardizedFileURL
                    == linked.standardizedFileURL
            }
        )

        await #expect(throws: GitOperationError.self) {
            try await client.removeWorktree(at: root, worktree: worktree)
        }
        #expect(FileManager.default.fileExists(atPath: linked.path))
        #expect(
            FileManager.default.fileExists(
                atPath: linked.appendingPathComponent("untracked.txt").path
            )
        )
    }

    @Test
    func prunesMissingWorktreeRegistrationImmediately() async throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkPruneWorktreeTests-\(UUID().uuidString)")
        let root = container.appendingPathComponent("repository")
        let linked = container.appendingPathComponent("stale-worktree")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)
        try runGit(["commit", "--allow-empty", "-m", "Initial commit"], at: root)
        try runGit(["worktree", "add", "--detach", linked.path, "HEAD"], at: root)
        try FileManager.default.removeItem(at: linked)

        let client = GitClient()
        let staleWorktree = try #require(
            try await client.snapshot(at: root).worktrees.first(where: \.isPrunable)
        )
        #expect(staleWorktree.isPrunable)
        #expect(staleWorktree.displayName == linked.lastPathComponent)
        #expect(
            GitClient.pruneStaleWorktreeArguments
                == ["worktree", "prune", "--expire", "now"]
        )

        try await client.pruneStaleWorktrees(at: root)

        #expect(try await client.snapshot(at: root).worktrees.count == 1)
    }

    @Test
    func repositoryStateTokenDetectsEditsAndNewBranches() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkMonitorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)

        let readme = root.appendingPathComponent("README.md")
        try "one\n".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)

        let client = GitClient()
        let clean = try await client.stateToken(at: root)

        try "two\n".write(to: readme, atomically: true, encoding: .utf8)
        let edited = try await client.stateToken(at: root)
        #expect(edited != clean)

        try "six\n".write(to: readme, atomically: true, encoding: .utf8)
        let editedAgain = try await client.stateToken(at: root)
        #expect(editedAgain != edited)

        try runGit(["branch", "feature/live-refresh"], at: root)
        let withBranch = try await client.stateToken(at: root)
        #expect(withBranch != editedAgain)
    }

    @Test
    func appliesSelectedLinesAcrossHunksAndDiscardsACompleteTrackedFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkPartialPatchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)

        let file = root.appendingPathComponent("lines.txt")
        let originalLines = (1...20).map { "line \($0)" }
        try (originalLines.joined(separator: "\n") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)
        try runGit(["add", "lines.txt"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)

        var editedLines = originalLines
        editedLines[1] = "LINE 2"
        editedLines[14] = "LINE 15"
        try (editedLines.joined(separator: "\n") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)

        let client = GitClient()
        var snapshot = try await client.snapshot(at: root)
        var change = try #require(snapshot.changes.first { $0.path == "lines.txt" })
        let workingDiff = try await client.diff(at: root, change: change, staged: false)
        let workingDocument = UnifiedDiff(workingDiff)
        let allEditedLines = selectedLineIDs(
            in: workingDocument,
            matching: ["-line 2", "+LINE 2", "-line 15", "+LINE 15"]
        )
        #expect(allEditedLines.count == 4)

        let stagePatch = try #require(
            workingDocument.partialPatch(
                selecting: allEditedLines,
                direction: .forward
            )
        )
        try await client.stage(at: root, patch: stagePatch)
        let stagedAfterStage = try runGitOutput(["diff", "--cached"], at: root)
        #expect(stagedAfterStage.contains("+LINE 2"))
        #expect(stagedAfterStage.contains("+LINE 15"))

        snapshot = try await client.snapshot(at: root)
        change = try #require(snapshot.changes.first { $0.path == "lines.txt" })
        let stagedDiff = try await client.diff(at: root, change: change, staged: true)
        let stagedDocument = UnifiedDiff(stagedDiff)
        let firstReplacement = selectedLineIDs(
            in: stagedDocument,
            matching: ["-line 2", "+LINE 2"]
        )
        let unstagePatch = try #require(
            stagedDocument.partialPatch(
                selecting: firstReplacement,
                direction: .reverse
            )
        )
        try await client.unstage(at: root, patch: unstagePatch)
        let stagedAfterUnstage = try runGitOutput(["diff", "--cached"], at: root)
        #expect(!stagedAfterUnstage.contains("+LINE 2"))
        #expect(stagedAfterUnstage.contains("+LINE 15"))

        snapshot = try await client.snapshot(at: root)
        change = try #require(snapshot.changes.first { $0.path == "lines.txt" })
        let remainingWorkingDiff = try await client.diff(
            at: root,
            change: change,
            staged: false
        )
        let remainingDocument = UnifiedDiff(remainingWorkingDiff)
        let discardSelection = selectedLineIDs(
            in: remainingDocument,
            matching: ["-line 2", "+LINE 2"]
        )
        let discardPatch = try #require(
            remainingDocument.partialPatch(
                selecting: discardSelection,
                direction: .reverse
            )
        )
        try await client.discard(at: root, patch: discardPatch)

        var contents = try String(contentsOf: file, encoding: .utf8)
        #expect(contents.contains("line 2\n"))
        #expect(contents.contains("LINE 15\n"))

        contents += "unstaged tail\n"
        try contents.write(to: file, atomically: true, encoding: .utf8)
        snapshot = try await client.snapshot(at: root)
        change = try #require(snapshot.changes.first { $0.path == "lines.txt" })
        try await client.discard(at: root, changes: [change])

        let restored = try String(contentsOf: file, encoding: .utf8)
        #expect(!restored.contains("unstaged tail"))
        #expect(restored.contains("LINE 15\n"))
    }

    @Test
    func partiallyStagesAndDiscardsUntrackedFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkUntrackedPatchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        let client = GitClient()

        let stagedFile = root.appendingPathComponent("partial.txt")
        try "alpha\nbeta\ngamma\n".write(
            to: stagedFile,
            atomically: true,
            encoding: .utf8
        )
        var snapshot = try await client.snapshot(at: root)
        var change = try #require(snapshot.changes.first { $0.path == "partial.txt" })
        let untrackedDiff = try await client.diff(at: root, change: change, staged: false)
        let untrackedDocument = UnifiedDiff(untrackedDiff)
        let betaLine = selectedLineIDs(in: untrackedDocument, matching: ["+beta"])
        let stagePatch = try #require(
            untrackedDocument.partialPatch(selecting: betaLine, direction: .forward)
        )
        try await client.stage(at: root, patch: stagePatch)
        #expect(try runGitOutput(["show", ":partial.txt"], at: root) == "beta\n")
        #expect(try String(contentsOf: stagedFile, encoding: .utf8) == "alpha\nbeta\ngamma\n")

        let fullyStagedFile = root.appendingPathComponent("full staged.txt")
        try "one\ntwo\nthree\n".write(
            to: fullyStagedFile,
            atomically: true,
            encoding: .utf8
        )
        try await client.stage(at: root, paths: ["full staged.txt"])
        snapshot = try await client.snapshot(at: root)
        change = try #require(snapshot.changes.first { $0.path == "full staged.txt" })
        let fullyStagedDiff = try await client.diff(at: root, change: change, staged: true)
        let fullyStagedDocument = UnifiedDiff(fullyStagedDiff)
        let stagedMiddleLine = selectedLineIDs(
            in: fullyStagedDocument,
            matching: ["+two"]
        )
        let partialUnstagePatch = try #require(
            fullyStagedDocument.partialPatch(
                selecting: stagedMiddleLine,
                direction: .reverse,
                treatNewFileAsExisting: true
            )
        )
        try await client.unstage(at: root, patch: partialUnstagePatch)
        #expect(
            try runGitOutput(["show", ":full staged.txt"], at: root)
                == "one\nthree\n"
        )
        #expect(
            try String(contentsOf: fullyStagedFile, encoding: .utf8)
                == "one\ntwo\nthree\n"
        )

        let discardedFile = root.appendingPathComponent("discard.txt")
        try "one\ntwo\nthree\n".write(
            to: discardedFile,
            atomically: true,
            encoding: .utf8
        )
        snapshot = try await client.snapshot(at: root)
        change = try #require(snapshot.changes.first { $0.path == "discard.txt" })
        let discardDiff = try await client.diff(at: root, change: change, staged: false)
        let discardDocument = UnifiedDiff(discardDiff)
        let middleLine = selectedLineIDs(in: discardDocument, matching: ["+two"])
        let discardPatch = try #require(
            discardDocument.partialPatch(
                selecting: middleLine,
                direction: .reverse,
                treatNewFileAsExisting: true
            )
        )
        try await client.discard(at: root, patch: discardPatch)
        #expect(try String(contentsOf: discardedFile, encoding: .utf8) == "one\nthree\n")

        snapshot = try await client.snapshot(at: root)
        change = try #require(snapshot.changes.first { $0.path == "discard.txt" })
        try await client.discard(at: root, changes: [change])
        #expect(!FileManager.default.fileExists(atPath: discardedFile.path))
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
    func buildsHistoryArgumentsWithoutSignatureVerification() {
        let allHistory = GitClient.historyArguments(revision: nil)
        let branchHistory = GitClient.historyArguments(revision: "refs/heads/main")

        #expect(allHistory.last == "--all")
        #expect(branchHistory.last == "refs/heads/main")
        #expect(!allHistory.joined().contains("%G?"))
        #expect(!allHistory.joined().contains("%GK"))
        #expect(!allHistory.joined().contains("%GS"))
    }

    @Test
    func buildsExplicitNonForcePushAndNonPruningFetchArguments() {
        let existingUpstream = GitPushTarget(
            remote: "origin",
            remoteRef: "refs/heads/main",
            establishesUpstream: false
        )
        let firstPush = GitPushTarget(
            remote: "backup",
            remoteRef: "refs/heads/feature/safe-push",
            establishesUpstream: true
        )

        #expect(
            GitClient.pushArguments(for: existingUpstream)
                == [
                    "-c",
                    "remote.origin.mirror=false",
                    "push",
                    "--no-force",
                    "--no-follow-tags",
                    "--",
                    "origin",
                    "HEAD:refs/heads/main"
                ]
        )
        #expect(
            GitClient.pushArguments(for: firstPush)
                == [
                    "-c",
                    "remote.backup.mirror=false",
                    "push",
                    "--no-force",
                    "--no-follow-tags",
                    "--set-upstream",
                    "--",
                    "backup",
                    "HEAD:refs/heads/feature/safe-push"
                ]
        )
        #expect(GitClient.fetchArguments() == ["fetch", "--all"])
    }

    @Test
    func buildsReferenceDeletionArguments() throws {
        let branch = GitReference(
            name: "feature/sidebar-delete",
            fullName: "refs/heads/feature/sidebar-delete",
            kind: .localBranch,
            target: "abcdef",
            isCurrent: false
        )
        let tag = GitReference(
            name: "v1.0",
            fullName: "refs/tags/v1.0",
            kind: .tag,
            target: "abcdef",
            isCurrent: false
        )
        let currentBranch = GitReference(
            name: "main",
            fullName: "refs/heads/main",
            kind: .localBranch,
            target: "abcdef",
            isCurrent: true
        )
        let remoteBranch = GitReference(
            name: "origin/main",
            fullName: "refs/remotes/origin/main",
            kind: .remoteBranch,
            target: "abcdef",
            isCurrent: false
        )

        #expect(
            try GitClient.deleteArguments(for: branch)
                == ["branch", "--delete", "--", "feature/sidebar-delete"]
        )
        #expect(
            try GitClient.deleteArguments(for: tag)
                == ["tag", "--delete", "--", "v1.0"]
        )
        #expect(
            try GitClient.forceDeleteArguments(for: branch)
                == ["branch", "-D", "--", "feature/sidebar-delete"]
        )
        #expect(throws: GitOperationError.self) {
            try GitClient.deleteArguments(for: currentBranch)
        }
        #expect(throws: GitOperationError.self) {
            try GitClient.deleteArguments(for: remoteBranch)
        }
        #expect(throws: GitOperationError.self) {
            try GitClient.forceDeleteArguments(for: tag)
        }
        #expect(throws: GitOperationError.self) {
            try GitClient.forceDeleteArguments(for: currentBranch)
        }
        #expect(throws: GitOperationError.self) {
            try GitClient.forceDeleteArguments(for: remoteBranch)
        }
    }

    @Test
    func buildsApplyAndDropStashArguments() {
        #expect(
            GitClient.stashArguments(message: "staged", scope: .staged)
                == ["stash", "push", "--staged", "-m", "staged"]
        )
        #expect(
            GitClient.stashArguments(message: "unstaged", scope: .unstaged)
                == [
                    "stash",
                    "push",
                    "--keep-index",
                    "--include-untracked",
                    "-m",
                    "unstaged"
                ]
        )
        #expect(
            GitClient.stashArguments(message: "all", scope: .all)
                == ["stash", "push", "--include-untracked", "-m", "all"]
        )
        #expect(
            GitClient.applyStashArguments(selector: "stash@{2}")
                == ["stash", "apply", "--index", "stash@{2}"]
        )
        #expect(
            GitClient.dropStashArguments(selector: "stash@{2}")
                == ["stash", "drop", "stash@{2}"]
        )
    }

    @Test
    func stashesStagedAndUnstagedScopesIndependently() async throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkStashScopeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: container,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: container) }

        func prepareRepository(named name: String) throws -> URL {
            let root = container.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            try runGit(["init", "-b", "main"], at: root)
            try runGit(["config", "user.name", "GitFork Tests"], at: root)
            try runGit(["config", "user.email", "tests@example.com"], at: root)

            try "base\n".write(
                to: root.appendingPathComponent("staged.txt"),
                atomically: true,
                encoding: .utf8
            )
            try "base\n".write(
                to: root.appendingPathComponent("unstaged.txt"),
                atomically: true,
                encoding: .utf8
            )
            try runGit(["add", "staged.txt", "unstaged.txt"], at: root)
            try runGit(["commit", "-m", "Initial commit"], at: root)

            try "staged\n".write(
                to: root.appendingPathComponent("staged.txt"),
                atomically: true,
                encoding: .utf8
            )
            try runGit(["add", "staged.txt"], at: root)
            try "unstaged\n".write(
                to: root.appendingPathComponent("unstaged.txt"),
                atomically: true,
                encoding: .utf8
            )
            try "untracked\n".write(
                to: root.appendingPathComponent("notes.txt"),
                atomically: true,
                encoding: .utf8
            )
            return root
        }

        let client = GitClient()

        let stagedRoot = try prepareRepository(named: "staged")
        try await client.stash(
            at: stagedRoot,
            message: "staged only",
            scope: .staged
        )
        let afterStaged = try await client.snapshot(at: stagedRoot)
        #expect(!afterStaged.changes.contains { $0.path == "staged.txt" })
        #expect(
            afterStaged.changes.first { $0.path == "unstaged.txt" }?.isUnstaged
                == true
        )
        #expect(
            afterStaged.changes.first { $0.path == "notes.txt" }?.isUntracked
                == true
        )
        #expect(afterStaged.stashes.count == 1)

        let unstagedRoot = try prepareRepository(named: "unstaged")
        try await client.stash(
            at: unstagedRoot,
            message: "unstaged only",
            scope: .unstaged
        )
        let afterUnstaged = try await client.snapshot(at: unstagedRoot)
        let remainingStaged = try #require(
            afterUnstaged.changes.first { $0.path == "staged.txt" }
        )
        #expect(remainingStaged.isStaged)
        #expect(!remainingStaged.isUnstaged)
        #expect(!afterUnstaged.changes.contains { $0.path == "unstaged.txt" })
        #expect(!afterUnstaged.changes.contains { $0.path == "notes.txt" })
        #expect(afterUnstaged.stashes.count == 1)
    }

    @Test
    func rejectsStagedOnlyStashBeforeMixedFileSideEffects() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkMixedStashTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)

        let file = root.appendingPathComponent("mixed.txt")
        try "one\ntwo\n".write(to: file, atomically: true, encoding: .utf8)
        try runGit(["add", "mixed.txt"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)

        try "ONE\ntwo\n".write(to: file, atomically: true, encoding: .utf8)
        try runGit(["add", "mixed.txt"], at: root)
        try "ONE\nTWO\n".write(to: file, atomically: true, encoding: .utf8)

        var rejected = false
        do {
            try await GitClient().stash(
                at: root,
                message: "unsafe staged stash",
                scope: .staged
            )
        } catch is GitOperationError {
            rejected = true
        }

        #expect(rejected)
        let snapshot = try await GitClient().snapshot(at: root)
        #expect(snapshot.stashes.isEmpty)
        let mixedChange = try #require(
            snapshot.changes.first { $0.path == "mixed.txt" }
        )
        #expect(mixedChange.isStaged)
        #expect(mixedChange.isUnstaged)
    }

    @Test
    func pushesOnlyToTheConfirmedUpstreamTarget() async throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkPushTargetTests-\(UUID().uuidString)")
        let root = container.appendingPathComponent("work")
        let origin = container.appendingPathComponent("origin.git")
        let backup = container.appendingPathComponent("backup.git")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        try runGit(["init", "--bare", origin.path], at: container)
        try runGit(["init", "--bare", backup.path], at: container)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)
        try runGit(["commit", "--allow-empty", "-m", "Initial commit"], at: root)
        try runGit(["remote", "add", "origin", origin.path], at: root)
        try runGit(["remote", "add", "backup", backup.path], at: root)
        try runGit(["push", "--set-upstream", "origin", "main"], at: root)
        try runGit(["push", "backup", "main"], at: root)
        try runGit(["commit", "--allow-empty", "-m", "Next commit"], at: root)
        try runGit(["config", "remote.pushDefault", "backup"], at: root)
        try runGit(["config", "push.default", "current"], at: root)
        try runGit(["config", "push.followTags", "true"], at: root)
        try runGit(["config", "remote.origin.mirror", "true"], at: root)
        try runGit(
            ["config", "--add", "remote.origin.push", "+refs/heads/*:refs/heads/*"],
            at: root
        )
        try runGit(["branch", "must-not-push"], at: root)
        try runGit(["tag", "must-not-follow"], at: root)

        let client = GitClient()
        let snapshot = try await client.snapshot(at: root)
        let target = try #require(snapshot.pushTarget)
        #expect(target.displayName == "origin/main")

        try await client.push(at: root, target: target)

        let head = try runGitOutput(["rev-parse", "HEAD"], at: root)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let originHead = try runGitOutput(["rev-parse", "refs/heads/main"], at: origin)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let backupHead = try runGitOutput(["rev-parse", "refs/heads/main"], at: backup)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(originHead == head)
        #expect(backupHead != head)
        #expect(
            try runGitOutput(["tag", "--list", "must-not-follow"], at: origin)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
        #expect(
            try runGitOutput(["branch", "--list", "must-not-push"], at: origin)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )

        try runGit(["switch", "-c", "feature/first-push"], at: root)
        let firstPushSnapshot = try await client.snapshot(at: root)
        let firstPushTarget = try #require(firstPushSnapshot.pushTarget)
        #expect(firstPushTarget.displayName == "backup/feature/first-push")
        #expect(firstPushTarget.establishesUpstream)
        try await client.push(at: root, target: firstPushTarget)
        #expect(
            try runGitOutput(
                ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
                at: root
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == "backup/feature/first-push"
        )
    }

    @Test
    func refusesToReuseLocalBranchTrackingAnotherRemote() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkRemoteCheckoutTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)
        try runGit(["commit", "--allow-empty", "-m", "Initial commit"], at: root)
        try runGit(
            ["remote", "add", "origin", "https://example.invalid/origin.git"],
            at: root
        )
        try runGit(
            ["remote", "add", "upstream", "https://example.invalid/upstream.git"],
            at: root
        )
        try runGit(["update-ref", "refs/remotes/origin/topic", "HEAD"], at: root)
        try runGit(["update-ref", "refs/remotes/upstream/topic", "HEAD"], at: root)
        try runGit(["branch", "topic"], at: root)
        try runGit(
            ["branch", "--set-upstream-to=upstream/topic", "topic"],
            at: root
        )

        let reference = GitReference(
            name: "origin/topic",
            fullName: "refs/remotes/origin/topic",
            kind: .remoteBranch,
            target: try runGitOutput(["rev-parse", "HEAD"], at: root)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            isCurrent: false
        )
        var rejected = false
        do {
            try await GitClient().checkout(at: root, reference: reference)
        } catch is GitOperationError {
            rejected = true
        }

        #expect(rejected)
        #expect(
            try runGitOutput(["branch", "--show-current"], at: root)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == "main"
        )

        try runGit(
            ["branch", "--set-upstream-to=origin/topic", "topic"],
            at: root
        )
        try await GitClient().checkout(at: root, reference: reference)
        #expect(
            try runGitOutput(["branch", "--show-current"], at: root)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == "topic"
        )

        try runGit(["switch", "main"], at: root)
        try runGit(["update-ref", "refs/remotes/origin/new-topic", "HEAD"], at: root)
        let newReference = GitReference(
            name: "origin/new-topic",
            fullName: "refs/remotes/origin/new-topic",
            kind: .remoteBranch,
            target: reference.target,
            isCurrent: false
        )
        try await GitClient().checkout(at: root, reference: newReference)
        #expect(
            try runGitOutput(["branch", "--show-current"], at: root)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == "new-topic"
        )
        #expect(
            try runGitOutput(
                ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
                at: root
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == "origin/new-topic"
        )
    }

    @Test
    @MainActor
    func serializesRepositoryOperationsAtTheStoreBoundary() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkOperationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)
        try runGit(["commit", "--allow-empty", "-m", "Initial commit"], at: root)

        let store = RepositoryStore()
        store.openRepository(root)
        store.openRepository(root)

        #expect(store.errorMessage?.contains("Wait for Opening repository") == true)
        for _ in 0..<500 {
            guard store.isLoading else { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!store.isLoading)
        #expect(store.repositoryURL?.standardizedFileURL == root.standardizedFileURL)
    }

    @Test
    @MainActor
    func separateStoresLoadRepositoriesIndependently() async throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkWindowStoreTests-\(UUID().uuidString)")
        let firstRoot = container.appendingPathComponent("First")
        let secondRoot = container.appendingPathComponent("Second")
        try FileManager.default.createDirectory(
            at: firstRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: container) }

        for (root, branch) in [(firstRoot, "first"), (secondRoot, "second")] {
            try runGit(["init", "-b", branch], at: root)
            try runGit(["config", "user.name", "GitFork Tests"], at: root)
            try runGit(["config", "user.email", "tests@example.com"], at: root)
            try runGit(["commit", "--allow-empty", "-m", "Initial commit"], at: root)
        }

        let firstStore = RepositoryStore()
        let secondStore = RepositoryStore()
        firstStore.openRepository(firstRoot)
        secondStore.openRepository(secondRoot)

        for _ in 0..<500 {
            guard firstStore.isLoading || secondStore.isLoading else { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!firstStore.isLoading)
        #expect(!secondStore.isLoading)
        #expect(
            firstStore.repositoryURL?.standardizedFileURL
                == firstRoot.standardizedFileURL
        )
        #expect(
            secondStore.repositoryURL?.standardizedFileURL
                == secondRoot.standardizedFileURL
        )
        #expect(firstStore.branch == "first")
        #expect(secondStore.branch == "second")
    }

    @Test
    @MainActor
    func routesRepositoryWindowsIntoTheSourceTabGroup() async {
        _ = NSApplication.shared
        let sourceWindow = NSWindow()
        let repositoryWindow = NSWindow()
        let coordinator = RepositoryTabCoordinator()
        let sourceTabID = UUID()

        coordinator.register(
            tabID: sourceTabID,
            repositoryPath: "/tmp/First",
            window: sourceWindow
        )
        coordinator.prepareNewTab(
            repositoryPath: "/tmp/Second",
            sourceTabID: sourceTabID
        )
        let requestedPath = coordinator.register(
            tabID: UUID(),
            repositoryPath: "",
            window: repositoryWindow
        )
        try? await Task.sleep(for: .milliseconds(300))

        #expect(requestedPath == "/tmp/Second")
        #expect(
            sourceWindow.tabbedWindows?.contains {
                $0 === repositoryWindow
            } == true
        )
        #expect(coordinator.focusTab(presenting: "/tmp/Second"))
        #expect(!coordinator.focusTab(presenting: "/tmp/Missing"))

        sourceWindow.close()
        repositoryWindow.close()
    }

    @Test
    @MainActor
    func appDelegateQueuesExternalRepositoryRequestsUntilConsumed() throws {
        let appDelegate = GitForkAppDelegate()
        let url = try #require(
            URL(string: "gitfork://open?path=%2Ftmp%2FFirst")
        )

        appDelegate.application(NSApplication.shared, open: [url])

        let request = try #require(appDelegate.openRequests.first)
        #expect(request.url == url)

        appDelegate.consume(request)
        #expect(appDelegate.openRequests.isEmpty)
    }

    @Test
    func appliesAStashWithoutRemovingItThenDropsIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkStashActionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)

        let readme = root.appendingPathComponent("README.md")
        let untracked = root.appendingPathComponent("notes.txt")
        try "one\n".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)

        try "two\n".write(to: readme, atomically: true, encoding: .utf8)
        try "untracked\n".write(to: untracked, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: root)

        let client = GitClient()
        try await client.stash(at: root, message: "stash actions")
        var snapshot = try await client.snapshot(at: root)
        let stash = try #require(snapshot.stashes.first)

        #expect(
            try String(contentsOf: readme, encoding: .utf8) == "one\n"
        )
        #expect(!FileManager.default.fileExists(atPath: untracked.path))

        try await client.applyStash(at: root, stash: stash)

        #expect(
            try String(contentsOf: readme, encoding: .utf8) == "two\n"
        )
        #expect(FileManager.default.fileExists(atPath: untracked.path))
        #expect(
            try runGitOutput(["diff", "--cached", "--", "README.md"], at: root)
                .contains("+two")
        )

        snapshot = try await client.snapshot(at: root)
        #expect(snapshot.stashes.map(\.id).contains(stash.id))

        try await client.dropStash(at: root, stash: stash)
        snapshot = try await client.snapshot(at: root)
        #expect(snapshot.stashes.isEmpty)
    }

    @Test
    func deletesMergedLocalBranchesAndLocalTags() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkDeleteReferenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)

        let readme = root.appendingPathComponent("README.md")
        try "# Delete references\n".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)
        try runGit(["branch", "feature/delete-me"], at: root)
        try runGit(["tag", "v-delete-me"], at: root)

        let client = GitClient()
        try await client.delete(
            at: root,
            reference: GitReference(
                name: "feature/delete-me",
                fullName: "refs/heads/feature/delete-me",
                kind: .localBranch,
                target: "abcdef",
                isCurrent: false
            )
        )
        try await client.delete(
            at: root,
            reference: GitReference(
                name: "v-delete-me",
                fullName: "refs/tags/v-delete-me",
                kind: .tag,
                target: "abcdef",
                isCurrent: false
            )
        )

        #expect(
            try runGitOutput(
                ["branch", "--list", "feature/delete-me"],
                at: root
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
        #expect(
            try runGitOutput(
                ["tag", "--list", "v-delete-me"],
                at: root
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
    }

    @Test
    func requiresForceToDeleteUnmergedLocalBranch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitForkForceDeleteBranchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitFork Tests"], at: root)
        try runGit(["config", "user.email", "tests@example.com"], at: root)

        let readme = root.appendingPathComponent("README.md")
        try "main\n".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)
        try runGit(["switch", "-c", "feature/unmerged"], at: root)

        let feature = root.appendingPathComponent("feature.txt")
        try "unmerged\n".write(to: feature, atomically: true, encoding: .utf8)
        try runGit(["add", "feature.txt"], at: root)
        try runGit(["commit", "-m", "Unmerged commit"], at: root)
        try runGit(["switch", "main"], at: root)

        let reference = GitReference(
            name: "feature/unmerged",
            fullName: "refs/heads/feature/unmerged",
            kind: .localBranch,
            target: "abcdef",
            isCurrent: false
        )
        let client = GitClient()

        do {
            try await client.delete(at: root, reference: reference)
            Issue.record("Safe deletion unexpectedly deleted an unmerged branch")
        } catch let error as UnmergedBranchDeletionError {
            #expect(error.branch == reference.name)
            #expect(error.message.contains("is not fully merged"))
        }

        #expect(
            !(try runGitOutput(["branch", "--list", reference.name], at: root)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty)
        )

        try await client.forceDelete(at: root, reference: reference)

        #expect(
            try runGitOutput(["branch", "--list", reference.name], at: root)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
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
        _ = try runGitCommand(arguments, at: root)
    }

    private func runGitOutput(_ arguments: [String], at root: URL) throws -> String {
        try runGitCommand(arguments, at: root)
    }

    private func runGitCommand(_ arguments: [String], at root: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.standardOutput = output
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

        return String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
    }

    private func selectedLineIDs(
        in document: UnifiedDiff,
        matching texts: Set<String>
    ) -> Set<Int> {
        Set(document.lines.filter { texts.contains($0.text) }.map(\.id))
    }
}

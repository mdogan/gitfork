import Foundation

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case changes = "Changes"
    case history = "All Commits"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .changes: "square.and.pencil"
        case .history: "clock.arrow.circlepath"
        }
    }
}

enum CommitHistoryScope: Equatable, Sendable {
    case all
    case revision(String)
    case path(String)
    case lostAndDangling

    init(revision: String?) {
        self = revision.map(Self.revision) ?? .all
    }
}

struct RepositoryPathItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case directory
        case file
    }

    let path: String
    let kind: Kind

    var id: String {
        "\(kind.rawValue):\(path)"
    }
}

enum ReferenceKind: String, Sendable {
    case localBranch
    case remoteBranch
    case tag

    var title: String {
        switch self {
        case .localBranch: "Branches"
        case .remoteBranch: "Remotes"
        case .tag: "Tags"
        }
    }

    var icon: String {
        switch self {
        case .localBranch: "arrow.triangle.branch"
        case .remoteBranch: "cloud"
        case .tag: "tag"
        }
    }
}

struct GitReference: Identifiable, Hashable, Sendable {
    let name: String
    let fullName: String
    let kind: ReferenceKind
    let target: String
    let isCurrent: Bool

    var id: String { fullName }

    static func primaryLocalBranch(in references: [GitReference]) -> GitReference? {
        references.first { $0.kind == .localBranch && $0.name == "main" }
            ?? references.first { $0.kind == .localBranch && $0.name == "master" }
    }
}

struct ReferenceTreeNode: Identifiable, Hashable, Sendable {
    let name: String
    let path: String
    let kind: ReferenceKind
    let reference: GitReference?
    let children: [ReferenceTreeNode]

    var id: String {
        "\(kind.rawValue):\(path)"
    }

    static func build(from references: [GitReference]) -> [ReferenceTreeNode] {
        build(from: references, components: [], depth: 0)
    }

    private static func build(
        from references: [GitReference],
        components: [String],
        depth: Int
    ) -> [ReferenceTreeNode] {
        let grouped = Dictionary(grouping: references) {
            $0.name.split(separator: "/", omittingEmptySubsequences: false)
                .map(String.init)[depth]
        }

        return grouped.map { name, matches in
            let pathComponents = components + [name]
            let path = pathComponents.joined(separator: "/")
            let exact = matches.first {
                $0.name.split(separator: "/", omittingEmptySubsequences: false).count == depth + 1
            }
            let descendants = matches.filter {
                $0.name.split(separator: "/", omittingEmptySubsequences: false).count > depth + 1
            }

            return ReferenceTreeNode(
                name: name,
                path: path,
                kind: matches[0].kind,
                reference: exact,
                children: descendants.isEmpty
                    ? []
                    : build(
                        from: descendants,
                        components: pathComponents,
                        depth: depth + 1
                    )
            )
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

struct GitStash: Identifiable, Hashable, Sendable {
    let selector: String
    let hash: String
    let subject: String

    var id: String { hash }

    var displayName: String {
        guard subject.hasPrefix("On "),
              let separator = subject.range(of: ": ") else {
            return subject
        }
        return String(subject[separator.upperBound...])
    }
}

struct GitPushTarget: Hashable, Sendable {
    let remote: String
    let remoteRef: String
    let establishesUpstream: Bool

    var branchName: String {
        remoteRef.hasPrefix("refs/heads/")
            ? String(remoteRef.dropFirst("refs/heads/".count))
            : remoteRef
    }

    var displayName: String {
        "\(remote)/\(branchName)"
    }
}

enum StashScope: String, Sendable {
    case staged
    case unstaged
    case all

    var title: String {
        switch self {
        case .staged: "Staged Changes"
        case .unstaged: "Unstaged Changes"
        case .all: "All Changes"
        }
    }

    var description: String {
        switch self {
        case .staged:
            "Only staged changes will be saved. Unstaged and untracked changes will remain."
        case .unstaged:
            "Unstaged and untracked changes will be saved. Staged changes will remain."
        case .all:
            "Staged, unstaged, and untracked changes will be saved."
        }
    }
}

struct GitWorktree: Identifiable, Hashable, Sendable {
    let path: String
    let head: String?
    let branch: String?
    let isBare: Bool
    let isDetached: Bool
    let isLocked: Bool
    let isPrunable: Bool
    let isCurrent: Bool

    var id: String { path }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var branchName: String? {
        branch.map {
            $0.hasPrefix("refs/heads/")
                ? String($0.dropFirst("refs/heads/".count))
                : $0
        }
    }
}

enum GitSignatureStatus: Character, Hashable, Sendable {
    case good = "G"
    case bad = "B"
    case unknownValidity = "U"
    case expiredSignature = "X"
    case expiredKey = "Y"
    case revokedKey = "R"
    case cannotCheck = "E"
    case none = "N"

    init(code: Character?) {
        self = code.flatMap(Self.init(rawValue:)) ?? .cannotCheck
    }

    var isSigned: Bool { self != .none }

    var title: String {
        switch self {
        case .good: "Verified signature"
        case .bad: "Bad signature"
        case .unknownValidity: "Signed · unknown trust"
        case .expiredSignature: "Signed · signature expired"
        case .expiredKey: "Signed · key expired"
        case .revokedKey: "Signed · key revoked"
        case .cannotCheck: "Signed · verification unavailable"
        case .none: "Unsigned"
        }
    }
}

struct GitCommitSignature: Hashable, Sendable {
    let status: GitSignatureStatus
    let keyID: String
    let signer: String

    static let unsigned = GitCommitSignature(
        status: .none,
        keyID: "",
        signer: ""
    )

    var details: String {
        var parts = [status.title]
        if !signer.isEmpty {
            parts.append(signer)
        }
        if !keyID.isEmpty {
            parts.append("Key \(keyID)")
        }
        return parts.joined(separator: " · ")
    }
}

struct GitCommit: Identifiable, Hashable, Sendable {
    let hash: String
    let parents: [String]
    let authorName: String
    let authorEmail: String
    let date: Date
    let decorations: [String]
    let signature: GitCommitSignature
    let subject: String

    var id: String { hash }
    var shortHash: String { String(hash.prefix(8)) }
    var initials: String {
        let parts = authorName.split(separator: " ")
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

struct WorkingChange: Identifiable, Hashable, Sendable {
    let path: String
    let originalPath: String?
    let indexStatus: Character
    let workTreeStatus: Character

    var id: String {
        "\(path)|\(indexStatus)|\(workTreeStatus)"
    }

    var isStaged: Bool {
        indexStatus != " " && indexStatus != "?"
    }

    var isUnstaged: Bool {
        workTreeStatus != " " || (indexStatus == "?" && workTreeStatus == "?")
    }

    var isUntracked: Bool {
        indexStatus == "?" && workTreeStatus == "?"
    }

    var displayStatus: String {
        displayStatus(staged: isStaged)
    }

    func displayStatus(staged: Bool) -> String {
        let status = staged ? indexStatus : workTreeStatus
        return switch status {
        case "A", "?": "Added"
        case "M": "Modified"
        case "D": "Deleted"
        case "R": "Renamed"
        case "C": "Copied"
        case "U": "Conflict"
        default: "Changed"
        }
    }

    var statusSymbol: String {
        statusSymbol(staged: isStaged)
    }

    func statusSymbol(staged: Bool) -> String {
        let status = staged ? indexStatus : workTreeStatus
        return status == "?" ? "A" : String(status)
    }
}

struct RepositorySnapshot: Sendable {
    let root: URL
    let branch: String
    let upstream: String?
    let pushTarget: GitPushTarget?
    let ahead: Int
    let behind: Int
    let changes: [WorkingChange]
    let references: [GitReference]
    let stashes: [GitStash]
    let worktrees: [GitWorktree]
    let commits: [GitCommit]
}

struct GitCommandResult: Sendable {
    let output: String
    let error: String
    let exitCode: Int32
}

struct GitOperationError: LocalizedError, Sendable {
    let command: String
    let message: String

    var errorDescription: String? {
        message.isEmpty ? "Git command failed: \(command)" : message
    }
}

struct UnmergedBranchDeletionError: LocalizedError, Sendable {
    let branch: String
    let message: String

    var errorDescription: String? {
        message
    }
}

enum GitParser {
    static func parseStatus(_ data: Data) -> [WorkingChange] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: true)
        var changes: [WorkingChange] = []
        var index = 0

        while index < fields.count {
            let field = String(decoding: fields[index], as: UTF8.self)
            guard field.count >= 3 else {
                index += 1
                continue
            }

            let status = Array(field.prefix(2))
            guard status[0] != "#" else {
                index += 1
                continue
            }
            let pathStart = field.index(field.startIndex, offsetBy: 3)
            let path = String(field[pathStart...])
            var originalPath: String?

            if status[0] == "R" || status[0] == "C" {
                index += 1
                if index < fields.count {
                    originalPath = String(decoding: fields[index], as: UTF8.self)
                }
            }

            changes.append(
                WorkingChange(
                    path: path,
                    originalPath: originalPath,
                    indexStatus: status[0],
                    workTreeStatus: status[1]
                )
            )
            index += 1
        }

        return changes.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    static func parseCommits(_ text: String) -> [GitCommit] {
        let formatter = ISO8601DateFormatter()

        return text
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { record in
                let clean = record.trimmingCharacters(in: .whitespacesAndNewlines)
                let fields = clean.components(separatedBy: "\u{1f}")
                guard fields.count >= 7 else { return nil }

                let decorations = fields[5]
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                let signature: GitCommitSignature
                let subject: String
                if fields.count >= 11 {
                    let rawVerification = fields[9]
                    let reportedStatus = GitSignatureStatus(code: fields[6].first)
                    signature = GitCommitSignature(
                        status: reportedStatus == .none && !rawVerification.isEmpty
                            ? .cannotCheck
                            : reportedStatus,
                        keyID: fields[7].isEmpty
                            ? signingKey(from: rawVerification)
                            : fields[7],
                        signer: fields[8]
                    )
                    subject = fields[10]
                } else {
                    signature = .unsigned
                    subject = fields[6]
                }

                return GitCommit(
                    hash: fields[0],
                    parents: fields[1].split(separator: " ").map(String.init),
                    authorName: fields[2],
                    authorEmail: fields[3],
                    date: formatter.date(from: fields[4]) ?? .distantPast,
                    decorations: decorations,
                    signature: signature,
                    subject: subject
                )
            }
    }

    private static func signingKey(from verification: String) -> String {
        for line in verification.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: " key ", options: .caseInsensitive) else {
                continue
            }
            return line[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    static func parseReferences(_ text: String, currentBranch: String) -> [GitReference] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { return nil }

            let fullName = fields[0]
            let kind: ReferenceKind
            let name: String

            if fullName.hasPrefix("refs/heads/") {
                kind = .localBranch
                name = String(fullName.dropFirst("refs/heads/".count))
            } else if fullName.hasPrefix("refs/remotes/") {
                guard !fullName.hasSuffix("/HEAD") else { return nil }
                kind = .remoteBranch
                name = String(fullName.dropFirst("refs/remotes/".count))
            } else if fullName.hasPrefix("refs/tags/") {
                kind = .tag
                name = String(fullName.dropFirst("refs/tags/".count))
            } else {
                return nil
            }

            return GitReference(
                name: name,
                fullName: fullName,
                kind: kind,
                target: fields[2],
                isCurrent: kind == .localBranch && name == currentBranch
            )
        }
        .sorted {
            if $0.kind.rawValue == $1.kind.rawValue {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }

    static func parseStashes(_ text: String) -> [GitStash] {
        text.split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { record in
                let fields = record
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "\u{1f}")
                guard fields.count >= 3 else { return nil }
                return GitStash(
                    selector: fields[0],
                    hash: fields[1],
                    subject: fields[2]
                )
            }
    }

    static func parseWorktrees(_ text: String, currentRoot: URL) -> [GitWorktree] {
        var worktrees: [GitWorktree] = []
        var attributes: [String: String] = [:]

        func finishRecord() {
            guard let path = attributes["worktree"] else {
                attributes.removeAll(keepingCapacity: true)
                return
            }
            let candidate = URL(fileURLWithPath: path)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            worktrees.append(
                GitWorktree(
                    path: path,
                    head: attributes["HEAD"],
                    branch: attributes["branch"],
                    isBare: attributes.keys.contains("bare"),
                    isDetached: attributes.keys.contains("detached"),
                    isLocked: attributes.keys.contains("locked"),
                    isPrunable: attributes.keys.contains("prunable"),
                    isCurrent: candidate
                        == currentRoot.resolvingSymlinksInPath().standardizedFileURL
                )
            )
            attributes.removeAll(keepingCapacity: true)
        }

        for field in text.components(separatedBy: "\0") {
            guard !field.isEmpty else {
                if !attributes.isEmpty {
                    finishRecord()
                }
                continue
            }

            if let separator = field.firstIndex(of: " ") {
                attributes[String(field[..<separator])] = String(field[field.index(after: separator)...])
            } else {
                attributes[field] = ""
            }
        }

        if !attributes.isEmpty {
            finishRecord()
        }
        return worktrees
    }
}

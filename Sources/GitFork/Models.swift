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
}

struct GitCommit: Identifiable, Hashable, Sendable {
    let hash: String
    let parents: [String]
    let authorName: String
    let authorEmail: String
    let date: Date
    let decorations: [String]
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
        let status = isStaged ? indexStatus : workTreeStatus
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
        let status = isStaged ? indexStatus : workTreeStatus
        return status == "?" ? "A" : String(status)
    }
}

struct RepositorySnapshot: Sendable {
    let root: URL
    let branch: String
    let upstream: String?
    let ahead: Int
    let behind: Int
    let changes: [WorkingChange]
    let references: [GitReference]
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

                return GitCommit(
                    hash: fields[0],
                    parents: fields[1].split(separator: " ").map(String.init),
                    authorName: fields[2],
                    authorEmail: fields[3],
                    date: formatter.date(from: fields[4]) ?? .distantPast,
                    decorations: decorations,
                    subject: fields[6]
                )
            }
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
}

import Foundation

public enum ForkInvocation: Equatable, Sendable {
    case open(path: String?)
    case help
    case version
}

public struct ForkCommandError: LocalizedError, Equatable, Sendable {
    public let message: String
    public let shouldShowUsage: Bool

    public init(_ message: String, shouldShowUsage: Bool = false) {
        self.message = message
        self.shouldShowUsage = shouldShowUsage
    }

    public var errorDescription: String? { message }
}

public enum ForkCommand {
    public static let version = "0.1.0"

    public static let usage = """
    usage: fork [<options>] <command> [<args>]

    These are common Fork commands:
        fork open           open current repository in Fork
        fork                same as 'fork open'

        fork --help         show this help
        fork --version      show version of Fork CLI helper
    """

    public static func parse(arguments: [String]) throws -> ForkInvocation {
        guard let first = arguments.first else {
            return .open(path: nil)
        }

        switch first {
        case "--help", "-h", "help":
            guard arguments.count == 1 else {
                throw ForkCommandError(
                    "The help command does not accept arguments.",
                    shouldShowUsage: true
                )
            }
            return .help

        case "--version", "-v", "version":
            guard arguments.count == 1 else {
                throw ForkCommandError(
                    "The version command does not accept arguments.",
                    shouldShowUsage: true
                )
            }
            return .version

        case "open":
            guard arguments.count <= 2 else {
                throw ForkCommandError(
                    "usage: fork open [<path>]",
                    shouldShowUsage: true
                )
            }
            return .open(path: arguments.dropFirst().first)

        default:
            throw ForkCommandError(
                "Unknown command '\(first)'.",
                shouldShowUsage: true
            )
        }
    }

    public static func repositoryRoot(
        path: String?,
        currentDirectory: URL
    ) throws -> URL {
        let candidate = try resolvePath(path, relativeTo: currentDirectory)
        let result = try run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", candidate.path, "rev-parse", "--show-toplevel"]
        )

        guard result.status == 0 else {
            let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ForkCommandError(
                detail.isEmpty
                    ? "'\(candidate.path)' is not inside a Git repository."
                    : detail
            )
        }

        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw ForkCommandError("Git did not return a repository root.")
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    public static func openURL(for repository: URL) throws -> URL {
        var components = URLComponents()
        components.scheme = "gitfork"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "path", value: repository.standardizedFileURL.path)
        ]

        guard let url = components.url else {
            throw ForkCommandError("Could not create the GitFork launch URL.")
        }
        return url
    }

    public static func launch(repository: URL) throws {
        let url = try openURL(for: repository)
        let result = try run(
            executable: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: [url.absoluteString]
        )

        guard result.status == 0 else {
            let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ForkCommandError(
                detail.isEmpty
                    ? "Could not open GitFork."
                    : detail
            )
        }
    }

    private static func resolvePath(
        _ path: String?,
        relativeTo currentDirectory: URL
    ) throws -> URL {
        guard let path, !path.isEmpty else {
            return currentDirectory.standardizedFileURL
        }

        let expanded = NSString(string: path).expandingTildeInPath
        let candidate: URL
        if expanded.hasPrefix("/") {
            candidate = URL(fileURLWithPath: expanded)
        } else {
            candidate = currentDirectory.appendingPathComponent(expanded)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: candidate.path,
            isDirectory: &isDirectory
        ) else {
            throw ForkCommandError("No file or directory exists at '\(candidate.path)'.")
        }

        return (isDirectory.boolValue ? candidate : candidate.deletingLastPathComponent())
            .standardizedFileURL
    }

    private static func run(
        executable: URL,
        arguments: [String]
    ) throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        try process.run()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            output: String(decoding: output, as: UTF8.self),
            error: String(decoding: error, as: UTF8.self),
            status: process.terminationStatus
        )
    }
}

private struct CommandResult {
    let output: String
    let error: String
    let status: Int32
}

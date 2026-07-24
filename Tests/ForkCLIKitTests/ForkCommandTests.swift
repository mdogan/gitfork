import Foundation
import Testing
@testable import ForkCLIKit

struct ForkCommandTests {
    @Test
    func parsesDocumentedCommands() throws {
        #expect(try ForkCommand.parse(arguments: []) == .open(path: nil))
        #expect(try ForkCommand.parse(arguments: ["open"]) == .open(path: nil))
        #expect(try ForkCommand.parse(arguments: ["open", "../repo"]) == .open(path: "../repo"))
        #expect(try ForkCommand.parse(arguments: ["--help"]) == .help)
        #expect(try ForkCommand.parse(arguments: ["--version"]) == .version)
    }

    @Test
    func rejectsUnknownCommandsAndExtraArguments() {
        #expect(throws: ForkCommandError.self) {
            try ForkCommand.parse(arguments: ["checkout"])
        }
        #expect(throws: ForkCommandError.self) {
            try ForkCommand.parse(arguments: ["open", "one", "two"])
        }
    }

    @Test
    func helpContainsThePublicCommandSurface() {
        #expect(ForkCommand.usage.contains("usage: fork"))
        #expect(ForkCommand.usage.contains("fork open"))
        #expect(ForkCommand.usage.contains("fork --help"))
        #expect(ForkCommand.usage.contains("fork --version"))
    }

    @Test
    func createsARepositoryOpenURLWithEncodedPath() throws {
        let repository = URL(fileURLWithPath: "/tmp/A Repository & Tools")
        let url = try ForkCommand.openURL(for: repository)
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        #expect(components.scheme == "gitfork")
        #expect(components.host == "open")
        #expect(components.queryItems?.first { $0.name == "path" }?.value == repository.path)
    }

    @Test
    func discoversRepositoryRootFromNestedDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForkCLITests-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("Sources/Feature")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)

        let discovered = try ForkCommand.repositoryRoot(
            path: nested.path,
            currentDirectory: FileManager.default.temporaryDirectory
        )
        #expect(discovered == root.standardizedFileURL)
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
            throw ForkCommandError(message)
        }
    }
}

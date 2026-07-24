import Darwin
import Foundation
import ForkCLIKit

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch try ForkCommand.parse(arguments: arguments) {
    case .help:
        print(ForkCommand.usage)

    case .version:
        print("fork version \(ForkCommand.version)")

    case let .open(path):
        let root = try ForkCommand.repositoryRoot(
            path: path,
            currentDirectory: URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
        )
        try ForkCommand.launch(repository: root)
    }
} catch let error as ForkCommandError {
    let suffix = error.shouldShowUsage ? "\n\n\(ForkCommand.usage)" : ""
    FileHandle.standardError.write(Data("fork: \(error.message)\(suffix)\n".utf8))
    exit(error.shouldShowUsage ? EX_USAGE : EXIT_FAILURE)
} catch {
    FileHandle.standardError.write(Data("fork: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}

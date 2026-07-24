import AppKit
import Foundation
import SwiftUI

enum CLIToolInstallationStatus: Equatable {
    case notInstalled
    case installed
    case differentExecutable
}

struct CLIInstallerError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

struct CLIInstallerService: Sendable {
    static let executableName = "fork"
    static let suggestedDirectories = [
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "~/.local/bin"
    ]

    private let helperOverride: URL?

    init(helperURL: URL? = nil) {
        helperOverride = helperURL
    }

    func status(in directory: String) -> CLIToolInstallationStatus {
        guard let directoryURL = try? validatedDirectory(directory) else {
            return .notInstalled
        }

        let target = directoryURL.appendingPathComponent(Self.executableName)
        guard FileManager.default.fileExists(atPath: target.path) else {
            return .notInstalled
        }

        guard let helper = try? bundledHelperURL() else {
            return .differentExecutable
        }

        return FileManager.default.contentsEqual(
            atPath: helper.path,
            andPath: target.path
        ) ? .installed : .differentExecutable
    }

    func targetURL(in directory: String) throws -> URL {
        try validatedDirectory(directory)
            .appendingPathComponent(Self.executableName)
    }

    func install(
        in directory: String,
        replacing: Bool
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let directoryURL = try validatedDirectory(directory)
            let helper = try bundledHelperURL()
            let target = directoryURL.appendingPathComponent(Self.executableName)
            let manager = FileManager.default

            if manager.fileExists(atPath: target.path),
               !manager.contentsEqual(atPath: helper.path, andPath: target.path),
               !replacing {
                throw CLIInstallerError(
                    message: "A different executable already exists at \(target.path)."
                )
            }

            do {
                try installDirectly(
                    helper: helper,
                    target: target,
                    directory: directoryURL
                )
            } catch {
                try installWithAdministratorPrivileges(
                    helper: helper,
                    target: target,
                    directory: directoryURL
                )
            }

            guard manager.isExecutableFile(atPath: target.path) else {
                throw CLIInstallerError(
                    message: "The helper was copied but is not executable at \(target.path)."
                )
            }
            return target
        }.value
    }

    private func validatedDirectory(_ rawPath: String) throws -> URL {
        let expanded = NSString(
            string: rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        ).expandingTildeInPath

        guard expanded.hasPrefix("/") else {
            throw CLIInstallerError(message: "Enter an absolute installation directory.")
        }

        let directory = URL(fileURLWithPath: expanded, isDirectory: true)
            .standardizedFileURL
        let protectedDirectories = ["/", "/bin", "/sbin", "/usr/bin", "/usr/sbin"]
        guard !protectedDirectories.contains(directory.path),
              !directory.path.hasPrefix("/System/")
        else {
            throw CLIInstallerError(
                message: "Choose a user-managed binary directory such as /usr/local/bin."
            )
        }

        return directory
    }

    private func bundledHelperURL() throws -> URL {
        if let helperOverride,
           FileManager.default.isExecutableFile(atPath: helperOverride.path) {
            return helperOverride
        }

        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers")
            .appendingPathComponent(Self.executableName)
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            let developmentHelper = executableDirectory.appendingPathComponent(Self.executableName)
            if FileManager.default.isExecutableFile(atPath: developmentHelper.path) {
                return developmentHelper
            }
        }

        throw CLIInstallerError(
            message: "The bundled fork helper is missing. Build and run GitFork.app before installing it."
        )
    }

    private func installDirectly(
        helper: URL,
        target: URL,
        directory: URL
    ) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let temporary = directory.appendingPathComponent(
            ".fork-install-\(UUID().uuidString)"
        )
        defer { try? manager.removeItem(at: temporary) }

        try manager.copyItem(at: helper, to: temporary)
        try manager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: temporary.path
        )

        if manager.fileExists(atPath: target.path) {
            _ = try manager.replaceItemAt(target, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: target)
        }
    }

    private func installWithAdministratorPrivileges(
        helper: URL,
        target: URL,
        directory: URL
    ) throws {
        let temporary = directory.appendingPathComponent(
            ".fork-install-\(UUID().uuidString)"
        )
        let script = """
        on run argv
            set installDirectory to item 1 of argv
            set helperPath to item 2 of argv
            set temporaryPath to item 3 of argv
            set targetPath to item 4 of argv
            set commandText to "/bin/mkdir -p " & quoted form of installDirectory & " && /bin/cp " & quoted form of helperPath & " " & quoted form of temporaryPath & " && /bin/chmod 755 " & quoted form of temporaryPath & " && /bin/mv -f " & quoted form of temporaryPath & " " & quoted form of targetPath
            do shell script commandText with administrator privileges
        end run
        """

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", script,
            directory.path,
            helper.path,
            temporary.path,
            target.path
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorText = String(decoding: error, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let outputText = String(decoding: output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CLIInstallerError(
                message: errorText.isEmpty
                    ? (outputText.isEmpty ? "The command-line tool was not installed." : outputText)
                    : errorText
            )
        }
    }
}

struct CLIInstallerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var directory = "/usr/local/bin"
    @State private var isInstalling = false
    @State private var installedTarget: URL?
    @State private var errorMessage: String?
    @State private var isConfirmingReplacement = false

    private let installer = CLIInstallerService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(GitForkTheme.accent.gradient)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "terminal.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Install Command Line Tool")
                        .font(.title2.weight(.semibold))
                    Text("Run `fork` from Terminal to open a repository in GitFork.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("INSTALLATION DIRECTORY")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Directory", text: $directory)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())

                    Menu {
                        ForEach(CLIInstallerService.suggestedDirectories, id: \.self) { path in
                            Button(path) {
                                directory = path
                                installedTarget = nil
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuStyle(.button)
                    .help("Choose a common binary directory")

                    Button {
                        chooseDirectory()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Choose an installation directory")
                }

                Text(targetDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("USAGE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("fork\nfork .\nfork ./foobar\nfork open\nfork --help")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.separator.opacity(0.6))
                    )
            }

            if let installedTarget {
                Label(
                    "Installed at \(installedTarget.path)",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(GitForkTheme.green)
                .textSelection(.enabled)
            } else if installer.status(in: directory) == .installed {
                Label("The GitFork CLI is already installed here.", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if installer.status(in: directory) == .differentExecutable {
                Label(
                    "Another executable named fork already exists here.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            } else {
                Text("Administrator approval is requested only when the directory is not writable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Close", role: .cancel) {
                    dismiss()
                }
                .help("Close without installing")

                Button(isInstalling ? "Installing…" : installButtonTitle) {
                    prepareInstallation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling || directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Install the fork command-line helper")
            }
        }
        .padding(24)
        .frame(width: 570)
        .alert("Replace Existing fork?", isPresented: $isConfirmingReplacement) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                install(replacing: true)
            }
        } message: {
            Text("A different executable already exists at \(targetDescription). Replacing it cannot be undone by GitFork.")
        }
        .alert(
            "Installation Failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var targetDescription: String {
        (try? installer.targetURL(in: directory).path)
            ?? "\(directory)/\(CLIInstallerService.executableName)"
    }

    private var installButtonTitle: String {
        installer.status(in: directory) == .installed ? "Reinstall" : "Install"
    }

    private func prepareInstallation() {
        installedTarget = nil
        if installer.status(in: directory) == .differentExecutable {
            isConfirmingReplacement = true
        } else {
            install(replacing: false)
        }
    }

    private func install(replacing: Bool) {
        isInstalling = true
        Task {
            defer { isInstalling = false }
            do {
                installedTarget = try await installer.install(
                    in: directory,
                    replacing: replacing
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose CLI Installation Directory"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        directory = url.path
        installedTarget = nil
    }
}

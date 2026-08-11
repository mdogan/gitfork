import AppKit
import Foundation

struct GhosttyLaunchRequest: Equatable, Sendable {
    static let bundleIdentifier = "com.mitchellh.ghostty"

    let repositoryRoot: URL

    var appleScriptSource: String {
        """
        tell application id "\(Self.bundleIdentifier)"
            new window with configuration {initial working directory:\(repositoryRoot.path.appleScriptStringLiteral)}
            activate
        end tell
        """
    }
}

private extension String {
    var appleScriptStringLiteral: String {
        let escaped = self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}

struct GhosttyNotInstalledError: LocalizedError, Sendable {
    var errorDescription: String? {
        "Ghostty is not installed. Install Ghostty and try again."
    }
}

struct GhosttyAutomationError: LocalizedError, Sendable {
    let detail: String

    var errorDescription: String? {
        "GitFork could not open a Ghostty window: \(detail)"
    }
}

@MainActor
struct GhosttyLauncher {
    func openRepository(at root: URL) async throws {
        let request = GhosttyLaunchRequest(repositoryRoot: root)
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: GhosttyLaunchRequest.bundleIdentifier
        ) else {
            throw GhosttyNotInstalledError()
        }

        do {
            try runNewWindowScript(request)
        } catch let automationError {
            // Automation is unavailable until the user approves the Apple Events
            // prompt. Fall back to handing the directory to Ghostty through
            // LaunchServices, which still reuses the running instance.
            do {
                try await openDirectory(root, withApplicationAt: applicationURL)
            } catch {
                throw automationError
            }
        }
    }

    private func runNewWindowScript(_ request: GhosttyLaunchRequest) throws {
        guard let script = NSAppleScript(source: request.appleScriptSource) else {
            throw GhosttyAutomationError(
                detail: "GitFork could not prepare the Ghostty automation command."
            )
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let detail = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "Ghostty automation failed."
            throw GhosttyAutomationError(detail: detail)
        }
    }

    private func openDirectory(_ root: URL, withApplicationAt applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Never launch a second Ghostty process; the running instance opens the
        // directory itself.
        configuration.createsNewApplicationInstance = false

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                [root],
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

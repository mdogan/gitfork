import AppKit
import Foundation

struct GhosttyLaunchRequest: Equatable, Sendable {
    static let bundleIdentifier = "com.mitchellh.ghostty"

    let repositoryRoot: URL

    var arguments: [String] {
        ["--working-directory=\(repositoryRoot.path)"]
    }
}

struct GhosttyNotInstalledError: LocalizedError, Sendable {
    var errorDescription: String? {
        "Ghostty is not installed. Install Ghostty and try again."
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

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = request.arguments

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
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

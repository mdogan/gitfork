import AppKit
import Combine

struct GitForkOpenRequest: Identifiable, Sendable {
    let id = UUID()
    let url: URL
}

@MainActor
final class GitForkAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var openRequests: [GitForkOpenRequest] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        openRequests.append(contentsOf: urls.map(GitForkOpenRequest.init(url:)))
    }

    func consume(_ request: GitForkOpenRequest) {
        openRequests.removeAll { $0.id == request.id }
    }
}

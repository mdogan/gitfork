import Foundation
import Testing
@testable import GitFork

struct GhosttyLauncherTests {
    @Test
    func buildsWorkingDirectoryArgumentWithoutShellEscaping() {
        let root = URL(fileURLWithPath: "/tmp/My Repository")
        let request = GhosttyLaunchRequest(repositoryRoot: root)

        #expect(GhosttyLaunchRequest.bundleIdentifier == "com.mitchellh.ghostty")
        #expect(request.arguments == ["--working-directory=/tmp/My Repository"])
    }
}

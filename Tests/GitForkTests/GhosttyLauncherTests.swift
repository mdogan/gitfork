import Foundation
import Testing
@testable import GitFork

struct GhosttyLauncherTests {
    @Test
    func buildsNewWindowAppleScriptForRepositoryRoot() {
        let root = URL(fileURLWithPath: "/tmp/My Repository")
        let request = GhosttyLaunchRequest(repositoryRoot: root)

        #expect(GhosttyLaunchRequest.bundleIdentifier == "com.mitchellh.ghostty")
        #expect(request.appleScriptSource == """
        tell application id "com.mitchellh.ghostty"
            new window with configuration {initial working directory:"/tmp/My Repository"}
            activate
        end tell
        """)
    }

    @Test
    func escapesRepositoryRootForAppleScriptStringLiteral() {
        let root = URL(fileURLWithPath: "/tmp/Quote \" and \\ and\nnewline")
        let request = GhosttyLaunchRequest(repositoryRoot: root)

        #expect(request.appleScriptSource.contains(
            "initial working directory:\"/tmp/Quote \\\" and \\\\ and\\nnewline\""
        ))
    }
}

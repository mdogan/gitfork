import Testing
@testable import GitFork

struct KeyboardShortcutReferenceTests {
    @Test
    func listsEveryApplicationShortcut() throws {
        let application = try #require(
            KeyboardShortcutSection.all.first { $0.title == "Application" }
        )

        #expect(
            application.shortcuts == [
                KeyboardShortcutReference(action: "Open Repository", keys: "⌘O"),
                KeyboardShortcutReference(action: "Switch Repository", keys: "⌘K"),
                KeyboardShortcutReference(action: "File or Directory History", keys: "⌘F"),
                KeyboardShortcutReference(action: "Show Changes", keys: "⌘P"),
                KeyboardShortcutReference(action: "Refresh", keys: "⌘R"),
            ]
        )
    }

    @Test
    func includesEveryChangesKeyboardAction() throws {
        let changes = try #require(
            KeyboardShortcutSection.all.first { $0.title == "Changes" }
        )

        #expect(changes.shortcuts.map(\.action) == [
            "Move Selection",
            "Extend Selection",
            "Add or Remove Selection",
            "Stage Selection",
            "Unstage Selection",
            "Open Side-by-Side Diff",
            "Commit Changes",
        ])
    }
}

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
                KeyboardShortcutReference(action: "New Window", keys: "⌘N"),
                KeyboardShortcutReference(action: "Open Repository", keys: "⌘O"),
                KeyboardShortcutReference(action: "Switch Repository", keys: "⌘K"),
                KeyboardShortcutReference(action: "Select Branch", keys: "⌘B"),
                KeyboardShortcutReference(action: "File or Directory History", keys: "⌘F"),
                KeyboardShortcutReference(action: "Open Commit", keys: "⌘G"),
                KeyboardShortcutReference(action: "Show Changes", keys: "⌘P"),
                KeyboardShortcutReference(action: "Open in Ghostty", keys: "⌘T"),
                KeyboardShortcutReference(action: "Open in Zed", keys: "⌘E"),
                KeyboardShortcutReference(action: "Refresh", keys: "⌘R"),
                KeyboardShortcutReference(action: "Keyboard Shortcuts", keys: "?"),
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

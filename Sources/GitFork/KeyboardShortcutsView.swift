import SwiftUI

struct KeyboardShortcutReference: Identifiable, Hashable {
    let action: String
    let keys: String

    var id: String { action }
}

struct KeyboardShortcutSection: Identifiable, Hashable {
    let title: String
    let shortcuts: [KeyboardShortcutReference]

    var id: String { title }

    static let all: [KeyboardShortcutSection] = [
        KeyboardShortcutSection(
            title: "Application",
            shortcuts: [
                KeyboardShortcutReference(action: "New Window", keys: "⌘N"),
                KeyboardShortcutReference(action: "Open Repository", keys: "⌘O"),
                KeyboardShortcutReference(action: "Switch Repository", keys: "⌘K"),
                KeyboardShortcutReference(action: "Select Branch", keys: "⌘B"),
                KeyboardShortcutReference(action: "File or Directory History", keys: "⌘F"),
                KeyboardShortcutReference(action: "Open Commit", keys: "⌘G"),
                KeyboardShortcutReference(action: "Show Changes", keys: "⌘P"),
                KeyboardShortcutReference(action: "Open in Ghostty", keys: "⌘T"),
                KeyboardShortcutReference(action: "Open in Zed", keys: "⌘E"),
                KeyboardShortcutReference(action: "Open in Finder", keys: "⇧⌘R"),
                KeyboardShortcutReference(action: "Refresh", keys: "⌘R"),
                KeyboardShortcutReference(action: "Keyboard Shortcuts", keys: "?"),
            ]
        ),
        KeyboardShortcutSection(
            title: "Changes",
            shortcuts: [
                KeyboardShortcutReference(action: "Move Selection", keys: "↑ / ↓"),
                KeyboardShortcutReference(action: "Extend Selection", keys: "⇧ Click"),
                KeyboardShortcutReference(action: "Add or Remove Selection", keys: "⌘ Click"),
                KeyboardShortcutReference(action: "Stage Selection", keys: "Return"),
                KeyboardShortcutReference(action: "Unstage Selection", keys: "Delete"),
                KeyboardShortcutReference(action: "Open Side-by-Side Diff", keys: "Space"),
                KeyboardShortcutReference(action: "Commit Changes", keys: "⌘ Return"),
            ]
        ),
        KeyboardShortcutSection(
            title: "Pickers and Dialogs",
            shortcuts: [
                KeyboardShortcutReference(action: "Move Selection", keys: "↑ / ↓"),
                KeyboardShortcutReference(action: "Confirm", keys: "Return"),
                KeyboardShortcutReference(action: "Cancel", keys: "Esc"),
            ]
        ),
    ]
}

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "command")
                    .font(.title)
                    .foregroundStyle(GitForkTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Keyboard Shortcuts")
                        .font(.title2.weight(.semibold))
                    Text("Navigate GitFork without leaving the keyboard.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)

            Divider()

            List {
                ForEach(KeyboardShortcutSection.all) { section in
                    Section(section.title) {
                        ForEach(section.shortcuts) { shortcut in
                            LabeledContent {
                                Text(shortcut.keys)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            } label: {
                                Text(shortcut.action)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 550)
    }
}

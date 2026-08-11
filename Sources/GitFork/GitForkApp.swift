import AppKit
import SwiftUI

@main
struct GitForkApp: App {
    static let repositoryWindowID = "repository"
    static let sideBySideDiffWindowID = "side-by-side-diff"

    var body: some Scene {
        WindowGroup(
            id: Self.repositoryWindowID,
            for: RepositoryWindowValue.self
        ) { repository in
            RepositoryWindow(repository: repository)
        }
        .defaultSize(width: 1380, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            GitForkCommands()
        }

        WindowGroup(
            id: Self.sideBySideDiffWindowID,
            for: SideBySideDiffWindowState.self
        ) { state in
            if let state = state.wrappedValue {
                SideBySideDiffWindow(state: state)
            } else {
                ContentUnavailableView(
                    "No Diff",
                    systemImage: "rectangle.split.2x1",
                    description: Text("Open a side-by-side diff from the Changes view.")
                )
            }
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
        }
    }
}

/// One window's repository. Every window owns its own `RepositoryStore`, so
/// windows show different repositories at the same time, and exposes it as the
/// focused scene object so menu commands act on the frontmost window.
struct RepositoryWindow: View {
    @Binding var repository: RepositoryWindowValue?
    @Environment(\.openWindow) private var openWindow
    @StateObject private var store = RepositoryStore()
    @State private var hostingWindow: NSWindow?

    var body: some View {
        RootView()
            .environmentObject(store)
            .focusedSceneObject(store)
            .frame(minWidth: 980, minHeight: 640)
            .tint(GitForkTheme.accent)
            .toolbarBackground(repositoryToolbarColor.opacity(0.22), for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .background(
                HostingWindowReader { window in
                    guard hostingWindow !== window else { return }
                    hostingWindow = window
                    if let window {
                        RepositoryWindowRegistry.shared.adoptPendingWindowSize(window)
                    }
                    registerWindow()
                }
            )
            .task(id: repository) {
                guard let repository,
                      store.repositoryURL?.standardizedFileURL.path != repository.path else {
                    return
                }
                store.openRepository(repository.url)
            }
            .onChange(of: store.repositoryURL) { _, _ in
                registerWindow()
            }
            .onChange(of: store.pendingOpenRequest) { _, request in
                guard let request else { return }
                store.clearPendingOpenRequest()
                route(to: request.root)
            }
    }

    private var repositoryToolbarColor: Color {
        guard let name = store.repositoryURL?.lastPathComponent else {
            return GitForkTheme.accent
        }
        return GitForkTheme.repositoryColor(for: name)
    }

    private func registerWindow() {
        RepositoryWindowRegistry.shared.update(
            window: hostingWindow,
            repository: store.repositoryURL
        )
    }

    /// Sends a resolved repository to the window that should show it: the one
    /// already showing it, this window while it is still empty, or a new window.
    private func route(to root: URL) {
        let value = RepositoryWindowValue(root)
        let destination = RepositoryWindowRouting.destination(
            root: root,
            currentRepository: store.repositoryURL,
            isOpenInAnotherWindow: RepositoryWindowRegistry.shared.isOpen(
                value,
                excluding: hostingWindow
            )
        )

        switch destination {
        case .currentWindow:
            break
        case .existingWindow:
            RepositoryWindowRegistry.shared.focus(value, excluding: hostingWindow)
        case .adoptInCurrentWindow:
            repository = value
        case .newWindow:
            RepositoryWindowRegistry.shared.prepareWindowSize(from: hostingWindow)
            openWindow(value: value)
        }
    }
}

struct GitForkCommands: Commands {
    @FocusedObject private var store: RepositoryStore?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .appSettings) {
            Button("Install Command Line Tool…") {
                store?.isShowingCLIInstaller = true
            }
            .disabled(store == nil)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                RepositoryWindowRegistry.shared.prepareWindowSize(
                    from: NSApplication.shared.keyWindow
                )
                openWindow(id: GitForkApp.repositoryWindowID)
            }
            .keyboardShortcut("n")

            Button("Open Repository…") {
                openRepository()
            }
            .keyboardShortcut("o")
        }

        CommandMenu("Repository") {
            Button("Switch Repository…") {
                store?.isShowingRepositorySwitcher = true
            }
            .keyboardShortcut("k")
            .disabled(store == nil)

            Button("File or Directory History…") {
                store?.showPathHistoryPicker()
            }
            .keyboardShortcut("f")
            .disabled(store?.repositoryURL == nil)

            Button("Open Commit…") {
                store?.showCommitHashPicker()
            }
            .keyboardShortcut("g")
            .disabled(store?.repositoryURL == nil)

            Button("Changes") {
                store?.selectChanges()
            }
            .keyboardShortcut("p")
            .disabled(store?.repositoryURL == nil)

            Button("Open in Ghostty") {
                store?.openGhosttyTerminal()
            }
            .keyboardShortcut("t")
            .disabled(store?.repositoryURL == nil)

            Divider()

            Button("Refresh") { store?.refresh() }
                .keyboardShortcut("r")
                .disabled(store?.repositoryURL == nil)
            Divider()
            Button("Fetch All") { store?.fetch() }
                .disabled(store?.repositoryURL == nil || store?.isLoading == true)
            Button("Pull") { store?.pull() }
                .disabled(store?.repositoryURL == nil || store?.isLoading == true)
            Button("Push") { store?.requestPushConfirmation() }
                .disabled(store?.repositoryURL == nil || store?.isLoading == true)
        }

        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts…") {
                store?.isShowingKeyboardShortcuts = true
            }
            .keyboardShortcut("?", modifiers: [])
            .disabled(store == nil)
        }
    }

    /// Without a focused window there is no store to route the choice, so the
    /// chosen folder opens a window directly and that window resolves its root.
    private func openRepository() {
        if let store {
            store.chooseRepository()
        } else if let url = RepositoryOpenPanel.run() {
            RepositoryWindowRegistry.shared.prepareWindowSize(
                from: NSApplication.shared.keyWindow
            )
            openWindow(value: RepositoryWindowValue(url))
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        Group {
            if store.repositoryURL == nil {
                WelcomeView()
            } else {
                RepositoryView()
            }
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            guard RepositoryWindowRegistry.shared.claimExternalURL(url) else { return }
            store.openExternalURL(url)
        }
        .sheet(isPresented: $store.isShowingCLIInstaller) {
            CLIInstallerView()
        }
        .sheet(isPresented: $store.isShowingRepositorySwitcher) {
            RepositorySwitcherSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isShowingPathHistoryPicker) {
            PathHistoryPickerSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isShowingCommitHashPicker) {
            CommitHashPickerSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isShowingKeyboardShortcuts) {
            KeyboardShortcutsView()
        }
        .alert(
            "GitFork",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Git executable", value: "/usr/bin/git")
            LabeledContent("Default pull strategy", value: "Fast-forward only")
            LabeledContent("Commit signing", value: "OpenPGP via Git configuration")
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 470, height: 180)
    }
}

import AppKit
import SwiftUI

@main
struct GitForkApp: App {
    static let repositoryWindowID = "repository"
    @NSApplicationDelegateAdaptor private var appDelegate: GitForkAppDelegate
    @StateObject private var tabCoordinator = RepositoryTabCoordinator()

    var body: some Scene {
        WindowGroup(id: Self.repositoryWindowID) {
            RepositoryWindow()
                .environmentObject(tabCoordinator)
                .environmentObject(appDelegate)
        }
        .handlesExternalEvents(matching: [])
        .defaultSize(width: 1380, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            GitForkCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

private struct RepositoryWindow: View {
    @State private var repositoryPath = ""
    @StateObject private var store = RepositoryStore()
    @State private var tabID = UUID()
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appDelegate: GitForkAppDelegate
    @EnvironmentObject private var tabCoordinator: RepositoryTabCoordinator

    var body: some View {
        RootView()
            .environmentObject(store)
            .focusedSceneObject(store)
            .frame(minWidth: 980, minHeight: 640)
            .tint(GitForkTheme.accent)
            .task(id: repositoryPath) {
                openPresentedRepository()
            }
            .onChange(of: store.repositoryURL) { _, repositoryURL in
                repositoryPath = repositoryURL?.standardizedFileURL.path ?? ""
                tabCoordinator.update(
                    tabID: tabID,
                    repositoryPath: repositoryPath
                )
            }
            .onReceive(appDelegate.$openRequests) { requests in
                guard let request = requests.first,
                      tabCoordinator.claim(
                        requestID: request.id,
                        for: tabID
                      ) else {
                    return
                }
                routeExternalURL(request.url)
                DispatchQueue.main.async {
                    appDelegate.consume(request)
                    tabCoordinator.complete(requestID: request.id)
                }
            }
            .background {
                WindowAccessor { window in
                    if let requestedPath = tabCoordinator.register(
                        tabID: tabID,
                        repositoryPath: repositoryPath,
                        window: window
                    ) {
                        DispatchQueue.main.async {
                            repositoryPath = requestedPath
                        }
                    }
                }
            }
    }

    private func openPresentedRepository() {
        guard !repositoryPath.isEmpty else { return }
        let repositoryURL = URL(
            fileURLWithPath: repositoryPath,
            isDirectory: true
        ).standardizedFileURL
        guard store.repositoryURL?.standardizedFileURL != repositoryURL else {
            return
        }
        store.openRepository(repositoryURL)
    }

    private func routeExternalURL(_ url: URL) {
        guard let path = GitForkExternalURL.repositoryPath(from: url) else {
            store.errorMessage = "GitFork received an invalid repository URL."
            return
        }

        if repositoryPath.isEmpty, store.repositoryURL == nil {
            repositoryPath = path
        } else if tabCoordinator.focusTab(presenting: path) {
            return
        } else {
            tabCoordinator.prepareNewTab(
                repositoryPath: path,
                sourceTabID: tabID
            )
            openWindow(id: GitForkApp.repositoryWindowID)
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onWindowAvailable: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReadingView {
        let view = WindowReadingView()
        view.onWindowAvailable = onWindowAvailable
        return view
    }

    func updateNSView(_ nsView: WindowReadingView, context: Context) {
        nsView.onWindowAvailable = onWindowAvailable
        if let window = nsView.window {
            onWindowAvailable(window)
        }
    }

    final class WindowReadingView: NSView {
        var onWindowAvailable: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindowAvailable?(window)
            }
        }
    }
}

private struct GitForkCommands: Commands {
    @FocusedObject private var store: RepositoryStore?

    var body: some Commands {
        CommandGroup(before: .appSettings) {
            Button("Install Command Line Tool…") {
                store?.isShowingCLIInstaller = true
            }
            .disabled(store == nil)
        }

        CommandGroup(replacing: .newItem) {
            Button("Open Repository…") {
                store?.chooseRepository()
            }
            .keyboardShortcut("o")
            .disabled(store == nil)
        }

        CommandMenu("Repository") {
            Button("Switch Repository…") {
                store?.isShowingRepositorySwitcher = true
            }
            .keyboardShortcut("k")
            .disabled(store == nil)

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
        .sheet(isPresented: $store.isShowingCLIInstaller) {
            CLIInstallerView()
        }
        .sheet(isPresented: $store.isShowingRepositorySwitcher) {
            RepositorySwitcherSheet()
                .environmentObject(store)
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

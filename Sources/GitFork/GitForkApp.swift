import SwiftUI

@main
struct GitForkApp: App {
    static let sideBySideDiffWindowID = "side-by-side-diff"
    @StateObject private var store = RepositoryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
                .tint(GitForkTheme.accent)
        }
        .defaultSize(width: 1380, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(before: .appSettings) {
                Button("Install Command Line Tool…") {
                    store.isShowingCLIInstaller = true
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("Open Repository…") {
                    store.chooseRepository()
                }
                .keyboardShortcut("o")
            }

            CommandMenu("Repository") {
                Button("Switch Repository…") {
                    store.isShowingRepositorySwitcher = true
                }
                .keyboardShortcut("k")

                Button("File or Directory History…") {
                    store.showPathHistoryPicker()
                }
                .keyboardShortcut("f")
                .disabled(store.repositoryURL == nil)

                Button("Changes") {
                    store.selectChanges()
                }
                .keyboardShortcut("p")
                .disabled(store.repositoryURL == nil)

                Divider()

                Button("Refresh") { store.refresh() }
                    .keyboardShortcut("r")
                    .disabled(store.repositoryURL == nil)
                Divider()
                Button("Fetch All") { store.fetch() }
                    .disabled(store.repositoryURL == nil || store.isLoading)
                Button("Pull") { store.pull() }
                    .disabled(store.repositoryURL == nil || store.isLoading)
                Button("Push") { store.requestPushConfirmation() }
                    .disabled(store.repositoryURL == nil || store.isLoading)
            }

            CommandGroup(after: .help) {
                Button("Keyboard Shortcuts…") {
                    store.isShowingKeyboardShortcuts = true
                }
            }
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

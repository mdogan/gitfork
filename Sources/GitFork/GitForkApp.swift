import SwiftUI

@main
struct GitForkApp: App {
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

                Divider()

                Button("Refresh") { store.refresh() }
                    .keyboardShortcut("r")
                    .disabled(store.repositoryURL == nil)
                Divider()
                Button("Fetch All") { store.fetch() }
                    .disabled(store.repositoryURL == nil)
                Button("Pull") { store.pull() }
                    .disabled(store.repositoryURL == nil)
                Button("Push") { store.push() }
                    .disabled(store.repositoryURL == nil)
            }
        }

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

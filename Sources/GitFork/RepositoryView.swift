import SwiftUI

struct RepositoryView: View {
    @EnvironmentObject private var store: RepositoryStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingBranchSheet = false
    @State private var showingStashSheet = false
    @State private var isConfirmingPush = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 310)
        } content: {
            Group {
                switch store.selectedSection {
                case .history:
                    HistoryView()
                case .changes:
                    ChangesView()
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 430, max: 600)
        } detail: {
            DetailView()
        }
        .toolbar {
            RepositoryToolbar(
                showingBranchSheet: $showingBranchSheet,
                showingStashSheet: $showingStashSheet,
                isConfirmingPush: $isConfirmingPush
            )
        }
        .sheet(isPresented: $showingBranchSheet) {
            BranchSheet(isPresented: $showingBranchSheet)
        }
        .sheet(isPresented: $showingStashSheet) {
            StashSheet(isPresented: $showingStashSheet)
        }
        .alert("Push \(store.branch)?", isPresented: $isConfirmingPush) {
            Button("Cancel", role: .cancel) {}
            Button("Push") {
                store.push()
            }
        } message: {
            Text(pushConfirmationMessage)
        }
        .overlay(alignment: .bottom) {
            if let label = store.operationLabel {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text(label)
                        .font(.callout.weight(.medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
                .shadow(radius: 8, y: 3)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: store.operationLabel)
        .navigationTitle(store.repositoryName)
    }

    private var pushConfirmationMessage: String {
        let summary: String
        if store.ahead > 0 {
            let plural = store.ahead == 1 ? "commit" : "commits"
            summary = "\(store.ahead) \(plural) from \(store.branch)"
        } else {
            summary = store.branch
        }

        if let upstream = store.upstream {
            return "This will push \(summary) to \(upstream)."
        }
        return "This will push \(summary) to the remote and set it as the upstream branch."
    }
}

struct RepositoryToolbar: ToolbarContent {
    @EnvironmentObject private var store: RepositoryStore
    @Binding var showingBranchSheet: Bool
    @Binding var showingStashSheet: Bool
    @Binding var isConfirmingPush: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            RepositorySwitcherMenu()

            Button {
                store.fetch()
            } label: {
                Label("Fetch", systemImage: "arrow.down.circle")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help("Fetch all remotes")
            .disabled(store.isLoading)

            Button {
                store.pull()
            } label: {
                Label("Pull", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help("Pull with fast-forward only")
            .disabled(store.isLoading)

            Button {
                isConfirmingPush = true
            } label: {
                Label("Push", systemImage: "arrow.up.to.line")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help("Push the current branch")
            .disabled(store.isLoading)
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(GitForkTheme.accent)
                Text(store.branch)
                    .font(.subheadline.weight(.semibold))

                if store.ahead > 0 {
                    Label("\(store.ahead)", systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(GitForkTheme.green)
                }
                if store.behind > 0 {
                    Label("\(store.behind)", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(GitForkTheme.blue)
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showingBranchSheet = true
            } label: {
                Label("New Branch", systemImage: "arrow.triangle.branch")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help("Create a branch")

            Button {
                showingStashSheet = true
            } label: {
                Label("Stash", systemImage: "archivebox")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help("Stash working directory changes")
            .disabled(store.changes.isEmpty)

            Button {
                store.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help("Refresh repository")
            .disabled(store.isLoading)
        }
    }
}

struct BranchSheet: View {
    @EnvironmentObject private var store: RepositoryStore
    @Binding var isPresented: Bool
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title)
                    .foregroundStyle(GitForkTheme.accent)
                VStack(alignment: .leading) {
                    Text("Create New Branch")
                        .font(.title2.weight(.semibold))
                    Text("The branch starts at the current HEAD.")
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Branch name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { create() }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                Button {
                    create()
                } label: {
                    Label("Create & Checkout", systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(.borderedProminent)
                .help("Create the branch at HEAD and check it out")
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func create() {
        store.createBranch(named: name)
        isPresented = false
    }
}

struct StashSheet: View {
    @EnvironmentObject private var store: RepositoryStore
    @Binding var isPresented: Bool
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Stash Changes", systemImage: "archivebox")
                .font(.title2.weight(.semibold))

            TextField("Message (optional)", text: $message)
                .textFieldStyle(.roundedBorder)

            Text("Tracked and untracked changes will be included.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                Button("Stash") {
                    store.stash(message: message)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .help("Stash tracked and untracked changes")
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

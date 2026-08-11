import SwiftUI

struct RepositoryView: View {
    @EnvironmentObject private var store: RepositoryStore
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingBranchSheet = false
    @State private var showingStashSheet = false
    @State private var stashScope: StashScope = .all

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
                    ChangesView(
                        showingStashSheet: $showingStashSheet,
                        stashScope: $stashScope
                    )
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
                stashScope: $stashScope
            )
        }
        .sheet(isPresented: $showingBranchSheet) {
            BranchSheet(isPresented: $showingBranchSheet)
        }
        .sheet(isPresented: $showingStashSheet) {
            StashSheet(
                isPresented: $showingStashSheet,
                scope: stashScope
            )
        }
        .alert("Push \(pushBranchName)?", isPresented: $store.isConfirmingPush) {
            Button("Cancel", role: .cancel) {
                store.cancelPushConfirmation()
            }
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
        .onAppear {
            store.setMonitoringActive(controlActiveState == .key)
        }
        .onChange(of: controlActiveState) { _, state in
            store.setMonitoringActive(state == .key)
        }
    }

    private var pushBranchName: String {
        store.pendingPushPlan?.branchName ?? store.branch
    }

    private var pushConfirmationMessage: String {
        guard let plan = store.pendingPushPlan else {
            return "GitFork could not resolve a safe push target."
        }

        let summary: String
        if let ahead = plan.ahead, ahead > 0 {
            let plural = ahead == 1 ? "commit" : "commits"
            summary = "\(ahead) \(plural) from \(plan.branchName)"
        } else {
            summary = plan.branchName
        }

        let upstreamAction = plan.target.establishesUpstream
            ? " and set it as the upstream branch"
            : ""
        return "This will push \(summary) to \(plan.target.displayName)\(upstreamAction)."
    }
}

struct RepositoryToolbar: ToolbarContent {
    @EnvironmentObject private var store: RepositoryStore
    @Binding var showingBranchSheet: Bool
    @Binding var showingStashSheet: Bool
    @Binding var stashScope: StashScope

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            RepositorySwitcherMenu()

            Button {
                store.openGhosttyTerminal()
            } label: {
                Label("Open in Ghostty", systemImage: "apple.terminal")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help("Open a new Ghostty window at the repository root")

            Button {
                store.openZedEditor()
            } label: {
                Label("Open in Zed", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help("Open the repository in Zed")

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
                store.requestPushConfirmation()
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
            .disabled(store.isLoading)

            Button {
                stashScope = .all
                showingStashSheet = true
            } label: {
                Label("Stash", systemImage: "archivebox")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help("Stash working directory changes")
            .disabled(store.changes.isEmpty || store.isLoading)

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
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || store.isLoading
                )
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

struct RenameBranchSheet: View {
    @EnvironmentObject private var store: RepositoryStore
    let reference: GitReference
    @Binding var isPresented: Bool
    @State private var name: String

    init(reference: GitReference, isPresented: Binding<Bool>) {
        self.reference = reference
        _isPresented = isPresented
        _name = State(initialValue: reference.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "pencil")
                    .font(.title)
                    .foregroundStyle(GitForkTheme.accent)
                VStack(alignment: .leading) {
                    Text("Rename Branch")
                        .font(.title2.weight(.semibold))
                    Text(renameDescription)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Branch name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { rename() }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                Button {
                    rename()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .buttonStyle(.borderedProminent)
                .help("Rename the branch and keep its commits and upstream")
                .disabled(!canRename)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var renameDescription: String {
        if reference.upstream == nil {
            return "“\(reference.name)” keeps its commits."
        }
        return "“\(reference.name)” keeps its commits and its upstream."
    }

    private var canRename: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanName.isEmpty && cleanName != reference.name && !store.isLoading
    }

    private func rename() {
        guard canRename else { return }
        store.rename(reference, to: name)
        isPresented = false
    }
}

struct StashSheet: View {
    @EnvironmentObject private var store: RepositoryStore
    @Binding var isPresented: Bool
    let scope: StashScope
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Stash \(scope.title)", systemImage: "archivebox")
                .font(.title2.weight(.semibold))

            TextField("Message (optional)", text: $message)
                .textFieldStyle(.roundedBorder)

            Text(scope.description)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                Button("Stash") {
                    store.stash(message: message, scope: scope)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .help("Stash \(scope.title.lowercased())")
                .disabled(store.isLoading)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

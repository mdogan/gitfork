import AppKit
import SwiftUI

struct SideBySideDiffWindowState: Codable, Hashable {
    let id: UUID
    let repositoryPath: String
    let path: String
    let originalPath: String?
    let indexStatus: String
    let workTreeStatus: String
    let status: String
    let statusSymbol: String
    let staged: Bool
    let diff: String

    init(
        repositoryURL: URL,
        change: WorkingChange,
        staged: Bool,
        diff: String
    ) {
        id = UUID()
        repositoryPath = repositoryURL.standardizedFileURL.path
        path = change.path
        originalPath = change.originalPath
        indexStatus = String(change.indexStatus)
        workTreeStatus = String(change.workTreeStatus)
        status = change.displayStatus(staged: staged)
        statusSymbol = change.statusSymbol(staged: staged)
        self.staged = staged
        self.diff = diff
    }

    var repositoryURL: URL {
        URL(fileURLWithPath: repositoryPath, isDirectory: true)
    }

    var change: WorkingChange {
        WorkingChange(
            path: path,
            originalPath: originalPath,
            indexStatus: indexStatus.first ?? " ",
            workTreeStatus: workTreeStatus.first ?? " "
        )
    }
}

private enum SideBySideDiffScope: String, CaseIterable, Identifiable {
    case diffOnly
    case fullFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diffOnly: "Diff Only"
        case .fullFile: "Full File"
        }
    }
}

@MainActor
private final class SideBySideDiffWindowStore: ObservableObject {
    let state: SideBySideDiffWindowState
    @Published private(set) var scope = SideBySideDiffScope.diffOnly
    @Published private(set) var fullFileDiff: String?
    @Published private(set) var isLoadingFullFile = false
    @Published var errorMessage: String?

    private let client = GitClient()

    init(state: SideBySideDiffWindowState) {
        self.state = state
    }

    var displayedDiff: String {
        scope == .fullFile ? fullFileDiff ?? "" : state.diff
    }

    func selectScope(_ scope: SideBySideDiffScope) {
        self.scope = scope
        guard scope == .fullFile, fullFileDiff == nil, !isLoadingFullFile else {
            return
        }

        isLoadingFullFile = true
        Task {
            do {
                let diff = try await client.diff(
                    at: state.repositoryURL,
                    change: state.change,
                    staged: state.staged,
                    fullFile: true
                )
                try Task.checkCancellation()
                fullFileDiff = diff
                isLoadingFullFile = false
            } catch is CancellationError {
                isLoadingFullFile = false
            } catch {
                isLoadingFullFile = false
                self.scope = .diffOnly
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Anchors the very top of a diff so "Scroll to Top" always has a target, in a
/// type of its own so it can never collide with a line or file identifier.
private enum DiffScrollAnchor: Hashable {
    case top
}

struct DetailView: View {
    @EnvironmentObject private var store: RepositoryStore
    @State private var parsedDiff = ParsedUnifiedDiff.empty
    @State private var focusedFileID: Int?
    @State private var scrollToTopToken: UUID?

    /// The parsed files, but only once they describe the diff on screen, so the
    /// file chooser never lists the previous selection's files.
    private var currentFiles: [UnifiedDiffFile] {
        parsedDiff.source == store.diff ? parsedDiff.document.files : []
    }

    var body: some View {
        VStack(spacing: 0) {
            if let commit = store.selectedCommit, store.selectedSection == .history {
                CommitHeader(
                    commit: commit,
                    files: currentFiles,
                    focusedFileID: focusedFileID,
                    focus: { focusedFileID = $0?.id },
                    scrollToTop: { scrollToTopToken = UUID() }
                )
                Divider()
                DiffTextView(
                    text: store.diff,
                    parsedDiff: parsedDiff,
                    focusedFileID: focusedFileID,
                    scrollToTopToken: scrollToTopToken
                )
            } else if let change = store.selectedChange, store.selectedSection == .changes {
                ChangeHeader(
                    change: change,
                    staged: store.selectedChangeIsStaged
                )
                Divider()
                if change.isConflicted,
                   let conflictDocument = store.conflictDocument {
                    ConflictDocumentView(document: conflictDocument)
                } else {
                    DiffTextView(
                        text: store.diff,
                        parsedDiff: parsedDiff,
                        change: change,
                        staged: store.selectedChangeIsStaged
                    )
                }
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a commit or changed file to inspect it.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: store.diff) {
            let text = store.diff
            guard !text.isEmpty else {
                parsedDiff = .empty
                return
            }
            let parsed = await DiffParsing.unified(text)
            guard !Task.isCancelled, parsed.source == store.diff else { return }
            parsedDiff = parsed
        }
        .onChange(of: store.diff) {
            // A new commit brings a new set of files; never carry a filter over.
            focusedFileID = nil
        }
    }
}

private struct CommitHeader: View {
    let commit: GitCommit
    let files: [UnifiedDiffFile]
    let focusedFileID: Int?
    let focus: (UnifiedDiffFile?) -> Void
    let scrollToTop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(commit.subject)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)

            HStack(spacing: 10) {
                IdentityAvatar(name: commit.authorName, initials: commit.initials, size: 22)
                Text(commit.authorName)
                    .font(.callout.weight(.medium))
                Text("·")
                    .foregroundStyle(.tertiary)
                Label {
                    Text(commit.date, format: .dateTime.year().month().day().hour().minute())
                } icon: {
                    Image(systemName: "calendar")
                }
                .foregroundStyle(.secondary)
                CommitSignatureBadge(signature: commit.signature)
            }
            .font(.callout)

            HStack(spacing: 6) {
                CopyableValue(label: "COMMIT", value: commit.hash, display: commit.shortHash)
                ForEach(Array(commit.parents.enumerated()), id: \.element) { index, parent in
                    CopyableValue(
                        label: commit.parents.count > 1 ? "PARENT \(index + 1)" : "PARENT",
                        value: parent,
                        display: String(parent.prefix(8))
                    )
                }
                if commit.parents.count > 1 {
                    Text("MERGE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GitForkTheme.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(GitForkTheme.purple.opacity(0.12), in: Capsule())
                }

                Spacer(minLength: 12)

                CommitFileChooser(
                    files: files,
                    focusedFileID: focusedFileID,
                    focus: focus,
                    scrollToTop: scrollToTop
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(HeaderBackground())
    }
}

/// A pull-down list of every file a commit touches. The list itself shows what
/// the commit changed; choosing a row narrows the diff to that single file, and
/// "All Files" restores the whole commit from the top.
private struct CommitFileChooser: View {
    @EnvironmentObject private var store: RepositoryStore
    let files: [UnifiedDiffFile]
    let focusedFileID: Int?
    let focus: (UnifiedDiffFile?) -> Void
    let scrollToTop: () -> Void

    private var focusedFile: UnifiedDiffFile? {
        files.first { $0.id == focusedFileID }
    }

    private var additions: Int {
        files.reduce(0) { $0 + $1.additions }
    }

    private var deletions: Int {
        files.reduce(0) { $0 + $1.deletions }
    }

    private var summary: String {
        let fileCount = files.count == 1 ? "1 file" : "\(files.count) files"
        return "\(fileCount) changed · +\(additions) −\(deletions)"
    }

    private var title: String {
        if let focusedFile {
            return URL(fileURLWithPath: focusedFile.path).lastPathComponent
        }
        if files.isEmpty { return "Files" }
        return files.count == 1 ? "1 File" : "All \(files.count) Files"
    }

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Section(summary) {
                    Button {
                        focus(nil)
                    } label: {
                        Label(
                            "All Files",
                            systemImage: focusedFile == nil
                                ? "checkmark"
                                : "square.stack.3d.up"
                        )
                    }

                    ForEach(files) { file in
                        Button {
                            focus(file)
                        } label: {
                            Label(
                                label(for: file),
                                systemImage: focusedFileID == file.id
                                    ? "checkmark"
                                    : symbolName(for: file.change)
                            )
                        }
                    }
                }

                Divider()

                Button(action: scrollToTop) {
                    Label("Scroll to Top", systemImage: "arrow.up.to.line")
                }

                Button {
                    store.showPathHistoryPicker()
                } label: {
                    Label("File or Directory History…", systemImage: "clock.arrow.circlepath")
                }
                .disabled(store.repositoryURL == nil)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: focusedFile == nil
                        ? "list.bullet.rectangle"
                        : "doc.text")
                        .foregroundStyle(GitForkTheme.accent)
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.callout.weight(.medium))
                .frame(maxWidth: 320)
            }
            .menuStyle(.button)
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .fixedSize()
            .disabled(files.isEmpty)
            .help(
                focusedFile == nil
                    ? "List the files in this commit and show one on its own"
                    : "Showing only \(focusedFile?.path ?? "") · choose another file or All Files"
            )
            .accessibilityLabel("Files changed in this commit")

            if focusedFile != nil {
                Button {
                    focus(nil)
                } label: {
                    Label("Show All", systemImage: "xmark.circle")
                        .font(.callout)
                }
                .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
                .help("Show every file in this commit again, from the top")
            }
        }
    }

    private func label(for file: UnifiedDiffFile) -> String {
        var label = file.path
        if let originalPath = file.originalPath, originalPath != file.path {
            label += "  ← \(originalPath)"
        }
        if file.additions > 0 || file.deletions > 0 {
            label += "  +\(file.additions) −\(file.deletions)"
        }
        return label
    }

    private func symbolName(for change: UnifiedDiffFileChange) -> String {
        switch change {
        case .added: "plus.circle"
        case .modified: "pencil.circle"
        case .deleted: "minus.circle"
        case .renamed: "arrow.turn.up.right"
        case .copied: "doc.on.doc"
        }
    }
}

/// A soft, tinted bar used behind the commit and change detail headers.
private struct HeaderBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.bar)
            LinearGradient(
                colors: [GitForkTheme.accent.opacity(0.07), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct ChangeHeader: View {
    @EnvironmentObject private var store: RepositoryStore
    @Environment(\.openWindow) private var openWindow
    let change: WorkingChange
    let staged: Bool
    @State private var isConfirmingFileDiscard = false
    @State private var pendingConflictSide: ConflictResolutionSide?

    var body: some View {
        let statusSymbol = change.statusSymbol(staged: staged)
        HStack(spacing: 12) {
            Text(statusSymbol)
                .font(.headline.monospaced())
                .foregroundStyle(Color.statusColor(statusSymbol))
                .frame(width: 32, height: 32)
                .background(Color.statusColor(statusSymbol).opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(change.path)
                    .font(.headline)
                    .textSelection(.enabled)
                Text(changeDetailStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if let repositoryURL = store.repositoryURL {
                    openWindow(
                        id: GitForkApp.sideBySideDiffWindowID,
                        value: SideBySideDiffWindowState(
                            repositoryURL: repositoryURL,
                            change: change,
                            staged: staged,
                            diff: store.diff
                        )
                    )
                }
            } label: {
                Label("Side by Side", systemImage: "rectangle.split.2x1")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help("Open a side-by-side comparison in a new window")
            .disabled(
                store.repositoryURL == nil
                    || store.diff.isEmpty
                    || change.isConflicted
            )

            if change.isConflicted {
                Menu {
                    Button(role: .destructive) {
                        pendingConflictSide = .ours
                    } label: {
                        Label("Use Ours…", systemImage: "arrow.left")
                    }

                    Button(role: .destructive) {
                        pendingConflictSide = .theirs
                    } label: {
                        Label("Use Theirs…", systemImage: "arrow.right")
                    }
                } label: {
                    Label("Choose Version", systemImage: "arrow.triangle.branch")
                }
                .menuStyle(.borderedButton)
                .help("Choose one side and replace the current file after confirmation")
                .disabled(store.isLoading)

                Button {
                    store.markConflictsResolved([conflictEntry])
                } label: {
                    Label("Mark Resolved", systemImage: "checkmark.circle")
                }
                .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
                .help("Stage the file’s current contents as the resolved version")
                .disabled(store.isLoading)
            } else {
                Button {
                    staged ? store.unstage(change) : store.stage(change)
                } label: {
                    Label(staged ? "Unstage" : "Stage", systemImage: staged ? "minus" : "plus")
                }
                .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
                .help(staged ? "Move this file back to working changes" : "Stage this file for commit")
                .disabled(store.isLoading)
            }

            if !staged && !change.isConflicted {
                Button(role: .destructive) {
                    isConfirmingFileDiscard = true
                } label: {
                    Label("Discard File…", systemImage: "trash")
                }
                .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
                .help("Permanently discard every unstaged change in this file after confirmation")
                .disabled(store.isLoading)
            }
        }
        .padding(14)
        .background(HeaderBackground())
        .alert("Discard All Changes in This File?", isPresented: $isConfirmingFileDiscard) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) {
                store.discard(change)
            }
        } message: {
            if change.isUntracked {
                Text("\(change.path) is untracked and will be permanently deleted. This cannot be undone.")
            } else {
                Text("All unstaged changes in \(change.path) will be permanently discarded. This cannot be undone.")
            }
        }
        .alert(
            pendingConflictSide.map { "Use \($0.title) for This File?" }
                ?? "Resolve Conflict?",
            isPresented: Binding(
                get: { pendingConflictSide != nil },
                set: { if !$0 { pendingConflictSide = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingConflictSide = nil
            }
            Button(
                pendingConflictSide.map { "Use \($0.title)" } ?? "Resolve",
                role: .destructive
            ) {
                if let side = pendingConflictSide {
                    store.resolveConflicts([conflictEntry], using: side)
                }
                pendingConflictSide = nil
            }
        } message: {
            if let side = pendingConflictSide {
                Text(
                    "This replaces the current contents of \(change.path) with "
                        + "Git’s \(side.title.lowercased()) version and marks the conflict "
                        + "resolved. Any manual edits in this file will be lost."
                )
            }
        }
    }

    private var conflictEntry: ChangeEntry {
        ChangeEntry(change, staged: false)
    }

    private var changeDetailStatus: String {
        if change.isConflicted {
            return "\(change.conflictDescription ?? "Unmerged") · Conflict"
        }
        return "\(change.displayStatus(staged: staged)) · \(staged ? "Staged" : "Working tree")"
    }
}

/// A hunk-like conflict resolver for textual working-tree markers. Each choice
/// edits only its block; `GitClient` leaves the path unmerged until the last
/// well-formed block has been chosen.
private struct ConflictDocumentView: View {
    @EnvironmentObject private var store: RepositoryStore
    let document: ConflictDocument

    var body: some View {
        GeometryReader { viewport in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(.orange)
                        Text(
                            "\(document.conflicts.count) unresolved conflict"
                                + (document.conflicts.count == 1 ? "" : "s")
                        )
                        .font(.callout.weight(.semibold))
                        Spacer()
                        Text("Choose a version for each block")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                    if document.hasUnparsedMarkers {
                        Label(
                            "Some marker-like lines could not be paired. Resolve them manually; "
                                + "GitFork will not mark the file resolved automatically.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(10)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    ForEach(document.conflicts) { block in
                        ConflictBlockView(
                            block: block,
                            number: (document.conflicts.firstIndex(of: block) ?? 0) + 1,
                            total: document.conflicts.count,
                            isLoading: store.isLoading,
                            resolve: { side in
                                store.resolveConflictBlock(block, using: side)
                            }
                        )
                    }
                }
                .padding(14)
                .frame(
                    minWidth: max(viewport.size.width, 760),
                    minHeight: viewport.size.height,
                    alignment: .topLeading
                )
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct ConflictBlockView: View {
    let block: ConflictBlock
    let number: Int
    let total: Int
    let isLoading: Bool
    let resolve: (ConflictResolutionSide) -> Void

    @State private var showsBase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Conflict \(number) of \(total)")
                    .font(.callout.weight(.semibold))
                Text("Lines \(block.id + 1)–\(block.endLine + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.primary.opacity(0.045))

            Divider()

            HStack(alignment: .top, spacing: 0) {
                ConflictVersionColumn(
                    title: "Ours",
                    label: block.oursLabel,
                    lines: block.oursLines,
                    tint: GitForkTheme.blue,
                    isLoading: isLoading,
                    action: { resolve(.ours) }
                )

                Divider()

                ConflictVersionColumn(
                    title: "Theirs",
                    label: block.theirsLabel,
                    lines: block.theirsLines,
                    tint: GitForkTheme.purple,
                    isLoading: isLoading,
                    action: { resolve(.theirs) }
                )
            }

            if let baseLines = block.baseLines {
                Divider()
                DisclosureGroup(isExpanded: $showsBase) {
                    ConflictCodeLines(lines: baseLines, tint: .secondary)
                        .padding(.top, 6)
                } label: {
                    HStack(spacing: 6) {
                        Text("Base")
                            .font(.caption.weight(.semibold))
                        if let baseLabel = block.baseLabel, !baseLabel.isEmpty {
                            Text(baseLabel)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.025))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(.orange.opacity(0.35))
        }
    }
}

private struct ConflictVersionColumn: View {
    let title: String
    let label: String
    let lines: [String]
    let tint: Color
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.bold))
                if !label.isEmpty {
                    Text(label)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Use \(title)", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(tint)
                    .help(
                        "Replace only this conflict block with Git’s "
                            + "\(title.lowercased()) version"
                    )
                    .disabled(isLoading)
            }
            .padding(9)
            .background(tint.opacity(0.08))

            Divider()

            ConflictCodeLines(lines: lines, tint: tint)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 340, maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ConflictCodeLines: View {
    let lines: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if lines.isEmpty {
                Text("No content — choosing this version removes the block")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
                    .padding(10)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .frame(
                            minHeight: DiffLayout.rowHeight,
                            alignment: .leading
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tint.opacity(0.8))
                .frame(width: DiffLayout.accentBarWidth)
        }
    }
}

/// A labelled hash that copies its full value on click, stays selectable, and
/// keeps a Copy item in its context menu.
private struct CopyableValue: View {
    let label: String
    let value: String
    let display: String

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                Text(display)
                    .font(.caption.monospaced())
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(
                        didCopy ? AnyShapeStyle(GitForkTheme.green) : AnyShapeStyle(.tertiary)
                    )
            }
        }
        .buttonStyle(GitForkHoverButtonStyle(.text))
        .help(didCopy ? "Copied \(value)" : "Copy \(value)")
        .accessibilityLabel("Copy \(label.lowercased()) \(value)")
        .contextMenu {
            Button("Copy \(label.capitalized)", action: copy)
        }
        .onDisappear {
            resetTask?.cancel()
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        didCopy = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}

private struct ParsedUnifiedDiff: Sendable {
    let source: String
    let document: UnifiedDiff

    static let empty = ParsedUnifiedDiff(source: "", document: UnifiedDiff(""))
}

private struct ParsedSideBySideDiff: Sendable {
    let source: String
    let document: SideBySideDiff

    static let empty = ParsedSideBySideDiff(
        source: "",
        document: SideBySideDiff(UnifiedDiff(""))
    )
}

private enum DiffParsing {
    static func unified(_ source: String) async -> ParsedUnifiedDiff {
        await Task.detached(priority: .userInitiated) {
            ParsedUnifiedDiff(source: source, document: UnifiedDiff(source))
        }.value
    }

    static func sideBySide(_ source: String) async -> ParsedSideBySideDiff {
        await Task.detached(priority: .userInitiated) {
            ParsedSideBySideDiff(
                source: source,
                document: SideBySideDiff(UnifiedDiff(source))
            )
        }.value
    }
}

private struct DiffTextView: View {
    @EnvironmentObject private var store: RepositoryStore
    let text: String
    let parsedDiff: ParsedUnifiedDiff
    var change: WorkingChange?
    var staged = false
    var focusedFileID: Int?
    var scrollToTopToken: UUID?

    @State private var showsLargeDiff = false
    @State private var selectedDisplayLineIDs: Set<Int> = []
    @State private var selectedHunkID: Int?
    @State private var pendingDiscardLineIDs: Set<Int>?

    private var document: UnifiedDiff {
        parsedDiff.document
    }

    private var isPreparingReplacement: Bool {
        !parsedDiff.source.isEmpty && parsedDiff.source != text
    }

    /// The one file the chooser narrowed to, if it is still part of this diff.
    private var focusedFile: UnifiedDiffFile? {
        guard let focusedFileID else { return nil }
        return document.files.first { $0.id == focusedFileID }
    }

    private var visibleFiles: [UnifiedDiffFile] {
        focusedFile.map { [$0] } ?? document.files
    }

    /// Narrowing to one file also narrows what the large-diff gate measures, so
    /// a small file stays readable inside an enormous commit.
    private var displayedLineCount: Int {
        focusedFile?.lines.count ?? document.lines.count
    }

    var body: some View {
        Group {
            if text.isEmpty {
                VStack {
                    ProgressView()
                    Text("Loading diff…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if parsedDiff.source.isEmpty {
                VStack {
                    ProgressView()
                    Text("Preparing diff…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedLineCount > DiffLayout.automaticLineLimit,
                      !showsLargeDiff {
                LargeDiffPlaceholder(
                    lineCount: displayedLineCount,
                    action: { showsLargeDiff = true }
                )
            } else {
                GeometryReader { viewport in
                    ScrollViewReader { proxy in
                        ScrollView([.horizontal, .vertical]) {
                            diffContent
                                .frame(
                                    minWidth: viewport.size.width,
                                    minHeight: viewport.size.height,
                                    alignment: .topLeading
                                )
                                // Tagging the whole content gives "Scroll to
                                // Top" a target in every diff layout.
                                .id(DiffScrollAnchor.top)
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                        // Rebuilding the scroll view for each focus change is
                        // what puts a newly chosen file at the top of the pane.
                        .id(focusedFileID)
                        .task(id: scrollToTopToken) {
                            guard scrollToTopToken != nil else { return }
                            try? await Task.sleep(for: .milliseconds(20))
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(DiffScrollAnchor.top, anchor: .topLeading)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: text) {
            clearSelection()
            showsLargeDiff = false
        }
        .onChange(of: focusedFileID) {
            showsLargeDiff = false
        }
        .alert(
            discardTitle,
            isPresented: Binding(
                get: { pendingDiscardLineIDs != nil },
                set: { if !$0 { pendingDiscardLineIDs = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingDiscardLineIDs = nil
            }
            Button("Discard", role: .destructive) {
                confirmDiscard()
            }
        } message: {
            Text(discardMessage)
        }
    }

    @ViewBuilder
    private var diffContent: some View {
        if change != nil,
           change?.isConflicted != true,
           !document.displayHunks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(document.displayHunks) { hunk in
                    DiffHunkView(
                        hunk: hunk,
                        selectedLineIDs: selectedHunkID == hunk.id
                            ? selectedDisplayLineIDs
                            : [],
                        staged: staged,
                        isLoading: store.isLoading || isPreparingReplacement,
                        selectRange: { lineIDs in
                            selectedHunkID = hunk.id
                            selectedDisplayLineIDs = lineIDs
                        },
                        apply: apply,
                        discard: requestDiscard
                    )
                }
            }
            // The enclosing viewport supplies a minimum height so short diffs
            // fill the pane. Keep that spare height out of the hunk rows.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
        } else if !document.files.isEmpty {
            LazyVStack(alignment: .leading, spacing: 16) {
                // The preamble is the commit's summary of every file, so it only
                // belongs to the unfiltered diff.
                if focusedFile == nil, !document.preambleLines.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(document.preambleLines) { line in
                            DiffLineView(
                                line: line,
                                isRangeSelected: false,
                                allowsTextSelection: true
                            )
                        }
                    }
                }

                ForEach(visibleFiles) { file in
                    CommitDiffFileView(file: file)
                }
            }
            .padding(12)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(document.lines) { line in
                    DiffLineView(
                        line: line,
                        isRangeSelected: false,
                        allowsTextSelection: true
                    )
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func apply(_ selection: Set<Int>) {
        guard let change,
              let patch = partialPatch(selecting: selection, direction: staged ? .reverse : .forward) else {
            return
        }
        clearSelection()
        if staged {
            store.unstage(patch, in: change)
        } else {
            store.stage(patch, in: change)
        }
    }

    private func requestDiscard(_ selection: Set<Int>) {
        let actionable = selection.intersection(document.selectableLineIDs)
        guard !actionable.isEmpty else { return }
        pendingDiscardLineIDs = actionable
    }

    private func confirmDiscard() {
        guard let change,
              let selection = pendingDiscardLineIDs,
              let patch = partialPatch(selecting: selection, direction: .reverse) else {
            return
        }
        pendingDiscardLineIDs = nil
        clearSelection()
        store.discard(patch, in: change)
    }

    private func partialPatch(
        selecting selection: Set<Int>,
        direction: PartialPatchDirection
    ) -> String? {
        let active = selection.intersection(document.selectableLineIDs)
        let isPartialReverseOfNewFile = direction == .reverse
            && active != document.selectableLineIDs
        return document.partialPatch(
            selecting: active,
            direction: direction,
            treatNewFileAsExisting: isPartialReverseOfNewFile
        )
    }

    private func clearSelection() {
        selectedDisplayLineIDs.removeAll()
        selectedHunkID = nil
    }

    private var discardTitle: String {
        "Discard Changes?"
    }

    private var discardMessage: String {
        guard let change else { return "" }
        return "The selected working-tree changes in \(change.path) will be permanently discarded. This cannot be undone."
    }
}

struct SideBySideDiffWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @StateObject private var model: SideBySideDiffWindowStore
    @State private var parsedDiff = ParsedSideBySideDiff.empty
    @State private var showsLargeDiff = false

    init(state: SideBySideDiffWindowState) {
        _model = StateObject(
            wrappedValue: SideBySideDiffWindowStore(state: state)
        )
    }

    private var document: SideBySideDiff {
        parsedDiff.document
    }

    private var windowTitle: String {
        "\(URL(fileURLWithPath: model.state.path).lastPathComponent) — Side by Side"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(model.state.statusSymbol)
                    .font(.headline.monospaced())
                    .foregroundStyle(Color.statusColor(model.state.statusSymbol))
                    .frame(width: 32, height: 32)
                    .background(
                        Color.statusColor(model.state.statusSymbol).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 7)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.state.path)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(
                        "\(model.state.status) · \(model.state.staged ? "Staged" : "Working tree")"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker(
                    "Comparison Scope",
                    selection: Binding(
                        get: { model.scope },
                        set: model.selectScope
                    )
                ) {
                    ForEach(SideBySideDiffScope.allCases) { scope in
                        Text(scope.title)
                            .tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Show only changed regions or the complete contents of both files")
            }
            .padding(14)
            .background(HeaderBackground())

            Divider()

            if model.isLoadingFullFile {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading full file contents…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if parsedDiff.source != model.displayedDiff {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Preparing side-by-side diff…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if document.rowCount > DiffLayout.automaticLineLimit,
                      !showsLargeDiff {
                LargeDiffPlaceholder(
                    lineCount: document.rowCount,
                    action: { showsLargeDiff = true }
                )
            } else if document.isEmpty {
                ContentUnavailableView(
                    "No Side-by-Side Changes",
                    systemImage: "rectangle.split.2x1",
                    description: Text("This diff has no comparable changed lines.")
                )
            } else {
                GeometryReader { viewport in
                    SideBySideDiffView(
                        diff: document,
                        availableWidth: viewport.size.width,
                        availableHeight: viewport.size.height,
                        staged: model.state.staged
                    )
                    .frame(
                        width: viewport.size.width,
                        height: viewport.size.height,
                        alignment: .topLeading
                    )
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .navigationTitle(windowTitle)
        .tint(GitForkTheme.accent)
        .task(id: model.displayedDiff) {
            let source = model.displayedDiff
            guard !source.isEmpty else {
                parsedDiff = .empty
                return
            }
            let parsed = await DiffParsing.sideBySide(source)
            guard !Task.isCancelled, parsed.source == model.displayedDiff else {
                return
            }
            parsedDiff = parsed
        }
        .onChange(of: model.displayedDiff) {
            showsLargeDiff = false
        }
        .onExitCommand {
            dismissWindow(
                id: GitForkApp.sideBySideDiffWindowID,
                value: model.state
            )
        }
        .alert(
            "Unable to Load Full File",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct CommitDiffFileView: View {
    let file: UnifiedDiffFile

    private var contentLines: ArraySlice<UnifiedDiffLine> {
        if file.lines.first?.text.hasPrefix("diff --git ") == true {
            return file.lines.dropFirst()
        }
        return file.lines[...]
    }

    private var statusColor: Color {
        Color.statusColor(file.change.symbol)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "doc.text")
                    .foregroundStyle(GitForkTheme.blue)
                Text(file.path)
                    .font(.callout.monospaced().weight(.semibold))
                    .textSelection(.enabled)
                Text(file.change.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12), in: Capsule())
                Spacer(minLength: 12)
                if file.additions > 0 {
                    Text("+\(file.additions)")
                        .foregroundStyle(GitForkTheme.green)
                }
                if file.deletions > 0 {
                    Text("−\(file.deletions)")
                        .foregroundStyle(GitForkTheme.red)
                }
            }
            .font(.caption.monospaced())
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.primary.opacity(0.045))

            Divider()

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(contentLines) { line in
                    DiffLineView(
                        line: line,
                        isRangeSelected: false,
                        allowsTextSelection: true
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.primary.opacity(0.14))
        }
    }
}

private enum DiffLayout {
    static let rowHeight: CGFloat = 20
    static let automaticLineLimit = 20_000
    static let lineNumberWidth: CGFloat = 34
    static let accentBarWidth: CGFloat = 2.5
    static let textPadding: CGFloat = 9
    static let dividerWidth: CGFloat = 1
    static let minimumSideBySideColumnWidth: CGFloat = 180
    static let sideBySideHeaderHeight: CGFloat = 24

    /// Everything a side-by-side cell draws around its text.
    static let cellChrome = accentBarWidth + lineNumberWidth + dividerWidth + textPadding * 2

    /// Width of one monospaced character in the diff font, used to size the
    /// side-by-side columns so long lines scroll instead of wrapping.
    static let characterWidth = NSFont
        .monospacedSystemFont(ofSize: 12, weight: .regular)
        .maximumAdvancement
        .width
}

private struct LargeDiffPlaceholder: View {
    let lineCount: Int
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Large Diff")
                .font(.headline)
            Text("\(lineCount.formatted()) lines are ready to display.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Display Diff", action: action)
                .buttonStyle(.borderedProminent)
                .help("Render this large diff")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Stage, unstage, and discard actions for a set of diff lines. Shared by the
/// unified hunk view and the side-by-side hunk view.
private struct DiffHunkActions: View {
    let staged: Bool
    let isLoading: Bool
    let subject: String
    let lineIDs: Set<Int>
    let apply: (Set<Int>) -> Void
    let discard: (Set<Int>) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(staged ? "Unstage" : "Stage") {
                apply(lineIDs)
            }
            .help(staged ? "Unstage \(subject)" : "Stage \(subject)")

            if !staged {
                Button("Discard Changes…", role: .destructive) {
                    discard(lineIDs)
                }
                .help("Permanently discard \(subject) after confirmation")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isLoading)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct DiffHunkMenu: View {
    let staged: Bool
    let isLoading: Bool
    let lineIDs: Set<Int>
    let apply: (Set<Int>) -> Void
    let discard: (Set<Int>) -> Void

    var body: some View {
        if !lineIDs.isEmpty {
            Button(staged ? "Unstage" : "Stage") {
                apply(lineIDs)
            }
            .disabled(isLoading)
            if !staged {
                Divider()
                Button("Discard Changes…", role: .destructive) {
                    discard(lineIDs)
                }
                .disabled(isLoading)
            }
        }
    }
}

private struct DiffHunkView: View {
    let hunk: UnifiedDiffHunk
    let selectedLineIDs: Set<Int>
    let staged: Bool
    let isLoading: Bool
    let selectRange: (Set<Int>) -> Void
    let apply: (Set<Int>) -> Void
    let discard: (Set<Int>) -> Void

    @State private var isHovering = false
    @State private var dragStartIndex: Int?

    private var selectedChangeLineIDs: Set<Int> {
        selectedLineIDs.intersection(hunk.selectableLineIDs)
    }

    private var targetLineIDs: Set<Int> {
        selectedLineIDs.isEmpty
            ? hunk.selectableLineIDs
            : selectedChangeLineIDs
    }

    private var selectedRowRange: ClosedRange<Int>? {
        let indices = hunk.lines.indices.filter {
            selectedLineIDs.contains(hunk.lines[$0].id)
        }
        guard let first = indices.first, let last = indices.last else { return nil }
        return first...last
    }

    private var actionOffset: CGFloat {
        CGFloat(selectedRowRange?.lowerBound ?? 0) * DiffLayout.rowHeight
    }

    private var shouldShowActions: Bool {
        (isHovering || selectedRowRange != nil) && !targetLineIDs.isEmpty
    }

    private var coordinateSpaceName: String {
        "diff-hunk-\(hunk.id)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: DiffLayout.accentBarWidth + DiffLayout.lineNumberWidth * 2)
                Divider()
                Text(hunk.header.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: DiffLayout.rowHeight, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035))

            ZStack(alignment: .topTrailing) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(hunk.lines) { line in
                        DiffLineView(
                            line: line,
                            isRangeSelected: selectedLineIDs.contains(line.id),
                            allowsTextSelection: false
                        )
                    }
                }
                .coordinateSpace(.named(coordinateSpaceName))
                .contentShape(Rectangle())
                .gesture(selectionGesture)

                if let selectedRowRange {
                    Rectangle()
                        .strokeBorder(GitForkTheme.blue, lineWidth: 1.5)
                        .frame(
                            height: CGFloat(selectedRowRange.count)
                                * DiffLayout.rowHeight
                        )
                        .offset(y: actionOffset)
                        .allowsHitTesting(false)
                }

                if shouldShowActions {
                    actionButtons
                        .padding(7)
                        .offset(y: actionOffset)
                }
            }
            .overlay {
                Rectangle()
                    .strokeBorder(
                        isHovering && selectedRowRange == nil
                            ? GitForkTheme.blue
                            : .clear,
                        lineWidth: 1.5
                    )
                    .allowsHitTesting(false)
            }
            .contextMenu {
                DiffHunkMenu(
                    staged: staged,
                    isLoading: isLoading,
                    lineIDs: targetLineIDs,
                    apply: apply,
                    discard: discard
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 10)
        .onHover { isHovering = $0 }
    }

    private var actionButtons: some View {
        DiffHunkActions(
            staged: staged,
            isLoading: isLoading,
            subject: selectedRowRange == nil ? "this hunk" : "the selected lines",
            lineIDs: targetLineIDs,
            apply: apply,
            discard: discard
        )
    }

    private var selectionGesture: some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(coordinateSpaceName)
        )
        .onChanged { value in
            guard !hunk.lines.isEmpty else { return }
            let currentIndex = rowIndex(at: value.location.y)
            if dragStartIndex == nil {
                dragStartIndex = rowIndex(at: value.startLocation.y)
            }
            guard let dragStartIndex else { return }
            let bounds = min(dragStartIndex, currentIndex)...max(dragStartIndex, currentIndex)
            selectRange(Set(hunk.lines[bounds].map(\.id)))
        }
        .onEnded { _ in
            dragStartIndex = nil
        }
    }

    private func rowIndex(at yPosition: CGFloat) -> Int {
        let rawIndex = Int(floor(yPosition / DiffLayout.rowHeight))
        return min(max(rawIndex, 0), hunk.lines.count - 1)
    }
}

/// The two versions of a file laid out in aligned, read-only columns.
private struct SideBySideDiffView: View {
    let diff: SideBySideDiff
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let staged: Bool

    private var oldTitle: String {
        staged ? "Last Commit" : "Staged"
    }

    private var newTitle: String {
        staged ? "Staged" : "Working Tree"
    }

    private var oldContentWidth: CGFloat {
        contentWidth(for: diff.oldColumnCharacters)
    }

    private var newContentWidth: CGFloat {
        contentWidth(for: diff.newColumnCharacters)
    }

    private func contentWidth(for characters: Int) -> CGFloat {
        DiffLayout.cellChrome
            + CGFloat(characters) * DiffLayout.characterWidth
    }

    private var contentHeight: CGFloat {
        DiffLayout.sideBySideHeaderHeight
            + DiffLayout.dividerWidth
            + 16
            + diff.hunks.reduce(0) { height, hunk in
                height
                    + DiffLayout.rowHeight
                    + CGFloat(hunk.rows.count) * DiffLayout.rowHeight
                    + 10
            }
    }

    var body: some View {
        ScrollView(.vertical) {
            HSplitView {
                SideBySideDiffPane(
                    title: oldTitle,
                    diff: diff,
                    side: .old,
                    contentWidth: oldContentWidth
                )
                .frame(
                    minWidth: DiffLayout.minimumSideBySideColumnWidth,
                    idealWidth: availableWidth / 2,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )

                SideBySideDiffPane(
                    title: newTitle,
                    diff: diff,
                    side: .new,
                    contentWidth: newContentWidth
                )
                .frame(
                    minWidth: DiffLayout.minimumSideBySideColumnWidth,
                    idealWidth: availableWidth / 2,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
            }
            .frame(
                width: availableWidth,
                height: max(availableHeight, contentHeight),
                alignment: .topLeading
            )
        }
    }
}

private struct SideBySideDiffPane: View {
    let title: String
    let diff: SideBySideDiff
    let side: SideBySideDiffSide
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(
                    .leading,
                    DiffLayout.accentBarWidth + DiffLayout.lineNumberWidth
                        + DiffLayout.dividerWidth + DiffLayout.textPadding
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: DiffLayout.sideBySideHeaderHeight,
                    maxHeight: DiffLayout.sideBySideHeaderHeight,
                    alignment: .leading
                )
                .background(.bar)

            Divider()

            GeometryReader { viewport in
                ScrollView(.horizontal) {
                    SideBySideDiffColumn(
                        diff: diff,
                        side: side,
                        contentWidth: max(contentWidth, viewport.size.width)
                    )
                    .padding(.vertical, 8)
                    .frame(
                        minHeight: viewport.size.height,
                        alignment: .topLeading
                    )
                }
            }
        }
    }
}

private struct SideBySideDiffColumn: View {
    let diff: SideBySideDiff
    let side: SideBySideDiffSide
    let contentWidth: CGFloat

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(diff.hunks) { hunk in
                SideBySideHunkColumnView(
                    hunk: hunk,
                    side: side,
                    contentWidth: contentWidth
                )
            }
        }
        .frame(width: contentWidth, alignment: .leading)
    }
}

private struct SideBySideHunkColumnView: View {
    let hunk: SideBySideDiffHunk
    let side: SideBySideDiffSide
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: DiffLayout.accentBarWidth + DiffLayout.lineNumberWidth)
                Divider()
                Text(hunk.header.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DiffLayout.textPadding)
                    .frame(height: DiffLayout.rowHeight, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(width: contentWidth, alignment: .leading)
            .background(Color.primary.opacity(0.035))

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(hunk.rows) { row in
                    SideBySideCell(
                        line: row.line(side),
                        side: side,
                        width: contentWidth
                    )
                }
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .padding(.bottom, 10)
    }
}

private struct SideBySideCell: View {
    @Environment(\.colorScheme) private var colorScheme
    let line: UnifiedDiffLine?
    let side: SideBySideDiffSide
    let width: CGFloat

    private var lineNumber: String {
        guard let line else { return "" }
        let number = side == .old ? line.oldLineNumber : line.newLineNumber
        return number.map(String.init) ?? ""
    }

    private var foreground: Color {
        guard let line else { return .clear }
        switch line.kind {
        case .addition: return GitForkTheme.diffAddition(colorScheme)
        case .deletion: return GitForkTheme.diffDeletion(colorScheme)
        case .noNewline: return .secondary
        default: return .primary
        }
    }

    private var background: Color {
        // A missing counterpart is filled so the eye can follow the gap.
        guard let line else { return Color.primary.opacity(0.04) }
        switch line.kind {
        case .addition: return GitForkTheme.green.opacity(0.11)
        case .deletion: return GitForkTheme.red.opacity(0.10)
        default: return .clear
        }
    }

    private var accentBar: Color {
        switch line?.kind {
        case .addition: return GitForkTheme.green.opacity(0.85)
        case .deletion: return GitForkTheme.red.opacity(0.85)
        default: return .clear
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentBar)
                .frame(width: DiffLayout.accentBarWidth)

            Text(lineNumber)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 5)
                .frame(
                    width: DiffLayout.lineNumberWidth,
                    height: DiffLayout.rowHeight,
                    alignment: .trailing
                )

            Divider()

            Text(line?.displayText ?? "")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(foreground)
                .textSelection(.enabled)
                .lineLimit(1)
                .padding(.horizontal, DiffLayout.textPadding)
                .frame(height: DiffLayout.rowHeight, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(width: width, height: DiffLayout.rowHeight, alignment: .leading)
        .background(background)
    }
}

private struct DiffLineView: View {
    @Environment(\.colorScheme) private var colorScheme
    let line: UnifiedDiffLine
    let isRangeSelected: Bool
    let allowsTextSelection: Bool

    private var foreground: Color {
        if line.kind == .addition { return GitForkTheme.diffAddition(colorScheme) }
        if line.kind == .deletion { return GitForkTheme.diffDeletion(colorScheme) }
        if line.kind == .hunkHeader { return GitForkTheme.blue }
        if line.text.hasPrefix("diff ") || line.text.hasPrefix("commit ") { return GitForkTheme.purple }
        return .primary
    }

    private var background: Color {
        if isRangeSelected { return GitForkTheme.blue.opacity(0.18) }
        if line.kind == .addition { return GitForkTheme.green.opacity(0.11) }
        if line.kind == .deletion { return GitForkTheme.red.opacity(0.10) }
        if line.kind == .hunkHeader { return GitForkTheme.blue.opacity(0.08) }
        return .clear
    }

    private var accentBar: Color {
        if line.kind == .addition { return GitForkTheme.green.opacity(0.85) }
        if line.kind == .deletion { return GitForkTheme.red.opacity(0.85) }
        return .clear
    }

    private var displayText: String {
        line.displayText
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentBar)
                .frame(width: DiffLayout.accentBarWidth)

            lineNumber(line.oldLineNumber)
            lineNumber(line.newLineNumber)

            Divider()

            Group {
                if allowsTextSelection {
                    Text(displayText.isEmpty ? " " : displayText)
                        .textSelection(.enabled)
                } else {
                    Text(displayText.isEmpty ? " " : displayText)
                }
            }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(foreground)
                .padding(.horizontal, DiffLayout.textPadding)
                .frame(height: DiffLayout.rowHeight, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private func lineNumber(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.trailing, 5)
            .frame(
                width: DiffLayout.lineNumberWidth,
                height: DiffLayout.rowHeight,
                alignment: .trailing
            )
    }
}

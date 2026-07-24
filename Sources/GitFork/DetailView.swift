import AppKit
import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            if let commit = store.selectedCommit, store.selectedSection == .history {
                CommitHeader(commit: commit)
                Divider()
                DiffTextView(text: store.diff)
            } else if let change = store.selectedChange, store.selectedSection == .changes {
                ChangeHeader(change: change, staged: store.selectedChangeIsStaged)
                Divider()
                DiffTextView(
                    text: store.diff,
                    change: change,
                    staged: store.selectedChangeIsStaged
                )
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a commit or changed file to inspect it.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CommitHeader: View {
    let commit: GitCommit

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

            HStack(spacing: 12) {
                CopyableValue(label: "COMMIT", value: commit.hash, display: commit.shortHash)
                if let parent = commit.parents.first {
                    CopyableValue(label: "PARENT", value: parent, display: String(parent.prefix(8)))
                }
                if commit.parents.count > 1 {
                    Text("MERGE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GitForkTheme.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(GitForkTheme.purple.opacity(0.12), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(HeaderBackground())
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
    let change: WorkingChange
    let staged: Bool
    @State private var isConfirmingFileDiscard = false

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
                Text("\(change.displayStatus(staged: staged)) · \(staged ? "Staged" : "Working tree")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                staged ? store.unstage(change) : store.stage(change)
            } label: {
                Label(staged ? "Unstage" : "Stage", systemImage: staged ? "minus" : "plus")
            }
            .buttonStyle(GitForkHoverButtonStyle(.toolbarAction))
            .help(staged ? "Move this file back to working changes" : "Stage this file for commit")
            .disabled(store.isLoading)

            if !staged {
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
    }
}

private struct CopyableValue: View {
    let label: String
    let value: String
    let display: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
            Text(display)
                .font(.caption.monospaced())
        }
        .contextMenu {
            Button("Copy \(label.capitalized)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
        }
    }
}

private struct DiffTextView: View {
    @EnvironmentObject private var store: RepositoryStore
    let text: String
    var change: WorkingChange?
    var staged = false

    @State private var selectedDisplayLineIDs: Set<Int> = []
    @State private var selectedHunkID: Int?
    @State private var pendingDiscardLineIDs: Set<Int>?

    private var document: UnifiedDiff {
        UnifiedDiff(text)
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
            } else {
                GeometryReader { viewport in
                    ScrollView([.horizontal, .vertical]) {
                        Group {
                            if change != nil, !document.displayHunks.isEmpty {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(document.displayHunks) { hunk in
                                        DiffHunkView(
                                            hunk: hunk,
                                            selectedLineIDs: selectedHunkID == hunk.id
                                                ? selectedDisplayLineIDs
                                                : [],
                                            staged: staged,
                                            isLoading: store.isLoading,
                                            selectRange: { lineIDs in
                                                selectedHunkID = hunk.id
                                                selectedDisplayLineIDs = lineIDs
                                            },
                                            apply: apply,
                                            discard: requestDiscard
                                        )
                                    }
                                }
                                .padding(.vertical, 8)
                            } else if !document.files.isEmpty {
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    if !document.preambleLines.isEmpty {
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

                                    ForEach(document.files) { file in
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
                        .frame(
                            minWidth: viewport.size.width,
                            minHeight: viewport.size.height,
                            alignment: .topLeading
                        )
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .onChange(of: text) {
            clearSelection()
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

private struct CommitDiffFileView: View {
    let file: UnifiedDiffFile

    private var contentLines: ArraySlice<UnifiedDiffLine> {
        if file.lines.first?.text.hasPrefix("diff --git ") == true {
            return file.lines.dropFirst()
        }
        return file.lines[...]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "doc.text")
                    .foregroundStyle(GitForkTheme.blue)
                Text(file.path)
                    .font(.callout.monospaced().weight(.semibold))
                    .textSelection(.enabled)
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.primary.opacity(0.045))

            Divider()

            ForEach(contentLines) { line in
                DiffLineView(
                    line: line,
                    isRangeSelected: false,
                    allowsTextSelection: true
                )
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
    static let lineNumberWidth: CGFloat = 34
    static let accentBarWidth: CGFloat = 2.5
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
                VStack(alignment: .leading, spacing: 0) {
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
                if !targetLineIDs.isEmpty {
                    Button(staged ? "Unstage" : "Stage") {
                        apply(targetLineIDs)
                    }
                    .disabled(isLoading)
                    if !staged {
                        Divider()
                        Button("Discard Changes…", role: .destructive) {
                            discard(targetLineIDs)
                        }
                        .disabled(isLoading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 10)
        .onHover { isHovering = $0 }
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button(staged ? "Unstage" : "Stage") {
                apply(targetLineIDs)
            }
            .help(
                staged
                    ? "Unstage this selected hunk"
                    : "Stage this selected hunk"
            )

            if !staged {
                Button("Discard Changes…", role: .destructive) {
                    discard(targetLineIDs)
                }
                .help("Permanently discard this selected hunk after confirmation")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isLoading)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
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
        switch line.kind {
        case .context, .addition, .deletion:
            return String(line.text.dropFirst())
        default:
            return line.text
        }
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
                .padding(.horizontal, 9)
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

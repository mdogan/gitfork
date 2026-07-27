import Foundation

/// Stable identity for a row in the working-tree change list.
///
/// Git status characters change as a file moves between the index and the
/// working tree, so `WorkingChange.id` does not survive a refresh. Selection is
/// tracked by path and side instead.
struct ChangeEntryID: Hashable, Sendable {
    let path: String
    let staged: Bool
}

/// One row in the working-tree change list: a file plus the side it is listed
/// under. A partially staged file appears on both sides.
struct ChangeEntry: Hashable, Identifiable, Sendable {
    let change: WorkingChange
    let staged: Bool

    init(_ change: WorkingChange, staged: Bool) {
        self.change = change
        self.staged = staged
    }

    var id: ChangeEntryID {
        ChangeEntryID(path: change.path, staged: staged)
    }
}

enum ChangeSelectionKey: Sendable {
    case returnKey
    case deleteKey
}

enum ChangeSelectionAction: Sendable {
    case stage
    case unstage
}

extension Array where Element == ChangeEntry {
    /// Rows listed under "Unstaged Changes": the ones `git add` and a discard
    /// apply to.
    var unstagedSide: [ChangeEntry] {
        filter { !$0.staged }
    }

    /// Rows listed under "Staged Changes": the ones `git restore --staged`
    /// applies to.
    var stagedSide: [ChangeEntry] {
        filter(\.staged)
    }

    var paths: [String] {
        map(\.change.path)
    }
}

/// Multi-selection for the change list: which rows are selected, which row
/// drives the diff pane, and the anchor a shift-click extends from.
struct ChangeSelectionModel: Equatable, Sendable {
    private(set) var selected: Set<ChangeEntryID> = []
    /// The row whose diff the detail pane shows. Always a member of `selected`
    /// unless nothing is selected.
    private(set) var primary: ChangeEntryID?
    private(set) var anchor: ChangeEntryID?

    var count: Int { selected.count }
    var isEmpty: Bool { selected.isEmpty }

    func contains(_ id: ChangeEntryID) -> Bool {
        selected.contains(id)
    }

    /// Return stages from the unstaged section; Delete unstages from the staged
    /// section. Other key/section combinations intentionally do nothing.
    func keyboardAction(for key: ChangeSelectionKey) -> ChangeSelectionAction? {
        guard let primary else { return nil }
        switch (key, primary.staged) {
        case (.returnKey, false):
            return .stage
        case (.deleteKey, true):
            return .unstage
        default:
            return nil
        }
    }

    /// Replaces the selection with a single row: a plain click.
    mutating func select(_ id: ChangeEntryID?) {
        selected = id.map { [$0] } ?? []
        primary = id
        anchor = id
    }

    mutating func clear() {
        select(nil)
    }

    /// Adds or removes one row and leaves the rest alone: a Command-click.
    mutating func toggle(_ id: ChangeEntryID, in order: [ChangeEntryID]) {
        if selected.contains(id) {
            selected.remove(id)
            if primary == id {
                primary = order.first(where: selected.contains)
            }
        } else {
            selected.insert(id)
            primary = id
        }
        anchor = id
    }

    /// Selects every row between the anchor and `id`: a Shift-click.
    /// Successive shift-clicks keep pivoting on the same anchor, as in Finder.
    mutating func extend(to id: ChangeEntryID, in order: [ChangeEntryID]) {
        guard let pivot = anchor ?? primary,
              let start = order.firstIndex(of: pivot),
              let end = order.firstIndex(of: id) else {
            select(id)
            return
        }
        let bounds = start <= end ? start...end : end...start
        selected = Set(order[bounds])
        primary = id
        anchor = pivot
    }

    /// Rebuilds the selection after a repository refresh. `survivor` maps a
    /// selected row to the row that now represents the same file — a staged
    /// file moves to the other side instead of losing its selection — or to
    /// `nil` once the file has no changes left.
    mutating func reconcile(
        order: [ChangeEntryID],
        survivor: (ChangeEntryID) -> ChangeEntryID?
    ) {
        let live = Set(order)
        selected = Set(selected.compactMap(survivor).filter(live.contains))
        primary = surviving(primary, survivor: survivor)
            ?? order.first(where: selected.contains)
        anchor = surviving(anchor, survivor: survivor) ?? primary
    }

    private func surviving(
        _ id: ChangeEntryID?,
        survivor: (ChangeEntryID) -> ChangeEntryID?
    ) -> ChangeEntryID? {
        guard let id, let candidate = survivor(id), selected.contains(candidate) else {
            return nil
        }
        return candidate
    }
}

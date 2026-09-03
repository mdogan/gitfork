import Foundation
import Testing
@testable import GitFork

struct RepositorySwitcherTests {
    @Test
    func filtersRepositoriesByNameAndPath() {
        let repositories = [
            URL(fileURLWithPath: "/Users/example/Projects/GitFork"),
            URL(fileURLWithPath: "/Users/example/Work/redis-server"),
            URL(fileURLWithPath: "/tmp/other")
        ]

        #expect(
            RepositorySwitcherSearch.filter(repositories, query: "gitfork")
                == [repositories[0]]
        )
        #expect(
            RepositorySwitcherSearch.filter(repositories, query: "WORK")
                == [repositories[1]]
        )
        #expect(
            RepositorySwitcherSearch.filter(repositories, query: "  ")
                == repositories
        )
        #expect(
            RepositorySwitcherSearch.filter(repositories, query: "missing")
                .isEmpty
        )
    }

    @Test
    func selectsAnAlternativeRepositoryAndPreservesMatchingSelection() {
        let current = URL(fileURLWithPath: "/repos/current")
        let other = URL(fileURLWithPath: "/repos/other")
        let third = URL(fileURLWithPath: "/repos/third")
        let repositories = [current, other, third]

        #expect(
            RepositorySwitcherNavigation.reconcile(
                selection: nil,
                repositories: repositories,
                currentRepository: current
            ) == other
        )
        #expect(
            RepositorySwitcherNavigation.reconcile(
                selection: third,
                repositories: [current, third],
                currentRepository: current
            ) == third
        )
        #expect(
            RepositorySwitcherNavigation.reconcile(
                selection: other,
                repositories: [current, third],
                currentRepository: current
            ) == third
        )
    }

    @Test
    func movesSelectionAndWrapsAtBothEnds() {
        let first = URL(fileURLWithPath: "/repos/first")
        let second = URL(fileURLWithPath: "/repos/second")
        let third = URL(fileURLWithPath: "/repos/third")
        let repositories = [first, second, third]

        #expect(
            RepositorySwitcherNavigation.move(
                selection: first,
                offset: 1,
                repositories: repositories
            ) == second
        )
        #expect(
            RepositorySwitcherNavigation.move(
                selection: first,
                offset: -1,
                repositories: repositories
            ) == third
        )
        #expect(
            RepositorySwitcherNavigation.move(
                selection: third,
                offset: 1,
                repositories: repositories
            ) == first
        )
        #expect(
            RepositorySwitcherNavigation.move(
                selection: nil,
                offset: -1,
                repositories: repositories
            ) == third
        )
        #expect(
            RepositorySwitcherNavigation.move(
                selection: first,
                offset: 1,
                repositories: []
            ) == nil
        )
    }

    @Test
    func worktreeSwitcherRequiresMultipleSelectableWorktrees() {
        let current = worktree(path: "/repos/main", branch: "refs/heads/main", isCurrent: true)
        let linked = worktree(path: "/repos/feature", branch: "refs/heads/feature")
        let stale = worktree(path: "/repos/stale", isPrunable: true)
        let bare = worktree(path: "/repos/bare.git", isBare: true)

        #expect(!WorktreeSwitcherOptions.shouldShow(for: [current]))
        #expect(!WorktreeSwitcherOptions.shouldShow(for: [current, stale, bare]))
        #expect(WorktreeSwitcherOptions.shouldShow(for: [current, linked, stale, bare]))
        #expect(
            WorktreeSwitcherOptions.selectable(from: [current, linked, stale, bare])
                == [current, linked]
        )
        #expect(WorktreeSwitcherOptions.current(in: [current, linked]) == current)
    }

    @Test
    func worktreeSwitcherLabelsBranchesAndDetachedHeads() {
        let branch = worktree(path: "/repos/feature-ui", branch: "refs/heads/feature/ui")
        let detached = worktree(
            path: "/repos/review",
            head: "1234567890abcdef",
            isDetached: true
        )

        #expect(WorktreeSwitcherOptions.currentLabel(for: branch) == "feature/ui")
        #expect(WorktreeSwitcherOptions.currentLabel(for: detached) == "Detached")
        #expect(
            WorktreeSwitcherOptions.optionLabel(for: branch)
                == "feature/ui — feature-ui"
        )
        #expect(
            WorktreeSwitcherOptions.optionLabel(for: detached)
                == "Detached at 12345678 — review"
        )
    }

    private func worktree(
        path: String,
        head: String? = nil,
        branch: String? = nil,
        isBare: Bool = false,
        isDetached: Bool = false,
        isPrunable: Bool = false,
        isCurrent: Bool = false
    ) -> GitWorktree {
        GitWorktree(
            path: path,
            head: head,
            branch: branch,
            isBare: isBare,
            isDetached: isDetached,
            isLocked: false,
            isPrunable: isPrunable,
            isCurrent: isCurrent
        )
    }
}

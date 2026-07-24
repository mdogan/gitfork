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
}

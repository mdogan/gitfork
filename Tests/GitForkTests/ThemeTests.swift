import Testing
@testable import GitFork

struct RepositoryColorTests {
    @Test
    func keepsRedisServerBlue() {
        #expect(
            GitForkTheme.repositoryColor(for: "redis-server")
                == GitForkTheme.blue
        )
        #expect(
            GitForkTheme.repositoryColor(for: "REDIS-SERVER")
                == GitForkTheme.blue
        )
    }

    @Test
    func derivesStableColorsFromRepositoryNames() {
        #expect(
            GitForkTheme.repositoryColor(for: "GitFork")
                == GitForkTheme.repositoryColor(for: "gitfork")
        )
        #expect(
            GitForkTheme.repositoryColor(for: "GitFork")
                != GitForkTheme.repositoryColor(for: "redis-server")
        )
    }
}

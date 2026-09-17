import Foundation
import Testing
@testable import GitFork

struct RepositoryWindowValueTests {
    @Test
    func standardizesRepositoryPaths() {
        let value = RepositoryWindowValue(
            URL(fileURLWithPath: "/tmp/repos/./project/")
        )

        #expect(value.path == "/tmp/repos/project")
        #expect(value == RepositoryWindowValue(URL(fileURLWithPath: "/tmp/repos/project")))
    }

    @Test
    func roundTripsThroughWindowRestoration() throws {
        let value = RepositoryWindowValue(URL(fileURLWithPath: "/tmp/repos/project"))
        let data = try JSONEncoder().encode(value)

        #expect(try JSONDecoder().decode(RepositoryWindowValue.self, from: data) == value)
    }
}

struct RepositoryWindowRoutingTests {
    private let root = URL(fileURLWithPath: "/tmp/repos/project")

    @Test
    func staysPutWhenTheAskingWindowAlreadyShowsTheRepository() {
        #expect(
            RepositoryWindowRouting.destination(
                root: root,
                currentRepository: URL(fileURLWithPath: "/tmp/repos/project/"),
                isOpenInAnotherWindow: false
            ) == .currentWindow
        )
    }

    @Test
    func focusesTheWindowThatAlreadyShowsTheRepository() {
        #expect(
            RepositoryWindowRouting.destination(
                root: root,
                currentRepository: URL(fileURLWithPath: "/tmp/repos/other"),
                isOpenInAnotherWindow: true
            ) == .existingWindow
        )

        #expect(
            RepositoryWindowRouting.destination(
                root: root,
                currentRepository: nil,
                isOpenInAnotherWindow: true
            ) == .existingWindow
        )
    }

    @Test
    func emptyWindowAdoptsTheRepository() {
        #expect(
            RepositoryWindowRouting.destination(
                root: root,
                currentRepository: nil,
                isOpenInAnotherWindow: false
            ) == .adoptInCurrentWindow
        )
    }

    @Test
    func anotherRepositoryOpensANewWindow() {
        #expect(
            RepositoryWindowRouting.destination(
                root: root,
                currentRepository: URL(fileURLWithPath: "/tmp/repos/other"),
                isOpenInAnotherWindow: false
            ) == .newWindow
        )
    }
}

struct NewWindowFrameTests {
    @Test
    func takesTheSourceSizeWithoutMovingTheTopLeftCorner() {
        let placed = CGRect(x: 120, y: 200, width: 1380, height: 840)

        let frame = NewWindowFrame.frame(
            placing: placed,
            at: CGSize(width: 1600, height: 1000)
        )

        #expect(frame.width == 1600)
        #expect(frame.height == 1000)
        #expect(frame.minX == placed.minX)
        #expect(frame.maxY == placed.maxY)
    }

    @Test
    func keepsTheTopLeftCornerWhenTheSourceWindowIsSmaller() {
        let placed = CGRect(x: 120, y: 200, width: 1380, height: 840)

        let frame = NewWindowFrame.frame(
            placing: placed,
            at: CGSize(width: 1000, height: 600)
        )

        #expect(frame.minX == placed.minX)
        #expect(frame.maxY == placed.maxY)
        #expect(frame.minY == placed.maxY - 600)
    }
}

struct ExternalURLClaimsTests {
    private let url = URL(string: "gitfork://open?path=/tmp/repos/project")!
    private let other = URL(string: "gitfork://open?path=/tmp/repos/other")!
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test
    func firstWindowClaimsTheURL() {
        var claims = ExternalURLClaims()
        let claimed = claims.claim(url, at: start)

        #expect(claimed)
    }

    @Test
    func ignoresTheSameURLDeliveredToOtherWindows() {
        var claims = ExternalURLClaims()
        let first = claims.claim(url, at: start)
        let sameInstant = claims.claim(url, at: start)
        let shortlyAfter = claims.claim(url, at: start.addingTimeInterval(0.2))

        #expect(first)
        #expect(!sameInstant)
        #expect(!shortlyAfter)
    }

    @Test
    func claimsADifferentURLImmediately() {
        var claims = ExternalURLClaims()
        let first = claims.claim(url, at: start)
        let second = claims.claim(other, at: start.addingTimeInterval(0.1))

        #expect(first)
        #expect(second)
    }

    @Test
    func claimsTheSameURLAgainAfterTheInterval() {
        var claims = ExternalURLClaims()
        let first = claims.claim(url, at: start)
        let later = claims.claim(
            url,
            at: start.addingTimeInterval(ExternalURLClaims.interval)
        )

        #expect(first)
        #expect(later)
    }
}

struct ExternalURLWindowCleanupTests {
    @Test
    func startsPendingCleanupDuringAnEmptyColdLaunch() {
        #expect(
            ExternalURLWindowCleanup.shouldStartPendingCleanup(
                paths: [nil]
            )
        )
    }

    @Test
    func preservesWindowsOnceARepositoryIsOpen() {
        #expect(
            !ExternalURLWindowCleanup.shouldStartPendingCleanup(
                paths: [nil, "/tmp/repos/project"]
            )
        )
    }
}

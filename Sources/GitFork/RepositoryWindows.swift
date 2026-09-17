import AppKit
import SwiftUI

/// The repository a window shows. `WindowGroup(for:)` brings an open window to
/// the front when `openWindow(value:)` passes a value that window already
/// presents, so this value is also the identity of a repository window.
struct RepositoryWindowValue: Codable, Hashable {
    let path: String

    init(_ url: URL) {
        path = url.standardizedFileURL.path
    }

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// Where a repository belongs once the window layer resolves its root.
enum RepositoryWindowDestination: Equatable {
    /// The asking window already shows the repository.
    case currentWindow
    /// Another window shows the repository and only needs to be brought forward.
    case existingWindow
    /// The asking window has no repository yet, so it adopts this one.
    case adoptInCurrentWindow
    case newWindow
}

enum RepositoryWindowRouting {
    /// One repository is never open in two windows: an already-open repository
    /// wins, an empty window adopts, and everything else opens a new window.
    static func destination(
        root: URL,
        currentRepository: URL?,
        isOpenInAnotherWindow: Bool
    ) -> RepositoryWindowDestination {
        if currentRepository?.standardizedFileURL.path == root.standardizedFileURL.path {
            return .currentWindow
        }
        if isOpenInAnotherWindow {
            return .existingWindow
        }
        return currentRepository == nil ? .adoptInCurrentWindow : .newWindow
    }
}

/// SwiftUI can hand the same `gitfork://` URL to every open window. The first
/// window claims it; repeats of the same URL within the claim interval are
/// duplicate deliveries and are ignored.
struct ExternalURLClaims {
    static let interval: TimeInterval = 1

    private var last: (url: URL, at: Date)?

    mutating func claim(_ url: URL, at now: Date = .now) -> Bool {
        if let last,
           last.url == url,
           now.timeIntervalSince(last.at) < Self.interval,
           now >= last.at {
            return false
        }

        last = (url, now)
        return true
    }
}

/// Tracks which window shows which repository. `openWindow(value:)` already
/// reuses the window it opened for a value, but a window that adopts a
/// repository after opening empty — or one opened from a subdirectory path — is
/// only known here.
@MainActor
final class RepositoryWindowRegistry {
    static let shared = RepositoryWindowRegistry()

    private struct Entry {
        weak var window: NSWindow?
        var path: String?
    }

    private var entries: [Entry] = []
    private var claims = ExternalURLClaims()
    private weak var pendingExternalURLWindow: NSWindow?
    private var pendingExternalURLCleanupDeadline: Date?
    private var pendingWindowSize: CGSize?
    private var closeObserver: NSObjectProtocol?

    private init() {
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated {
                self?.forget(window)
            }
        }
    }

    /// Records the repository `window` shows, including empty windows so a
    /// duplicate created during a custom-URL launch can be identified.
    func update(window: NSWindow?, repository: URL?) {
        entries.removeAll { $0.window == nil || $0.window === window }
        guard let window else { return }
        entries.append(
            Entry(window: window, path: repository?.standardizedFileURL.path)
        )
        finishPendingExternalURLCleanupIfNeeded()
    }

    func isOpen(_ repository: RepositoryWindowValue, excluding window: NSWindow?) -> Bool {
        self.window(showing: repository, excluding: window) != nil
    }

    /// Brings the window that already shows `repository` to the front.
    func focus(_ repository: RepositoryWindowValue, excluding window: NSWindow?) {
        guard let target = self.window(showing: repository, excluding: window) else { return }
        NSApplication.shared.activate()
        if target.isMiniaturized {
            target.deminiaturize(nil)
        }
        target.makeKeyAndOrderFront(nil)
    }

    func claimExternalURL(_ url: URL) -> Bool {
        claims.claim(url)
    }

    /// Newer macOS releases can create both the URL-targeted repository window
    /// and the app's default welcome window during a cold launch. Close only
    /// redundant empty windows; once any repository is open, preserve every
    /// user-created window.
    func closeDuplicateEmptyWindows(excluding window: NSWindow) {
        entries.removeAll { $0.window == nil }
        guard ExternalURLWindowCleanup.shouldStartPendingCleanup(
            paths: entries.map(\.path)
        ) else {
            return
        }

        pendingExternalURLWindow = window
        pendingExternalURLCleanupDeadline = .now.addingTimeInterval(2)
        finishPendingExternalURLCleanupIfNeeded()
    }

    /// Hands the size of the window a new window is opened from to that window,
    /// so a repository opens at the size the user is already working at. Call
    /// immediately before `openWindow`; the next repository window takes it.
    func prepareWindowSize(from window: NSWindow?) {
        let source = window?.sheetParent ?? window
        pendingWindowSize = source?.frame.size
    }

    /// Resizes a freshly opened window to the size of the window it came from,
    /// keeping the corner SwiftUI placed it at.
    func adoptPendingWindowSize(_ window: NSWindow) {
        guard let size = pendingWindowSize else { return }
        pendingWindowSize = nil
        guard window.frame.size != size else { return }

        let frame = NewWindowFrame.frame(placing: window.frame, at: size)
        window.setFrame(
            window.screen.map { window.constrainFrameRect(frame, to: $0) } ?? frame,
            display: true
        )
    }

    private func window(
        showing repository: RepositoryWindowValue,
        excluding window: NSWindow?
    ) -> NSWindow? {
        entries.removeAll { $0.window == nil }
        return entries.first {
            $0.path == repository.path && $0.window !== window
        }?.window
    }

    private func forget(_ window: NSWindow?) {
        entries.removeAll { $0.window == nil || $0.window === window }
    }

    private func finishPendingExternalURLCleanupIfNeeded(at now: Date = .now) {
        guard let pendingExternalURLWindow,
              let deadline = pendingExternalURLCleanupDeadline,
              now <= deadline else {
            self.pendingExternalURLWindow = nil
            pendingExternalURLCleanupDeadline = nil
            return
        }

        let duplicates = entries.compactMap { entry -> NSWindow? in
            guard entry.path == nil, entry.window !== pendingExternalURLWindow else {
                return nil
            }
            return entry.window
        }
        guard !duplicates.isEmpty else { return }

        self.pendingExternalURLWindow = nil
        pendingExternalURLCleanupDeadline = nil
        duplicates.forEach { $0.close() }
    }
}

enum ExternalURLWindowCleanup {
    static func shouldStartPendingCleanup(paths: [String?]) -> Bool {
        !paths.contains { $0 != nil }
    }
}

enum NewWindowFrame {
    /// Grows a window from its top-left corner, which is where SwiftUI cascades
    /// a new window and the corner a resize should not move.
    static func frame(placing frame: CGRect, at size: CGSize) -> CGRect {
        CGRect(
            x: frame.minX,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

/// Reports the AppKit window hosting a SwiftUI window's content, so a window
/// can register the repository it shows and be brought forward later.
struct HostingWindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onChange(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onChange(view.window) }
    }
}

enum RepositoryOpenPanel {
    /// Runs the repository chooser. Returns `nil` when the user cancels.
    static func run() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Git Repository"
        panel.message = "Choose a folder containing a Git repository."
        panel.prompt = "Open Repository"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

import AppKit
import Combine

@MainActor
final class RepositoryTabCoordinator: ObservableObject {
    private final class WindowRegistration {
        weak var window: NSWindow?
        var repositoryPath: String

        init(window: NSWindow, repositoryPath: String) {
            self.window = window
            self.repositoryPath = repositoryPath
        }
    }

    private final class PendingTab {
        weak var sourceWindow: NSWindow?
        let repositoryPath: String

        init(sourceWindow: NSWindow?, repositoryPath: String) {
            self.sourceWindow = sourceWindow
            self.repositoryPath = repositoryPath
        }
    }

    private var registrations: [UUID: WindowRegistration] = [:]
    private var pendingTabs: [PendingTab] = []
    private var claimedRequestIDs: Set<UUID> = []

    @discardableResult
    func register(
        tabID: UUID,
        repositoryPath: String,
        window: NSWindow
    ) -> String? {
        let isNewTab = registrations[tabID] == nil
        registrations[tabID] = WindowRegistration(
            window: window,
            repositoryPath: repositoryPath
        )

        guard isNewTab,
              repositoryPath.isEmpty,
              !pendingTabs.isEmpty else {
            return nil
        }

        let pendingTab = pendingTabs.removeFirst()
        registrations[tabID]?.repositoryPath = pendingTab.repositoryPath
        attach(window: window, to: pendingTab.sourceWindow)
        return pendingTab.repositoryPath
    }

    func update(tabID: UUID, repositoryPath: String) {
        registrations[tabID]?.repositoryPath = repositoryPath
    }

    func claim(requestID: UUID, for tabID: UUID) -> Bool {
        pruneRegistrations()
        guard !claimedRequestIDs.contains(requestID) else { return false }

        let keyTabID = registrations.first {
            $0.value.window?.isKeyWindow == true
        }?.key
        let mainTabID = registrations.first {
            $0.value.window === NSApp.mainWindow
        }?.key
        let targetTabID = keyTabID ?? mainTabID ?? registrations.keys.first
        guard targetTabID == tabID else {
            return false
        }

        claimedRequestIDs.insert(requestID)
        return true
    }

    func complete(requestID: UUID) {
        claimedRequestIDs.remove(requestID)
    }

    func focusTab(presenting repositoryPath: String) -> Bool {
        pruneRegistrations()
        guard let window = registrations.values.first(where: {
            $0.repositoryPath == repositoryPath
        })?.window else {
            return false
        }

        pendingTabs.removeAll { $0.repositoryPath == repositoryPath }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func prepareNewTab(repositoryPath: String, sourceTabID: UUID) {
        pruneRegistrations()
        let sourceWindow = registrations[sourceTabID]?.window ?? NSApp.keyWindow
        pendingTabs.append(
            PendingTab(
                sourceWindow: sourceWindow,
                repositoryPath: repositoryPath
            )
        )
    }

    private func attach(window: NSWindow, to sourceWindow: NSWindow?) {
        guard let sourceWindow, sourceWindow !== window else {
            return
        }

        Task { @MainActor [weak sourceWindow, weak window] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let sourceWindow, let window else { return }

            for attempt in 0..<2 {
                if sourceWindow.tabbedWindows?.contains(where: {
                    $0 === window
                }) == true {
                    break
                }

                sourceWindow.tabbingMode = .preferred
                window.tabbingMode = .preferred
                window.tabbingIdentifier = sourceWindow.tabbingIdentifier
                sourceWindow.addTabbedWindow(window, ordered: .above)

                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func pruneRegistrations() {
        registrations = registrations.filter { $0.value.window != nil }
    }
}

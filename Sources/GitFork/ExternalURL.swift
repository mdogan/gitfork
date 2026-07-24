import Foundation

enum GitForkExternalURL {
    static let scheme = "gitfork"
    static let openHost = "open"

    static func repositoryPath(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == openHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              path.hasPrefix("/")
        else {
            return nil
        }

        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

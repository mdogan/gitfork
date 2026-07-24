import SwiftUI

enum GitForkTheme {
    static let accent = Color(red: 0.94, green: 0.50, blue: 0.18)
    static let blue = Color(red: 0.24, green: 0.55, blue: 0.96)
    static let green = Color(red: 0.25, green: 0.70, blue: 0.42)
    static let red = Color(red: 0.88, green: 0.32, blue: 0.31)
    static let purple = Color(red: 0.57, green: 0.42, blue: 0.82)
}

extension Color {
    static func statusColor(_ status: String) -> Color {
        switch status {
        case "A": GitForkTheme.green
        case "D": GitForkTheme.red
        case "R": GitForkTheme.purple
        case "U": .orange
        default: GitForkTheme.blue
        }
    }
}

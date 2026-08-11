import SwiftUI

enum GitForkTheme {
    static let accent = Color(red: 0.24, green: 0.55, blue: 0.96)
    static let blue = Color(red: 0.24, green: 0.55, blue: 0.96)
    static let green = Color(red: 0.22, green: 0.71, blue: 0.44)
    static let red = Color(red: 0.88, green: 0.33, blue: 0.33)
    static let purple = Color(red: 0.58, green: 0.43, blue: 0.84)
    static let orange = Color(red: 0.95, green: 0.56, blue: 0.24)

    /// A curated, harmonious palette used to give authors and labels a stable,
    /// recognizable color. Kept mid-saturation so white glyphs stay legible.
    static let identityPalette: [Color] = [
        Color(red: 0.90, green: 0.35, blue: 0.42),  // rose
        Color(red: 0.95, green: 0.56, blue: 0.24),  // orange
        Color(red: 0.89, green: 0.68, blue: 0.24),  // amber
        Color(red: 0.28, green: 0.72, blue: 0.46),  // green
        Color(red: 0.20, green: 0.68, blue: 0.66),  // teal
        Color(red: 0.28, green: 0.56, blue: 0.94),  // blue
        Color(red: 0.42, green: 0.48, blue: 0.90),  // indigo
        Color(red: 0.60, green: 0.42, blue: 0.85),  // purple
        Color(red: 0.90, green: 0.42, blue: 0.68)   // pink
    ]

    /// Deterministically maps a seed (e.g. an author name) to a palette color,
    /// so the same person keeps the same color across launches.
    static func identityColor(for seed: String) -> Color {
        guard !identityPalette.isEmpty else { return accent }
        var hash: UInt64 = 1469598103934665603  // FNV-1a offset basis
        for byte in seed.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return identityPalette[Int(hash % UInt64(identityPalette.count))]
    }

    /// Gives each repository name a stable window-toolbar color. Keep the
    /// redis-server repository on GitFork's original blue accent while other
    /// names use the same curated deterministic palette as identities.
    static func repositoryColor(for name: String) -> Color {
        if name.caseInsensitiveCompare("redis-server") == .orderedSame {
            return blue
        }
        return identityColor(for: name)
    }

    /// Foreground for added diff lines, tuned for legibility in each appearance.
    static func diffAddition(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.49, green: 0.86, blue: 0.58)
            : Color(red: 0.11, green: 0.53, blue: 0.27)
    }

    /// Foreground for removed diff lines, tuned for legibility in each appearance.
    static func diffDeletion(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.96, green: 0.51, blue: 0.51)
            : Color(red: 0.78, green: 0.18, blue: 0.18)
    }
}

/// A colorful, deterministic avatar built from a person's initials. The fill
/// color is derived from `name`, so each author is visually recognizable.
struct IdentityAvatar: View {
    let name: String
    let initials: String
    var size: CGFloat = 18

    private var color: Color { GitForkTheme.identityColor(for: name) }

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: max(7, size * 0.42), weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
            }
            .overlay {
                Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            }
            .shadow(color: color.opacity(0.35), radius: size * 0.08, y: 0.5)
    }
}

enum GitForkHoverButtonVariant {
    case toolbarAction
    case icon
    case text
    case row(isSelected: Bool)
    case compactRow(isSelected: Bool)
}

struct GitForkHoverButtonStyle: ButtonStyle {
    let variant: GitForkHoverButtonVariant

    init(_ variant: GitForkHoverButtonVariant) {
        self.variant = variant
    }

    func makeBody(configuration: Configuration) -> some View {
        GitForkHoverButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            variant: variant
        )
    }
}

private struct GitForkHoverButtonBody<Label: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let label: Label
    let isPressed: Bool
    let variant: GitForkHoverButtonVariant

    var body: some View {
        label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(
                maxWidth: expandsHorizontally ? .infinity : nil,
                alignment: .leading
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(isPressed && isEnabled ? 0.97 : 1)
            .onHover { hovering in
                isHovering = hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private var expandsHorizontally: Bool {
        switch variant {
        case .row, .compactRow: true
        default: false
        }
    }

    private var horizontalPadding: CGFloat {
        switch variant {
        case .toolbarAction: 7
        case .icon: 5
        case .text: 6
        case .row: 7
        case .compactRow: 5
        }
    }

    private var verticalPadding: CGFloat {
        switch variant {
        case .toolbarAction: 5
        case .icon: 4
        case .text: 3
        case .row: 5
        case .compactRow: 2
        }
    }

    private var cornerRadius: CGFloat {
        switch variant {
        case .row: 7
        case .compactRow: 6
        default: 6
        }
    }

    private var backgroundColor: Color {
        if isPressed && isEnabled {
            return GitForkTheme.accent.opacity(0.24)
        }

        switch variant {
        case let .row(isSelected), let .compactRow(isSelected):
            if isSelected {
                return GitForkTheme.accent.opacity(isHovering ? 0.21 : 0.13)
            }
            return isHovering ? neutralHoverColor : .clear

        case .toolbarAction, .icon:
            return isHovering && isEnabled
                ? GitForkTheme.accent.opacity(0.14)
                : .clear

        case .text:
            return isHovering && isEnabled
                ? GitForkTheme.accent.opacity(0.12)
                : .clear
        }
    }

    private var borderColor: Color {
        guard isHovering && isEnabled else { return .clear }
        switch variant {
        case .row, .compactRow:
            return GitForkTheme.accent.opacity(0.24)
        case .toolbarAction, .icon, .text:
            return GitForkTheme.accent.opacity(0.34)
        }
    }

    private var neutralHoverColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.065)
    }
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

import SwiftUI

enum GitForkTheme {
    static let accent = Color(red: 0.24, green: 0.55, blue: 0.96)
    static let blue = Color(red: 0.24, green: 0.55, blue: 0.96)
    static let green = Color(red: 0.25, green: 0.70, blue: 0.42)
    static let red = Color(red: 0.88, green: 0.32, blue: 0.31)
    static let purple = Color(red: 0.57, green: 0.42, blue: 0.82)
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

import AppKit
import SwiftUI

/// The windows' colors, taken from the user's Ghostty theme so GitFork matches
/// their terminal. Follows the system appearance for themes with a light and a
/// dark side, and reloads the config whenever the app becomes active.
@MainActor
@Observable
final class Look {
    static let shared = Look()

    private(set) var colors: TerminalColors
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    private init() {
        colors = GhosttyConfig.colors(dark: Self.systemIsDark)
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func reload() {
        let new = GhosttyConfig.colors(dark: Self.systemIsDark)
        if new != colors { colors = new }
    }

    var isDark: Bool { colors.isDark }
    var background: Color { Color(colors.background) }
    /// A little apart from the main surface, toward the text color.
    var sidebar: Color { Color(colors.background.mixed(with: colors.foreground, isDark ? 0.045 : 0.035)) }
    var text: Color { Color(colors.foreground) }
    var secondary: Color { Color(colors.foreground).opacity(0.58) }
    var hover: Color { Color(colors.foreground).opacity(0.05) }
    var fieldBackground: Color { Color(colors.foreground).opacity(0.07) }
    var divider: Color { Color(colors.foreground).opacity(0.12) }

    private func ansi(_ index: Int, _ fallback: RGB) -> Color {
        Color(colors.palette[index] ?? fallback)
    }

    var accent: Color { ansi(4, isDark ? RGB(0.47, 0.63, 1) : RGB(0.18, 0.37, 0.84)) }
    var green: Color { ansi(2, isDark ? RGB(0.47, 0.78, 0.55) : RGB(0.1, 0.53, 0.25)) }
    var yellow: Color { ansi(3, isDark ? RGB(0.9, 0.75, 0.24) : RGB(0.65, 0.41, 0)) }
    var red: Color { ansi(1, isDark ? RGB(0.94, 0.4, 0.4) : RGB(0.75, 0.15, 0.15)) }
    var magenta: Color { ansi(5, isDark ? RGB(0.73, 0.52, 0.93) : RGB(0.48, 0.24, 0.62)) }

    /// Makes the window chrome match: its background shows behind the content,
    /// and its appearance sets light or dark controls for the theme.
    func style(_ window: NSWindow) {
        window.backgroundColor = NSColor(colors.background)
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        if window.appearance?.name != appearance?.name { window.appearance = appearance }
    }
}

extension Color {
    init(_ c: RGB) {
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b)
    }
}

extension NSColor {
    convenience init(_ c: RGB) {
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }
}

/// Paints a window in the Ghostty theme: text, accent, background, and the
/// window's own background and light or dark appearance.
private struct LookWindowStyle: ViewModifier {
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        let look = Look.shared
        content
            .foregroundStyle(look.text)
            .tint(look.accent)
            .background(look.background)
            .background(
                HostingWindowReader { window in
                    if self.window !== window { self.window = window }
                    if let window { look.style(window) }
                }
            )
            .onChange(of: look.colors) { _, _ in
                if let window { look.style(window) }
            }
    }
}

/// A text field drawn on the theme instead of the system's white box with a
/// blue focus ring: a faint fill, and an accent border while it has focus.
private struct LookField: ViewModifier {
    let isFocused: Bool
    let systemImage: String?

    func body(content: Content) -> some View {
        let look = Look.shared
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(isFocused ? look.accent : look.secondary)
            }
            content
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(look.fieldBackground, in: shape)
        .overlay(
            shape.strokeBorder(
                isFocused ? look.accent.opacity(0.75) : look.divider,
                lineWidth: isFocused ? 1.5 : 1
            )
        )
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

extension View {
    /// Apply last, after `.focused` and key handlers, to a `TextField`.
    func lookField(isFocused: Bool, systemImage: String? = nil) -> some View {
        modifier(LookField(isFocused: isFocused, systemImage: systemImage))
    }

    func lookWindowStyle() -> some View {
        modifier(LookWindowStyle())
    }

    /// A list drawn on a theme surface instead of the system one.
    func lookListBackground(_ color: Color) -> some View {
        scrollContentBackground(.hidden)
            .background(color)
    }
}

/// A `List` row's background in the theme: a soft accent fill when selected,
/// like the sidebar rows. It also turns off the system selection highlight,
/// whose blue and white text ignore the theme and hide the row's own colors.
struct LookListRowBackground: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isSelected ? Look.shared.accent.opacity(0.20) : .clear)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(SystemSelectionHighlightRemover())
    }
}

/// Finds the table that AppKit hosts a `List` in and stops it drawing its
/// selection. Selection, keyboard navigation, and clicks keep working; if the
/// table is not found, the list keeps the system highlight.
struct SystemSelectionHighlightRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        RemoverView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? RemoverView)?.hideSelection()
    }

    private final class RemoverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideSelection()
        }

        func hideSelection() {
            var view = superview
            while let current = view {
                if let table = current as? NSTableView {
                    if table.selectionHighlightStyle != .none {
                        table.selectionHighlightStyle = .none
                    }
                    return
                }
                view = current.superview
            }
        }
    }
}

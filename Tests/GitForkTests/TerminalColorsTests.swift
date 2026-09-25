import Foundation
import Testing
@testable import GitFork

struct TerminalColorsTests {
    @Test
    func readsHexColors() {
        #expect(RGB(hex: "#FF0000") == RGB(1, 0, 0))
        #expect(RGB(hex: "00ff00") == RGB(0, 1, 0))
        #expect(RGB(hex: "red") == nil)
        #expect(RGB(hex: "#FFF") == nil)
    }

    @Test
    func appliesThemeThenOwnSettings() {
        let config = """
        # comment
        theme = Violet Light
        foreground = #111111
        palette = 4=#2e8bce
        """
        let theme = """
        background = #fcf4dc
        foreground = #536870
        palette = 1=#c94c22
        palette = 4=#000000
        """
        var asked: String?
        let colors = TerminalColors.from(config: config, dark: false) { name in
            asked = name
            return theme
        }
        #expect(asked == "Violet Light")
        #expect(colors.background == RGB(hex: "fcf4dc"))
        #expect(colors.foreground == RGB(hex: "111111"))
        #expect(colors.palette[1] == RGB(hex: "c94c22"))
        #expect(colors.palette[4] == RGB(hex: "2e8bce"))
        #expect(!colors.isDark)
    }

    @Test
    func usesGhosttyDefaultsWithoutTheme() {
        let colors = TerminalColors.from(config: "font-size = 12", dark: false) { _ in nil }
        #expect(colors == .ghostty)
        #expect(colors.isDark)
    }

    @Test
    func picksThemeSideForAppearance() {
        let value = "light:Alabaster, dark:Afterglow"
        #expect(TerminalColors.pickTheme(value, dark: false) == "Alabaster")
        #expect(TerminalColors.pickTheme(value, dark: true) == "Afterglow")
        #expect(TerminalColors.pickTheme("Violet Light", dark: true) == "Violet Light")
    }

    @Test
    func fallbackFollowsAppearance() {
        #expect(!TerminalColors.fallback(dark: false).isDark)
        #expect(TerminalColors.fallback(dark: true).isDark)
    }

    @Test
    func findsConfigAndThemeFiles() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitfork-ghostty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }

        let xdg = home.appendingPathComponent("xdg")
        let ghostty = xdg.appendingPathComponent("ghostty")
        let support = home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty")
        try FileManager.default.createDirectory(
            at: ghostty.appendingPathComponent("themes"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let environment = ["XDG_CONFIG_HOME": xdg.path]
        #expect(GhosttyConfig.text(environment: environment, home: home.path) == nil)

        try "theme = Mine\nforeground = #111111".write(
            to: ghostty.appendingPathComponent("config"), atomically: true, encoding: .utf8
        )
        try "foreground = #222222".write(
            to: support.appendingPathComponent("config"), atomically: true, encoding: .utf8
        )
        try "background = #333333".write(
            to: ghostty.appendingPathComponent("themes/Mine"), atomically: true, encoding: .utf8
        )

        let text = try #require(GhosttyConfig.text(environment: environment, home: home.path))
        let colors = TerminalColors.from(config: text, dark: false) {
            GhosttyConfig.themeText($0, environment: environment, home: home.path)
        }
        // The Application Support config loads last, so it wins.
        #expect(colors.foreground == RGB(hex: "222222"))
        #expect(colors.background == RGB(hex: "333333"))
    }
}

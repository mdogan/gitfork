import Foundation

/// A color with 0-1 sRGB components.
struct RGB: Equatable, Sendable {
    var r, g, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        (self.r, self.g, self.b) = (r, g, b)
    }

    /// `#RRGGBB` or `RRGGBB`. Ghostty also knows X11 color names; those are
    /// not read here.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(Double(v >> 16 & 0xFF) / 255, Double(v >> 8 & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// Perceived brightness, 0-1.
    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    /// This color moved `amount` (0-1) of the way to `other`.
    func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(r + (other.r - r) * amount, g + (other.g - g) * amount, b + (other.b - b) * amount)
    }
}

/// The colors of a Ghostty terminal theme, so GitFork's windows can match the
/// user's terminal.
struct TerminalColors: Equatable, Sendable {
    var background: RGB
    var foreground: RGB
    /// ANSI colors by index: 1 red, 2 green, 3 yellow, 4 blue, 5 magenta, ...
    var palette: [Int: RGB] = [:]

    init(background: RGB, foreground: RGB, palette: [Int: RGB] = [:]) {
        self.background = background
        self.foreground = foreground
        self.palette = palette
    }

    var isDark: Bool { background.luminance < 0.5 }

    /// Ghostty's own colors when its config sets none.
    static let ghostty = TerminalColors(background: RGB(hex: "282C34")!, foreground: RGB(hex: "FFFFFF")!)

    /// Used when there is no Ghostty config: Alabaster when light, Afterglow
    /// when dark, the same defaults as the Agentz terminals.
    static func fallback(dark: Bool) -> TerminalColors {
        dark
            ? TerminalColors(
                background: RGB(hex: "212121")!,
                foreground: RGB(hex: "D0D0D0")!,
                palette: [
                    1: RGB(hex: "AC4142")!, 2: RGB(hex: "7E8E50")!, 3: RGB(hex: "E4B567")!,
                    4: RGB(hex: "6C99BB")!, 5: RGB(hex: "9F4E86")!, 6: RGB(hex: "7DD5CF")!
                ]
            )
            : TerminalColors(
                background: RGB(hex: "F7F7F7")!,
                foreground: RGB(hex: "000000")!,
                palette: [
                    1: RGB(hex: "AA3731")!, 2: RGB(hex: "448C27")!, 3: RGB(hex: "CB8800")!,
                    4: RGB(hex: "325CC0")!, 5: RGB(hex: "7A3E9D")!, 6: RGB(hex: "0083B2")!
                ]
            )
    }

    /// The colors in Ghostty config text: its theme's first, then its own
    /// color settings on top, as Ghostty does. `dark` picks the side of a
    /// `light:...,dark:...` theme. `readTheme` returns a theme file's text.
    static func from(config: String, dark: Bool, readTheme: (String) -> String?) -> TerminalColors {
        var colors = ghostty
        let settings = parse(config)
        if let theme = settings.last(where: { $0.key == "theme" })?.value,
           let name = pickTheme(theme, dark: dark), let text = readTheme(name)
        {
            colors.apply(parse(text))
        }
        colors.apply(settings)
        return colors
    }

    /// The colors of one theme file alone, on Ghostty's defaults. Used for a
    /// theme picked in GitFork, so the config's own color settings do not
    /// cover it.
    static func from(theme text: String) -> TerminalColors {
        var colors = ghostty
        colors.apply(parse(text))
        return colors
    }

    private mutating func apply(_ settings: [(key: String, value: String)]) {
        for (key, value) in settings {
            switch key {
            case "background": background = RGB(hex: value) ?? background
            case "foreground": foreground = RGB(hex: value) ?? foreground
            case "palette":
                let parts = value.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let i = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                   let c = RGB(hex: String(parts[1]))
                {
                    palette[i] = c
                }
            default: break
            }
        }
    }

    /// `key = value` lines, without comments and blank lines.
    static func parse(_ text: String) -> [(key: String, value: String)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { return nil }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            return (key, value.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
    }

    /// `Name` or `light:Name,dark:Name`.
    static func pickTheme(_ value: String, dark: Bool) -> String? {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let wanted = dark ? "dark:" : "light:"
        if let side = parts.first(where: { $0.hasPrefix(wanted) }) {
            return String(side.dropFirst(wanted.count))
        }
        return parts.first { !$0.hasPrefix("light:") && !$0.hasPrefix("dark:") } ?? parts.first
    }
}

/// A Ghostty theme GitFork can switch to.
struct GhosttyTheme: Hashable, Sendable {
    var name: String
    var isDark: Bool
}

/// Finds the user's Ghostty config and theme files on disk.
enum GhosttyConfig {
    /// The config files Ghostty loads on macOS, in its order, so later ones
    /// win. `nil` when none exists.
    static func text(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> String? {
        let xdg = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config"
        let support = home + "/Library/Application Support/com.mitchellh.ghostty"
        let texts = [
            xdg + "/ghostty/config",
            xdg + "/ghostty/config.ghostty",
            support + "/config",
            support + "/config.ghostty"
        ].compactMap { path -> String? in
            guard fileManager.fileExists(atPath: path) else { return nil }
            return try? String(contentsOfFile: path, encoding: .utf8)
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    /// A theme's text by name or absolute path. User themes come before the
    /// ones that ship inside Ghostty.app.
    static func themeText(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> String? {
        if name.hasPrefix("/") {
            return try? String(contentsOfFile: name, encoding: .utf8)
        }
        for directory in themeDirectories(environment: environment, home: home) {
            if let text = try? String(contentsOfFile: directory + "/" + name, encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    /// Every theme name `themeText` can find, each once, in Finder's order.
    static func themeNames(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> [String] {
        var names = Set<String>()
        for directory in themeDirectories(environment: environment, home: home) {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: directory + "/" + entry, isDirectory: &isDirectory),
                   !isDirectory.boolValue
                {
                    names.insert(entry)
                }
            }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Each named theme with whether its background is dark, for the Light and
    /// Dark theme menus. A theme without a background keeps Ghostty's dark one.
    static func themes(
        named names: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> [GhosttyTheme] {
        names.map { name in
            let text = themeText(name, environment: environment, home: home) ?? ""
            return GhosttyTheme(name: name, isDark: TerminalColors.from(theme: text).isDark)
        }
    }

    /// Where Ghostty looks for themes by name. User themes come first.
    private static func themeDirectories(environment: [String: String], home: String) -> [String] {
        let xdg = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config"
        return [
            xdg + "/ghostty/themes",
            home + "/Library/Application Support/com.mitchellh.ghostty/themes",
            "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
            home + "/Applications/Ghostty.app/Contents/Resources/ghostty/themes"
        ]
    }

    /// The terminal colors for the current system appearance, or those of
    /// `theme` alone when it is set and can be found.
    static func colors(dark: Bool, theme: String? = nil) -> TerminalColors {
        if let theme, let text = themeText(theme) { return .from(theme: text) }
        guard let config = text() else { return .fallback(dark: dark) }
        return TerminalColors.from(config: config, dark: dark) { themeText($0) }
    }
}

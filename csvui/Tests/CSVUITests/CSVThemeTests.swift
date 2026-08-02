import Foundation
import Testing

@testable import CSVUI

@Suite("csvui theme")
struct CSVThemeTests {
  @Test("printed default round trips and covers every role")
  func defaultRoundTrip() throws {
    #expect(try CSVThemeTOMLDecoder().decode(CSVTheme.defaultTOML) == .default)
  }

  @Test("partial theme inherits built-in values")
  func partialTheme() throws {
    let theme = try CSVThemeTOMLDecoder().decode(
      """
      version = 1
      [theme]
      accent = "#112233"
      """
    )
    #expect(theme.accent.hex == "#112233")
    #expect(theme.background == CSVTheme.default.background)
  }

  @Test("unknown, duplicate, unquoted, and invalid colors fail")
  func strictGrammar() {
    for source in [
      "version = 1\n[other]\nx = \"#000000\"",
      "version = 1\n[theme]\naccent = \"#000000\"\naccent = \"#111111\"",
      "version = 1\n[theme]\naccent = #000000",
      "version = 1\n[theme]\naccent = \"red\"",
      "version = 1\n[theme]\nunknown = \"#000000\"",
    ] {
      #expect(throws: CSVThemeTOMLError.self) {
        _ = try CSVThemeTOMLDecoder().decode(source)
      }
    }
  }

  @Test("theme lookup follows no-config, explicit, XDG, and fallback order")
  func paths() {
    let paths = CSVThemePaths()
    let cwd = URL(fileURLWithPath: "/work", isDirectory: true)
    let home = URL(fileURLWithPath: "/home/person", isDirectory: true)
    #expect(
      paths.resolve(
        explicitPath: nil,
        noConfig: true,
        environment: ["XDG_CONFIG_HOME": "/xdg"],
        currentDirectory: cwd,
        homeDirectory: home
      ) == .builtIn
    )
    #expect(
      paths.resolve(
        explicitPath: "theme.toml",
        noConfig: false,
        environment: [:],
        currentDirectory: cwd,
        homeDirectory: home
      ) == .file(URL(fileURLWithPath: "/work/theme.toml"), explicit: true)
    )
    #expect(
      paths.resolve(
        explicitPath: nil,
        noConfig: false,
        environment: ["XDG_CONFIG_HOME": "/xdg"],
        currentDirectory: cwd,
        homeDirectory: home
      ) == .file(URL(fileURLWithPath: "/xdg/csvui/theme.toml"), explicit: false)
    )
    #expect(
      paths.resolve(
        explicitPath: nil,
        noConfig: false,
        environment: ["XDG_CONFIG_HOME": "relative"],
        currentDirectory: cwd,
        homeDirectory: home
      ) == .file(URL(fileURLWithPath: "/home/person/.config/csvui/theme.toml"), explicit: false)
    )
  }
}

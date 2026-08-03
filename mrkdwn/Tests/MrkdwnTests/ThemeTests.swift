import Foundation
import Testing

@testable import Mrkdwn

@Suite("theme contract")
struct ThemeTests {
  @Test("printed default theme round trips")
  func defaultRoundTrip() throws {
    #expect(try ThemeTOMLDecoder().decode(ViewerTheme.defaultTOML) == .default)
  }

  @Test("partial theme overrides documented roles")
  func partialOverride() throws {
    let theme = try ThemeTOMLDecoder().decode(
      """
      version = 1
      [theme]
      accent = "#010203"
      code_background = "#A0B0C0"
      """
    )
    #expect(theme.accent.hex == "#010203")
    #expect(theme.codeBackground.hex == "#A0B0C0")
    #expect(theme.foreground == ViewerTheme.default.foreground)
  }

  @Test(
    "invalid TOML is rejected",
    arguments: [
      "version = 2",
      "version = 1\n[theme]\nunknown = \"#000000\"",
      "version = 1\n[theme]\naccent = \"red\"",
      "version = 1\n[theme]\naccent = \"#ＦＦ００００\"",
      "version = 1\n[theme]\naccent = \"#000000\"\naccent = \"#FFFFFF\"",
      "version = 1\nitems = []",
    ]
  )
  func invalidTOML(source: String) {
    do {
      _ = try ThemeTOMLDecoder().decode(source)
      Issue.record("Expected theme decode failure")
    } catch let error as ThemeTOMLError {
      #expect(error.line > 0)
      #expect(error.column > 0)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("path precedence follows explicit, XDG, and home rules")
  func pathPrecedence() {
    let cwd = URL(fileURLWithPath: "/work", isDirectory: true)
    let home = URL(fileURLWithPath: "/home/reader", isDirectory: true)
    let paths = ThemePaths()

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
      ) == .file(URL(fileURLWithPath: "/xdg/mrkdwn/theme.toml"), explicit: false)
    )
    #expect(
      paths.resolve(
        explicitPath: nil,
        noConfig: false,
        environment: ["XDG_CONFIG_HOME": "relative"],
        currentDirectory: cwd,
        homeDirectory: home
      )
        == .file(
          URL(fileURLWithPath: "/home/reader/.config/mrkdwn/theme.toml"),
          explicit: false
        )
    )
  }
}

import Foundation

public enum ThemeSelection: Equatable, Sendable {
  case builtIn
  case file(URL, explicit: Bool)
}

public struct ThemePaths: Sendable {
  public init() {}

  public func resolve(
    explicitPath: String?,
    noConfig: Bool,
    environment: [String: String],
    currentDirectory: URL,
    homeDirectory: URL
  ) -> ThemeSelection {
    if noConfig {
      return .builtIn
    }
    if let explicitPath {
      return .file(
        URL(fileURLWithPath: explicitPath, relativeTo: currentDirectory).standardizedFileURL,
        explicit: true
      )
    }
    if let xdg = environment["XDG_CONFIG_HOME"],
      !xdg.isEmpty,
      xdg.hasPrefix("/")
    {
      return .file(
        URL(fileURLWithPath: xdg)
          .appendingPathComponent("mrkdwn/theme.toml"),
        explicit: false
      )
    }
    return .file(
      homeDirectory
        .appendingPathComponent(".config/mrkdwn/theme.toml"),
      explicit: false
    )
  }
}

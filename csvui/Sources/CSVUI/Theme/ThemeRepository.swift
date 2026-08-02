public import Foundation

public enum CSVThemeSelection: Equatable, Sendable {
  case builtIn
  case file(URL, explicit: Bool)
}

public struct CSVLoadedTheme: Equatable, Sendable {
  public var theme: CSVTheme
  public var sourceURL: URL?
}

public enum CSVThemeRepositoryError: Error, Sendable, LocalizedError {
  case missingExplicit(URL)
  case unreadable(URL, String)
  case tooLarge(URL, Int)
  case invalid(URL, String)

  public var errorDescription: String? {
    switch self {
    case .missingExplicit(let url): "theme file does not exist: \(url.path)"
    case .unreadable(let url, let reason): "cannot read theme \(url.path): \(reason)"
    case .tooLarge(let url, let count): "theme \(url.path) is \(count) bytes; maximum is 1 MiB"
    case .invalid(let url, let reason): "\(url.path): \(reason)"
    }
  }
}

public struct CSVThemePaths: Sendable {
  public init() {}

  public func resolve(
    explicitPath: String?,
    noConfig: Bool,
    environment: [String: String],
    currentDirectory: URL,
    homeDirectory: URL
  ) -> CSVThemeSelection {
    if noConfig { return .builtIn }
    if let explicitPath {
      return .file(
        URL(fileURLWithPath: explicitPath, relativeTo: currentDirectory).standardizedFileURL,
        explicit: true
      )
    }
    if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty, xdg.hasPrefix("/") {
      return .file(
        URL(fileURLWithPath: xdg).appendingPathComponent("csvui/theme.toml"),
        explicit: false
      )
    }
    return .file(
      homeDirectory.appendingPathComponent(".config/csvui/theme.toml"),
      explicit: false
    )
  }
}

public struct CSVThemeRepository: Sendable {
  public static let maximumBytes = 1_048_576

  public init() {}

  public func load(_ selection: CSVThemeSelection) throws -> CSVLoadedTheme {
    switch selection {
    case .builtIn:
      return CSVLoadedTheme(theme: .default, sourceURL: nil)
    case .file(let url, let explicit):
      guard FileManager.default.fileExists(atPath: url.path) else {
        if explicit { throw CSVThemeRepositoryError.missingExplicit(url) }
        return CSVLoadedTheme(theme: .default, sourceURL: url)
      }
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
      guard size <= Self.maximumBytes else {
        throw CSVThemeRepositoryError.tooLarge(url, size)
      }
      let data: Data
      do { data = try Data(contentsOf: url, options: .mappedIfSafe) } catch {
        throw CSVThemeRepositoryError.unreadable(url, error.localizedDescription)
      }
      guard data.count <= Self.maximumBytes else {
        throw CSVThemeRepositoryError.tooLarge(url, data.count)
      }
      guard let source = String(data: data, encoding: .utf8) else {
        throw CSVThemeRepositoryError.invalid(url, "theme is not valid UTF-8")
      }
      do {
        return CSVLoadedTheme(theme: try CSVThemeTOMLDecoder().decode(source), sourceURL: url)
      } catch {
        throw CSVThemeRepositoryError.invalid(url, error.localizedDescription)
      }
    }
  }
}

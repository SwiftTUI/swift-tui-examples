import Foundation

public struct LoadedTheme: Equatable, Sendable {
  public var theme: ViewerTheme
  public var sourceURL: URL?

  public init(theme: ViewerTheme, sourceURL: URL?) {
    self.theme = theme
    self.sourceURL = sourceURL
  }
}

public enum ThemeRepositoryError: Error, Sendable, LocalizedError {
  case missingExplicit(URL)
  case unreadable(URL, String)
  case tooLarge(URL, Int)
  case invalid(URL, String)

  public var errorDescription: String? {
    switch self {
    case .missingExplicit(let url):
      "theme file does not exist: \(url.path)"
    case .unreadable(let url, let reason):
      "cannot read theme \(url.path): \(reason)"
    case .tooLarge(let url, let count):
      "theme \(url.path) is \(count) bytes; maximum is 1 MiB"
    case .invalid(let url, let reason):
      "\(url.path): \(reason)"
    }
  }
}

public struct ThemeRepository: Sendable {
  public static let maximumBytes = 1_048_576

  private let decoder: ThemeTOMLDecoder

  public init(decoder: ThemeTOMLDecoder = ThemeTOMLDecoder()) {
    self.decoder = decoder
  }

  public func load(_ selection: ThemeSelection) throws -> LoadedTheme {
    switch selection {
    case .builtIn:
      return LoadedTheme(theme: .default, sourceURL: nil)
    case .file(let url, let explicit):
      guard FileManager.default.fileExists(atPath: url.path) else {
        if explicit {
          throw ThemeRepositoryError.missingExplicit(url)
        }
        return LoadedTheme(theme: .default, sourceURL: url)
      }
      let data: Data
      do {
        data = try BoundedRegularFileReader.read(
          url,
          maximumBytes: Self.maximumBytes
        )
      } catch BoundedRegularFileReadError.tooLarge(let count) {
        throw ThemeRepositoryError.tooLarge(url, count)
      } catch {
        throw ThemeRepositoryError.unreadable(url, error.localizedDescription)
      }
      guard let source = String(data: data, encoding: .utf8) else {
        throw ThemeRepositoryError.invalid(url, "theme is not valid UTF-8")
      }
      do {
        return LoadedTheme(theme: try decoder.decode(source), sourceURL: url)
      } catch {
        throw ThemeRepositoryError.invalid(url, error.localizedDescription)
      }
    }
  }
}

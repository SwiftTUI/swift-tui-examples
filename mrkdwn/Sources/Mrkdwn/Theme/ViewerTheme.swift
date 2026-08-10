public import Foundation

public struct ThemeColor: Equatable, Hashable, Sendable, CustomStringConvertible {
  public var hex: String

  public init(_ hex: String) throws {
    guard ThemeColor.isValid(hex) else {
      throw ThemeColorError.invalidHex(hex)
    }
    self.hex = hex.uppercased()
  }

  public var description: String { hex }

  public static func isValid(_ value: String) -> Bool {
    guard value.count == 7, value.first == "#" else { return false }
    return value.dropFirst().unicodeScalars.allSatisfy {
      switch $0.value {
      case 48...57, 65...70, 97...102:
        true
      default:
        false
      }
    }
  }
}

public enum ThemeColorError: Error, Equatable, Sendable, LocalizedError {
  case invalidHex(String)

  public var errorDescription: String? {
    switch self {
    case .invalidHex(let value):
      "expected #RRGGBB, received '\(value)'"
    }
  }
}

public struct ViewerTheme: Equatable, Sendable {
  public var background: ThemeColor
  public var foreground: ThemeColor
  public var muted: ThemeColor
  public var accent: ThemeColor
  public var selectionBackground: ThemeColor
  public var headings: [ThemeColor]
  public var link: ThemeColor
  public var quote: ThemeColor
  public var codeForeground: ThemeColor
  public var codeBackground: ThemeColor
  public var tableBorder: ThemeColor
  public var rule: ThemeColor
  public var searchMatch: ThemeColor
  public var error: ThemeColor

  public static let `default`: ViewerTheme = {
    func color(_ value: String) -> ThemeColor {
      try! ThemeColor(value)
    }
    return ViewerTheme(
      background: color("#272822"),
      foreground: color("#F8F8F2"),
      muted: color("#75715E"),
      accent: color("#A6E22E"),
      selectionBackground: color("#49483E"),
      headings: [
        color("#F92672"), color("#FD971F"), color("#E6DB74"),
        color("#A6E22E"), color("#66D9EF"), color("#AE81FF"),
      ],
      link: color("#66D9EF"),
      quote: color("#75715E"),
      codeForeground: color("#F8F8F2"),
      codeBackground: color("#3E3D32"),
      tableBorder: color("#75715E"),
      rule: color("#75715E"),
      searchMatch: color("#E6DB74"),
      error: color("#F92672")
    )
  }()

  public static let defaultTOML = """
    version = 1

    [theme]
    background = "#272822"
    foreground = "#F8F8F2"
    muted = "#75715E"
    accent = "#A6E22E"
    selection_background = "#49483E"
    heading_1 = "#F92672"
    heading_2 = "#FD971F"
    heading_3 = "#E6DB74"
    heading_4 = "#A6E22E"
    heading_5 = "#66D9EF"
    heading_6 = "#AE81FF"
    link = "#66D9EF"
    quote = "#75715E"
    code_foreground = "#F8F8F2"
    code_background = "#3E3D32"
    table_border = "#75715E"
    rule = "#75715E"
    search_match = "#E6DB74"
    error = "#F92672"
    """
}

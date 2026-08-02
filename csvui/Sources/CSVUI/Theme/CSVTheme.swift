public import Foundation

public struct CSVThemeColor: Equatable, Hashable, Sendable, CustomStringConvertible {
  public var hex: String

  public init(_ hex: String) throws {
    guard Self.isValid(hex) else {
      throw CSVThemeColorError.invalidHex(hex)
    }
    self.hex = hex.uppercased()
  }

  public static func isValid(_ value: String) -> Bool {
    guard value.count == 7, value.first == "#" else { return false }
    return value.dropFirst().unicodeScalars.allSatisfy {
      switch $0.value {
      case 48...57, 65...70, 97...102: true
      default: false
      }
    }
  }

  public var description: String { hex }
}

public enum CSVThemeColorError: Error, Equatable, Sendable, LocalizedError {
  case invalidHex(String)

  public var errorDescription: String? {
    switch self {
    case .invalidHex(let value): "expected #RRGGBB, received '\(value)'"
    }
  }
}

public struct CSVTheme: Equatable, Sendable {
  public var background: CSVThemeColor
  public var foreground: CSVThemeColor
  public var muted: CSVThemeColor
  public var accent: CSVThemeColor
  public var border: CSVThemeColor
  public var menuBackground: CSVThemeColor
  public var menuForeground: CSVThemeColor
  public var menuActiveBackground: CSVThemeColor
  public var menuActiveForeground: CSVThemeColor
  public var headerBackground: CSVThemeColor
  public var headerForeground: CSVThemeColor
  public var gutter: CSVThemeColor
  public var cursorBackground: CSVThemeColor
  public var cursorForeground: CSVThemeColor
  public var searchMatch: CSVThemeColor
  public var edited: CSVThemeColor
  public var warning: CSVThemeColor
  public var error: CSVThemeColor

  public static let `default`: CSVTheme = {
    func color(_ value: String) -> CSVThemeColor { try! CSVThemeColor(value) }
    return CSVTheme(
      background: color("#0D1117"),
      foreground: color("#C9D1D9"),
      muted: color("#8B949E"),
      accent: color("#58A6FF"),
      border: color("#30363D"),
      menuBackground: color("#161B22"),
      menuForeground: color("#C9D1D9"),
      menuActiveBackground: color("#1F6FEB"),
      menuActiveForeground: color("#FFFFFF"),
      headerBackground: color("#161B22"),
      headerForeground: color("#E6EDF3"),
      gutter: color("#8B949E"),
      cursorBackground: color("#1F6FEB"),
      cursorForeground: color("#FFFFFF"),
      searchMatch: color("#E3B341"),
      edited: color("#D2A8FF"),
      warning: color("#FFA657"),
      error: color("#FF7B72")
    )
  }()

  public static let defaultTOML = """
    version = 1

    [theme]
    background = "#0D1117"
    foreground = "#C9D1D9"
    muted = "#8B949E"
    accent = "#58A6FF"
    border = "#30363D"
    menu_background = "#161B22"
    menu_foreground = "#C9D1D9"
    menu_active_background = "#1F6FEB"
    menu_active_foreground = "#FFFFFF"
    header_background = "#161B22"
    header_foreground = "#E6EDF3"
    gutter = "#8B949E"
    cursor_background = "#1F6FEB"
    cursor_foreground = "#FFFFFF"
    search_match = "#E3B341"
    edited = "#D2A8FF"
    warning = "#FFA657"
    error = "#FF7B72"
    """
}

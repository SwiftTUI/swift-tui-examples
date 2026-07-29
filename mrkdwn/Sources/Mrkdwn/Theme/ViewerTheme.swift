import Foundation

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

public struct MermaidTheme: Equatable, Sendable {
  public var background: ThemeColor
  public var border: ThemeColor
  public var text: ThemeColor
  public var edge: ThemeColor
  public var edgeLabel: ThemeColor
  public var title: ThemeColor
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
  public var mermaid: MermaidTheme

  public static let `default`: ViewerTheme = {
    func color(_ value: String) -> ThemeColor {
      try! ThemeColor(value)
    }
    return ViewerTheme(
      background: color("#0D1117"),
      foreground: color("#C9D1D9"),
      muted: color("#8B949E"),
      accent: color("#58A6FF"),
      selectionBackground: color("#1F6FEB"),
      headings: [
        color("#79C0FF"), color("#A5D6FF"), color("#D2A8FF"),
        color("#FFA657"), color("#7EE787"), color("#FF7B72"),
      ],
      link: color("#58A6FF"),
      quote: color("#8B949E"),
      codeForeground: color("#E6EDF3"),
      codeBackground: color("#161B22"),
      tableBorder: color("#30363D"),
      rule: color("#30363D"),
      searchMatch: color("#E3B341"),
      error: color("#FF7B72"),
      mermaid: MermaidTheme(
        background: color("#161B22"),
        border: color("#8B949E"),
        text: color("#E6EDF3"),
        edge: color("#8B949E"),
        edgeLabel: color("#C9D1D9"),
        title: color("#79C0FF")
      )
    )
  }()

  public static let defaultTOML = """
    version = 1

    [theme]
    background = "#0D1117"
    foreground = "#C9D1D9"
    muted = "#8B949E"
    accent = "#58A6FF"
    selection_background = "#1F6FEB"
    heading_1 = "#79C0FF"
    heading_2 = "#A5D6FF"
    heading_3 = "#D2A8FF"
    heading_4 = "#FFA657"
    heading_5 = "#7EE787"
    heading_6 = "#FF7B72"
    link = "#58A6FF"
    quote = "#8B949E"
    code_foreground = "#E6EDF3"
    code_background = "#161B22"
    table_border = "#30363D"
    rule = "#30363D"
    search_match = "#E3B341"
    error = "#FF7B72"

    [theme.mermaid]
    background = "#161B22"
    border = "#8B949E"
    text = "#E6EDF3"
    edge = "#8B949E"
    edge_label = "#C9D1D9"
    title = "#79C0FF"
    """
}

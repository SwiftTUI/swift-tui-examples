public import Foundation

public struct CSVThemeTOMLError: Error, Equatable, Sendable, LocalizedError {
  public var line: Int
  public var column: Int
  public var message: String

  public init(line: Int, column: Int, message: String) {
    self.line = line
    self.column = column
    self.message = message
  }

  public var errorDescription: String? {
    "theme.toml:\(line):\(column): \(message)"
  }
}

public struct CSVThemeTOMLDecoder: Sendable {
  private static let keys: Set<String> = [
    "background", "foreground", "muted", "accent", "border",
    "menu_background", "menu_foreground", "menu_active_background",
    "menu_active_foreground", "header_background", "header_foreground",
    "gutter", "cursor_background", "cursor_foreground", "search_match",
    "edited", "warning", "error",
  ]

  public init() {}

  public func decode(_ source: String) throws -> CSVTheme {
    var inTheme = false
    var sawTheme = false
    var version: Int?
    var values: [String: (String, Int, Int)] = [:]

    for (offset, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
    {
      let lineNumber = offset + 1
      let line = try stripComment(String(rawLine), line: lineNumber)
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }

      if trimmed.first == "[" {
        guard trimmed == "[theme]" else {
          throw error(lineNumber, 1, "unknown or unsupported table")
        }
        guard !sawTheme else { throw error(lineNumber, 1, "duplicate table '[theme]'") }
        sawTheme = true
        inTheme = true
        continue
      }

      guard let equals = unquotedEquals(in: line) else {
        throw error(lineNumber, 1, "expected key = value")
      }
      let rawKey = String(line[..<equals])
      let key = rawKey.trimmingCharacters(in: .whitespaces)
      guard isSimpleKey(key) else {
        throw error(lineNumber, contentColumn(rawKey), "unsupported key syntax")
      }
      let valueStart = line.index(after: equals)
      let rawValue = String(line[valueStart...])
      let value = rawValue.trimmingCharacters(in: .whitespaces)
      let valueColumn =
        line.distance(from: line.startIndex, to: valueStart) + 1
        + rawValue.prefix(while: { $0 == " " || $0 == "\t" }).count

      if !inTheme {
        guard key == "version" else { throw error(lineNumber, 1, "unknown root key '\(key)'") }
        guard version == nil else { throw error(lineNumber, 1, "duplicate key 'version'") }
        guard let parsed = Int(value), String(parsed) == value else {
          throw error(lineNumber, valueColumn, "version must be an integer")
        }
        version = parsed
        continue
      }
      guard Self.keys.contains(key) else {
        throw error(lineNumber, 1, "unknown key 'theme.\(key)'")
      }
      guard values[key] == nil else {
        throw error(lineNumber, 1, "duplicate key 'theme.\(key)'")
      }
      let decoded = try decodeBasicString(value, line: lineNumber, column: valueColumn)
      guard CSVThemeColor.isValid(decoded) else {
        throw error(lineNumber, valueColumn, "'theme.\(key)' must be exactly #RRGGBB")
      }
      values[key] = (decoded, lineNumber, valueColumn)
    }

    guard let version else { throw error(1, 1, "missing required version = 1") }
    guard version == 1 else {
      throw error(1, 1, "unsupported theme version \(version); expected 1")
    }

    var theme = CSVTheme.default
    func assign(_ key: String, _ body: (CSVThemeColor) -> Void) throws {
      guard let value = values[key] else { return }
      body(try CSVThemeColor(value.0))
    }
    try assign("background") { theme.background = $0 }
    try assign("foreground") { theme.foreground = $0 }
    try assign("muted") { theme.muted = $0 }
    try assign("accent") { theme.accent = $0 }
    try assign("border") { theme.border = $0 }
    try assign("menu_background") { theme.menuBackground = $0 }
    try assign("menu_foreground") { theme.menuForeground = $0 }
    try assign("menu_active_background") { theme.menuActiveBackground = $0 }
    try assign("menu_active_foreground") { theme.menuActiveForeground = $0 }
    try assign("header_background") { theme.headerBackground = $0 }
    try assign("header_foreground") { theme.headerForeground = $0 }
    try assign("gutter") { theme.gutter = $0 }
    try assign("cursor_background") { theme.cursorBackground = $0 }
    try assign("cursor_foreground") { theme.cursorForeground = $0 }
    try assign("search_match") { theme.searchMatch = $0 }
    try assign("edited") { theme.edited = $0 }
    try assign("warning") { theme.warning = $0 }
    try assign("error") { theme.error = $0 }
    return theme
  }

  private func stripComment(_ source: String, line: Int) throws -> String {
    var escaped = false
    var quoted = false
    for index in source.indices {
      let character = source[index]
      if quoted && escaped {
        escaped = false
        continue
      }
      if quoted && character == "\\" {
        escaped = true
        continue
      }
      if character == "\"" {
        quoted.toggle()
        continue
      }
      if character == "#", !quoted { return String(source[..<index]) }
    }
    if quoted { throw error(line, source.count + 1, "unterminated basic string") }
    return source
  }

  private func unquotedEquals(in source: String) -> String.Index? {
    var escaped = false
    var quoted = false
    for index in source.indices {
      let character = source[index]
      if quoted && escaped {
        escaped = false
      } else if quoted && character == "\\" {
        escaped = true
      } else if character == "\"" {
        quoted.toggle()
      } else if character == "=", !quoted {
        return index
      }
    }
    return nil
  }

  private func isSimpleKey(_ key: String) -> Bool {
    !key.isEmpty
      && key.allSatisfy {
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")
      }
  }

  private func decodeBasicString(_ source: String, line: Int, column: Int) throws -> String {
    guard source.first == "\"", source.last == "\"", source.count >= 2 else {
      throw error(line, column, "expected a basic quoted string")
    }
    let content = source.dropFirst().dropLast()
    var result = ""
    var index = content.startIndex
    while index < content.endIndex {
      let character = content[index]
      guard character == "\\" else {
        result.append(character)
        index = content.index(after: index)
        continue
      }
      let escapeColumn = column + content.distance(from: content.startIndex, to: index) + 1
      index = content.index(after: index)
      guard index < content.endIndex else { throw error(line, escapeColumn, "incomplete escape") }
      switch content[index] {
      case "\"": result.append("\"")
      case "\\": result.append("\\")
      case "b": result.append("\u{08}")
      case "t": result.append("\t")
      case "n": result.append("\n")
      case "f": result.append("\u{0C}")
      case "r": result.append("\r")
      default: throw error(line, escapeColumn, "invalid escape")
      }
      index = content.index(after: index)
    }
    return result
  }

  private func contentColumn(_ source: String) -> Int {
    source.prefix(while: { $0 == " " || $0 == "\t" }).count + 1
  }

  private func error(_ line: Int, _ column: Int, _ message: String) -> CSVThemeTOMLError {
    CSVThemeTOMLError(line: line, column: column, message: message)
  }
}

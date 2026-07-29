public import Foundation

public struct ThemeTOMLError: Error, Equatable, Sendable, LocalizedError {
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

public struct ThemeTOMLDecoder: Sendable {
  private static let themeKeys: Set<String> = [
    "background", "foreground", "muted", "accent", "selection_background",
    "heading_1", "heading_2", "heading_3", "heading_4", "heading_5", "heading_6",
    "link", "quote", "code_foreground", "code_background", "table_border", "rule",
    "search_match", "error",
  ]
  private static let mermaidKeys: Set<String> = [
    "background", "border", "text", "edge", "edge_label", "title",
  ]

  public init() {}

  public func decode(_ source: String) throws -> ViewerTheme {
    var table = ""
    var seenTables: Set<String> = []
    var values: [String: (value: String, line: Int, column: Int)] = [:]
    var version: Int?

    for (offset, rawLine) in source.split(
      separator: "\n",
      omittingEmptySubsequences: false
    ).enumerated() {
      let lineNumber = offset + 1
      let line = try stripComment(String(rawLine), line: lineNumber)
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }

      if trimmed.first == "[" {
        guard trimmed.last == "]", trimmed.filter({ $0 == "[" }).count == 1,
          trimmed.filter({ $0 == "]" }).count == 1
        else {
          throw error(lineNumber, 1, "unsupported table syntax")
        }
        let name = String(trimmed.dropFirst().dropLast())
        guard name == "theme" || name == "theme.mermaid" else {
          throw error(lineNumber, 2, "unknown table '\(name)'")
        }
        guard seenTables.insert(name).inserted else {
          throw error(lineNumber, 1, "duplicate table '[\(name)]'")
        }
        table = name
        continue
      }

      guard let equals = unquotedEquals(in: line) else {
        throw error(lineNumber, 1, "expected key = value")
      }
      let rawKey = String(line[..<equals])
      let key = rawKey.trimmingCharacters(in: .whitespaces)
      guard isSimpleKey(key) else {
        throw error(lineNumber, firstContentColumn(rawKey), "unsupported key syntax")
      }
      let valueStart = line.index(after: equals)
      let rawValue = String(line[valueStart...])
      let value = rawValue.trimmingCharacters(in: .whitespaces)
      let valueColumn =
        line.distance(from: line.startIndex, to: valueStart) + 1
        + rawValue.prefix(while: { $0 == " " || $0 == "\t" }).count

      if table.isEmpty {
        guard key == "version" else {
          throw error(lineNumber, 1, "unknown root key '\(key)'")
        }
        guard version == nil else {
          throw error(lineNumber, 1, "duplicate key 'version'")
        }
        guard let parsed = Int(value), String(parsed) == value else {
          throw error(lineNumber, valueColumn, "version must be an integer")
        }
        version = parsed
        continue
      }

      let allowed = table == "theme" ? Self.themeKeys : Self.mermaidKeys
      guard allowed.contains(key) else {
        throw error(lineNumber, 1, "unknown key '\(table).\(key)'")
      }
      let qualified = "\(table).\(key)"
      guard values[qualified] == nil else {
        throw error(lineNumber, 1, "duplicate key '\(qualified)'")
      }
      let decoded = try decodeBasicString(value, line: lineNumber, column: valueColumn)
      guard ThemeColor.isValid(decoded) else {
        throw error(lineNumber, valueColumn, "'\(qualified)' must be exactly #RRGGBB")
      }
      values[qualified] = (decoded, lineNumber, valueColumn)
    }

    guard let version else {
      throw error(1, 1, "missing required version = 1")
    }
    guard version == 1 else {
      throw error(1, 1, "unsupported theme version \(version); expected 1")
    }

    var theme = ViewerTheme.default
    func assign(_ qualified: String, _ body: (ThemeColor) -> Void) throws {
      guard let entry = values[qualified] else { return }
      do {
        body(try ThemeColor(entry.value))
      } catch {
        throw self.error(entry.line, entry.column, String(describing: error))
      }
    }

    try assign("theme.background") { theme.background = $0 }
    try assign("theme.foreground") { theme.foreground = $0 }
    try assign("theme.muted") { theme.muted = $0 }
    try assign("theme.accent") { theme.accent = $0 }
    try assign("theme.selection_background") { theme.selectionBackground = $0 }
    for index in 0..<6 {
      try assign("theme.heading_\(index + 1)") { theme.headings[index] = $0 }
    }
    try assign("theme.link") { theme.link = $0 }
    try assign("theme.quote") { theme.quote = $0 }
    try assign("theme.code_foreground") { theme.codeForeground = $0 }
    try assign("theme.code_background") { theme.codeBackground = $0 }
    try assign("theme.table_border") { theme.tableBorder = $0 }
    try assign("theme.rule") { theme.rule = $0 }
    try assign("theme.search_match") { theme.searchMatch = $0 }
    try assign("theme.error") { theme.error = $0 }
    try assign("theme.mermaid.background") { theme.mermaid.background = $0 }
    try assign("theme.mermaid.border") { theme.mermaid.border = $0 }
    try assign("theme.mermaid.text") { theme.mermaid.text = $0 }
    try assign("theme.mermaid.edge") { theme.mermaid.edge = $0 }
    try assign("theme.mermaid.edge_label") { theme.mermaid.edgeLabel = $0 }
    try assign("theme.mermaid.title") { theme.mermaid.title = $0 }
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
      if character == "#", !quoted {
        return String(source[..<index])
      }
    }
    if quoted {
      throw error(line, source.count + 1, "unterminated basic string")
    }
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
    !key.isEmpty && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
  }

  private func decodeBasicString(_ source: String, line: Int, column: Int) throws -> String {
    guard source.first == "\"" else {
      throw error(line, column, "expected a basic quoted string")
    }
    guard source.last == "\"", source.count >= 2 else {
      throw error(line, column, "unterminated basic string")
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
      guard index < content.endIndex else {
        throw error(line, escapeColumn, "incomplete escape")
      }
      let escape = content[index]
      switch escape {
      case "\"": result.append("\"")
      case "\\": result.append("\\")
      case "b": result.append("\u{08}")
      case "t": result.append("\t")
      case "n": result.append("\n")
      case "f": result.append("\u{0C}")
      case "r": result.append("\r")
      case "u", "U":
        let count = escape == "u" ? 4 : 8
        var digits = ""
        for _ in 0..<count {
          index = content.index(after: index)
          guard index < content.endIndex, content[index].isHexDigit else {
            throw error(line, escapeColumn, "invalid Unicode escape")
          }
          digits.append(content[index])
        }
        guard let value = UInt32(digits, radix: 16), let scalar = UnicodeScalar(value) else {
          throw error(line, escapeColumn, "invalid Unicode scalar")
        }
        result.unicodeScalars.append(scalar)
      default:
        throw error(line, escapeColumn, "invalid escape '\\\(escape)'")
      }
      index = content.index(after: index)
    }
    return result
  }

  private func firstContentColumn(_ source: String) -> Int {
    source.prefix(while: { $0 == " " || $0 == "\t" }).count + 1
  }

  private func error(_ line: Int, _ column: Int, _ message: String) -> ThemeTOMLError {
    ThemeTOMLError(line: line, column: column, message: message)
  }
}

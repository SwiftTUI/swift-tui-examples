// Structured semantic-cell concepts adapted from grok-mermaid canvas.ts/types.ts at
// commit 6be6507; substantially modified for public validation and continuation cells.

public struct MermaidSize: Equatable, Hashable, Sendable {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = max(0, width)
    self.height = max(0, height)
  }
}

public struct MermaidLayoutMetrics: Equatable, Hashable, Sendable {
  public let minimumWidth: Int
  public let idealSize: MermaidSize

  public init(minimumWidth: Int, idealSize: MermaidSize) {
    self.minimumWidth = max(1, minimumWidth)
    self.idealSize = idealSize
  }
}

public struct MermaidRole: RawRepresentable, Equatable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let background = Self(rawValue: "background")
  public static let border = Self(rawValue: "border")
  public static let text = Self(rawValue: "text")
  public static let edge = Self(rawValue: "edge")
  public static let edgeLabel = Self(rawValue: "edgeLabel")
  public static let title = Self(rawValue: "title")
}

public enum MermaidCell: Equatable, Hashable, Sendable {
  case empty(role: MermaidRole)
  case grapheme(String, role: MermaidRole, spanWidth: Int)
  case continuation(leadColumn: Int, role: MermaidRole)

  public var role: MermaidRole {
    switch self {
    case .empty(let role), .grapheme(_, let role, _), .continuation(_, let role):
      role
    }
  }
}

public struct MermaidSurface: Equatable, Sendable {
  public let size: MermaidSize
  public let rows: [[MermaidCell]]

  init(validating rows: [[MermaidCell]]) {
    let width = rows.first?.count ?? 0
    precondition(Self.rowsAreValid(rows), "invalid MermaidSurface cell topology")
    self.rows = rows
    self.size = MermaidSize(width: width, height: rows.count)
  }

  static func rowsAreValid(_ rows: [[MermaidCell]]) -> Bool {
    let width = rows.first?.count ?? 0
    guard rows.allSatisfy({ $0.count == width }) else { return false }

    for row in rows {
      for (column, cell) in row.enumerated() {
        switch cell {
        case .empty:
          continue
        case .grapheme(let grapheme, let role, let spanWidth):
          guard
            grapheme.count == 1,
            spanWidth > 0,
            spanWidth <= row.count - column
          else {
            return false
          }
          guard spanWidth > 1 else { continue }
          for continuationColumn in (column + 1)..<(column + spanWidth) {
            guard
              case .continuation(let leadColumn, let continuationRole) =
                row[continuationColumn],
              leadColumn == column,
              continuationRole == role
            else {
              return false
            }
          }
        case .continuation(let leadColumn, let role):
          guard leadColumn >= 0, leadColumn < column else { return false }
          guard
            case .grapheme(_, let leadRole, let spanWidth) = row[leadColumn],
            spanWidth > 0,
            spanWidth <= row.count - leadColumn,
            leadRole == role,
            column < leadColumn + spanWidth
          else {
            return false
          }
        }
      }
    }
    return true
  }

  public func cell(atX x: Int, y: Int) -> MermaidCell? {
    guard rows.indices.contains(y), rows[y].indices.contains(x) else { return nil }
    return rows[y][x]
  }

  public var plainLines: [String] {
    serializedLines(as: .unicode)
  }

  public func serialized(as glyphMode: MermaidGlyphMode = .unicode) -> String {
    serializedLines(as: glyphMode).joined(separator: "\n")
  }

  public func serializedLines(as glyphMode: MermaidGlyphMode = .unicode) -> [String] {
    rows.map { row in
      guard
        let lastContent = row.lastIndex(where: { cell in
          if case .empty = cell { return false }
          return true
        })
      else {
        return ""
      }
      var result = ""
      for cell in row[...lastContent] {
        switch cell {
        case .empty:
          result.append(" ")
        case .grapheme(let grapheme, let role, _):
          result.append(
            mermaidSerializedGrapheme(grapheme, role: role, glyphMode: glyphMode)
          )
        case .continuation:
          break
        }
      }
      return result
    }
  }
}

func mermaidSerializedGrapheme(
  _ grapheme: String,
  role: MermaidRole,
  glyphMode: MermaidGlyphMode
) -> String {
  guard glyphMode == .ascii else { return grapheme }
  if role == .border || role == .edge {
    return mermaidASCIIEquivalent(of: grapheme)
  }
  if role == .title, grapheme == "·" {
    return mermaidASCIIEquivalent(of: grapheme)
  }
  return grapheme
}

func mermaidASCIIEquivalent(of grapheme: String) -> String {
  switch grapheme {
  case "─", "━", "╌": "-"
  case "═": "="
  case "│", "┃", "╎", "║": "|"
  case "┌", "┐", "└", "┘", "├", "┤", "┬", "┴", "┼",
    "╠", "╣":
    "+"
  case "╭", "╮": "."
  case "╰", "╯": "'"
  case "╔", "╚": "["
  case "╗", "╝": "]"
  case "╱": "/"
  case "╲": "\\"
  case "⟨": "<"
  case "⟩": ">"
  case "▶", "▷", "►", "→", "⟶": ">"
  case "◀", "◁", "◄", "←", "⟵": "<"
  case "▲", "△", "↑": "^"
  case "▼", "▽", "↓": "v"
  case "●", "○", "◎", "◆", "◇", "•": "*"
  case "·": "-"
  case "♙": "@"
  case "█": "#"
  case "↶": "<"
  case "↻": "@"
  default: grapheme
  }
}

public struct POSIXWordLexer: Sendable {
  public enum Failure: Error, Equatable, Sendable {
    case danglingEscape
    case unterminatedSingleQuote
    case unterminatedDoubleQuote
  }

  public init() {}

  public func parse(_ source: String) throws -> [String] {
    enum Mode {
      case unquoted
      case singleQuoted
      case doubleQuoted
    }

    var mode = Mode.unquoted
    var words: [String] = []
    var current = ""
    var hasWord = false
    var escaping = false

    for character in source {
      if escaping {
        current.append(character)
        hasWord = true
        escaping = false
        continue
      }

      switch mode {
      case .unquoted:
        if character == "\\" {
          escaping = true
          hasWord = true
        } else if character == "'" {
          mode = .singleQuoted
          hasWord = true
        } else if character == "\"" {
          mode = .doubleQuoted
          hasWord = true
        } else if character.isWhitespace {
          if hasWord {
            words.append(current)
            current = ""
            hasWord = false
          }
        } else {
          current.append(character)
          hasWord = true
        }

      case .singleQuoted:
        if character == "'" {
          mode = .unquoted
        } else {
          current.append(character)
        }

      case .doubleQuoted:
        if character == "\"" {
          mode = .unquoted
        } else if character == "\\" {
          escaping = true
        } else {
          current.append(character)
        }
      }
    }

    if escaping {
      throw Failure.danglingEscape
    }
    switch mode {
    case .unquoted:
      break
    case .singleQuoted:
      throw Failure.unterminatedSingleQuote
    case .doubleQuoted:
      throw Failure.unterminatedDoubleQuote
    }
    if hasWord {
      words.append(current)
    }
    return words
  }
}

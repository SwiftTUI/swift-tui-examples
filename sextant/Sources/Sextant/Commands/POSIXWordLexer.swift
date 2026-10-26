/// Splits an editor command such as `VISUAL` or `EDITOR` into argv words with
/// the shell's quoting rules, without expanding or executing anything.
///
/// It follows POSIX.1-2024 XCU 2.2 and 2.3, scalar by scalar:
/// - Unquoted, a backslash preserves the next character, except that
///   backslash-newline is a line continuation and is removed.
/// - Single quotes preserve everything up to the closing quote.
/// - Inside double quotes a backslash escapes only `$`, backquote, `"`, `\`
///   and newline (a continuation, removed); before anything else it is kept.
/// - Unquoted space, tab and newline delimit words. Other spaces, such as
///   U+00A0 and U+3000, are word characters.
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
    var current = String.UnicodeScalarView()
    var hasWord = false
    var escaping = false

    for scalar in source.unicodeScalars {
      if escaping {
        escaping = false
        if scalar == "\n" {
          continue
        }
        if mode == .doubleQuoted, !Self.doubleQuoteEscapable.contains(scalar) {
          current.append("\\")
        }
        current.append(scalar)
        hasWord = true
        continue
      }

      switch mode {
      case .unquoted:
        if scalar == "\\" {
          escaping = true
        } else if scalar == "'" {
          mode = .singleQuoted
          hasWord = true
        } else if scalar == "\"" {
          mode = .doubleQuoted
          hasWord = true
        } else if Self.delimiters.contains(scalar) {
          if hasWord {
            words.append(String(current))
            current = String.UnicodeScalarView()
            hasWord = false
          }
        } else {
          current.append(scalar)
          hasWord = true
        }

      case .singleQuoted:
        if scalar == "'" {
          mode = .unquoted
        } else {
          current.append(scalar)
        }

      case .doubleQuoted:
        if scalar == "\"" {
          mode = .unquoted
        } else if scalar == "\\" {
          escaping = true
        } else {
          current.append(scalar)
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
      words.append(String(current))
    }
    return words
  }

  /// `<blank>` (space and tab) and newline: XCU 2.3, XBD 7.3.1.
  private static let delimiters: Set<Unicode.Scalar> = [" ", "\t", "\n"]

  /// The characters a backslash escapes inside double quotes (XCU 2.2.3),
  /// besides newline.
  private static let doubleQuoteEscapable: Set<Unicode.Scalar> = ["$", "`", "\"", "\\"]
}

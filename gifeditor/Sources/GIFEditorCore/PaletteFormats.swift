import Foundation

/// The community palette file formats the editor can read.
///
/// Both are plain UTF-8 text and both describe fully opaque colors —
/// neither carries an alpha channel — so a parsed palette's slot 0 is a
/// real color, *not* the transparent sentinel `ColorPalette` reserves.
/// Deciding whether to prepend `.transparent` before adopting an
/// imported palette is the caller's policy call, not the parser's.
public enum PaletteFormat: String, Sendable, CaseIterable {
  /// Lospec's `.hex`: one bare `RRGGBB` per line.
  case lospecHex = "hex"
  /// GIMP's `.gpl`: a `GIMP Palette` magic line, optional `Name:` /
  /// `Columns:` headers, `#` comments, then `R G B [name]` rows.
  case gimpPalette = "gpl"
}

/// Errors thrown while parsing a community palette file.
///
/// Every case names the offending 1-based physical line where one
/// exists, counting comments and blanks, so a UI can point at it. The
/// parsers never skip a line they failed to understand — the only lines
/// legally ignored are comments and blanks.
public enum PaletteParseError: Error, Equatable {
  /// The bytes were not valid UTF-8.
  case notUTF8
  /// A `.gpl` file did not open with its `GIMP Palette` magic line.
  case missingGIMPHeader(firstLine: String)
  /// A line that had to be a color entry was not one.
  case malformedEntry(line: Int, text: String)
  /// A `.gpl` channel parsed as an integer but fell outside `0...255`.
  case channelOutOfRange(line: Int, value: Int)
  /// A `.gpl` header (`Name:` / `Columns:`) appeared after the first
  /// color row, where the format does not allow it.
  case misplacedHeader(line: Int, text: String)
  /// The file held no color entries at all.
  case noColors
  /// The file held more colors than a GIF palette can hold.
  case tooManyColors(count: Int, capacity: Int)
  /// A file path could not be read.
  case unreadable(URL)
  /// A file path carried an extension no parser claims.
  case unknownFormat(pathExtension: String)
}

/// Reads Lospec `.hex` and GIMP `.gpl` palettes into `ColorPalette`.
///
/// Parsing is filesystem-free: the two real parsers take a `String`, so
/// every edge case is a unit test rather than a temp file. The `Data`
/// and `URL` entry points are thin conveniences over them.
///
/// Both parsers tolerate CRLF (and lone-CR) line endings, a UTF-8 BOM,
/// blank lines, and leading/trailing whitespace on every line. Anything
/// else that is not a comment must parse or the file is rejected —
/// silently dropping a color would hand the author a palette that is
/// quietly missing entries.
public enum PaletteImport {

  // MARK: - Entry points

  public static func palette(from text: String, format: PaletteFormat) throws(PaletteParseError)
    -> ColorPalette
  {
    switch format {
    case .lospecHex: return try lospecHex(text)
    case .gimpPalette: return try gimpPalette(text)
    }
  }

  public static func palette(from data: Data, format: PaletteFormat) throws(PaletteParseError)
    -> ColorPalette
  {
    guard let text = String(data: data, encoding: .utf8) else {
      throw PaletteParseError.notUTF8
    }
    return try palette(from: text, format: format)
  }

  /// Reads a palette off disk, choosing the parser by file extension.
  public static func palette(contentsOf url: URL) throws(PaletteParseError) -> ColorPalette {
    let ext = url.pathExtension.lowercased()
    guard let format = PaletteFormat(rawValue: ext) else {
      throw PaletteParseError.unknownFormat(pathExtension: url.pathExtension)
    }
    guard let data = try? Data(contentsOf: url) else {
      throw PaletteParseError.unreadable(url)
    }
    return try palette(from: data, format: format)
  }

  // MARK: - Lospec .hex

  /// Parses one `RRGGBB` per line.
  ///
  /// Tolerances, all deliberate:
  ///
  /// - A leading `#` is accepted, because hand-edited files carry it and
  ///   real Lospec exports do not.
  /// - `;` starts a comment. `#` deliberately does **not**: it is the
  ///   color prefix above, and reading `#FF0000` as a comment would drop
  ///   a color without saying so.
  /// - Exactly six hex digits. Eight-digit `RRGGBBAA` is rejected rather
  ///   than guessed at, because an accidental alpha in slot 0 would
  ///   silently rewrite the document's transparency sentinel.
  public static func lospecHex(_ text: String) throws(PaletteParseError) -> ColorPalette {
    var entries: [EditorColor] = []

    for (number, raw) in numberedLines(of: text) {
      let line = raw.trimmed
      if line.isEmpty || line.hasPrefix(";") { continue }

      let digits = line.hasPrefix("#") ? String(line.dropFirst()) : line
      guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
        throw PaletteParseError.malformedEntry(line: number, text: raw)
      }
      entries.append(EditorColor(rgbHex: value))
    }

    return try assemble(entries)
  }

  // MARK: - GIMP .gpl

  /// Parses the GIMP palette format.
  ///
  /// The magic line must come before any other content (a BOM, blank
  /// lines, comments, and leading whitespace are skipped to reach it)
  /// and is matched case-insensitively. `Name:` and `Columns:` are
  /// optional and legal only before the first color row; any other
  /// `Key: value` line is malformed rather than ignored.
  /// Color rows are whitespace-separated `R G B`, each channel a decimal
  /// integer in `0...255`, with everything after the third field taken
  /// as the entry's (discarded) name.
  public static func gimpPalette(_ text: String) throws(PaletteParseError) -> ColorPalette {
    var entries: [EditorColor] = []
    var sawHeader = false

    for (number, raw) in numberedLines(of: text) {
      let line = raw.trimmed
      if line.isEmpty || line.hasPrefix("#") { continue }

      guard sawHeader else {
        guard line.lowercased() == "gimp palette" else {
          throw PaletteParseError.missingGIMPHeader(firstLine: line)
        }
        sawHeader = true
        continue
      }

      if let colonIndex = line.firstIndex(of: ":"), isKeyword(String(line[..<colonIndex])) {
        guard entries.isEmpty else {
          throw PaletteParseError.misplacedHeader(line: number, text: raw)
        }
        continue
      }

      let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
      guard fields.count >= 3 else {
        throw PaletteParseError.malformedEntry(line: number, text: raw)
      }

      var channels: [UInt8] = []
      for field in fields.prefix(3) {
        guard let value = Int(field) else {
          throw PaletteParseError.malformedEntry(line: number, text: raw)
        }
        guard (0...255).contains(value) else {
          throw PaletteParseError.channelOutOfRange(line: number, value: value)
        }
        channels.append(UInt8(value))
      }
      entries.append(EditorColor(red: channels[0], green: channels[1], blue: channels[2]))
    }

    guard sawHeader else {
      throw PaletteParseError.missingGIMPHeader(firstLine: "")
    }
    return try assemble(entries)
  }

  // MARK: - Shared

  /// `Name:` and `Columns:` are the only headers GIMP writes.
  private static func isKeyword(_ key: String) -> Bool {
    let normalized = key.trimmed.lowercased()
    return normalized == "name" || normalized == "columns"
  }

  /// An empty file and an over-full file are both rejected. Truncating
  /// at 256 would hand back a palette the author never asked for; better
  /// to say so and let the caller quantize deliberately.
  private static func assemble(
    _ entries: [EditorColor]
  ) throws(PaletteParseError) -> ColorPalette {
    guard !entries.isEmpty else { throw PaletteParseError.noColors }
    guard entries.count <= ColorPalette.capacity else {
      throw PaletteParseError.tooManyColors(
        count: entries.count,
        capacity: ColorPalette.capacity
      )
    }
    return ColorPalette(colors: entries)
  }

  /// Splits into 1-based numbered physical lines after normalizing CRLF
  /// and lone-CR endings and stripping a leading BOM. Empty lines are
  /// kept so the numbering matches what an editor shows.
  private static func numberedLines(of text: String) -> [(Int, String)] {
    var normalized = text
    if normalized.hasPrefix("\u{FEFF}") {
      normalized.removeFirst()
    }
    normalized =
      normalized
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    return
      normalized
      .split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
      .map { ($0.offset + 1, String($0.element)) }
  }
}

extension StringProtocol {
  /// Leading/trailing spaces and tabs are noise in both formats.
  fileprivate var trimmed: String {
    trimmingCharacters(in: .whitespaces)
  }
}

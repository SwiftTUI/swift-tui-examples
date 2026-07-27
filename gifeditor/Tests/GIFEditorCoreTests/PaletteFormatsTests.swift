import Foundation
import Testing

@testable import GIFEditorCore

@Suite("Palette formats")
struct PaletteFormatsTests {

  // MARK: - Lospec .hex

  @Test("A plain .hex file parses one color per line")
  func hexHappyPath() throws {
    let palette = try PaletteImport.lospecHex(
      """
      FF0000
      00FF00
      0000FF
      """
    )
    #expect(palette.usedCount == 3)
    #expect(
      palette.usedColors == [
        EditorColor(rgbHex: 0xFF0000),
        EditorColor(rgbHex: 0x00FF00),
        EditorColor(rgbHex: 0x0000FF),
      ]
    )
    #expect(palette.colors.count == ColorPalette.capacity)
  }

  @Test(".hex tolerates CRLF, a BOM, blank lines, indentation, ; comments, and # prefixes")
  func hexTolerances() throws {
    let text = "\u{FEFF}; a palette\r\n\r\n  FF0000  \r\n#00ff00\r\n\t0000FF\r\n"
    let palette = try PaletteImport.lospecHex(text)
    #expect(palette.usedCount == 3)
    #expect(
      palette.usedColors == [
        EditorColor(rgbHex: 0xFF0000),
        EditorColor(rgbHex: 0x00FF00),
        EditorColor(rgbHex: 0x0000FF),
      ]
    )
  }

  @Test("Lone-CR line endings still split")
  func hexClassicMacLineEndings() throws {
    let palette = try PaletteImport.lospecHex("FF0000\r00FF00\r")
    #expect(palette.usedCount == 2)
  }

  @Test(".hex rejects a malformed line instead of skipping it")
  func hexRejectsMalformedLine() throws {
    #expect(throws: PaletteParseError.malformedEntry(line: 2, text: "ZZZZZZ")) {
      try PaletteImport.lospecHex("FF0000\nZZZZZZ\n00FF00")
    }
    // Wrong digit count is malformed too, including 8-digit RRGGBBAA:
    // guessing at an alpha channel would quietly rewrite slot 0's role.
    #expect(throws: PaletteParseError.malformedEntry(line: 1, text: "FF00")) {
      try PaletteImport.lospecHex("FF00")
    }
    #expect(throws: PaletteParseError.malformedEntry(line: 1, text: "FF0000FF")) {
      try PaletteImport.lospecHex("FF0000FF")
    }
  }

  @Test(".hex rejects an empty file")
  func hexRejectsEmptyFile() throws {
    #expect(throws: PaletteParseError.noColors) {
      try PaletteImport.lospecHex("; nothing but a comment\n\n")
    }
  }

  @Test(".hex rejects more colors than a GIF palette can hold")
  func hexRejectsOversizedFile() throws {
    let text = (0...ColorPalette.capacity)
      .map { String(format: "%06X", $0) }
      .joined(separator: "\n")
    #expect(
      throws: PaletteParseError.tooManyColors(
        count: ColorPalette.capacity + 1,
        capacity: ColorPalette.capacity
      )
    ) {
      try PaletteImport.lospecHex(text)
    }
    // Exactly capacity is fine.
    let atLimit = (0..<ColorPalette.capacity)
      .map { String(format: "%06X", $0) }
      .joined(separator: "\n")
    #expect(try PaletteImport.lospecHex(atLimit).usedCount == ColorPalette.capacity)
  }

  // MARK: - GIMP .gpl

  @Test("A plain .gpl file parses its headers, comments, and rows")
  func gplHappyPath() throws {
    let palette = try PaletteImport.gimpPalette(
      """
      GIMP Palette
      Name: Test
      Columns: 4
      # a comment
      255   0   0	red
        0 255   0	green
        0   0 255
      """
    )
    #expect(palette.usedCount == 3)
    #expect(
      palette.usedColors == [
        EditorColor(rgbHex: 0xFF0000),
        EditorColor(rgbHex: 0x00FF00),
        EditorColor(rgbHex: 0x0000FF),
      ]
    )
  }

  @Test(".gpl tolerates CRLF, a BOM, blank lines, and indentation")
  func gplTolerances() throws {
    let text = "\u{FEFF}GIMP Palette\r\n\r\nName: Test\r\n\r\n  255 0 0 red\r\n"
    let palette = try PaletteImport.gimpPalette(text)
    #expect(palette.usedCount == 1)
    #expect(palette[0] == EditorColor(rgbHex: 0xFF0000))
  }

  @Test(".gpl requires its magic line")
  func gplRequiresHeader() throws {
    #expect(throws: PaletteParseError.missingGIMPHeader(firstLine: "255 0 0")) {
      try PaletteImport.gimpPalette("255 0 0\n0 255 0")
    }
    #expect(throws: PaletteParseError.missingGIMPHeader(firstLine: "")) {
      try PaletteImport.gimpPalette("\n\n# only comments\n")
    }
    // The magic line is matched case-insensitively.
    #expect(try PaletteImport.gimpPalette("gimp palette\n1 2 3\n").usedCount == 1)
  }

  @Test(".gpl rejects short, non-numeric, and out-of-range rows")
  func gplRejectsMalformedRows() throws {
    #expect(throws: PaletteParseError.malformedEntry(line: 2, text: "255 0")) {
      try PaletteImport.gimpPalette("GIMP Palette\n255 0")
    }
    #expect(throws: PaletteParseError.malformedEntry(line: 2, text: "255 zero 0")) {
      try PaletteImport.gimpPalette("GIMP Palette\n255 zero 0")
    }
    #expect(throws: PaletteParseError.channelOutOfRange(line: 2, value: 300)) {
      try PaletteImport.gimpPalette("GIMP Palette\n300 0 0")
    }
    #expect(throws: PaletteParseError.channelOutOfRange(line: 2, value: -1)) {
      try PaletteImport.gimpPalette("GIMP Palette\n-1 0 0")
    }
  }

  @Test(".gpl rejects a header that arrives after the first color row")
  func gplRejectsMisplacedHeader() throws {
    #expect(throws: PaletteParseError.misplacedHeader(line: 3, text: "Columns: 4")) {
      try PaletteImport.gimpPalette("GIMP Palette\n255 0 0\nColumns: 4")
    }
  }

  @Test(".gpl rejects a file with no color rows")
  func gplRejectsEmptyFile() throws {
    #expect(throws: PaletteParseError.noColors) {
      try PaletteImport.gimpPalette("GIMP Palette\nName: Empty\n# nothing here\n")
    }
  }

  @Test(".gpl rejects more colors than a GIF palette can hold")
  func gplRejectsOversizedFile() throws {
    var lines = ["GIMP Palette"]
    for i in 0...ColorPalette.capacity {
      lines.append("\(i % 256) 0 0")
    }
    #expect(
      throws: PaletteParseError.tooManyColors(
        count: ColorPalette.capacity + 1,
        capacity: ColorPalette.capacity
      )
    ) {
      try PaletteImport.gimpPalette(lines.joined(separator: "\n"))
    }
  }

  // MARK: - Data / URL entry points

  @Test("Non-UTF-8 bytes are rejected")
  func nonUTF8IsRejected() throws {
    let invalid = Data([0xFF, 0xFE, 0x00, 0x80])
    #expect(throws: PaletteParseError.notUTF8) {
      try PaletteImport.palette(from: invalid, format: .lospecHex)
    }
  }

  @Test("An unknown extension names itself in the error")
  func unknownExtensionIsRejected() throws {
    let url = URL(fileURLWithPath: "/tmp/does-not-matter.act")
    #expect(throws: PaletteParseError.unknownFormat(pathExtension: "act")) {
      try PaletteImport.palette(contentsOf: url)
    }
  }

  @Test("A missing file is reported as unreadable")
  func missingFileIsRejected() throws {
    let url = Self.fixturesDirectory
      .appendingPathComponent("definitely-not-here-\(UUID().uuidString).hex")
    #expect(throws: PaletteParseError.unreadable(url)) {
      try PaletteImport.palette(contentsOf: url)
    }
  }

  // MARK: - Golden fixtures

  /// The two fixtures are the editor's own default palette, slots
  /// 1...31 — slot 0 is the transparency sentinel and neither format can
  /// express an alpha channel — so the expected colors are checked
  /// against `ColorPalette.default` rather than a second hard-coded
  /// table.
  private var expectedFixtureColors: [EditorColor] {
    Array(ColorPalette.default.usedColors.dropFirst())
  }

  @Test("The golden .hex fixture parses to the editor's default palette")
  func goldenHexFixture() throws {
    let url = Self.fixturesDirectory.appendingPathComponent("gifeditor-default.hex")
    // No self-skip: a missing fixture is a failure, not a pass.
    #expect(FileManager.default.fileExists(atPath: url.path), "missing fixture at \(url.path)")
    let palette = try PaletteImport.palette(contentsOf: url)

    #expect(palette.usedCount == 31)
    #expect(palette.usedColors == expectedFixtureColors)
  }

  @Test("The golden .gpl fixture parses to the editor's default palette")
  func goldenGPLFixture() throws {
    let url = Self.fixturesDirectory.appendingPathComponent("gifeditor-default.gpl")
    #expect(FileManager.default.fileExists(atPath: url.path), "missing fixture at \(url.path)")
    let palette = try PaletteImport.palette(contentsOf: url)

    #expect(palette.usedCount == 31)
    #expect(palette.usedColors == expectedFixtureColors)
  }

  @Test("Both golden fixtures describe the same colors")
  func goldenFixturesAgree() throws {
    let hex = try PaletteImport.palette(
      contentsOf: Self.fixturesDirectory.appendingPathComponent("gifeditor-default.hex")
    )
    let gpl = try PaletteImport.palette(
      contentsOf: Self.fixturesDirectory.appendingPathComponent("gifeditor-default.gpl")
    )
    #expect(hex == gpl)
  }

  /// `Fixtures/` sits at the package root, outside every target path, so
  /// it is located relative to this source file rather than the working
  /// directory.
  private static var fixturesDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Tests/GIFEditorCoreTests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // <package root>/
      .appendingPathComponent("Fixtures")
  }
}

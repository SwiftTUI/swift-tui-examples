import Foundation
import Testing

@testable import GIFEditorCore

/// Tier 2: the checked-in artifacts the export family must keep
/// producing, byte for byte.
///
/// **What these files are.** Each one was produced by the encoders in
/// this package and then *validated by two independent decoders* before
/// being committed — not eyeballed, not trusted because the writer
/// looked right. A byte-identical match against one of them therefore
/// says more than "the encoder is self-consistent": it says the encoder
/// still emits the exact bytes that Pillow and ImageMagick both accepted
/// and decoded to the expected pixels. That is how conformance stays
/// pinned on a machine with no image tooling installed, which is every
/// CI lane this package runs in.
///
/// **Validated with** — recorded here because a golden whose provenance
/// is unknown is just a checksum of yesterday's bug:
///
/// | | |
/// | --- | --- |
/// | Date | 2026-07-26 |
/// | Pillow | 12.2.0 on CPython 3.13.5 |
/// | ImageMagick | 7.1.2-26 Q16-HDRI aarch64 |
/// | Platform | macOS 27 (Darwin arm64) |
///
/// Every file below was decoded by both: geometry and format via
/// `magick identify`, full pixel data via `magick <file> -depth 8
/// RGBA:-`, and pixel data plus APNG frame count and per-frame delays via
/// Pillow. Their acceptance is evidence rather than politeness, because
/// each decoder was separately confirmed to *reject* damaged copies of
/// these exact files: one flipped IDAT byte, a truncated stream, and a
/// zlib Adler-32 deliberately made wrong with the chunk CRC repaired so
/// only the inner checksum disagrees. One honest exception, recorded
/// because it bounds what these goldens prove: Pillow loads APNG frames
/// lazily, so a truncation of `export-golden-anim.png` that leaves frame
/// zero's `IDAT` intact still opens — it is the frame-count assertion in
/// `ExportExternalDecoderTests`, not an exception, that catches that
/// one. ImageMagick rejects it outright.
///
/// **Regenerating.** Do not regenerate to make a failing test pass. A
/// diff here means the encoder's output changed; the file is the record
/// of what was blessed. If the change is intentional, rewrite the files
/// from ``ExportGoldens/expected()``, re-run
/// `ExportExternalDecoderTests` on a machine that has both decoders so
/// the new bytes are validated the same way, and update the table above.
/// There is deliberately no auto-regeneration path: a golden that
/// rewrites itself when absent is a golden that silently blesses
/// whatever the encoder does today.
@Suite("Export goldens")
struct ExportGoldenTests {

  @Test("Every golden artifact still encodes byte-for-byte", arguments: ExportGoldens.names)
  func goldenBytes(name: String) throws {
    let onDisk = try Data(contentsOf: ExportGoldens.directory.appendingPathComponent(name))
    let expected = try #require(try ExportGoldens.expected()[name])
    #expect(
      [UInt8](onDisk) == expected,
      """
      \(name) no longer matches the checked-in golden. If this change is \
      intentional, see the regeneration note on ExportGoldenTests — the \
      new bytes need re-validating against both decoders before they are \
      committed.
      """
    )
  }

  @Test("The golden APNG still parses as the animation it was blessed as")
  func goldenAPNGStructure() throws {
    // A second, independent reading of the same file: the byte
    // comparison above would still pass if both sides drifted together,
    // whereas this asserts the animation's actual shape.
    let bytes = [UInt8](
      try Data(contentsOf: ExportGoldens.directory.appendingPathComponent(ExportGoldens.apng))
    )
    let chunks = try PNGChunkReader.chunks(in: bytes)
    let actl = try #require(chunks.first { $0.type == "acTL" })
    #expect(PNGChunkReader.uint32(actl.payload, at: 0) == 4, "num_frames")
    #expect(PNGChunkReader.uint32(actl.payload, at: 4) == 3, "num_plays")

    let delays = chunks.filter { $0.type == "fcTL" }.map { chunk -> (Int, Int) in
      (
        Int(UInt16(chunk.payload[20]) << 8 | UInt16(chunk.payload[21])),
        Int(UInt16(chunk.payload[22]) << 8 | UInt16(chunk.payload[23]))
      )
    }
    #expect(delays.map(\.0) == [0, 3, 10, 250])
    #expect(delays.allSatisfy { $0.1 == 100 })

    let frames = try PNGTestDecoder.decodeFrames(bytes)
    #expect(frames.count == 4)
    #expect(frames.map(\.size) == Array(repeating: PixelSize(width: 4, height: 3), count: 4))
  }

  @Test("The golden sidecar still describes the golden sheet")
  func goldenSidecar() throws {
    let json = try JSONSerialization.jsonObject(
      with: try Data(
        contentsOf: ExportGoldens.directory.appendingPathComponent(ExportGoldens.sheetMetadata)
      )
    )
    let root = try #require(json as? [String: Any])
    #expect(root["format"] as? String == "gifeditor-spritesheet")
    #expect(root["version"] as? Int == 1)
    #expect(root["columns"] as? Int == 3)
    #expect(root["rows"] as? Int == 2)
    #expect(root["frameCount"] as? Int == 5)

    let sheet = try PNGTestDecoder.decode(
      [UInt8](
        try Data(contentsOf: ExportGoldens.directory.appendingPathComponent(ExportGoldens.sheet))
      )
    )
    #expect(sheet.size.width == (root["image"] as? [String: Any])?["width"] as? Int)
    #expect(sheet.size.height == (root["image"] as? [String: Any])?["height"] as? Int)
  }
}

/// The golden set: the documents each artifact is built from, and where
/// the artifacts live.
///
/// Small on purpose. Goldens buy conformance-by-transitivity, and the
/// cases where hand-written PNG framing goes wrong are structural — the
/// degenerate 1x1 raster, the three alpha states, an animation's chunk
/// order and delay fractions, a grid with a padding cell. None of those
/// need a large image, and a large one would cost a checkout what it does
/// not buy a reviewer. The one case deliberately *not* pinned by a golden
/// is the multi-stored-block split: it would need a ~65 KB fixture to
/// cross the 65535-byte `LEN` ceiling, and tier 1 already asserts the
/// exact framing bytes on both sides of that boundary and round-trips
/// eight sizes through an independently written reader.
enum ExportGoldens {
  static let onePixelOpaque = "export-golden-1x1-opaque.png"
  static let onePixelTransparent = "export-golden-1x1-transparent.png"
  static let mixed = "export-golden-mixed-alpha.png"
  static let apng = "export-golden-anim.png"
  static let sheet = "export-golden-sheet.png"
  static let sheetMetadata = "export-golden-sheet.json"

  static let names = [
    onePixelOpaque, onePixelTransparent, mixed, apng, sheet, sheetMetadata,
  ]

  /// Resolved relative to this source file rather than the working
  /// directory. The package declares no test resources, so `Fixtures/`
  /// sits beside `Sources/` and `Tests/` at the package root.
  static var directory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Tests/GIFEditorCoreTests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // <package root>/
      .appendingPathComponent("Fixtures")
  }

  /// The 4x3, four-frame animation behind the APNG golden. Delays cover
  /// zero (as fast as possible), a small odd number, the document
  /// default, and 250 cs — far enough apart that a x10 or /10 slip in the
  /// delay fraction cannot look plausible.
  static func animationDocument() -> GIFDocument {
    slabDocument(
      size: PixelSize(width: 4, height: 3),
      slots: [1, 2, 3, nil],
      delays: [0, 3, 10, 250],
      loopCount: 3
    )
  }

  /// The five-frame, 4x3 document behind the spritesheet golden: a 3x2
  /// grid with one transparent frame and one padding cell.
  static func sheetDocument() -> GIFDocument {
    slabDocument(
      size: PixelSize(width: 4, height: 3),
      slots: [1, 2, 3, 4, nil],
      delays: [10, 5, 5, 20, 3],
      loopCount: 2
    )
  }

  /// What each golden's bytes must be, rebuilt from the documents above.
  static func expected() throws -> [String: [UInt8]] {
    let spritesheet = SpritesheetExport.encode(document: sheetDocument())
    return [
      onePixelOpaque: PNGEncoder.encode(
        document: slabDocument(size: PixelSize(width: 1, height: 1), slots: [1]),
        frameIndex: 0
      ),
      onePixelTransparent: PNGEncoder.encode(
        document: slabDocument(size: PixelSize(width: 1, height: 1), slots: [nil]),
        frameIndex: 0
      ),
      mixed: PNGEncoder.encode(document: mixedTransparencyDocument(), frameIndex: 0),
      apng: APNGEncoder.encode(document: animationDocument()),
      sheet: spritesheet.png,
      sheetMetadata: [UInt8](try spritesheet.metadata.jsonData()),
    ]
  }
}

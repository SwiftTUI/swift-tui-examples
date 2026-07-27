import EditorGIF
import Foundation

@testable import GIFEditorCore

/// Deterministic generator for `Fixtures/multi-palette-gradient.gif`, the
/// fixture that forces the quantizer to do real work.
///
/// `SaturatingGIFFixture` fills the palette but cannot *overflow* it: the
/// vendored `GIF.Encoder` writes a single global color table, so any GIF
/// it produces carries at most 256 distinct colors — 256 reduced to 255
/// merges exactly one pair, and the resulting error is far too small to
/// tell a good quantizer from a lazy one. Real animated GIFs escape that
/// ceiling with a **local color table per frame**, which the decoder
/// supports and the encoder does not.
///
/// So this fixture is assembled byte by byte: four frames, each with its
/// own 256-entry local color table, 1024 distinct colors in the union.
/// The image data uses the standard "uncompressed GIF" idiom — a clear
/// code often enough that every code stays 9 bits wide and no dictionary
/// entry is ever reused — which is a legal LZW stream, just a large one.
/// The fixture is under 20 KiB and reproduces from a bare checkout with
/// nothing but a Swift toolchain.
///
/// To regenerate after an intentional change, delete the `.gif` and run
/// the suite again; ``ensureOnDisk()`` rewrites it and
/// `ImportQuantizationTests.multiPaletteFixtureMatchesItsGenerator`
/// re-checks it.
enum MultiPaletteGIFFixture {

  /// Canvas edge length. 32×32 = 1024 pixels, four per local-table entry.
  static let side = 32

  /// One local color table per frame.
  static let frameCount = 4

  static let delayCentiseconds = 5

  /// 8 red levels × 8 green levels × 4 blue levels *per frame*, with the
  /// blue ramp offset by frame so the four tables never overlap.
  /// 4 × 256 = 1024 distinct colors, four times the palette ceiling.
  static let distinctColorCount = frameCount * 256

  static var url: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Tests/GIFEditorCoreTests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // <package root>/
      .appendingPathComponent("Fixtures")
      .appendingPathComponent("multi-palette-gradient.gif")
  }

  /// The local color table for one frame.
  static func colorTable(frame: Int) -> [(r: UInt8, g: UInt8, b: UInt8)] {
    (0..<256).map { i in
      let red: Int = (i >> 5) * 36
      let green: Int = ((i >> 2) & 0b111) * 36
      let blue: Int = (i & 0b11) * 64 + frame * 16
      return (r: UInt8(red), g: UInt8(green), b: UInt8(blue))
    }
  }

  /// Row-major indices into that frame's local table. Every entry is
  /// painted, and the sweep is rotated per frame so no two frames are
  /// identical.
  static func indices(frame: Int) -> [UInt8] {
    (0..<(side * side)).map { UInt8((($0 + frame * 41) % 256)) }
  }

  /// The color every pixel of every frame is *supposed* to be — ground
  /// truth for the error measurements, independent of the decoder.
  static func expectedColors(frame: Int) -> [EditorColor] {
    let table = colorTable(frame: frame)
    return indices(frame: frame).map { index in
      let entry = table[Int(index)]
      return EditorColor(red: entry.r, green: entry.g, blue: entry.b)
    }
  }

  // MARK: - Encoding

  /// Assembles the GIF89a byte stream. Pure function of the constants
  /// above, so two runs on any machine produce identical output.
  static func encodedBytes() -> [UInt8] {
    var out: [UInt8] = Array("GIF89a".utf8)

    // Logical screen descriptor. No global color table — every frame
    // brings its own, which is the whole point of the fixture.
    out += littleEndian(side)
    out += littleEndian(side)
    out.append(0x70)  // GCT flag 0, color resolution 8 bits.
    out.append(0)  // Background index (unused without a GCT).
    out.append(0)  // Pixel aspect ratio.

    for frame in 0..<frameCount {
      // Graphics control extension: keep disposal, no transparency.
      out += [0x21, 0xF9, 0x04, 0x04]
      out += littleEndian(delayCentiseconds)
      out += [0x00, 0x00]

      // Image descriptor with the local-color-table flag set and a
      // size field of 7, meaning 2^(7+1) = 256 entries.
      out.append(0x2C)
      out += littleEndian(0)
      out += littleEndian(0)
      out += littleEndian(side)
      out += littleEndian(side)
      out.append(0x87)

      for entry in colorTable(frame: frame) {
        out += [entry.r, entry.g, entry.b]
      }

      out += literalLZW(indices: indices(frame: frame))
    }

    out.append(0x3B)  // Trailer.
    return out
  }

  /// Writes the fixture if it is not already checked out, then returns
  /// the bytes on disk.
  ///
  /// The write is `.atomic` because the test suite runs in parallel:
  /// several tests call this, and a reader must never observe a
  /// half-written file. Without it a fresh checkout fails with
  /// "GIF stream truncated during signature" on whichever test loses
  /// the race.
  @discardableResult
  static func ensureOnDisk() throws -> Data {
    let url = Self.url
    if !FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data(encodedBytes()).write(to: url, options: .atomic)
    }
    return try Data(contentsOf: url)
  }

  // MARK: - Minimal LZW

  private static func littleEndian(_ value: Int) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
  }

  /// Emits each index as its own 9-bit literal code, restarting the
  /// dictionary often enough that the code width never grows past the
  /// initial 9 bits. Legal LZW, no compression — and short enough to
  /// audit, which matters more here than size.
  private static func literalLZW(indices: [UInt8]) -> [UInt8] {
    let minimumCodeSize = 8
    let clearCode = 1 << minimumCodeSize  // 256
    let endCode = clearCode + 1  // 257
    let codeWidth = minimumCodeSize + 1  // 9

    var writer = BitWriter()
    var sinceClear = 0
    writer.write(clearCode, width: codeWidth)
    for index in indices {
      // The decoder grows its dictionary once per code after a clear; a
      // restart every 128 codes keeps it far below the 512-entry point
      // where the width would have to increase.
      if sinceClear >= 128 {
        writer.write(clearCode, width: codeWidth)
        sinceClear = 0
      }
      writer.write(Int(index), width: codeWidth)
      sinceClear += 1
    }
    writer.write(endCode, width: codeWidth)
    writer.flush()

    return [UInt8(minimumCodeSize)] + subBlocks(writer.bytes)
  }

  /// GIF data is carried in length-prefixed sub-blocks of at most 255
  /// bytes, terminated by a zero-length block.
  private static func subBlocks(_ payload: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    var offset = 0
    while offset < payload.count {
      let length = min(255, payload.count - offset)
      out.append(UInt8(length))
      out += payload[offset..<(offset + length)]
      offset += length
    }
    out.append(0)
    return out
  }

  /// Packs codes least-significant-bit first, as GIF requires.
  private struct BitWriter {
    private(set) var bytes: [UInt8] = []
    private var accumulator: UInt32 = 0
    private var pendingBits = 0

    mutating func write(_ code: Int, width: Int) {
      accumulator |= UInt32(code) << UInt32(pendingBits)
      pendingBits += width
      while pendingBits >= 8 {
        bytes.append(UInt8(accumulator & 0xFF))
        accumulator >>= 8
        pendingBits -= 8
      }
    }

    mutating func flush() {
      if pendingBits > 0 {
        bytes.append(UInt8(accumulator & 0xFF))
        accumulator = 0
        pendingBits = 0
      }
    }
  }
}

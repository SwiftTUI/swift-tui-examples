import EditorGIF
import Foundation

/// Deterministic generator for `Fixtures/saturating-gradient.gif`, the one
/// fixture in the package that fills the loader's 256-entry palette.
///
/// None of the checked-in sample GIFs come close — `nyan.gif` carries 14
/// distinct opaque colors, `abom_h.gif` 6, `abom_eat.gif` 12 — so the
/// loader's palette-saturation path had no coverage at all. This fixture
/// is four frames of a 32×32 gradient sweep over a **256-entry global
/// color table**, and *frame 0 alone* paints every one of those entries
/// opaquely. The palette therefore fills while the first frame is still
/// being scanned, which is the worst case: a loader that stops collecting
/// frames when the palette fills keeps exactly one of the four.
///
/// The bytes come from the package's own vendored `EditorGIF` encoder, so
/// the fixture reproduces from a bare checkout with nothing but a Swift
/// toolchain — no ImageMagick, no Python, no new package dependency. To
/// regenerate after an intentional change, delete the `.gif` and run the
/// suite again; ``ensureOnDisk()`` rewrites it and
/// `GIFLoaderTests.saturatingFixtureMatchesItsGenerator` re-checks it.
enum SaturatingGIFFixture {

  /// Canvas edge length. 32×32 = 1024 pixels, four per palette entry.
  static let side = 32

  /// Frame count. Anything above one exposes the truncation; four keeps
  /// the fixture under 3 KiB while still reading as an animation.
  static let frameCount = 4

  /// Per-frame delay. Non-zero so the loader's `max(1, delay)` clamp is
  /// not what makes the assertion pass.
  static let delayCentiseconds = 6

  /// The generated file, resolved relative to this source file rather
  /// than the current working directory.
  static var url: URL {
    let here = URL(fileURLWithPath: #filePath)
    return
      here
      .deletingLastPathComponent()  // Tests/GIFEditorCoreTests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // <package root>/
      .appendingPathComponent("Fixtures")
      .appendingPathComponent("saturating-gradient.gif")
  }

  /// 256 distinct sRGB colors: 8 red levels × 8 green levels × 4 blue
  /// levels, indexed by the byte's own bit fields so the mapping is
  /// bijective and every entry is unique.
  static var colorTable: [(r: UInt8, g: UInt8, b: UInt8)] {
    var table: [(r: UInt8, g: UInt8, b: UInt8)] = []
    table.reserveCapacity(256)
    for i in 0..<256 {
      let red: Int = (i >> 5) * 36
      let green: Int = ((i >> 2) & 0b111) * 36
      let blue: Int = (i & 0b11) * 85
      table.append((r: UInt8(red), g: UInt8(green), b: UInt8(blue)))
    }
    return table
  }

  /// Row-major palette indices for one frame. Each frame is a full-canvas
  /// sweep through all 256 entries, rotated by frame so no two frames are
  /// identical and every frame is fully opaque.
  static func indices(frame: Int) -> [UInt8] {
    (0..<(side * side)).map { UInt8((($0 + frame * 67) % 256)) }
  }

  /// Encodes the fixture. Pure function of the constants above, so two
  /// runs on any machine produce byte-identical output.
  static func encodedBytes() throws -> [UInt8] {
    let frames = (0..<frameCount).map { frame in
      GIF.IndexedFrame(
        width: side,
        height: side,
        indices: indices(frame: frame),
        transparentIndex: nil,
        delayCentiseconds: delayCentiseconds,
        disposal: .keep
      )
    }
    let image = GIF.IndexedImage(
      size: (x: side, y: side),
      globalColorTable: colorTable,
      backgroundIndex: 0,
      loopCount: 0,
      frames: frames
    )
    return try GIF.Encoder.encode(image)
  }

  /// Writes the fixture if it is not already checked out, then returns
  /// the bytes on disk. Regeneration is the documented recovery path;
  /// in a normal checkout this only ever reads.
  @discardableResult
  static func ensureOnDisk() throws -> Data {
    let url = Self.url
    if !FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data(try encodedBytes()).write(to: url)
    }
    return try Data(contentsOf: url)
  }
}

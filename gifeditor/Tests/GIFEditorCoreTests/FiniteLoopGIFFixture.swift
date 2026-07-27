import EditorGIF
import Foundation

/// Deterministic generator for `Fixtures/finite-loop-3.gif`, the one
/// fixture in the package that declares a **finite** `NETSCAPE2.0` loop
/// count.
///
/// Every other GIF checked in here loops forever: `nyan.gif`, `abom_h.gif`,
/// `abom_eat.gif` and `saturating-gradient.gif` all declare `0`, and
/// `multi-palette-gradient.gif` carries no application extension at all.
/// So the one value a loader can get wrong by ignoring the block — a count
/// that is neither "forever" nor "the absent-block default" — had no
/// fixture, and `GIFLoader` dropping it went unnoticed.
///
/// Three plays is deliberately none of `0` (forever), `1` (what the format
/// means by a missing block) and the frame count, so an implementation that
/// confuses any of those with the declared count fails here.
///
/// The bytes come from the package's own vendored `EditorGIF` encoder, so
/// the fixture reproduces from a bare checkout with nothing but a Swift
/// toolchain. Unlike the two older fixture generators this one never
/// writes: ``data()`` reads the checked-in file and fails loudly if it has
/// gone, and `GIFLoaderTests.finiteLoopFixtureMatchesItsGenerator` pins the
/// bytes against ``encodedBytes()``. To regenerate after an intentional
/// change, print `encodedBytes()` and write it to ``url`` by hand.
enum FiniteLoopGIFFixture {

  /// The declared loop count. See the type doc for why it is 3.
  static let loopCount = 3

  /// Canvas edge length. Small on purpose — the fixture is about four
  /// bytes of application extension, not about pixels.
  static let side = 4

  /// Two frames, because the encoder only writes the `NETSCAPE2.0` block
  /// for a multi-frame image (or a single frame that does not play once),
  /// and because a one-frame animation cannot loop in any visible sense.
  static let frameCount = 2

  static let delayCentiseconds = 7

  /// The checked-in file, resolved relative to this source file rather
  /// than the current working directory.
  static var url: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Tests/GIFEditorCoreTests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // <package root>/
      .appendingPathComponent("Fixtures")
      .appendingPathComponent("finite-loop-3.gif")
  }

  /// Four unmistakable colors, so a frame that came back wrong is wrong
  /// in a way a human reading the failure can see.
  static let colorTable: [(r: UInt8, g: UInt8, b: UInt8)] = [
    (r: 0, g: 0, b: 0),
    (r: 255, g: 0, b: 0),
    (r: 0, g: 255, b: 0),
    (r: 0, g: 0, b: 255),
  ]

  /// Row-major palette indices for one frame — a diagonal sweep rotated
  /// by frame so the two frames differ everywhere.
  static func indices(frame: Int) -> [UInt8] {
    (0..<(side * side)).map { UInt8(($0 + frame) % colorTable.count) }
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
        disposal: .background
      )
    }
    let image = GIF.IndexedImage(
      size: (x: side, y: side),
      globalColorTable: colorTable,
      backgroundIndex: 0,
      loopCount: loopCount,
      frames: frames
    )
    return try GIF.Encoder.encode(image)
  }

  /// The bytes on disk. Read-only: a missing fixture is a failure, not a
  /// reason to quietly regenerate and pass.
  static func data() throws -> Data {
    let url = Self.url
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try Data(contentsOf: url)
  }
}

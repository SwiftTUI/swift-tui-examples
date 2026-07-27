import EditorGIF
import Foundation
import Testing

@testable import GIFEditorCore

/// Delta-coded export is only worth anything if it is *invisible*: the
/// same animation, in fewer bytes. Every test here therefore encodes the
/// same document twice — once ``GIFEncoder/FrameCoding/fullFrames``, once
/// ``GIFEncoder/FrameCoding/deltaFrames`` — decodes both, and demands the
/// composited frames match pixel for pixel. Size is asserted only after
/// that.
@Suite("Delta GIF export")
struct GIFDeltaEncodingTests {

  // MARK: - Round-trip identity on the fixture corpus

  @Test(
    "Fixtures render identically under both codings",
    arguments: [
      "nyan.gif",
      "abom_eat.gif",
      "abom_h.gif",
      "Fixtures/saturating-gradient.gif",
    ]
  )
  func fixturesRenderIdentically(fixture: String) throws {
    let document = try GIFLoader.load(contentsOf: try fixtureURL(fixture))
    try expectRenderIdentical(document, label: fixture)
  }

  /// Only the fixtures whose motion is *local* are held to a size claim.
  ///
  /// `Fixtures/saturating-gradient.gif` and `abom_h.gif` are deliberately
  /// absent: measured, every one of their frames differs from its
  /// predecessor across the whole canvas, so the changed rectangle is the
  /// canvas and there is no geometry left to save. What those two are
  /// worth is the identity check above.
  @Test("Locally-animated fixtures shrink", arguments: ["nyan.gif", "abom_eat.gif"])
  func animatedFixturesShrink(fixture: String) throws {
    let document = try GIFLoader.load(contentsOf: try fixtureURL(fixture))
    let sizes = try expectRenderIdentical(document, label: fixture)
    #expect(
      sizes.delta < sizes.full,
      "\(fixture): delta \(sizes.delta) B is not smaller than full \(sizes.full) B"
    )
  }

  @Test("A partly-moving animation gets meaningfully smaller")
  func localMotionShrinks() throws {
    let document = slidingSquareDocument()
    let sizes = try expectRenderIdentical(document, label: "sliding square")
    // 24 frames of a 6×6 sprite crossing a 128×128 canvas: the changed
    // rectangle is a rounding error next to the canvas on every frame but
    // the first, so anything short of halving the file means the frame
    // rect is not actually being applied.
    #expect(
      sizes.delta * 2 < sizes.full,
      "sliding square: delta \(sizes.delta) B is not under half of full \(sizes.full) B"
    )
  }

  // MARK: - Degenerate cases

  @Test("Identical consecutive frames collapse to a 1×1 no-op rectangle")
  func identicalFramesEmitMinimalRect() throws {
    let filled = uniform(index: 1)
    let document = makeDocument(frames: [filled, filled, filled])
    _ = try expectRenderIdentical(document, label: "identical frames")

    let frames = try deltaFrameGeometry(of: document)
    #expect(frames.count == 3)
    // GIF cannot express a zero-area frame, so "nothing changed" is a 1×1
    // transparent pixel at the origin that paints nothing.
    #expect(frames[1].width == 1 && frames[1].height == 1)
    #expect(frames[1].left == 0 && frames[1].top == 0)
    #expect(frames[2].width == 1 && frames[2].height == 1)
  }

  @Test("A single changed pixel emits a 1×1 rectangle at that pixel")
  func singlePixelChangeEmitsSinglePixelRect() throws {
    var moved = uniform(index: 1)
    moved[PixelPoint(x: 5, y: 2)] = 2
    let document = makeDocument(frames: [uniform(index: 1), moved])
    _ = try expectRenderIdentical(document, label: "single pixel")

    let frames = try deltaFrameGeometry(of: document)
    #expect(frames[1].left == 5)
    #expect(frames[1].top == 2)
    #expect(frames[1].width == 1)
    #expect(frames[1].height == 1)
  }

  @Test("A frame that changes everything falls back to the full canvas")
  func fullCanvasChangeEmitsFullRect() throws {
    let document = makeDocument(frames: [uniform(index: 1), uniform(index: 2)])
    _ = try expectRenderIdentical(document, label: "full canvas change")

    let frames = try deltaFrameGeometry(of: document)
    #expect(frames[1].left == 0 && frames[1].top == 0)
    #expect(frames[1].width == canvas.width)
    #expect(frames[1].height == canvas.height)
  }

  /// The rule this pins: a `.keep` delta cannot erase. A transparent
  /// index under `.keep` means "leave what was there", so a pixel that
  /// goes painted → transparent is inexpressible as a delta and forces a
  /// full-canvas `.background` clear on the *previous* frame.
  @Test("A painted → transparent pixel forces a background clear")
  func paintedToTransparentForcesClear() throws {
    var punched = uniform(index: 1)
    punched[PixelPoint(x: 3, y: 3)] = nil
    let document = makeDocument(frames: [uniform(index: 1), punched, punched])
    _ = try expectRenderIdentical(document, label: "painted to transparent")

    let frames = try deltaFrameGeometry(of: document)
    // Frame 0 must clear the whole screen so frame 1's hole can appear…
    #expect(frames[0].disposal == .background)
    #expect(frames[0].width == canvas.width && frames[0].height == canvas.height)
    // …and frame 1 has to be full-canvas, because a `.background`
    // disposal only clears the disposing frame's own rectangle.
    #expect(frames[1].width == canvas.width && frames[1].height == canvas.height)
    // Frame 2 repeats frame 1, so the hole is already background there
    // and no further clear is needed.
    #expect(frames[1].disposal == .keep)
    #expect(frames[2].width == 1 && frames[2].height == 1)
  }

  /// The second half of the transparency rule, and the easier one to
  /// miss: the canvas a decoder starts with is transparent, but the
  /// canvas a `.background` disposal leaves holds the logical-screen
  /// background colour. A hole inherited from frame 0 is therefore *not*
  /// the same pixel as a hole left by a clear, and cannot be carried
  /// across by `.keep`.
  @Test("A hole inherited from frame 0 is not reused as a background hole")
  func frameZeroHoleIsNotABackgroundHole() throws {
    var punched = uniform(index: 1)
    punched[PixelPoint(x: 2, y: 2)] = nil
    let document = makeDocument(frames: [punched, punched])
    _ = try expectRenderIdentical(document, label: "frame-zero hole")

    let hole = canvas.indexOf(PixelPoint(x: 2, y: 2))
    let reference = try decode(try GIFEncoder.encode(document: document, frameCoding: .fullFrames))
    let referenceFrame1 = reference.composited(frameIndex: 1, as: GIF.RGBA<UInt8>.self)
    // Frame 1 of the full-frame coding paints onto a canvas the previous
    // frame cleared to the background colour, so the hole is *opaque*
    // there even though it is transparent in frame 0. Carrying frame 0's
    // transparent hole forward with `.keep` would have produced alpha 0
    // and quietly changed the render.
    #expect(referenceFrame1[hole].a != 0)

    let frames = try deltaFrameGeometry(of: document)
    #expect(frames[0].disposal == .background)
    #expect(frames[1].width == canvas.width && frames[1].height == canvas.height)
  }

  /// A `.background` disposal clears **the disposing frame's rectangle**,
  /// not the screen. So it is not enough to mark the predecessor
  /// `.background`; the predecessor must also be widened to the full
  /// canvas, even when its own diff was a single pixel on the far side of
  /// the image.
  @Test("A clear after a sub-rectangle delta widens that delta to full canvas")
  func clearAfterSubRectDeltaWidensThePredecessor() throws {
    var moved = uniform(index: 1)
    moved[PixelPoint(x: 5, y: 5)] = 2
    var punched = moved
    punched[PixelPoint(x: 2, y: 2)] = nil
    let document = makeDocument(frames: [uniform(index: 1), moved, punched])
    _ = try expectRenderIdentical(document, label: "clear after sub-rect delta")

    let frames = try deltaFrameGeometry(of: document)
    // Frame 1 would have been a 1×1 rectangle at (5, 5) on its own merits.
    #expect(frames[1].disposal == .background)
    #expect(frames[1].width == canvas.width && frames[1].height == canvas.height)
    #expect(frames[2].width == canvas.width && frames[2].height == canvas.height)
  }

  /// The worst case for delta coding, and the one that shows the clear is
  /// driven by the *successor's* needs rather than by the frame itself.
  @Test("A hole that moves clears only where a hole is about to open")
  func movingHoleClearsOnlyWhereNeeded() throws {
    let holes = [PixelPoint(x: 0, y: 0), PixelPoint(x: 1, y: 1), PixelPoint(x: 2, y: 2)]
    let document = makeDocument(
      frames: holes.map { hole in
        var pixels = uniform(index: 1)
        pixels[hole] = nil
        return pixels
      } + [uniform(index: 1)]
    )
    _ = try expectRenderIdentical(document, label: "moving hole")

    let frames = try deltaFrameGeometry(of: document)
    // Frames 1 and 2 each open a hole where the canvas is painted, so
    // their predecessors clear and both frames go full-canvas.
    for index in 0..<3 {
      #expect(frames[index].width == canvas.width && frames[index].height == canvas.height)
    }
    #expect(frames[0].disposal == .background)
    #expect(frames[1].disposal == .background)
    // Frame 3 has no holes at all, so frame 2 has nothing to clear for.
    #expect(frames[2].disposal == .keep)
    // …but frame 0 does have a hole, so the last frame still has to clear
    // for the loop boundary.
    #expect(frames[3].disposal == .background)
  }

  @Test("A transparent frame 0 keeps the loop boundary honest")
  func transparentFirstFrameClearsAtTheLoopBoundary() throws {
    var punched = uniform(index: 1)
    punched[PixelPoint(x: 1, y: 1)] = nil
    var later = uniform(index: 2)
    later[PixelPoint(x: 1, y: 1)] = nil
    let document = makeDocument(frames: [punched, later])

    let frames = try deltaFrameGeometry(of: document)
    // `composited(frameIndex:)` never applies the last frame's disposal,
    // but a looping player does: without this the second pass would paint
    // frame 0 over frame N's leftovers and its holes would show them.
    #expect(frames[frames.count - 1].disposal == .background)
    #expect(frames[frames.count - 1].width == canvas.width)
    #expect(frames[frames.count - 1].height == canvas.height)
  }

  // MARK: - When delta coding declines

  @Test("An authored non-background disposal is written through verbatim")
  func authoredDisposalDeclinesDeltaCoding() throws {
    let pixels = uniform(index: 1)
    var moved = uniform(index: 1)
    moved[PixelPoint(x: 4, y: 4)] = 2
    var document = makeDocument(frames: [pixels, moved])
    document.frames[0].disposal = .keep

    let delta = try GIFEncoder.encode(document: document, frameCoding: .deltaFrames)
    let full = try GIFEncoder.encode(document: document, frameCoding: .fullFrames)
    #expect(delta == full)
  }

  @Test("A single-frame document has no delta to take")
  func singleFrameDocumentIsUnchanged() throws {
    let document = makeDocument(frames: [uniform(index: 1)])
    let delta = try GIFEncoder.encode(document: document, frameCoding: .deltaFrames)
    let full = try GIFEncoder.encode(document: document, frameCoding: .fullFrames)
    #expect(delta == full)
  }

  @Test("Delta coding is the default")
  func deltaIsTheDefault() throws {
    let document = slidingSquareDocument()
    let implicit = try GIFEncoder.encode(document: document)
    let explicit = try GIFEncoder.encode(document: document, frameCoding: .deltaFrames)
    #expect(implicit == explicit)
  }

  // MARK: - Emitted geometry

  @Test("Every emitted rectangle stays inside the logical screen")
  func emittedRectanglesAreInBounds() throws {
    let document = try GIFLoader.load(contentsOf: try fixtureURL("nyan.gif"))
    let frames = try deltaFrameGeometry(of: document)
    var sawSubRect = false
    for frame in frames {
      #expect(frame.left >= 0 && frame.top >= 0)
      #expect(frame.left + frame.width <= document.size.width)
      #expect(frame.top + frame.height <= document.size.height)
      if frame.width < document.size.width || frame.height < document.size.height {
        sawSubRect = true
      }
    }
    // If nothing came back as a sub-rectangle the Image Descriptor
    // offsets are not actually being used and every other assertion here
    // is passing for the wrong reason.
    #expect(sawSubRect)
  }

  // MARK: - Helpers

  private let canvas = PixelSize(width: 8, height: 8)

  /// Deliberately black-free. The logical-screen background is the colour
  /// at ``ColorPalette/transparentSlot`` — `.transparent`, whose RGB is
  /// `(0, 0, 0)` — and a `.background` disposal paints it *opaque*. A
  /// black drawing colour would therefore be pixel-identical to a cleared
  /// pixel, and every case below that distinguishes "painted" from
  /// "cleared" would pass no matter what the planner did.
  private var palette: ColorPalette {
    ColorPalette(
      colors: [
        .transparent,
        .white,
        EditorColor(rgbHex: 0xE05757),
        EditorColor(rgbHex: 0x5BA3FF),
      ]
    )
  }

  private func uniform(index: PaletteIndex) -> PixelBuffer {
    PixelBuffer(size: canvas, fill: index)
  }

  private func makeDocument(frames: [PixelBuffer]) -> GIFDocument {
    GIFDocument(
      size: frames[0].size,
      palette: palette,
      frames: frames.map { EditorFrame(layers: [EditorLayer(name: "L", pixels: $0)]) }
    )
  }

  /// A 6×6 sprite crossing a 128×128 opaque canvas — the shape of
  /// animation delta coding exists for, and the one no fixture in the
  /// corpus supplies.
  private func slidingSquareDocument() -> GIFDocument {
    let size = PixelSize(width: 128, height: 128)
    let frames: [EditorFrame] = (0..<24).map { step in
      var pixels = PixelBuffer(size: size, fill: 1)
      for dy in 0..<6 {
        for dx in 0..<6 {
          pixels[PixelPoint(x: step * 4 + dx, y: step * 4 + dy)] = 3
        }
      }
      return EditorFrame(layers: [EditorLayer(name: "L", pixels: pixels)])
    }
    return GIFDocument(size: size, palette: palette, frames: frames)
  }

  private struct EncodedSizes {
    var full: Int
    var delta: Int
  }

  /// Encodes `document` both ways, decodes both, and fails if any
  /// composited frame differs by a single pixel. Returns the two byte
  /// counts so the caller can make its own size claim.
  @discardableResult
  private func expectRenderIdentical(
    _ document: GIFDocument,
    label: String
  ) throws -> EncodedSizes {
    let fullBytes = try GIFEncoder.encode(document: document, frameCoding: .fullFrames)
    let deltaBytes = try GIFEncoder.encode(document: document, frameCoding: .deltaFrames)

    let full = try decode(fullBytes)
    let delta = try decode(deltaBytes)

    #expect(delta.size.x == full.size.x && delta.size.y == full.size.y, "\(label): screen size")
    guard delta.frames.count == full.frames.count else {
      Issue.record(
        "\(label): frame count \(delta.frames.count) != \(full.frames.count)"
      )
      throw ComparisonFailure.frameCountMismatch
    }
    #expect(delta.frames.count == document.frames.count, "\(label): frame count vs document")

    for index in 0..<full.frames.count {
      #expect(
        delta.frames[index].delayCentiseconds == full.frames[index].delayCentiseconds,
        "\(label): frame \(index) delay"
      )
      let expected = full.composited(frameIndex: index, as: GIF.RGBA<UInt8>.self)
      let actual = delta.composited(frameIndex: index, as: GIF.RGBA<UInt8>.self)
      guard expected.count == actual.count else {
        Issue.record("\(label): frame \(index) pixel count differs")
        continue
      }
      // One recorded issue per frame, not per pixel: a broken delta plan
      // misses thousands of pixels and the first one is the diagnostic.
      if let offset = expected.indices.first(where: { expected[$0] != actual[$0] }) {
        let want = expected[offset]
        let got = actual[offset]
        Issue.record(
          """
          \(label): frame \(index) pixel \(offset) differs — \
          full (\(want.r), \(want.g), \(want.b), \(want.a)) vs \
          delta (\(got.r), \(got.g), \(got.b), \(got.a))
          """
        )
        break
      }
    }

    return EncodedSizes(full: fullBytes.count, delta: deltaBytes.count)
  }

  /// The image-descriptor geometry the delta coding actually emitted, read
  /// back out of the encoded bytes rather than out of the planner — so
  /// the assertions are about the file, not about the intent.
  private func deltaFrameGeometry(of document: GIFDocument) throws -> [GIF.Frame] {
    try decode(try GIFEncoder.encode(document: document, frameCoding: .deltaFrames)).frames
  }

  private func decode(_ bytes: [UInt8]) throws -> GIF.Image {
    var source = ArraySource(bytes: bytes)
    return try GIF.Image.decompress(stream: &source)
  }

  private enum ComparisonFailure: Error {
    case frameCountMismatch
  }

  /// Resolves a fixture relative to the package root. A missing fixture is
  /// a failure, never a skip — a test that quietly passes when its input
  /// vanished is worse than no test.
  private func fixtureURL(_ relativePath: String) throws -> URL {
    let packageRoot =
      URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Tests/GIFEditorCoreTests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // <package root>/
    let url = packageRoot.appendingPathComponent(relativePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      Issue.record("fixture \(relativePath) is missing at \(url.path)")
      throw CocoaError(.fileNoSuchFile)
    }
    return url
  }
}

private struct ArraySource: GIF.BytestreamSource {
  var bytes: [UInt8]
  var offset = 0

  mutating func read(count: Int) -> [UInt8]? {
    guard offset < bytes.count else { return nil }
    let end = min(offset + count, bytes.count)
    let chunk = Array(bytes[offset..<end])
    offset = end
    return chunk
  }
}

import EditorGIF
import Foundation
import Testing

@testable import GIFEditorCore

@Suite("GIFLoader")
struct GIFLoaderTests {

  @Test("Loading nyan.gif produces a multi-frame document with one layer per frame")
  func nyanLoads() throws {
    let url = try nyanURL()
    let document = try GIFLoader.load(contentsOf: url)
    #expect(document.size.width == 70)
    #expect(document.size.height == 70)
    #expect(document.frames.count >= 6)
    for frame in document.frames {
      #expect(frame.layers.count == 1)
      #expect(frame.layers[0].pixels.size == document.size)
    }
  }

  @Test("Re-encoding a loaded document round-trips composited pixels")
  func reEncodingRoundTrip() throws {
    let url = try nyanURL()
    let document = try GIFLoader.load(contentsOf: url)
    let bytes = try GIFEncoder.encode(document: document)

    var source = ArraySource(bytes: bytes)
    let reDecoded = try GIF.Image.decompress(stream: &source)

    #expect(reDecoded.size.x == document.size.width)
    #expect(reDecoded.size.y == document.size.height)
    #expect(reDecoded.frames.count == document.frames.count)

    // Pick three sample cells per frame; if the encoder corrupted the
    // bitstream they would be wildly off, but the loader's quantizer can
    // introduce small perceptual differences for GIFs that had >255
    // distinct opaque colors. We assert the cells are at least
    // perceptually close (squared distance well under saturation).
    // `ImportQuantizationTests` makes the stronger, exact claim for
    // nyan specifically, which is under the ceiling.
    let toleranceSquared = 60 * 60 * 3
    for frameIndex in 0..<min(3, document.frames.count) {
      let originalFlat = document.flattenedColors(frameIndex: frameIndex)
      let reFlat = reDecoded.composited(frameIndex: frameIndex, as: GIF.RGBA<UInt8>.self)
      let samples = [0, originalFlat.count / 2, originalFlat.count - 1]
      for sample in samples {
        let original = originalFlat[sample]
        let actual = reFlat[sample]
        if let original, actual.a > 0 {
          let dr = Int(original.red) - Int(actual.r)
          let dg = Int(original.green) - Int(actual.g)
          let db = Int(original.blue) - Int(actual.b)
          let dist = dr * dr + dg * dg + db * db
          #expect(dist <= toleranceSquared)
        }
      }
    }
  }

  @Test("The saturating fixture on disk is the generator's output")
  func saturatingFixtureMatchesItsGenerator() throws {
    let onDisk = try SaturatingGIFFixture.ensureOnDisk()
    let generated = try Data(SaturatingGIFFixture.encodedBytes())
    #expect(onDisk == generated)
  }

  @Test("A palette-saturating GIF keeps every frame")
  func saturatingGIFKeepsEveryFrame() throws {
    let data = try SaturatingGIFFixture.ensureOnDisk()

    var source = ArraySource(bytes: Array(data))
    let decoded = try GIF.Image.decompress(stream: &source)

    // Guard the fixture itself: the loader reserves slot 0 for
    // transparency, so it saturates at 255 distinct opaque colors, and
    // frame 0 alone has to exceed that for this test to mean anything.
    #expect(decoded.frames.count == SaturatingGIFFixture.frameCount)
    let frameZeroColors = Set(
      decoded.composited(frameIndex: 0, as: GIF.RGBA<UInt8>.self)
        .filter { $0.a > 0 }
        .map { EditorColor(red: $0.r, green: $0.g, blue: $0.b) }
    )
    #expect(frameZeroColors.count > 255)

    let loaded = try GIFLoader.load(data: data)
    #expect(loaded.frames.count == decoded.frames.count)
  }

  @Test("Colors past the palette ceiling quantize to their nearest neighbor")
  func saturatingGIFQuantizesOverflowColors() throws {
    let data = try SaturatingGIFFixture.ensureOnDisk()
    let loaded = try GIFLoader.load(data: data)

    var source = ArraySource(bytes: Array(data))
    let decoded = try GIF.Image.decompress(stream: &source)

    #expect(loaded.palette.usedCount == ColorPalette.capacity)

    // The fixture is fully opaque, so every pixel of every frame must
    // land on a real palette slot, and the slot it lands on must be a
    // near neighbor. The source carries 256 distinct colors and the
    // palette holds 255, so median cut has to merge exactly one pair —
    // and because it splits the widest channel first, that pair differs
    // by a single gradient step (36 per channel), halved by the box's
    // representative.
    let tolerance = 36 * 36
    var quantizedPixels = 0
    for frameIndex in 0..<loaded.frames.count {
      let flattened = loaded.flattenedColors(frameIndex: frameIndex)
      let original = decoded.composited(frameIndex: frameIndex, as: GIF.RGBA<UInt8>.self)
      #expect(flattened.count == original.count)
      for (mapped, source) in zip(flattened, original) {
        guard let mapped else {
          Issue.record("opaque pixel came back as transparent")
          continue
        }
        let expected = EditorColor(red: source.r, green: source.g, blue: source.b)
        let distance = mapped.distanceSquared(to: expected)
        #expect(distance <= tolerance)
        if distance > 0 { quantizedPixels += 1 }
      }
    }
    // The 256th color has nowhere to go, so the quantizer must have
    // merged something.
    #expect(quantizedPixels > 0)
  }

  // MARK: - Loop count

  @Test("A GIF's finite NETSCAPE loop count survives the import")
  func finiteLoopCountSurvivesImport() throws {
    let data = try FiniteLoopGIFFixture.data()
    let document = try GIFLoader.load(data: data)

    // The whole defect in one assertion: the importer used to hand back a
    // document with `loopCount == 0`, silently promoting a three-play
    // animation to an infinite one on the next export.
    #expect(document.loopCount == FiniteLoopGIFFixture.loopCount)
  }

  @Test("The finite-loop fixture on disk is the generator's output")
  func finiteLoopFixtureMatchesItsGenerator() throws {
    let onDisk = try FiniteLoopGIFFixture.data()
    let generated = try Data(FiniteLoopGIFFixture.encodedBytes())
    #expect(onDisk == generated)
  }

  @Test("Loading through the URL entry point reads the loop count too")
  func finiteLoopCountSurvivesURLImport() throws {
    let document = try GIFLoader.load(contentsOf: FiniteLoopGIFFixture.url)
    #expect(document.loopCount == FiniteLoopGIFFixture.loopCount)
  }

  @Test("A GIF declaring an infinite loop imports as infinite")
  func infiniteLoopCountSurvivesImport() throws {
    // `nyan.gif` carries a `NETSCAPE2.0` block declaring 0.
    let document = try GIFLoader.load(contentsOf: try nyanURL())
    #expect(document.loopCount == 0)
  }

  @Test("A GIF with no NETSCAPE block imports as playing once")
  func absentLoopBlockImportsAsPlayingOnce() throws {
    // The format defines an animation with no application extension as
    // playing through exactly once, and `multi-palette-gradient.gif` is
    // the fixture that carries none. Reading it back as 0 would be the
    // same silent promotion to infinity the finite case suffers.
    let data = try MultiPaletteGIFFixture.ensureOnDisk()
    #expect(GIFLoader.declaredLoopCount(in: data) == nil)

    let document = try GIFLoader.load(data: data)
    #expect(document.loopCount == GIFLoader.playsOnce)
  }

  @Test("The loop count survives an import / export round trip")
  func loopCountSurvivesReExport() throws {
    let document = try GIFLoader.load(data: try FiniteLoopGIFFixture.data())
    let bytes = try GIFEncoder.encode(document: document)

    #expect(
      GIFLoader.declaredLoopCount(in: Data(bytes)) == FiniteLoopGIFFixture.loopCount
    )
    let reimported = try GIFLoader.load(data: Data(bytes))
    #expect(reimported.loopCount == FiniteLoopGIFFixture.loopCount)
  }

  @Test("The probe rejects bytes that only look like the block")
  func loopProbeRejectsNearMisses() {
    // Truncated, and not a decodable GIF: nothing was declared.
    #expect(GIFLoader.declaredLoopCount(in: Data()) == nil)
    #expect(
      GIFLoader.declaredLoopCount(
        in: Data(Array("GIF89a".utf8) + [UInt8](repeating: 0, count: 32))
      ) == nil
    )

    // The block's full byte signature, floating free of any GIF
    // structure. The probe used to scan for exactly this and answer `5`;
    // it now parses, so an anchor that is not an application extension of
    // an actual file declares nothing. The same bytes *inside* a GIF are
    // read, which is the case below.
    let anchor = [0x21, 0xFF, 0x0B] as [UInt8] + Array("NETSCAPE2.0".utf8)
    #expect(GIFLoader.declaredLoopCount(in: Data(anchor + [0x03, 0x01, 0x05, 0x00])) == nil)

    // An application extension wearing the `NETSCAPE2.0` name but
    // carrying some other sub-block — `02` is the buffering size —
    // declares no loop count either.
    #expect(
      GIFLoader.declaredLoopCount(
        in: onePixelGIF(extensions: applicationExtension(subBlocks: [[0x02, 0x10, 0x27, 0x00]]))
      ) == nil
    )
  }

  @Test("The probe reads the count out of a real file's block")
  func loopProbeReadsTheDeclaredCount() {
    #expect(GIFLoader.declaredLoopCount(in: onePixelGIF(extensions: loopBlock(5))) == 5)
    // Little-endian, and the high byte matters.
    #expect(GIFLoader.declaredLoopCount(in: onePixelGIF(extensions: loopBlock(256))) == 256)
    // Zero is a declaration too — "forever" — not the absence of one.
    #expect(GIFLoader.declaredLoopCount(in: onePixelGIF(extensions: loopBlock(0))) == 0)
    #expect(GIFLoader.declaredLoopCount(in: onePixelGIF()) == nil)
  }

  // MARK: - Hand-assembled fixtures

  /// A minimal 1×1 GIF89a with `extensions` spliced in ahead of the image
  /// descriptor.
  ///
  /// Hand-assembled because `GIF.Encoder` writes exactly one application
  /// extension and these tests are about what the *decoder* does with the
  /// others — including one wearing the looping block's name without its
  /// payload.
  private func onePixelGIF(extensions: [UInt8] = []) -> Data {
    let header: [UInt8] = [
      // "GIF89a"
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
      // Logical screen descriptor: 1×1, global table of 2 entries.
      0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
      // Global color table: red, white.
      0xFF, 0x00, 0x00,
      0xFF, 0xFF, 0xFF,
    ]
    let image: [UInt8] = [
      // Image descriptor at (0,0), 1×1, no local table.
      0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
      // LZW: minimum code size 2, one literal 0, EOI.
      0x02, 0x02, 0x44, 0x01, 0x00,
      // Trailer.
      0x3B,
    ]
    return Data(header + extensions + image)
  }

  /// `21 FF <len> <identifier> <sub-blocks…> 00`.
  private func applicationExtension(
    identifier: String = "NETSCAPE2.0",
    subBlocks: [[UInt8]]
  ) -> [UInt8] {
    var out: [UInt8] = [0x21, 0xFF, UInt8(identifier.utf8.count)]
    out.append(contentsOf: Array(identifier.utf8))
    for block in subBlocks {
      out.append(UInt8(block.count))
      out.append(contentsOf: block)
    }
    out.append(0x00)
    return out
  }

  private func loopBlock(_ count: Int) -> [UInt8] {
    applicationExtension(
      subBlocks: [[0x01, UInt8(count & 0xFF), UInt8((count >> 8) & 0xFF)]]
    )
  }

  /// Locate `nyan.gif` in the package root, walking up from this source
  /// file. Avoids hard-coded absolute paths and works whether the tests
  /// run from the example package or from the repo root.
  ///
  /// This used to walk up one level too far, to `swift-tui-examples/`,
  /// where no GIF has ever lived — so both nyan tests took a
  /// "fixture missing, self-skip" branch on every run. The skip itself
  /// is gone too: a missing fixture is now a failure, because a test
  /// that quietly passes when its input vanished is worse than no test.
  private func nyanURL() throws -> URL {
    let here = URL(fileURLWithPath: #filePath)
    let packageRoot =
      here
      .deletingLastPathComponent()  // Tests/GIFEditorCoreTests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // gifeditor/
    let url = packageRoot.appendingPathComponent("nyan.gif")
    guard FileManager.default.fileExists(atPath: url.path) else {
      Issue.record("nyan.gif is missing from the package root at \(url.path)")
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

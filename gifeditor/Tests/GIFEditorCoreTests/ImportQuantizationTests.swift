import EditorGIF
import Foundation
import Testing

@testable import GIFEditorCore

/// Import-path tests that run through `GIFLoader` end to end: real GIF
/// bytes in, a `GIFDocument` out. `QuantizerTests` covers the median-cut
/// algorithm in isolation; this suite covers the wiring and the promises
/// the import path makes to the rest of the editor.
///
/// Nothing here self-skips. Both fixtures either exist or are
/// regenerated from a checked-in Swift generator, so a missing file is a
/// failure rather than a silently green run.
@Suite("Import quantization")
struct ImportQuantizationTests {

  // MARK: - Lossless path

  @Test("A GIF that already fits imports with an exact palette and zero pixel error")
  func belowTheCeilingImportsLosslessly() throws {
    let data = try nyanData()
    let document = try GIFLoader.load(data: data)

    var source = ArraySource(bytes: Array(data))
    let decoded = try GIF.Image.decompress(stream: &source)

    // Ground truth: every distinct opaque color the decoder composites.
    var sourceColors = Set<EditorColor>()
    for frameIndex in 0..<decoded.frames.count {
      for px in decoded.composited(frameIndex: frameIndex, as: GIF.RGBA<UInt8>.self)
      where px.a > 0 {
        sourceColors.insert(EditorColor(red: px.r, green: px.g, blue: px.b))
      }
    }
    // Guard the fixture: this test only means "lossless" if the GIF is
    // actually under the ceiling.
    #expect(sourceColors.count <= ColorPalette.capacity - 1)
    #expect(sourceColors.count > 1)

    // The palette is *exactly* slot 0 plus those colors — no median-cut
    // representatives, no padding masquerading as content.
    #expect(document.palette[ColorPalette.transparentSlot] == .transparent)
    #expect(document.palette.usedCount == sourceColors.count + 1)
    #expect(Set(document.palette.usedColors.dropFirst()) == sourceColors)

    // And every pixel maps bit-exactly, transparency included.
    #expect(document.frames.count == decoded.frames.count)
    var comparedPixels = 0
    for frameIndex in 0..<document.frames.count {
      let mapped = document.flattenedColors(frameIndex: frameIndex)
      let original = decoded.composited(frameIndex: frameIndex, as: GIF.RGBA<UInt8>.self)
      #expect(mapped.count == original.count)
      for (actual, expected) in zip(mapped, original) {
        if expected.a == 0 {
          #expect(actual == nil)
        } else {
          #expect(actual == EditorColor(red: expected.r, green: expected.g, blue: expected.b))
        }
        comparedPixels += 1
      }
    }
    #expect(comparedPixels == decoded.frames.count * document.size.area)
  }

  // MARK: - Saturating path

  @Test("A palette-saturating GIF keeps every frame and fills all 256 slots")
  func saturatingImportFillsThePaletteAndKeepsEveryFrame() throws {
    let data = try SaturatingGIFFixture.ensureOnDisk()
    let document = try GIFLoader.load(data: data)

    #expect(document.frames.count == SaturatingGIFFixture.frameCount)
    // 255 median-cut representatives plus the reserved transparent slot.
    #expect(document.palette.usedCount == ColorPalette.capacity)
    #expect(Set(document.palette.usedColors).count == ColorPalette.capacity)
    #expect(document.palette[ColorPalette.transparentSlot] == .transparent)
    for frame in document.frames {
      #expect(frame.layers.count == 1)
      #expect(frame.layers[0].pixels.size == document.size)
    }
  }

  @Test("Saturating-fixture color error stays inside its measured bounds")
  func saturatingImportErrorIsBounded() throws {
    let data = try SaturatingGIFFixture.ensureOnDisk()
    let document = try GIFLoader.load(data: data)

    var source = ArraySource(bytes: Array(data))
    let decoded = try GIF.Image.decompress(stream: &source)

    var maxSquared = 0
    var totalSquared = 0
    var pixels = 0
    for frameIndex in 0..<document.frames.count {
      let mapped = document.flattenedColors(frameIndex: frameIndex)
      let original = decoded.composited(frameIndex: frameIndex, as: GIF.RGBA<UInt8>.self)
      #expect(mapped.count == original.count)
      for (actual, expected) in zip(mapped, original) {
        guard let actual else {
          Issue.record("opaque pixel came back as transparent")
          continue
        }
        let squared = actual.distanceSquared(
          to: EditorColor(red: expected.r, green: expected.g, blue: expected.b)
        )
        maxSquared = max(maxSquared, squared)
        totalSquared += squared
        pixels += 1
      }
    }
    let expectedPixels =
      SaturatingGIFFixture.frameCount * SaturatingGIFFixture.side * SaturatingGIFFixture.side
    #expect(pixels == expectedPixels)

    // Measured on this fixture: max squared RGB distance 324 — a single
    // channel off by 18 — and mean squared distance 2.53125. The source
    // is a 256-entry table quantized to 255, so exactly one pair of
    // colors has to merge: (252,216,255) and (252,252,255) become
    // (252,234,255), splitting a 36-step green difference down the
    // middle. Every other color survives exactly, which is why the mean
    // is two orders of magnitude below the max.
    let meanSquared = Double(totalSquared) / Double(pixels)
    #expect(maxSquared == 324)
    #expect(Double(maxSquared).squareRoot() == 18.0)
    #expect(meanSquared <= 2.6)
    #expect(abs(meanSquared - 2.531_25) < 1e-9)
  }

  // MARK: - Determinism

  @Test("Importing the same bytes twice yields byte-identical palettes")
  func repeatedImportsAgree() throws {
    let data = try SaturatingGIFFixture.ensureOnDisk()
    let first = try GIFLoader.load(data: data)
    let second = try GIFLoader.load(data: data)
    #expect(first.palette.colors == second.palette.colors)
    #expect(first.frames.map { $0.layers[0].pixels } == second.frames.map { $0.layers[0].pixels })
  }

  @Test("The saturating fixture's palette matches its golden bytes")
  func saturatingPaletteMatchesGolden() throws {
    let data = try SaturatingGIFFixture.ensureOnDisk()
    let document = try GIFLoader.load(data: data)

    // Slot 0 is asserted separately: its RGB triple is indistinguishable
    // from opaque black, so the hex dump alone could not tell them apart.
    #expect(document.palette[ColorPalette.transparentSlot] == .transparent)
    let actual =
      document.palette.usedColors
      .dropFirst()
      .map { String(format: "%02x%02x%02x", $0.red, $0.green, $0.blue) }
      .joined()
    #expect(actual.count == 255 * 6)
    #expect(actual == Self.goldenSaturatingPalette)
  }

  // MARK: - Order independence

  @Test("The imported palette does not depend on frame order")
  func paletteIsIndependentOfFrameOrder() throws {
    // Every frame of the saturating fixture is fully opaque and covers
    // the whole canvas, so permuting the frames permutes *which colors
    // are seen first* without changing the set of colors present. A
    // palette built by keeping the first N colors encountered therefore
    // shifts under this permutation; a palette built from the union of
    // all frames cannot.
    let forward = try GIFLoader.load(data: Data(saturatingBytes(frameOrder: [0, 1, 2, 3])))
    let reversed = try GIFLoader.load(data: Data(saturatingBytes(frameOrder: [3, 2, 1, 0])))
    let rotated = try GIFLoader.load(data: Data(saturatingBytes(frameOrder: [2, 3, 0, 1])))

    #expect(forward.palette.colors == reversed.palette.colors)
    #expect(forward.palette.colors == rotated.palette.colors)
  }

  // MARK: - Dithering toggle

  @Test("Import dithering is off by default")
  func importDitheringDefaultsToOff() throws {
    let data = try SaturatingGIFFixture.ensureOnDisk()
    let byDefault = try GIFLoader.load(data: data)
    let explicit = try GIFLoader.load(data: data, dithering: .none)
    #expect(
      byDefault.frames.map { $0.layers[0].pixels }
        == explicit.frames.map { $0.layers[0].pixels }
    )
  }

  @Test("Enabling import dithering changes pixels but not the palette, and repeats exactly")
  func importDitheringIsOptionalAndDeterministic() throws {
    // Deliberately the *multi-palette* fixture, not the saturating one.
    // A 256-color source reduced to 255 merges a single pair, and the
    // resulting error (18 in one channel, against a 36-step palette
    // spacing) is too small to move any neighbouring pixel — dithering
    // there is provably a no-op, so asserting "the output changed"
    // against it would be asserting something false.
    let data = try MultiPaletteGIFFixture.ensureOnDisk()
    let plain = try GIFLoader.load(data: data)
    let dithered = try GIFLoader.load(data: data, dithering: .floydSteinberg)
    let ditheredAgain = try GIFLoader.load(data: data, dithering: .floydSteinberg)

    // Color *selection* is a property of the source, not of the mapping.
    #expect(plain.palette.colors == dithered.palette.colors)
    #expect(
      plain.frames.map { $0.layers[0].pixels } != dithered.frames.map { $0.layers[0].pixels }
    )
    #expect(
      dithered.frames.map { $0.layers[0].pixels }
        == ditheredAgain.frames.map { $0.layers[0].pixels }
    )
    #expect(dithered.frames.count == MultiPaletteGIFFixture.frameCount)
  }

  // MARK: - Beyond the ceiling

  @Test("The multi-palette fixture on disk is the generator's output")
  func multiPaletteFixtureMatchesItsGenerator() throws {
    let onDisk = try MultiPaletteGIFFixture.ensureOnDisk()
    #expect(onDisk == Data(MultiPaletteGIFFixture.encodedBytes()))
  }

  @Test("The multi-palette fixture really carries 1024 colors the decoder reproduces exactly")
  func multiPaletteFixtureIsWellFormed() throws {
    // The fixture is hand-assembled GIF89a, so it has to prove itself
    // before anything measured against it means anything.
    let data = try MultiPaletteGIFFixture.ensureOnDisk()
    var source = ArraySource(bytes: Array(data))
    let decoded = try GIF.Image.decompress(stream: &source)

    #expect(decoded.frames.count == MultiPaletteGIFFixture.frameCount)
    #expect(decoded.size.x == MultiPaletteGIFFixture.side)
    #expect(decoded.size.y == MultiPaletteGIFFixture.side)

    var union = Set<EditorColor>()
    for frameIndex in 0..<decoded.frames.count {
      let actual = decoded.composited(frameIndex: frameIndex, as: GIF.RGBA<UInt8>.self)
      let expected = MultiPaletteGIFFixture.expectedColors(frame: frameIndex)
      #expect(actual.count == expected.count)
      for (got, want) in zip(actual, expected) {
        #expect(got.a == 255)
        #expect(EditorColor(red: got.r, green: got.g, blue: got.b) == want)
        union.insert(EditorColor(red: got.r, green: got.g, blue: got.b))
      }
    }
    #expect(union.count == MultiPaletteGIFFixture.distinctColorCount)
    #expect(union.count > ColorPalette.capacity)
  }

  @Test("A 1024-color GIF imports every frame with a bounded, deterministic reduction")
  func multiPaletteImportIsBoundedAndDeterministic() throws {
    let data = try MultiPaletteGIFFixture.ensureOnDisk()
    let document = try GIFLoader.load(data: data)
    let again = try GIFLoader.load(data: data)

    #expect(document.frames.count == MultiPaletteGIFFixture.frameCount)
    #expect(document.palette.usedCount == ColorPalette.capacity)
    #expect(document.palette.colors == again.palette.colors)

    var maxSquared = 0
    var totalSquared = 0
    var pixels = 0
    for frameIndex in 0..<document.frames.count {
      let mapped = document.flattenedColors(frameIndex: frameIndex)
      let expected = MultiPaletteGIFFixture.expectedColors(frame: frameIndex)
      #expect(mapped.count == expected.count)
      for (actual, want) in zip(mapped, expected) {
        guard let actual else {
          Issue.record("opaque pixel came back as transparent")
          continue
        }
        let squared = actual.distanceSquared(to: want)
        maxSquared = max(maxSquared, squared)
        totalSquared += squared
        pixels += 1
      }
    }

    // Measured: max squared distance 712 (Euclidean 26.7), mean squared
    // distance 390.53 (mean Euclidean 19.75) over 4096 pixels while
    // discarding three quarters of the source's colors. The bounds are
    // stated with headroom so a legitimate improvement to the split
    // heuristic does not read as a regression; the golden palette test
    // is what pins the exact behaviour.
    #expect(pixels == MultiPaletteGIFFixture.frameCount * 32 * 32)
    #expect(maxSquared <= 712)
    #expect(Double(totalSquared) / Double(pixels) <= 391.0)
  }

  // MARK: - Helpers

  /// Re-encodes the saturating fixture's frames in an arbitrary order.
  ///
  /// Built from `SaturatingGIFFixture`'s own constants rather than a
  /// second checked-in file, so there is no fixture that can go missing
  /// and no test that can silently skip.
  private func saturatingBytes(frameOrder: [Int]) throws -> [UInt8] {
    let frames = frameOrder.map { frame in
      GIF.IndexedFrame(
        width: SaturatingGIFFixture.side,
        height: SaturatingGIFFixture.side,
        indices: SaturatingGIFFixture.indices(frame: frame),
        transparentIndex: nil,
        delayCentiseconds: SaturatingGIFFixture.delayCentiseconds,
        disposal: .keep
      )
    }
    let image = GIF.IndexedImage(
      size: (x: SaturatingGIFFixture.side, y: SaturatingGIFFixture.side),
      globalColorTable: SaturatingGIFFixture.colorTable,
      backgroundIndex: 0,
      loopCount: 0,
      frames: frames
    )
    return try GIF.Encoder.encode(image)
  }

  /// `nyan.gif` from the package root — the lossless-path fixture. A
  /// missing file fails here rather than turning every assertion above
  /// into a no-op, which is exactly what the old `guard … else { return }`
  /// skip did.
  private func nyanData() throws -> Data {
    let url =
      URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Tests/GIFEditorCoreTests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // <package root>/
      .appendingPathComponent("nyan.gif")
    guard FileManager.default.fileExists(atPath: url.path) else {
      Issue.record("nyan.gif is missing from the package root at \(url.path)")
      throw CocoaError(.fileNoSuchFile)
    }
    return try Data(contentsOf: url)
  }

  /// Golden palette for `Fixtures/saturating-gradient.gif`: slots 1...255
  /// as RRGGBB hex, in palette order. Pinned because cross-platform
  /// determinism is the whole point of the quantizer's tie-breaking
  /// rules — a change here means a tie resolved differently, not merely
  /// "the picture moved".
  private static let goldenSaturatingPalette: String = [
    "0000000000550000aa0000ff0024000024550024aa0024ff0048000048550048aa0048ff006c00006c55006caa006cff",
    "0090000090550090aa0090ff00b40000b45500b4aa00b4ff00d80000d85500d8aa00d8ff00fc0000fc5500fcaa00fcff",
    "2400002400552400aa2400ff2424002424552424aa2424ff2448002448552448aa2448ff246c00246c55246caa246cff",
    "2490002490552490aa2490ff24b40024b45524b4aa24b4ff24d80024d85524d8aa24d8ff24fc0024fc5524fcaa24fcff",
    "4800004800554800aa4800ff4824004824554824aa4824ff4848004848554848aa4848ff486c00486c55486caa486cff",
    "4890004890554890aa4890ff48b40048b45548b4aa48b4ff48d80048d85548d8aa48d8ff48fc0048fc5548fcaa48fcff",
    "6c00006c00556c00aa6c00ff6c24006c24556c24aa6c24ff6c48006c48556c48aa6c48ff6c6c006c6c556c6caa6c6cff",
    "6c90006c90556c90aa6c90ff6cb4006cb4556cb4aa6cb4ff6cd8006cd8556cd8aa6cd8ff6cfc006cfc556cfcaa6cfcff",
    "9000009000559000aa9000ff9024009024559024aa9024ff9048009048559048aa9048ff906c00906c55906caa906cff",
    "9090009090559090aa9090ff90b40090b45590b4aa90b4ff90d80090d85590d8aa90d8ff90fc0090fc5590fcaa90fcff",
    "b40000b40055b400aab400ffb42400b42455b424aab424ffb44800b44855b448aab448ffb46c00b46c55b46caab46cff",
    "b49000b49055b490aab490ffb4b400b4b455b4b4aab4b4ffb4d800b4d855b4d8aab4d8ffb4fc00b4fc55b4fcaab4fcff",
    "d80000d80055d800aad800ffd82400d82455d824aad824ffd84800d84855d848aad848ffd86c00d86c55d86caad86cff",
    "d89000d89055d890aad890ffd8b400d8b455d8b4aad8b4ffd8d800d8d855d8d8aad8d8ffd8fc00d8fc55d8fcaad8fcff",
    "fc0000fc0055fc00aafc00fffc2400fc2455fc24aafc24fffc4800fc4855fc48aafc48fffc6c00fc6c55fc6caafc6cff",
    // The one merged pair lives in this run: `fceaff` is the midpoint of
    // (252,216,255) and (252,252,255), the two colors that shared the
    // final box.
    "fc9000fc9055fc90aafc90fffcb400fcb455fcb4aafcb4fffcd800fcd855fcd8aafceafffcfc00fcfc55fcfcaa",
  ].joined()
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

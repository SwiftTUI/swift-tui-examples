import Foundation
import Testing

@testable import GIFEditorCore

/// Tier 3: the export artifacts decoded by software this package did not
/// write.
///
/// This is the only tier that proves *conformance* directly rather than
/// by transitivity. Tier 1 checks the encoder against a reader written by
/// the same author from the same spec, and tier 2 checks it against bytes
/// that were blessed once; only this suite puts a freshly encoded file in
/// front of Pillow and ImageMagick and asks them what they see.
///
/// **The gate, and why it is a gate rather than a hard requirement.**
/// These tests need `magick` and `python3` with Pillow. The org's example
/// gate runs `swift test` inside a Linux container that has neither, and
/// provisioning image tooling into that container to satisfy one
/// example's suite is the wrong trade. So the suite is conditional — and
/// conditional in the one way that stays honest: `.enabled(if:)` reports
/// every test in it as **skipped, with the reason printed**, which is
/// categorically different from the `guard fileExists else { return }`
/// pattern that silently turned two of this package's suites into no-ops
/// while still reporting green. A machine without the tools runs tiers 1
/// and 2 and is told, in the output, exactly what it did not run.
///
/// Inside the suite there is still no soft failure: once the gate opens,
/// a tool that then misbehaves throws.
@Suite(
  "Export conformance (external decoders)",
  .enabled(
    if: ExternalImage.isAvailable,
    """
    requires ImageMagick (`magick`) and Python 3 with Pillow; \
    tiers 1 and 2 cover these encoders without them
    """
  )
)
struct ExportExternalDecoderTests {

  // MARK: - Still PNG

  @Test("A 1x1 image round-trips pixel-exactly in both alpha states", arguments: [1, nil])
  func onePixel(slot: PaletteIndex?) throws {
    let size = PixelSize(width: 1, height: 1)
    let document = slabDocument(size: size, slots: [slot])
    let expected: [UInt8] = slot == nil ? [0, 0, 0, 0] : [255, 0, 0, 255]

    try withTemporaryDirectory { scratch in
      let url = scratch.appendingPathComponent("one.png")
      try Data(PNGEncoder.encode(document: document, frameIndex: 0)).write(to: url)

      let pillow = try ExternalImage.pillow(url, scratch: scratch)
      #expect(pillow.format == "PNG")
      #expect(pillow.size == size)
      #expect(pillow.frames.count == 1)
      #expect(pillow.frames[0].rgba == expected)

      let identity = try ExternalImage.magickIdentify(url, scratch: scratch)
      #expect(identity.format == "PNG")
      #expect(identity.imageCount == 1, "a still export must not look like a sequence")
      #expect(identity.channels.contains("a"), "the file must declare an alpha channel")
      let magick = try ExternalImage.magickRGBA(url, scratch: scratch)
      #expect(magick == expected)
    }
  }

  @Test("Transparent, opaque and partly-opaque pixels survive both decoders")
  func mixedTransparency() throws {
    let document = mixedTransparencyDocument()

    try withTemporaryDirectory { scratch in
      let url = scratch.appendingPathComponent("mixed.png")
      try Data(PNGEncoder.encode(document: document, frameIndex: 0)).write(to: url)

      let pillow = try ExternalImage.pillow(url, scratch: scratch)
      #expect(pillow.frames[0].rgba == expectedRGBA(document, frameIndex: 0))

      let magick = try ExternalImage.magickRGBA(url, scratch: scratch)
      #expect(magick == pillow.frames[0].rgba, "two decoders must agree pixel for pixel")
    }
  }

  @Test("An image spanning several stored blocks decodes exactly")
  func multipleStoredBlocks() throws {
    let document = multiBlockDocument()

    try withTemporaryDirectory { scratch in
      let url = scratch.appendingPathComponent("blocks.png")
      try Data(PNGEncoder.encode(document: document, frameIndex: 0)).write(to: url)

      let identity = try ExternalImage.magickIdentify(url, scratch: scratch)
      #expect(identity.size == document.size)

      let pillow = try ExternalImage.pillow(url, scratch: scratch)
      #expect(pillow.size == document.size)
      #expect(pillow.frames[0].rgba == expectedRGBA(document, frameIndex: 0))
    }
  }

  @Test(
    "Python's zlib inflates the stream back to the exact bytes",
    arguments: [0, 1, 65_535, 65_536, 131_071]
  )
  func referenceInflate(byteCount: Int) throws {
    // The same boundaries tier 1 checks with its own reader, re-checked
    // against the implementation the format is specified against.
    let raw = [UInt8]((0..<byteCount).map { UInt8(($0 &* 37) % 256) })
    let stream = StoredDeflate.zlibStream(for: raw)
    try withTemporaryDirectory { scratch in
      let inflated = try ExternalImage.inflate(stream, scratch: scratch)
      #expect(inflated == raw)
    }
  }

  @Test("A corrupted byte is rejected by both decoders")
  func corruptionIsDetected() throws {
    // Verifies the verifier. If the external decoders accepted damaged
    // pixel data, every pixel-exact assertion here would be worthless —
    // and `magick identify` on its own *does* accept it, which is why
    // the pixel path decodes instead of identifying.
    let document = slabDocument(size: PixelSize(width: 8, height: 8), slots: [3])
    var png = PNGEncoder.encode(document: document, frameIndex: 0)
    let idat = try #require(PNGChunkReader.chunks(in: png).first { $0.type == "IDAT" })
    png[idat.payloadOffset + 12] ^= 0xFF

    try withTemporaryDirectory { scratch in
      let url = scratch.appendingPathComponent("corrupt.png")
      try Data(png).write(to: url)
      #expect(throws: (any Error).self) {
        _ = try ExternalImage.pillow(url, scratch: scratch)
      }
      #expect(throws: (any Error).self) {
        _ = try ExternalImage.magickRGBA(url, scratch: scratch)
      }
    }
  }

  // MARK: - APNG

  @Test("Frame count and per-frame delays are exact to an animation decoder")
  func apngDelays() throws {
    let document = slabDocument(
      size: PixelSize(width: 4, height: 3),
      slots: [1, 2, 3, nil],
      delays: [0, 3, 10, 250]
    )

    try withTemporaryDirectory { scratch in
      let url = scratch.appendingPathComponent("anim.png")
      try Data(APNGEncoder.encode(document: document)).write(to: url)

      let decoded = try ExternalImage.pillow(url, scratch: scratch)
      #expect(decoded.format == "PNG")
      #expect(decoded.size == document.size)
      #expect(decoded.frames.count == 4)
      // This is the assertion the whole delay mapping rests on: the
      // decoder's own milliseconds, computed from the fraction in the
      // file, not the numerator this package wrote.
      #expect(
        decoded.frames.map(\.durationMilliseconds) == [0, 30, 100, 2500],
        "centiseconds map onto delay_num over a denominator of 100, exactly"
      )
    }
  }

  @Test("Every APNG frame decodes pixel-exactly, transparency included")
  func apngFramePixels() throws {
    let size = PixelSize(width: 4, height: 3)
    var document = slabDocument(size: size, slots: [1, nil, 4], delays: [5, 5, 5])
    var middle = PixelBuffer(size: size)
    middle[PixelPoint(x: 0, y: 0)] = 2
    middle[PixelPoint(x: 3, y: 2)] = 3
    document.frames[1].layers[0].pixels = middle

    try withTemporaryDirectory { scratch in
      let url = scratch.appendingPathComponent("frames.png")
      try Data(APNGEncoder.encode(document: document)).write(to: url)

      let decoded = try ExternalImage.pillow(url, scratch: scratch)
      #expect(decoded.frames.count == 3)
      for index in 0..<3 {
        // A decoder that composited frames over one another instead of
        // replacing them would show frame 0's red under frame 1's
        // transparency here.
        #expect(
          decoded.frames[index].rgba == expectedRGBA(document, frameIndex: index),
          "frame \(index) must decode to the composited document frame"
        )
      }
    }
  }

  @Test("The loop count reaches the decoder, forever included", arguments: [0, 1, 7])
  func apngLoopCount(loops: Int) throws {
    let document = slabDocument(
      size: PixelSize(width: 2, height: 2),
      slots: [1, 2],
      loopCount: loops
    )

    try withTemporaryDirectory { scratch in
      let url = scratch.appendingPathComponent("loop.png")
      try Data(APNGEncoder.encode(document: document)).write(to: url)
      let decoded = try ExternalImage.pillow(url, scratch: scratch)
      #expect(decoded.loopCount == loops)
    }
  }

  @Test("A single-frame APNG still opens as an ordinary still")
  func apngSingleFrame() throws {
    let document = slabDocument(size: PixelSize(width: 1, height: 1), slots: [2], delays: [7])

    try withTemporaryDirectory { scratch in
      let url = scratch.appendingPathComponent("single.png")
      try Data(APNGEncoder.encode(document: document)).write(to: url)

      let decoded = try ExternalImage.pillow(url, scratch: scratch)
      #expect(decoded.frames.count == 1)
      #expect(decoded.frames[0].rgba == [0, 255, 0, 255])
      #expect(decoded.frames[0].durationMilliseconds == 70)

      let identity = try ExternalImage.magickIdentify(url, scratch: scratch)
      #expect(identity.format == "PNG")
      #expect(identity.size == document.size)
    }
  }

  // MARK: - Spritesheet and frame sequence

  @Test("The spritesheet decodes to the grid the sidecar describes")
  func spritesheetPixels() throws {
    let cell = PixelSize(width: 4, height: 3)
    let document = slabDocument(size: cell, slots: [1, 2, 3, 4, nil])
    let sheet = SpritesheetExport.encode(document: document)

    try withTemporaryDirectory { scratch in
      let url = scratch.appendingPathComponent("sheet.png")
      try Data(sheet.png).write(to: url)

      let decoded = try ExternalImage.pillow(url, scratch: scratch)
      #expect(decoded.size == sheet.layout.sheet)
      #expect(decoded.frames.count == 1, "a spritesheet is one still image")
      #expect(decoded.frames[0].rgba == expectedSheetRGBA(document, layout: sheet.layout))
    }
  }

  @Test("Every exported frame file decodes to its frame")
  func frameSequencePixels() throws {
    let size = PixelSize(width: 3, height: 2)
    let document = slabDocument(size: size, slots: [1, nil, 4, 2])

    try withTemporaryDirectory { scratch in
      let written = try FrameSequenceExport.write(
        document: document,
        toDirectory: scratch.appendingPathComponent("frames"),
        baseName: "walk"
      )
      #expect(written.count == 4)
      for index in written.indices {
        let decoded = try ExternalImage.pillow(written[index], scratch: scratch)
        #expect(decoded.size == size)
        #expect(decoded.frames.count == 1, "a frame export is a still, not an animation")
        #expect(decoded.frames[0].rgba == expectedRGBA(document, frameIndex: index))
      }
    }
  }
}

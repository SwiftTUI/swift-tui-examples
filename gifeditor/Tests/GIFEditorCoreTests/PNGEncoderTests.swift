import Foundation
import Testing

@testable import GIFEditorCore

// The export suites are tiered, and which tier a test belongs to is a
// deployment decision, not a taste one:
//
//   1. **Always-on, dependency-free** — this file and the other
//      export suites. Pure Swift, so they run on every machine and in
//      every container.
//   2. **Always-on goldens** — `ExportGoldenTests`. Byte-for-byte
//      comparisons against checked-in artifacts that two independent
//      decoders validated when they were created, which is how
//      conformance stays pinned on a machine with no decoders.
//   3. **Opt-in external verification** — `ExportExternalDecoderTests`.
//      Real round-trips through Pillow and ImageMagick, skipped *with a
//      stated reason* where those are absent.
//
// Tier 1 is where the framing arithmetic lives, because that is what is
// wrong-or-right on its own: a PNG whose Adler-32 covers the framed
// output instead of the raw bytes, or whose `NLEN` is not the one's
// complement of `LEN`, still looks like a PNG and still opens in some
// viewers.

@Suite("PNG stored-block writer")
struct PNGStoredBlockTests {

  @Test("CRC-32 matches the published check values")
  func crc32CheckValues() {
    #expect(PNGChecksum.crc32([UInt8]()) == 0x0000_0000)
    #expect(PNGChecksum.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
    // The two that appear verbatim in every PNG: `IEND`'s chunk CRC is a
    // constant, because the chunk has no data.
    #expect(PNGChecksum.crc32(Array("IEND".utf8)) == 0xAE42_6082)
    #expect(PNGChecksum.crc32(Array("IHDR".utf8)) == 0xA8A1_AE0A)
  }

  @Test("Adler-32 matches the published check values")
  func adler32CheckValues() {
    // Adler-32 of nothing is 1, not 0 — the `a` accumulator starts at 1.
    // Getting this wrong only shows up on an empty stream, which is
    // exactly the case a writer never tries by hand.
    #expect(PNGChecksum.adler32([]) == 0x0000_0001)
    #expect(PNGChecksum.adler32(Array("123456789".utf8)) == 0x091E_01DE)
    #expect(PNGChecksum.adler32(Array("Wikipedia".utf8)) == 0x11E6_0398)
  }

  @Test(
    "The deferred-modulo Adler-32 agrees with the naive one past its window",
    arguments: [0, 1, 5_551, 5_552, 5_553, 11_104, 76_800]
  )
  func adler32AgreesWithNaiveImplementation(byteCount: Int) {
    // `PNGChecksum.adler32` defers its modulo for 5552 bytes at a time
    // (zlib's NMAX) so the inner loop is division-free; that window is
    // the part that could overflow or drift. `naiveAdler32` reduces after
    // every byte instead. Past one window they must still agree.
    let bytes = [UInt8]((0..<byteCount).map { UInt8($0 % 256) })
    #expect(PNGChecksum.adler32(bytes) == StoredDeflateReader.naiveAdler32(bytes))
  }

  @Test("The zlib header is deflate/32K with a valid check byte")
  func zlibHeader() {
    let stream = StoredDeflate.zlibStream(for: [1, 2, 3])
    #expect(stream[0] == 0x78)
    #expect(stream[1] == 0x01)
    let header = UInt32(stream[0]) << 8 | UInt32(stream[1])
    #expect(header % 31 == 0, "zlib requires the two header bytes to be a multiple of 31")
    #expect(stream[0] & 0x0F == 8, "compression method must be deflate")
    #expect(stream[1] & 0x20 == 0, "no preset dictionary")
  }

  @Test("An empty payload still emits one final, empty stored block")
  func emptyPayloadFraming() {
    // A decoder reads block headers until it sees BFINAL. Emitting no
    // block at all leaves it reading the Adler-32 as a block header.
    #expect(
      StoredDeflate.zlibStream(for: []) == [
        0x78, 0x01,  // zlib header
        0x01,  // BFINAL = 1, BTYPE = 00 (stored)
        0x00, 0x00,  // LEN  = 0
        0xFF, 0xFF,  // NLEN = ~0
        0x00, 0x00, 0x00, 0x01,  // Adler-32 of nothing
      ]
    )
  }

  @Test("Stored blocks split at 65535 bytes with only the last marked final")
  func blockSplitting() {
    let raw = [UInt8]((0..<65_536).map { UInt8($0 % 251) })
    let stream = StoredDeflate.zlibStream(for: raw)

    // header(2) + [block header(1) + LEN(2) + NLEN(2) + 65535] +
    // [block header(1) + LEN(2) + NLEN(2) + 1] + adler(4)
    #expect(stream.count == 2 + 5 + 65_535 + 5 + 1 + 4)

    #expect(stream[2] == 0x00, "the first of two blocks must not be final")
    #expect(stream[3] == 0xFF && stream[4] == 0xFF, "LEN 65535, little-endian")
    #expect(stream[5] == 0x00 && stream[6] == 0x00, "NLEN is LEN's one's complement")

    let secondBlock = 2 + 5 + 65_535
    #expect(stream[secondBlock] == 0x01, "the last block must be final")
    #expect(stream[secondBlock + 1] == 0x01 && stream[secondBlock + 2] == 0x00, "LEN 1")
    #expect(stream[secondBlock + 3] == 0xFE && stream[secondBlock + 4] == 0xFF, "NLEN ~1")
  }

  @Test(
    "The stream survives a strict reader at every block boundary",
    arguments: [0, 1, 4_096, 65_534, 65_535, 65_536, 131_070, 131_071]
  )
  func inflateRoundTrip(byteCount: Int) throws {
    // `StoredDeflateReader` is written from the RFC rather than derived
    // from the writer, and it rejects a wrong header, a wrong
    // complement, a missing final block, trailing bytes, and a wrong
    // Adler-32. The sizes bracket the 65535-byte `LEN` ceiling from both
    // sides. Where the tools exist, tier 3 repeats this against Python's
    // `zlib` — the reference implementation.
    let raw = [UInt8]((0..<byteCount).map { UInt8(($0 &* 37) % 256) })
    #expect(try StoredDeflateReader.inflate(StoredDeflate.zlibStream(for: raw)) == raw)
  }
}

@Suite("PNGEncoder")
struct PNGEncoderTests {

  @Test("The chunk sequence is signature, IHDR, IDAT, IEND")
  func chunkLayout() throws {
    let document = slabDocument(size: PixelSize(width: 5, height: 4), slots: [2])
    let png = PNGEncoder.encode(document: document, frameIndex: 0)

    #expect(Array(png.prefix(8)) == PNGEncoder.signature)
    let chunks = try PNGChunkReader.chunks(in: png)
    #expect(chunks.map(\.type) == ["IHDR", "IDAT", "IEND"])

    let ihdr = chunks[0].payload
    #expect(ihdr.count == 13)
    #expect(PNGChunkReader.uint32(ihdr, at: 0) == 5)
    #expect(PNGChunkReader.uint32(ihdr, at: 4) == 4)
    #expect(ihdr[8] == 8, "bit depth 8")
    #expect(ihdr[9] == 6, "color type 6: truecolor with alpha")
    #expect(
      ihdr[10] == 0 && ihdr[11] == 0 && ihdr[12] == 0,
      "deflate, adaptive filter, no interlace"
    )
  }

  @Test("A 1x1 image survives the round-trip in both alpha states", arguments: [1, nil])
  func onePixel(slot: PaletteIndex?) throws {
    // The degenerate case: one scanline, one pixel, five raster bytes.
    // An off-by-one in the filter byte or the row stride has nowhere to
    // hide here, and no other image in the suite is small enough to make
    // that failure unambiguous.
    let size = PixelSize(width: 1, height: 1)
    let document = slabDocument(size: size, slots: [slot])
    let decoded = try PNGTestDecoder.decode(PNGEncoder.encode(document: document, frameIndex: 0))
    #expect(decoded.size == size)
    #expect(decoded.rgba == expectedRGBA(document, frameIndex: 0))
    #expect(decoded.rgba == (slot == nil ? [0, 0, 0, 0] : [255, 0, 0, 255]))
  }

  @Test("Transparent, opaque and partly-opaque pixels all survive")
  func mixedTransparency() throws {
    let document = mixedTransparencyDocument()
    let decoded = try PNGTestDecoder.decode(PNGEncoder.encode(document: document, frameIndex: 0))
    #expect(
      decoded.rgba == [
        255, 0, 0, 255,
        0, 0, 0, 0,
        0, 255, 0, 255,
        0, 0, 255, 255,
        40, 60, 80, 128,
        0, 0, 0, 0,
      ]
    )
  }

  @Test("An image large enough to need several stored blocks decodes exactly")
  func multipleStoredBlocks() throws {
    // 200 x 100 RGBA plus filter bytes is 80,100 raster bytes: two
    // stored blocks, with the split landing mid-scanline. Nothing about
    // the split may be visible to a reader.
    let document = multiBlockDocument()
    let png = PNGEncoder.encode(document: document, frameIndex: 0)
    let decoded = try PNGTestDecoder.decode(png)
    #expect(decoded.size == document.size)
    #expect(decoded.rgba == expectedRGBA(document, frameIndex: 0))
    #expect(
      Double(png.count) / Double(document.size.area * 4) < 1.01,
      "stored-block overhead must stay near 1x raw"
    )
  }

  @Test("A corrupted byte does not survive a strict reader")
  func corruptionIsDetected() throws {
    // The tier-1 half of "verify the verifier": flipping a byte inside
    // the compressed data breaks the Adler-32 that covers it, so the
    // reader must refuse the stream rather than return plausible
    // garbage. Tier 3 asserts Pillow and ImageMagick refuse the same
    // file.
    let document = slabDocument(size: PixelSize(width: 8, height: 8), slots: [3])
    var png = PNGEncoder.encode(document: document, frameIndex: 0)
    let idat = try #require(PNGChunkReader.chunks(in: png).first { $0.type == "IDAT" })
    png[idat.payloadOffset + 12] ^= 0xFF
    #expect(throws: (any Error).self) {
      _ = try PNGTestDecoder.decode(png)
    }
  }
}

// MARK: - Shared documents

/// A 3x2 canvas covering all three alpha states a PNG has to carry:
/// fully opaque, fully transparent, and a palette color whose alpha is
/// between the two.
func mixedTransparencyDocument() -> GIFDocument {
  let size = PixelSize(width: 3, height: 2)
  var pixels = PixelBuffer(size: size)
  pixels[PixelPoint(x: 0, y: 0)] = 1  // opaque red
  pixels[PixelPoint(x: 1, y: 0)] = nil  // transparent
  pixels[PixelPoint(x: 2, y: 0)] = 2  // opaque green
  pixels[PixelPoint(x: 0, y: 1)] = 3  // opaque blue
  pixels[PixelPoint(x: 1, y: 1)] = 4  // alpha 128
  pixels[PixelPoint(x: 2, y: 1)] = nil  // transparent

  var document = slabDocument(size: size, slots: [nil])
  document.frames[0].layers[0].pixels = pixels
  return document
}

/// A canvas whose raster (80,100 bytes) needs more than one stored
/// block, with the boundary falling inside a scanline.
func multiBlockDocument() -> GIFDocument {
  let size = PixelSize(width: 200, height: 100)
  var pixels = PixelBuffer(size: size)
  for index in 0..<size.area {
    pixels.pixels[index] = index % 7 == 0 ? nil : PaletteIndex((index % 3) + 1)
  }
  var document = slabDocument(size: size, slots: [nil])
  document.frames[0].layers[0].pixels = pixels
  return document
}

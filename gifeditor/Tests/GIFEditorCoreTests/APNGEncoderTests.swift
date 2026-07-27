import Foundation
import Testing

@testable import GIFEditorCore

/// APNG structure and per-frame content, asserted without any tooling
/// installed.
///
/// The delay assertions here are on the *bytes* — `delay_num` over
/// `delay_den` as written into each `fcTL`. What that fraction means to a
/// real animation decoder is tier 3's job (Pillow reports milliseconds,
/// which is what proves the centisecond mapping is exact rather than
/// approximately right), and the checked-in golden keeps a
/// decoder-blessed copy of these exact bytes in between.
@Suite("APNGEncoder")
struct APNGEncoderTests {

  @Test("Frame zero is the default image and lives in IDAT, not fdAT")
  func chunkLayout() throws {
    let document = slabDocument(size: PixelSize(width: 2, height: 2), slots: [1, 2, 3])
    let apng = APNGEncoder.encode(document: document)
    let chunks = try PNGChunkReader.chunks(in: apng)

    #expect(
      chunks.map(\.type) == [
        "IHDR", "acTL",
        "fcTL", "IDAT",
        "fcTL", "fdAT",
        "fcTL", "fdAT",
        "IEND",
      ]
    )

    // `acTL` before the first `IDAT`: a decoder that meets `IDAT` first
    // has already committed to reading a still image.
    let actl = try #require(chunks.first { $0.type == "acTL" })
    #expect(PNGChunkReader.uint32(actl.payload, at: 0) == 3, "num_frames")

    // One counter across both chunk types, no gaps and no repeats — a
    // decoder treats either as a corrupt stream rather than a hint.
    let sequenceNumbers =
      chunks
      .filter { $0.type == "fcTL" || $0.type == "fdAT" }
      .map { PNGChunkReader.uint32($0.payload, at: 0) }
    #expect(sequenceNumbers == [0, 1, 2, 3, 4])
  }

  @Test("Centiseconds are written as an exact fraction over 100")
  func delayFraction() throws {
    // 0 cs (as fast as possible), 3 cs, 10 cs (the document default) and
    // 250 cs, which is past anything a x10 or /10 slip could disguise.
    let delays = [0, 3, 10, 250]
    let document = slabDocument(
      size: PixelSize(width: 4, height: 3),
      slots: [1, 2, 3, nil],
      delays: delays
    )
    let fctl = try PNGChunkReader.chunks(in: APNGEncoder.encode(document: document))
      .filter { $0.type == "fcTL" }
    #expect(fctl.count == 4)

    for (index, chunk) in fctl.enumerated() {
      let numerator = UInt16(chunk.payload[20]) << 8 | UInt16(chunk.payload[21])
      let denominator = UInt16(chunk.payload[22]) << 8 | UInt16(chunk.payload[23])
      #expect(Int(numerator) == delays[index], "delay_num is the centisecond count itself")
      #expect(denominator == APNGEncoder.delayDenominator)
      #expect(denominator == 100, "a denominator of 100 makes the mapping an identity")
    }
  }

  @Test("Frames are written full-canvas with SOURCE blending")
  func frameControlFields() throws {
    let document = slabDocument(
      size: PixelSize(width: 6, height: 5), slots: [1, 2], delays: [4, 9])
    let apng = APNGEncoder.encode(document: document)
    let fctl = try PNGChunkReader.chunks(in: apng).filter { $0.type == "fcTL" }
    #expect(fctl.count == 2)

    for chunk in fctl {
      let payload = chunk.payload
      #expect(payload.count == 26)
      #expect(PNGChunkReader.uint32(payload, at: 4) == 6, "frame width is the canvas width")
      #expect(PNGChunkReader.uint32(payload, at: 8) == 5, "frame height is the canvas height")
      #expect(PNGChunkReader.uint32(payload, at: 12) == 0, "x_offset")
      #expect(PNGChunkReader.uint32(payload, at: 16) == 0, "y_offset")
      #expect(payload[24] == 0, "dispose_op NONE")
      // SOURCE, not OVER: the frames are already composited full-canvas,
      // so each one replaces the buffer outright. OVER would make a
      // transparent frame show the previous one through it.
      #expect(payload[25] == 0, "blend_op SOURCE")
    }
  }

  @Test("Every frame's stream carries that frame's composited pixels")
  func framePixels() throws {
    let size = PixelSize(width: 4, height: 3)
    var document = slabDocument(size: size, slots: [1, nil, 4], delays: [5, 5, 5])
    // Give the middle frame some structure so a writer that reused the
    // previous frame's raster — or wrote frames out of order — shows up
    // as a mismatch rather than as a plausible animation.
    var middle = PixelBuffer(size: size)
    middle[PixelPoint(x: 0, y: 0)] = 2
    middle[PixelPoint(x: 3, y: 2)] = 3
    document.frames[1].layers[0].pixels = middle

    let frames = try PNGTestDecoder.decodeFrames(APNGEncoder.encode(document: document))
    #expect(frames.count == 3)
    for index in 0..<3 {
      #expect(frames[index].size == size)
      #expect(
        frames[index].rgba == expectedRGBA(document, frameIndex: index),
        "frame \(index) must carry the composited document frame"
      )
    }
  }

  @Test("The loop count is written straight through, forever included", arguments: [0, 1, 7])
  func loopCount(loops: Int) throws {
    let document = slabDocument(
      size: PixelSize(width: 2, height: 2),
      slots: [1, 2],
      loopCount: loops
    )
    let chunks = try PNGChunkReader.chunks(in: APNGEncoder.encode(document: document))
    let actl = try #require(chunks.first { $0.type == "acTL" })
    // Zero means "play forever" in both `acTL.num_plays` and
    // `GIFDocument.loopCount`, so the field needs no translation.
    #expect(PNGChunkReader.uint32(actl.payload, at: 4) == UInt32(loops))
  }

  @Test("A single-frame document is still a valid animated PNG")
  func singleFrame() throws {
    let document = slabDocument(size: PixelSize(width: 1, height: 1), slots: [2], delays: [7])
    let apng = APNGEncoder.encode(document: document)

    let chunks = try PNGChunkReader.chunks(in: apng)
    #expect(chunks.map(\.type) == ["IHDR", "acTL", "fcTL", "IDAT", "IEND"])
    let actl = try #require(chunks.first { $0.type == "acTL" })
    #expect(PNGChunkReader.uint32(actl.payload, at: 0) == 1)

    // A decoder with no APNG support must still see an ordinary PNG,
    // which is the entire reason frame zero's pixels live in `IDAT`.
    let still = try PNGTestDecoder.decode(apng)
    #expect(still.rgba == [0, 255, 0, 255])
  }
}

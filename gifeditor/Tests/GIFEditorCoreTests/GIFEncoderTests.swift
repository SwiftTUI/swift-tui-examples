import EditorGIF
import Foundation
import Testing

@testable import GIFEditorCore

@Suite("GIFEncoder")
struct GIFEncoderTests {

  @Test("Single-frame document round-trips through swift-gif's decoder")
  func singleFrameRoundTrip() throws {
    let palette = ColorPalette(
      colors: [
        .transparent,  // slot 0 transparent
        EditorColor(rgbHex: 0x000000),
        EditorColor(rgbHex: 0xFF0000),
        EditorColor(rgbHex: 0x00FF00),
        EditorColor(rgbHex: 0x0000FF),
      ]
    )
    // Build a 4×3 layer with each color used somewhere.
    var pixels = PixelBuffer(size: PixelSize(width: 4, height: 3))
    pixels[PixelPoint(x: 0, y: 0)] = 1  // black
    pixels[PixelPoint(x: 1, y: 0)] = 2  // red
    pixels[PixelPoint(x: 2, y: 0)] = 3  // green
    pixels[PixelPoint(x: 3, y: 0)] = 4  // blue
    pixels[PixelPoint(x: 0, y: 1)] = nil  // transparent
    pixels[PixelPoint(x: 1, y: 1)] = 1
    pixels[PixelPoint(x: 2, y: 1)] = 2
    pixels[PixelPoint(x: 3, y: 1)] = 3
    pixels[PixelPoint(x: 0, y: 2)] = 4
    pixels[PixelPoint(x: 1, y: 2)] = 1
    pixels[PixelPoint(x: 2, y: 2)] = 2
    pixels[PixelPoint(x: 3, y: 2)] = 3

    let layer = EditorLayer(name: "L", pixels: pixels)
    let frame = EditorFrame(layers: [layer], delayCentiseconds: 8)
    let document = GIFDocument(
      size: PixelSize(width: 4, height: 3),
      palette: palette,
      frames: [frame]
    )

    let bytes = try GIFEncoder.encode(document: document)
    var source = ArraySource(bytes: bytes)
    let decoded = try GIF.Image.decompress(stream: &source)
    #expect(decoded.size.x == 4)
    #expect(decoded.size.y == 3)
    #expect(decoded.frames.count == 1)
    #expect(decoded.frames[0].delayCentiseconds == 8)

    let composited = decoded.composited(frameIndex: 0, as: GIF.RGBA<UInt8>.self)
    #expect(composited.count == 12)
    // black @ (0,0), opaque
    #expect(composited[0] == GIF.RGBA<UInt8>(0, 0, 0, 255))
    // red @ (1,0)
    #expect(composited[1] == GIF.RGBA<UInt8>(255, 0, 0, 255))
    // green @ (2,0)
    #expect(composited[2] == GIF.RGBA<UInt8>(0, 255, 0, 255))
    // blue @ (3,0)
    #expect(composited[3] == GIF.RGBA<UInt8>(0, 0, 255, 255))
    // transparent @ (0,1)
    #expect(composited[4].a == 0)
  }

  @Test("Multi-frame document encodes and decodes frame count and delays")
  func multiFrameRoundTrip() throws {
    let palette = ColorPalette(
      colors: [
        .transparent,
        .black,
        .white,
      ]
    )
    let size = PixelSize(width: 2, height: 2)

    var first = PixelBuffer(size: size)
    first[PixelPoint(x: 0, y: 0)] = 1  // black
    var second = PixelBuffer(size: size)
    second[PixelPoint(x: 1, y: 1)] = 2  // white

    let frames = [
      EditorFrame(
        layers: [EditorLayer(name: "1", pixels: first)],
        delayCentiseconds: 5
      ),
      EditorFrame(
        layers: [EditorLayer(name: "2", pixels: second)],
        delayCentiseconds: 12
      ),
    ]

    let document = GIFDocument(size: size, palette: palette, frames: frames)
    let bytes = try GIFEncoder.encode(document: document)
    var source = ArraySource(bytes: bytes)
    let decoded = try GIF.Image.decompress(stream: &source)

    #expect(decoded.frames.count == 2)
    #expect(decoded.frames[0].delayCentiseconds == 5)
    #expect(decoded.frames[1].delayCentiseconds == 12)

    let frame0 = decoded.composited(frameIndex: 0, as: GIF.RGBA<UInt8>.self)
    #expect(frame0[0] == GIF.RGBA<UInt8>(0, 0, 0, 255))  // black @ (0,0)
    let frame1 = decoded.composited(frameIndex: 1, as: GIF.RGBA<UInt8>.self)
    #expect(frame1[3] == GIF.RGBA<UInt8>(255, 255, 255, 255))  // white @ (1,1)
  }

  @Test("Repeated patterns compress without corruption")
  func compressionRoundTrip() throws {
    // Long runs are exactly the case where LZW dictionary growth and
    // codeSize bumps matter; if any of that is wrong, decoded pixels
    // will diverge from what was encoded.
    let palette = ColorPalette(
      colors: [.transparent, .black, .white, EditorColor(rgbHex: 0x808080)]
    )
    let size = PixelSize(width: 32, height: 4)
    var pixels = PixelBuffer(size: size)
    for y in 0..<size.height {
      for x in 0..<size.width {
        let idx: PaletteIndex = ((x + y) % 3 == 0) ? 1 : ((x + y) % 3 == 1 ? 2 : 3)
        pixels[PixelPoint(x: x, y: y)] = idx
      }
    }
    let document = GIFDocument(
      size: size,
      palette: palette,
      frames: [EditorFrame(layers: [EditorLayer(name: "L", pixels: pixels)])]
    )

    let bytes = try GIFEncoder.encode(document: document)
    var source = ArraySource(bytes: bytes)
    let decoded = try GIF.Image.decompress(stream: &source)
    let composited = decoded.composited(frameIndex: 0, as: GIF.RGBA<UInt8>.self)

    for y in 0..<size.height {
      for x in 0..<size.width {
        let actual = composited[y * size.width + x]
        let expectedIdx = pixels[PixelPoint(x: x, y: y)]!
        let expectedColor = palette[expectedIdx]
        #expect(actual.r == expectedColor.red)
        #expect(actual.g == expectedColor.green)
        #expect(actual.b == expectedColor.blue)
      }
    }
  }

  // MARK: - Global color table sizing

  @Test("The emitted color table is sized to the palette the document uses")
  func colorTableIsTrimmedToTheUsedPalette() throws {
    // `ColorPalette` is always 256 entries in memory. Writing all of them
    // cost every export a 768-byte table and a 9-bit LZW start, whatever
    // the document held; five used slots should buy an eight-entry table.
    let palette = ColorPalette(
      colors: [
        .transparent,
        .black,
        .white,
        EditorColor(rgbHex: 0xFF0000),
        EditorColor(rgbHex: 0x00FF00),
      ]
    )
    #expect(palette.colors.count == ColorPalette.capacity)

    let size = PixelSize(width: 4, height: 2)
    var pixels = PixelBuffer(size: size)
    // Slot 0 is the transparency sentinel, so the painted pixels use
    // 1...4 and the holes are the editor's `nil`.
    for x in 0..<size.width {
      pixels[PixelPoint(x: x, y: 0)] = PaletteIndex(1 + x % 4)
      pixels[PixelPoint(x: x, y: 1)] = x == 0 ? nil : PaletteIndex(1 + (x + 2) % 4)
    }
    let document = GIFDocument(
      size: size,
      palette: palette,
      frames: [EditorFrame(layers: [EditorLayer(name: "L", pixels: pixels)])]
    )

    let bytes = try GIFEncoder.encode(document: document)
    var source = ArraySource(bytes: bytes)
    let decoded = try GIF.Image.decompress(stream: &source)

    // Five used slots pad to the next power of two, and the whole table
    // is 24 bytes rather than 768.
    #expect(decoded.frames[0].palette.count == 8)
    #expect(bytes.count < 128)

    // And not one pixel moved.
    let composited = decoded.composited(frameIndex: 0, as: GIF.RGBA<UInt8>.self)
    for y in 0..<size.height {
      for x in 0..<size.width {
        let actual = composited[y * size.width + x]
        guard let index = pixels[PixelPoint(x: x, y: y)] else {
          #expect(actual.a == 0)
          continue
        }
        let expected = palette[index]
        #expect(actual == GIF.RGBA<UInt8>(expected.red, expected.green, expected.blue, 255))
      }
    }
  }

  @Test("A pixel indexing past the used palette still encodes")
  func indexPastUsedCountWidensTheTable() throws {
    // The palette's subscript setter writes padding slots verbatim
    // without growing `usedCount`, so a buffer can legitimately reference
    // an index the used range does not cover. The table has to cover it
    // anyway, or the encoder rejects the document.
    var palette = ColorPalette(colors: [.transparent, .black])
    palette[9] = EditorColor(rgbHex: 0x00FFFF)
    #expect(palette.usedCount == 2)

    let size = PixelSize(width: 2, height: 1)
    var pixels = PixelBuffer(size: size)
    pixels[PixelPoint(x: 0, y: 0)] = 1
    pixels[PixelPoint(x: 1, y: 0)] = 9
    let document = GIFDocument(
      size: size,
      palette: palette,
      frames: [EditorFrame(layers: [EditorLayer(name: "L", pixels: pixels)])]
    )

    let bytes = try GIFEncoder.encode(document: document)
    var source = ArraySource(bytes: bytes)
    let decoded = try GIF.Image.decompress(stream: &source)

    #expect(decoded.frames[0].palette.count == 16)
    let composited = decoded.composited(frameIndex: 0, as: GIF.RGBA<UInt8>.self)
    #expect(composited[0] == GIF.RGBA<UInt8>(0, 0, 0, 255))
    #expect(composited[1] == GIF.RGBA<UInt8>(0, 255, 255, 255))
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

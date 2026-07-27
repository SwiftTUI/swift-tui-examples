import Foundation
import Testing

@testable import GIFEditorCore

/// Documents used by the project-format tests. Kept here so the
/// round-trip, malformed-corpus, and golden suites all describe the same
/// shape of document and a failure in one is comparable to a failure in
/// another.
enum ProjectTestDocuments {

  /// A deterministic pattern with genuinely mixed transparency and a
  /// wide spread of palette indices — a uniformly-filled buffer would
  /// let a broken opacity plane or a swapped-plane bug pass.
  static func pattern(size: PixelSize, seed: Int) -> PixelBuffer {
    var buffer = PixelBuffer(size: size)
    for y in 0..<size.height {
      for x in 0..<size.width {
        let value = (x * 7 + y * 13 + seed * 31) % 11
        // Every eleventh cell stays transparent, so the mask is neither
        // all-zero nor all-one on any row.
        if value == 0 { continue }
        buffer[PixelPoint(x: x, y: y)] = PaletteIndex((value * 17 + seed) % 256)
      }
    }
    return buffer
  }

  /// 3 frames x 3 named layers, mixed visibility, a palette in an order
  /// the default never produces, mixed delays and disposals,
  /// `loopCount = 5`, and a `path` that must not survive encoding.
  static func roundTripSubject() -> GIFDocument {
    let size = PixelSize(width: 12, height: 9)
    let palette = ColorPalette(colors: [
      .transparent,
      EditorColor(rgbHex: 0xC0FF33),  // lime first — the default puts it last
      EditorColor(rgbHex: 0xFF005D),
      .white,
      EditorColor(rgbHex: 0x1E5AAE),
      .black,
      EditorColor(red: 10, green: 20, blue: 30, alpha: 128),  // partial alpha
    ])

    let disposals: [EditorFrame.FrameDisposal] = [.keep, .background, .previous]
    let delays = [3, 17, 250]
    let frames = (0..<3).map { frameIndex in
      let layers = (0..<3).map { layerIndex -> EditorLayer in
        EditorLayer(
          name: "Frame \(frameIndex) / Layer \(layerIndex)",
          // One hidden layer per frame, in a different slot each time.
          isVisible: layerIndex != frameIndex % 3,
          pixels: pattern(size: size, seed: frameIndex * 3 + layerIndex)
        )
      }
      return EditorFrame(
        layers: layers,
        delayCentiseconds: delays[frameIndex],
        disposal: disposals[frameIndex]
      )
    }

    return GIFDocument(
      size: size,
      palette: palette,
      frames: frames,
      path: URL(fileURLWithPath: "/Users/somebody/Documents/secret.halfcell"),
      loopCount: 5
    )
  }

  /// The size the plan's file-size argument is stated in: 256x256 x 20
  /// frames, one layer each.
  static func representativeForSizing() -> GIFDocument {
    let size = PixelSize(width: 256, height: 256)
    let frames = (0..<20).map { frameIndex in
      EditorFrame(
        layers: [
          EditorLayer(name: "Layer \(frameIndex)", pixels: pattern(size: size, seed: frameIndex))
        ]
      )
    }
    return GIFDocument(size: size, frames: frames)
  }
}

@Suite("Project file — lossless round-trip")
struct ProjectFileRoundTripTests {

  @Test("Encoding then decoding preserves every authored field except the path")
  func roundTripPreservesEverything() throws {
    let original = ProjectTestDocuments.roundTripSubject()
    let data = try ProjectFile.data(for: original)
    let decoded = try ProjectFile.document(from: data)

    // Asserted field by field rather than with a single `==` so a
    // regression names what was lost instead of just "not equal".
    #expect(decoded.size == original.size)
    #expect(decoded.loopCount == original.loopCount)
    #expect(decoded.frames.count == original.frames.count)

    #expect(decoded.palette.usedCount == original.palette.usedCount)
    #expect(decoded.palette.usedColors == original.palette.usedColors)
    #expect(decoded.palette.colors == original.palette.colors)

    for (frameIndex, expectedFrame) in original.frames.enumerated() {
      guard frameIndex < decoded.frames.count else { break }
      let frame = decoded.frames[frameIndex]
      #expect(frame.id == expectedFrame.id, "frame \(frameIndex) id")
      #expect(
        frame.delayCentiseconds == expectedFrame.delayCentiseconds,
        "frame \(frameIndex) delay"
      )
      #expect(frame.disposal == expectedFrame.disposal, "frame \(frameIndex) disposal")
      #expect(frame.layers.count == expectedFrame.layers.count, "frame \(frameIndex) layer count")

      for (layerIndex, expectedLayer) in expectedFrame.layers.enumerated() {
        guard layerIndex < frame.layers.count else { break }
        let layer = frame.layers[layerIndex]
        let label = "frame \(frameIndex) layer \(layerIndex)"
        #expect(layer.id == expectedLayer.id, "\(label) id")
        #expect(layer.name == expectedLayer.name, "\(label) name")
        #expect(layer.isVisible == expectedLayer.isVisible, "\(label) visibility")
        #expect(layer.pixels.size == expectedLayer.pixels.size, "\(label) buffer size")
        #expect(layer.pixels.pixels == expectedLayer.pixels.pixels, "\(label) pixels")
      }
    }

    // The authoring machine's absolute path is not part of the artwork.
    #expect(decoded.path == nil)
    #expect(
      original.path != nil, "the subject must actually carry a path for that to mean anything")
    #expect(!String(decoding: data, as: UTF8.self).contains("secret.halfcell"))

    var expected = original
    expected.path = nil
    #expect(decoded == expected)
  }

  @Test("A re-encode of a decoded document is byte-identical")
  func reEncodeIsStable() throws {
    var original = ProjectTestDocuments.roundTripSubject()
    original.path = nil
    let first = try ProjectFile.data(for: original)
    let second = try ProjectFile.data(for: try ProjectFile.document(from: first))
    #expect(first == second)
  }

  @Test("The envelope is a versioned object with the document under 'document'")
  func envelopeShape() throws {
    let data = try ProjectFile.data(for: GIFDocument.blank(size: PixelSize(width: 2, height: 2)))
    let object = try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(object.keys.sorted() == ["document", "formatVersion"])
    #expect(object["formatVersion"] as? Int == 1)
    #expect(ProjectFile.currentFormatVersion == 1)
    #expect(ProjectFile.fileExtension == "halfcell")

    let document = try #require(object["document"] as? [String: Any])
    #expect(document.keys.sorted() == ["frames", "loopCount", "palette", "size"])
    #expect(document["path"] == nil)

    let frames = try #require(document["frames"] as? [[String: Any]])
    let layers = try #require(frames.first?["layers"] as? [[String: Any]])
    let pixels = try #require(layers.first?["pixels"] as? [String: Any])
    #expect(pixels.keys.sorted() == ["indices", "opaqueMask", "size"])
    // Base64 strings, not arrays — the whole point of the payload shape.
    #expect(pixels["indices"] is String)
    #expect(pixels["opaqueMask"] is String)
  }

  @Test("Documents with 1x1 canvases and fully transparent buffers survive")
  func degenerateShapesRoundTrip() throws {
    let tiny = GIFDocument.blank(size: PixelSize(width: 1, height: 1))
    let decoded = try ProjectFile.document(from: try ProjectFile.data(for: tiny))
    #expect(decoded.size == tiny.size)
    #expect(decoded.frames[0].layers[0].pixels.pixels == [nil])
    // The operations the F5 table says a bad `PixelSize` breaks.
    #expect(decoded.size.point(at: 0) == PixelPoint(x: 0, y: 0))
    #expect(decoded.size.indexOf(PixelPoint(x: 0, y: 0)) == 0)
  }
}

@Suite("Project file — pixel payload")
struct ProjectPixelPayloadTests {

  @Test("Pack/unpack is exact for every combination of transparency and index")
  func packUnpackRoundTrip() throws {
    // 19 pixels: not a multiple of 8, so the mask's tail byte is partial.
    let pixels: [PaletteIndex?] = [
      nil, 0, 255, nil, 1, 128, nil, nil, 7, 200, nil, 0, 0, nil, 42, 42, 255, nil, 3,
    ]
    let packed = ProjectPixelPayload.pack(pixels)
    #expect(packed.indices.count == 19)
    #expect(packed.opaqueMask.count == 3)
    let unpacked = try ProjectPixelPayload.unpack(
      indices: packed.indices,
      opaqueMask: packed.opaqueMask,
      count: pixels.count
    )
    #expect(unpacked == pixels)
  }

  @Test("A transparent pixel is stored as slot 0, not as its previous index")
  func transparentPixelsWriteSlotZero() {
    let packed = ProjectPixelPayload.pack([nil, 9, nil])
    #expect(packed.indices == [0, 9, 0])
    #expect(packed.opaqueMask == [0b0000_0010])
  }

  @Test("Slot 0 as a drawing color is distinguishable from transparent")
  func slotZeroIsNotTransparency() throws {
    let pixels: [PaletteIndex?] = [0, nil]
    let packed = ProjectPixelPayload.pack(pixels)
    #expect(packed.indices == [0, 0])
    #expect(packed.opaqueMask == [0b0000_0001])
    let unpacked = try ProjectPixelPayload.unpack(
      indices: packed.indices,
      opaqueMask: packed.opaqueMask,
      count: 2
    )
    #expect(unpacked == pixels)
  }
}

@Suite("Project file — size envelope")
struct ProjectFileSizeTests {

  /// Packed cost is 1 byte of index plus 1 bit of mask per pixel =
  /// 1.125 bytes; base64 multiplies that by 4/3 = 1.500. The measured
  /// total for the document below is 1.505 B/px — the extra 0.005 is
  /// the per-layer JSON keys, the palette, and the envelope. The
  /// ceiling leaves room for a little more metadata and nothing like
  /// enough for a regression to array-encoded pixels, which costs a
  /// measured 3.6 B/px for the same content.
  static let bytesPerPixelCeiling = 1.55

  @Test("A 256x256 x 20-frame document stays inside the base64-plane envelope")
  func representativeDocumentSize() throws {
    let document = ProjectTestDocuments.representativeForSizing()
    let data = try ProjectFile.data(for: document)

    let pixelCount = document.frames.reduce(0) { total, frame in
      total + frame.layers.reduce(0) { $0 + $1.pixels.size.area }
    }
    #expect(pixelCount == 256 * 256 * 20)

    let bytesPerPixel = Double(data.count) / Double(pixelCount)
    #expect(
      bytesPerPixel < Self.bytesPerPixelCeiling,
      "\(data.count) bytes for \(pixelCount) pixels = \(bytesPerPixel) B/px"
    )
  }

  @Test("The packed planes cost far less than the array encoding they replaced")
  func packedPlanesBeatArrayEncoding() throws {
    let size = PixelSize(width: 64, height: 64)
    let buffer = ProjectTestDocuments.pattern(size: size, seed: 3)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let planeEncoded = try encoder.encode(buffer)
    // What synthesized `Codable` would have written for the same pixels.
    let arrayEncoded = try encoder.encode(buffer.pixels)

    let planeCost = Double(planeEncoded.count) / Double(size.area)
    let arrayCost = Double(arrayEncoded.count) / Double(size.area)
    #expect(planeCost < arrayCost * 0.45, "planes \(planeCost) B/px vs array \(arrayCost) B/px")
    #expect(arrayCost > 3.0, "the array encoding is expected to cost 4-5 B/px")
  }
}

@Suite("Project file — open routing")
struct ProjectFileSniffTests {

  @Test("GIF bytes are recognised by signature, project bytes are not")
  func signatureSniffing() throws {
    #expect(ProjectFile.hasGIFSignature(Data("GIF89a…".utf8)))
    #expect(ProjectFile.hasGIFSignature(Data("GIF87a…".utf8)))
    #expect(!ProjectFile.hasGIFSignature(Data()))
    #expect(!ProjectFile.hasGIFSignature(Data("GIF".utf8)))
    #expect(!ProjectFile.hasGIFSignature(Data("{\"formatVersion\":1}".utf8)))

    let project = try ProjectFile.data(for: GIFDocument.blank(size: PixelSize(width: 2, height: 2)))
    #expect(!ProjectFile.hasGIFSignature(project))
  }
}

import EditorGIF
import Foundation
import Testing

@testable import GIFEditorCore

@Suite("Campaign E1 GIF and project contracts", .serialized)
struct AdversarialSetAGIFTests {
  @Test(arguments: Array(31...60))
  func gif(id: Int) throws {
    if id >= 51 {
      try e1PaletteAndProject(id)
      return
    }
    if id >= 48 {
      let bytes: [UInt8]
      switch id {
      case 48: bytes = Array("GIF89".utf8)
      case 49:
        let complete = try GIFEncoder.encode(document: e1GIFDocument([[1, 2]]))
        bytes = Array(complete.prefix(complete.count / 2))
      default:
        // 1x1 GIF89a screen, two-entry global table, trailer, no image.
        bytes = Array("GIF89a".utf8) + [1, 0, 1, 0, 0x80, 0, 0, 0, 0, 0, 255, 255, 255, 0x3B]
      }
      #expect(throws: GIFLoaderError.self) { _ = try GIFLoader.load(data: Data(bytes)) }
      return
    }
    let slots: [[PaletteIndex?]]
    switch id {
    case 31, 37...40: slots = [[1]]
    case 32: slots = [[nil]]
    case 33: slots = [[1, 2]]
    case 34: slots = [[1, 2, 3, 4]]
    case 35: slots = [[1, 2, 1, 2, 1, 2, 1, 2]]
    case 36: slots = [(0..<32).map { PaletteIndex($0 % 4 + 1) }]
    case 41: slots = [[1, 2], [1, 2]]
    case 42: slots = [[1, 2], [1, 3]]
    case 43: slots = [[1, 1], [nil, 1]]
    case 44: slots = [[nil, 1], [nil, 3], [2, nil]]
    case 45, 46: slots = [[1, 1], [nil, 3]]
    default: slots = [[1, 1], [3, nil], [nil, 2]]
    }
    var document = e1GIFDocument(slots)
    if id == 37 { document.loopCount = 1 }
    if id == 38 { document.loopCount = 0 }
    if id == 39 { document.loopCount = 3 }
    if id == 40 { document.frames[0].delayCentiseconds = 0 }
    if id == 45 { document.frames[0].disposal = .keep }
    if id == 47 {
      document.frames[0].disposal = .keep
      document.frames[1].disposal = .previous
      document.frames[2].disposal = .keep
    }
    let full = try e1GIFDecode(GIFEncoder.encode(document: document, frameCoding: .fullFrames))
    let deltaBytes = try GIFEncoder.encode(document: document, frameCoding: .deltaFrames)
    let delta = try e1GIFDecode(deltaBytes)
    #expect(full.frames.count == slots.count && delta.frames.count == slots.count)
    var expected = slots.map { row in row.flatMap(e1RGBA) }
    let black: [UInt8] = [0, 0, 0, 255]
    if id == 43 { expected[1] = black + e1RGBA(1) }
    if id == 44 {
      expected[1] = black + e1RGBA(3)
      expected[2] = e1RGBA(2) + black
    }
    if id == 45 { expected[1] = e1RGBA(1) + e1RGBA(3) }
    if id == 46 { expected[1] = black + e1RGBA(3) }
    if id == 47 {
      expected[1] = e1RGBA(3) + e1RGBA(1)
      expected[2] = e1RGBA(1) + e1RGBA(2)
    }
    for frame in slots.indices {
      let a = e1Composite(full, frame: frame)
      let b = e1Composite(delta, frame: frame)
      #expect(a == expected[frame])
      #expect(b == expected[frame])
      #expect(a == b)
    }
    if (37...40).contains(id) {
      let loaded = try GIFLoader.load(data: Data(deltaBytes))
      #expect(loaded.loopCount == document.loopCount)
      #expect(loaded.frames[0].delayCentiseconds == (id == 40 ? 1 : 10))
    }
    if id == 45 || id == 47 { #expect(!GIFEncoder.supportsDeltaCoding(document)) }
  }
}

private func e1GIFDocument(_ frames: [[PaletteIndex?]]) -> GIFDocument {
  let size = PixelSize(width: frames[0].count, height: 1)
  let palette = ColorPalette(colors: [
    .transparent, .init(rgbHex: 0xFF0000), .init(rgbHex: 0x00FF00), .init(rgbHex: 0x0000FF), .white,
  ])
  return GIFDocument(
    size: size, palette: palette,
    frames: frames.map {
      EditorFrame(layers: [EditorLayer(name: "E1", pixels: PixelBuffer(size: size, pixels: $0))])
    })
}
private func e1RGBA(_ slot: PaletteIndex?) -> [UInt8] {
  switch slot {
  case 1: [255, 0, 0, 255]
  case 2: [0, 255, 0, 255]
  case 3: [0, 0, 255, 255]
  case 4: [255, 255, 255, 255]
  default: [0, 0, 0, 0]
  }
}
private struct E1GIFSource: GIF.BytestreamSource {
  var bytes: [UInt8]
  var offset = 0
  mutating func read(count: Int) -> [UInt8]? {
    guard count >= 0, count <= bytes.count - offset else { return nil }
    defer { offset += count }
    return Array(bytes[offset..<(offset + count)])
  }
}
private func e1GIFDecode(_ bytes: [UInt8]) throws -> GIF.Image {
  var source = E1GIFSource(bytes: bytes)
  return try GIF.Image.decompress(stream: &source)
}
private func e1Composite(_ image: GIF.Image, frame: Int) -> [UInt8] {
  image.composited(frameIndex: frame, as: GIF.RGBA<UInt8>.self).flatMap {
    [$0.r, $0.g, $0.b, $0.a]
  }
}
private func e1PaletteAndProject(_ id: Int) throws {
  switch id {
  case 51, 52, 54, 55:
    let palette: ColorPalette
    if id == 51 {
      palette = try PaletteImport.lospecHex("#fF0000\n00fF00")
    } else if id == 52 {
      palette = try PaletteImport.lospecHex("; comment\nFF0000\n\n00FF00\n")
    } else if id == 54 {
      palette = try PaletteImport.gimpPalette("\u{FEFF}gimp palette\n255 0 0\n0 255 0")
    } else {
      palette = try PaletteImport.gimpPalette(
        "GIMP Palette\n255 0 0 red color\n0 255 0 green color")
    }
    #expect(palette.usedColors == [.init(rgbHex: 0xFF0000), .init(rgbHex: 0x00FF00)])
  case 53:
    #expect(throws: PaletteParseError.self) { _ = try PaletteImport.lospecHex("FF0000FF") }
  case 56:
    #expect(throws: PaletteParseError.self) {
      _ = try PaletteImport.gimpPalette("GIMP Palette\n256 0 0")
    }
  case 57:
    var document = e1GIFDocument([[1, nil], [2, 3]])
    document.frames[0].layers.append(
      EditorLayer(name: "Overlay", pixels: PixelBuffer(size: document.size, pixels: [nil, 4])))
    let bytes = try ProjectFile.data(for: document)
    let loaded = try ProjectFile.document(from: bytes)
    #expect(loaded == document)
    #expect(try ProjectFile.data(for: loaded) == bytes)
  case 58:
    #expect(throws: ProjectDecodeError.self) {
      _ = try ProjectFile.document(from: Data("{\"formatVersion\":999,\"document\":{}}".utf8))
    }
  case 59:
    let valid = try ProjectFile.data(for: e1GIFDocument([[1, 2]]))
    var envelope = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    var document = try #require(envelope["document"] as? [String: Any])
    var frames = try #require(document["frames"] as? [[String: Any]])
    var layers = try #require(frames[0]["layers"] as? [[String: Any]])
    var pixels = try #require(layers[0]["pixels"] as? [String: Any])
    pixels["indices"] = "AQ=="  // One index for the declared two-pixel plane.
    layers[0]["pixels"] = pixels
    frames[0]["layers"] = layers
    document["frames"] = frames
    envelope["document"] = document
    let invalid = try JSONSerialization.data(withJSONObject: envelope)
    #expect(throws: ProjectDecodeError.self) { _ = try ProjectFile.document(from: invalid) }
  default:
    #expect(ProjectFile.hasGIFSignature(Data("GIF87a".utf8)))
    #expect(ProjectFile.hasGIFSignature(Data("GIF89a".utf8)))
    for text in ["", "GIF", "GIF8", "GIF8xx", "GIF90a"] {
      let bytes = Data(text.utf8)
      #expect(!ProjectFile.hasGIFSignature(bytes))
      if text == "GIF8" || text == "GIF8xx" {
        #expect(throws: GIFLoaderError.self) { _ = try GIFLoader.load(data: bytes) }
      }
    }
  }
}

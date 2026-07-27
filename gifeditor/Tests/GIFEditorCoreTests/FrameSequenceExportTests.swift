import Foundation
import Testing

@testable import GIFEditorCore

@Suite("FrameSequenceExport")
struct FrameSequenceExportTests {

  @Test("Every frame becomes a still PNG carrying that frame")
  func perFramePixels() throws {
    let size = PixelSize(width: 3, height: 2)
    let document = slabDocument(size: size, slots: [1, nil, 4, 2])
    let pngs = FrameSequenceExport.pngs(document: document)
    #expect(pngs.count == 4)

    for (index, png) in pngs.enumerated() {
      let chunks = try PNGChunkReader.chunks(in: png)
      #expect(
        !chunks.contains { $0.type == "acTL" },
        "a frame export is a still, not a one-frame animation"
      )
      let decoded = try PNGTestDecoder.decode(png)
      #expect(decoded.size == size)
      #expect(decoded.rgba == expectedRGBA(document, frameIndex: index))
    }
  }

  @Test(
    "Names are zero-padded so a lexicographic listing is frame order",
    arguments: [
      (index: 0, count: 5, name: "walk-000.png"),
      (index: 9, count: 12, name: "walk-009.png"),
      (index: 10, count: 12, name: "walk-010.png"),
      // 1200 frames means the widest index is 1199, so every name in the
      // export widens to four digits rather than only the ones past 999.
      (index: 7, count: 1200, name: "walk-0007.png"),
      (index: 1199, count: 1200, name: "walk-1199.png"),
    ]
  )
  func fileNaming(index: Int, count: Int, name: String) {
    #expect(
      FrameSequenceExport.fileName(baseName: "walk", frameIndex: index, frameCount: count) == name
    )
  }

  @Test("Written files sort into frame order and each one decodes")
  func writesSortableFiles() throws {
    // Twelve frames is the smallest count where the naive `frame-9`,
    // `frame-10` spelling would sort 10 before 9.
    let size = PixelSize(width: 2, height: 2)
    let slots: [PaletteIndex?] = (0..<12).map { index -> PaletteIndex? in
      let slot: Int = index % 4
      return slot == 3 ? nil : PaletteIndex(slot + 1)
    }
    let document = slabDocument(size: size, slots: slots)

    try withTemporaryDirectory { scratch in
      let directory = scratch.appendingPathComponent("frames")
      let written = try FrameSequenceExport.write(
        document: document,
        toDirectory: directory,
        baseName: "walk"
      )
      #expect(written.count == 12)

      let listed = try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .map(\.lastPathComponent)
        .sorted()
      #expect(listed == written.map(\.lastPathComponent))

      // The file order is the frame order: name `n` must hold frame `n`,
      // which is the whole point of the padding rule.
      for index in written.indices {
        let decoded = try PNGTestDecoder.decode([UInt8](try Data(contentsOf: written[index])))
        #expect(decoded.rgba == expectedRGBA(document, frameIndex: index))
      }
    }
  }

  @Test("A one-frame document exports exactly one file")
  func singleFrame() throws {
    let document = slabDocument(size: PixelSize(width: 1, height: 1), slots: [1])
    try withTemporaryDirectory { scratch in
      let written = try FrameSequenceExport.write(
        document: document,
        toDirectory: scratch.appendingPathComponent("single"),
        baseName: "idle"
      )
      #expect(written.map(\.lastPathComponent) == ["idle-000.png"])
      let decoded = try PNGTestDecoder.decode([UInt8](try Data(contentsOf: written[0])))
      #expect(decoded.rgba == [255, 0, 0, 255])
    }
  }
}

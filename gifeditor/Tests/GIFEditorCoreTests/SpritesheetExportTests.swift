import Foundation
import Testing

@testable import GIFEditorCore

@Suite("SpritesheetExport")
struct SpritesheetExportTests {

  @Test(
    "The default column count is ceil(sqrt(frameCount))",
    arguments: [
      (frames: 1, columns: 1, rows: 1),
      (frames: 2, columns: 2, rows: 1),
      (frames: 3, columns: 2, rows: 2),
      (frames: 4, columns: 2, rows: 2),
      (frames: 5, columns: 3, rows: 2),
      (frames: 9, columns: 3, rows: 3),
      (frames: 10, columns: 4, rows: 3),
      (frames: 16, columns: 4, rows: 4),
      (frames: 17, columns: 5, rows: 4),
      (frames: 60, columns: 8, rows: 8),
    ]
  )
  func defaultColumnRule(frames: Int, columns: Int, rows: Int) {
    let layout = SpritesheetLayout(
      frameCount: frames,
      cell: PixelSize(width: 8, height: 4)
    )
    #expect(layout.columns == columns)
    #expect(layout.rows == rows)
    #expect(layout.sheet == PixelSize(width: columns * 8, height: rows * 4))
    #expect(layout.rows * layout.columns >= frames, "every frame needs a cell")
  }

  @Test("An explicit column count wins over the default")
  func explicitColumns() {
    let layout = SpritesheetLayout(
      frameCount: 5,
      cell: PixelSize(width: 16, height: 16),
      columns: 1
    )
    #expect(layout.columns == 1)
    #expect(layout.rows == 5)
    #expect(layout.sheet == PixelSize(width: 16, height: 80))
  }

  @Test("Frames land in row-major cells and padding cells stay transparent")
  func sheetPixels() throws {
    // Five frames in a 3x2 grid: cell (2, 1) is padding, and a consumer
    // slicing the grid must find it empty rather than a repeat of the
    // last frame.
    let cell = PixelSize(width: 4, height: 3)
    let document = slabDocument(size: cell, slots: [1, 2, 3, 4, nil])
    let sheet = SpritesheetExport.encode(document: document)
    #expect(sheet.layout.columns == 3)
    #expect(sheet.layout.rows == 2)
    #expect(sheet.layout.sheet == PixelSize(width: 12, height: 6))

    let decoded = try PNGTestDecoder.decode(sheet.png)
    #expect(decoded.size == sheet.layout.sheet)
    #expect(decoded.rgba == expectedSheetRGBA(document, layout: sheet.layout))

    // The padding cell, spelled out: bottom-right 4x3 block, every byte
    // zero.
    for row in 3..<6 {
      for column in 8..<12 {
        let offset = (row * 12 + column) * 4
        #expect(
          Array(decoded.rgba[offset..<(offset + 4)]) == [0, 0, 0, 0],
          "padding cell pixel (\(column), \(row)) must be transparent"
        )
      }
    }
  }

  @Test("The sidecar describes the grid a consumer has to slice")
  func metadataSchema() throws {
    let cell = PixelSize(width: 4, height: 3)
    let document = slabDocument(
      size: cell,
      slots: [1, 2, 3, 4, nil],
      delays: [10, 5, 5, 20, 3],
      loopCount: 2
    )
    let sheet = SpritesheetExport.encode(document: document)

    // Parsed with JSONSerialization rather than through the metadata's
    // own `Codable` conformance: the file is read by other people's
    // tooling, so what matters is the key names and value types that
    // land on disk, not that the type round-trips through itself.
    let json = try JSONSerialization.jsonObject(with: sheet.metadata.jsonData())
    let root = try #require(json as? [String: Any])

    #expect(root["format"] as? String == "gifeditor-spritesheet")
    #expect(root["version"] as? Int == 1)
    #expect(root["columns"] as? Int == 3)
    #expect(root["rows"] as? Int == 2)
    #expect(root["frameCount"] as? Int == 5)
    #expect(root["loopCount"] as? Int == 2)
    #expect((root["cell"] as? [String: Any])?["width"] as? Int == 4)
    #expect((root["cell"] as? [String: Any])?["height"] as? Int == 3)
    #expect((root["image"] as? [String: Any])?["width"] as? Int == 12)
    #expect((root["image"] as? [String: Any])?["height"] as? Int == 6)

    let frames = try #require(root["frames"] as? [[String: Any]])
    #expect(frames.count == 5)
    for (index, frame) in frames.enumerated() {
      #expect(frame["index"] as? Int == index)
      #expect(frame["column"] as? Int == index % 3)
      #expect(frame["row"] as? Int == index / 3)
      #expect(frame["x"] as? Int == (index % 3) * 4)
      #expect(frame["y"] as? Int == (index / 3) * 3)
      #expect(frame["width"] as? Int == 4)
      #expect(frame["height"] as? Int == 3)
      let centiseconds = document.frames[index].delayCentiseconds
      #expect(frame["delayCentiseconds"] as? Int == centiseconds)
      #expect(
        frame["delayMilliseconds"] as? Int == centiseconds * 10,
        "the millisecond mirror exists to stop a x10 slip at the import site"
      )
    }
  }

  @Test("A one-frame, one-pixel document exports a 1x1 sheet")
  func degenerateSheet() throws {
    let document = slabDocument(size: PixelSize(width: 1, height: 1), slots: [3])
    let sheet = SpritesheetExport.encode(document: document)
    #expect(sheet.layout.sheet == PixelSize(width: 1, height: 1))

    let decoded = try PNGTestDecoder.decode(sheet.png)
    #expect(decoded.size == PixelSize(width: 1, height: 1))
    #expect(decoded.rgba == [0, 0, 255, 255])
  }

  @Test("Writing produces a readable PNG and a parsable sidecar next to it")
  func writesBothFiles() throws {
    let document = slabDocument(size: PixelSize(width: 2, height: 2), slots: [1, 2, 3])
    let sheet = SpritesheetExport.encode(document: document)

    try withTemporaryDirectory { scratch in
      let directory = scratch.appendingPathComponent("out")
      let urls = try SpritesheetExport.write(sheet, toDirectory: directory, baseName: "walk")
      #expect(urls.png.lastPathComponent == "walk.png")
      #expect(urls.metadata.lastPathComponent == "walk.json")

      let written = [UInt8](try Data(contentsOf: urls.png))
      #expect(written == sheet.png, "the file must be the bytes the encoder produced")
      let decoded = try PNGTestDecoder.decode(written)
      #expect(decoded.size == sheet.layout.sheet)

      let sidecar = try JSONSerialization.jsonObject(with: Data(contentsOf: urls.metadata))
      #expect((sidecar as? [String: Any])?["frameCount"] as? Int == 3)
    }
  }
}

/// The sheet raster a document *should* produce, laid out here from the
/// layout's own row-major rule rather than from the exporter's blitting
/// loop, so the assertion is a cross-check and not a mirror.
func expectedSheetRGBA(_ document: GIFDocument, layout: SpritesheetLayout) -> [UInt8] {
  var expected = [UInt8](repeating: 0, count: layout.sheet.area * 4)
  for frameIndex in 0..<document.frames.count {
    let frame = expectedRGBA(document, frameIndex: frameIndex)
    let originX = (frameIndex % layout.columns) * layout.cell.width
    let originY = (frameIndex / layout.columns) * layout.cell.height
    for row in 0..<layout.cell.height {
      for column in 0..<layout.cell.width {
        let source = (row * layout.cell.width + column) * 4
        let target = ((originY + row) * layout.sheet.width + originX + column) * 4
        expected.replaceSubrange(target..<(target + 4), with: frame[source..<(source + 4)])
      }
    }
  }
  return expected
}

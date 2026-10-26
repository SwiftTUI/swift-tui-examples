import Foundation
import Testing

@testable import GIFEditorCore

@Suite("Document ingestion")
struct DocumentIngestionTests {
  @Test("Recognition is content-based and bounded")
  func recognition() {
    #expect(DocumentIngestion.kind(of: Data("GIF89a".utf8)) == .gif)
    #expect(DocumentIngestion.kind(of: Data("\n \t{\"formatVersion\":1}".utf8)) == .project)
    #expect(DocumentIngestion.kind(of: Data("notes".utf8)) == nil)

    let beyondBound = Data(
      [UInt8](repeating: UInt8(ascii: " "), count: 64)
        + [UInt8(ascii: "{")]
    )
    #expect(DocumentIngestion.kind(of: beyondBound) == nil)
  }

  @Test("Only a complete supported GIF header routes to the GIF decoder")
  func gifRoutingRequiresACompleteSupportedHeader() throws {
    #expect(DocumentIngestion.kind(of: Data("GIF87a".utf8)) == .gif)
    #expect(DocumentIngestion.kind(of: Data("GIF89".utf8)) == nil)
    #expect(DocumentIngestion.kind(of: Data("GIF88a".utf8)) == nil)

    let encoded = try GIFEncoder.encode(
      document: GIFDocument.blank(size: PixelSize(width: 2, height: 2)))
    try #require(Array(encoded.prefix(6)) == Array("GIF89a".utf8))

    // The same stream under the other supported version still opens.
    var gif87a = encoded
    gif87a[4] = UInt8(ascii: "7")
    let ingested = try DocumentIngestion.ingest(Data(gif87a))
    #expect(ingested.kind == .gif)
    #expect(ingested.document.frames.count == 1)

    // Under a version the decoder does not read, it is not a GIF this
    // build supports, so it is unrecognized rather than a damaged GIF.
    var gif88a = encoded
    gif88a[4] = UInt8(ascii: "8")
    do {
      _ = try DocumentIngestion.ingest(Data(gif88a))
      Issue.record("expected an unsupported GIF version to be refused")
    } catch {
      #expect(error == .unrecognizedFormat)
    }
  }

  @Test("A GIF is imported with its policy and provenance")
  func gifIngestion() throws {
    let sourceDocument = GIFDocument.blank(size: PixelSize(width: 2, height: 2))
    let bytes = Data(try GIFEncoder.encode(document: sourceDocument))
    let url = URL(fileURLWithPath: "/fixtures/animation.renamed")

    let ingested = try DocumentIngestion.ingest(
      bytes,
      source: .file(url),
      policy: GIFImportPolicy(dithering: .none)
    )

    #expect(ingested.kind == .gif)
    #expect(ingested.provenance == DocumentProvenance(source: .file(url), kind: .gif))
    #expect(ingested.document.frames.count == 1)
    #expect(ingested.document.frames[0].layers.map(\.name) == ["Imported"])
  }

  @Test("A project restores authoring structure without acquiring a backing")
  func projectIngestion() throws {
    let size = PixelSize(width: 3, height: 2)
    let document = GIFDocument(
      size: size,
      frames: [
        EditorFrame(layers: [
          EditorLayer(name: "Bottom", pixels: PixelBuffer(size: size, fill: 1)),
          EditorLayer(name: "Top", isVisible: false, pixels: PixelBuffer(size: size, fill: 2)),
        ])
      ],
      loopCount: 4
    )
    let url = URL(fileURLWithPath: "/fixtures/session")

    let ingested = try DocumentIngestion.ingest(
      ProjectFile.data(for: document),
      source: .file(url)
    )

    #expect(ingested.kind == .project)
    #expect(ingested.document.frames[0].layers.map(\.name) == ["Bottom", "Top"])
    #expect(ingested.document.frames[0].layers.map(\.isVisible) == [true, false])
    #expect(ingested.document.loopCount == 4)
  }

  @Test("Unsupported and malformed bytes have neutral typed failures")
  func failures() {
    do {
      _ = try DocumentIngestion.ingest(Data("not a supported document".utf8))
      Issue.record("expected unrecognized bytes to fail")
    } catch {
      #expect(error == .unrecognizedFormat)
    }

    do {
      _ = try DocumentIngestion.ingest(Data("GIF89a".utf8))
      Issue.record("expected a damaged GIF to fail")
    } catch {
      guard case .malformed(kind: .gif, detail: let detail) = error else {
        Issue.record("expected a malformed GIF, got \(error)")
        return
      }
      #expect(!detail.isEmpty)
    }

    do {
      _ = try DocumentIngestion.ingest(Data("{\"formatVersion\":1}".utf8))
      Issue.record("expected a damaged project to fail")
    } catch {
      guard case .malformed(kind: .project, detail: let detail) = error else {
        Issue.record("expected a malformed project, got \(error)")
        return
      }
      #expect(!detail.isEmpty)
    }
  }
}

// Wave-3 regression hunt, part CA (STUI-1167): neighbours of the STUI-1184 header
// predicate (5c5d547) in core routing. Case w3ca030; the hypotheses precede this test
// in the hunt's evidence directory.
@Suite("Wave-3 hunt CA: GIF87a routing neighbours")
struct Wave3RegressionHuntIngestionTests {
  @Test("w3ca030 a genuine GIF87a stream routes and decodes, also from a Data slice")
  func w3ca030GenuineGIF87aStreamIngests() throws {
    // A 1x1 red GIF87a: no extension blocks, so nothing in it needs 89a. LZW codes
    // clear (4), 0 and end (5) at 3 bits, packed LSB first: 0x44 0x01.
    let gif87a: [UInt8] = [
      0x47, 0x49, 0x46, 0x38, 0x37, 0x61,  // "GIF87a"
      0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,  // 1x1, 2-entry global table
      0xFF, 0x00, 0x00, 0xFF, 0xFF, 0xFF,  // red, white
      0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,  // image descriptor
      0x02, 0x02, 0x44, 0x01, 0x00,  // LZW minimum code size 2, one sub-block
      0x3B,  // trailer
    ]
    let slice = Data([0x00, 0x01, 0x02] + gif87a).dropFirst(3)
    try #require(slice.startIndex == 3)
    for (name, data) in [("whole", Data(gif87a)), ("slice", slice)] {
      #expect(DocumentIngestion.kind(of: data) == .gif, "\(name)")
      let ingested = try DocumentIngestion.ingest(data)
      #expect(ingested.kind == .gif, "\(name)")
      #expect(ingested.document.frames.count == 1, "\(name)")
      #expect(ingested.document.size == PixelSize(width: 1, height: 1), "\(name)")
    }
  }
}

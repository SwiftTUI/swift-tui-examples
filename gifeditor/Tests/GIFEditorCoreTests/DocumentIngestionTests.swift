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

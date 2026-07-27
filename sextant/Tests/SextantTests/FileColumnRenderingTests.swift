import Foundation
import SwiftTUI
import Testing

@testable import Sextant

@MainActor
struct FileColumnRenderingTests {
  @Test("deep independent scrolls retain absolute geometry with bounded authored rows")
  func deepIndependentScrollWindow() {
    let range = FileColumnWindowPolicy.authoredRange(
      entryCount: 1_000,
      viewportTop: 900
    )

    #expect(range.contains(900))
    #expect(range.count <= 48)
    #expect(range == 900..<948)
    #expect(
      range.lowerBound + range.count + (1_000 - range.upperBound)
        == 1_000
    )
  }

  @Test("authored row windows cover both collection boundaries")
  func authoredWindowBoundaries() {
    let first = FileColumnWindowPolicy.authoredRange(
      entryCount: 1_000,
      viewportTop: 0
    )
    let last = FileColumnWindowPolicy.authoredRange(
      entryCount: 1_000,
      viewportTop: 999
    )

    #expect(first == 0..<48)
    #expect(last == 952..<1_000)
  }

  @Test("tall viewports author every visible row plus bounded overscan")
  func tallViewportWindow() {
    let range = FileColumnWindowPolicy.authoredRange(
      entryCount: 1_000,
      viewportTop: 900,
      viewportHeight: 80
    )

    #expect(range == 900..<988)
    #expect(range.contains(979))
  }

  @Test("a tall rendered viewport does not replace visible entries with spacer rows")
  func tallViewportRendering() {
    let directory = URL(fileURLWithPath: "/tmp/large")
    let entries = makeEntries(count: 100)
    let artifacts = DefaultRenderer().render(
      FileColumn(
        directory: directory,
        entries: entries,
        selection: entries[0].id,
        isActive: true
      ),
      context: .init(identity: Identity(components: ["TallColumn"])),
      proposal: .init(width: 30, height: 60)
    )
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(rendered.contains("file-55.swift"))
    #expect(!rendered.contains("file-99.swift"))
  }

  @Test("filtering recomputes visibility for an unchanged selection identity")
  func filteringRecomputesSelectionLocation() throws {
    let entries = makeEntries(count: 1_000)
    let selected = entries[900]
    let filtered = [selected]

    #expect(
      FileColumnWindowPolicy.selectionIndex(
        entries: entries,
        selection: selected.id
      ) == 900
    )
    #expect(
      FileColumnWindowPolicy.selectionIndex(
        entries: filtered,
        selection: selected.id
      ) == 0
    )
  }

  @Test("re-sorting recomputes visibility for an unchanged selection identity")
  func sortingRecomputesSelectionLocation() {
    let entries = makeEntries(count: 1_000)
    let selected = entries[0]
    let reversed = Array(entries.reversed())

    #expect(
      FileColumnWindowPolicy.selectionIndex(
        entries: entries,
        selection: selected.id
      ) == 0
    )
    #expect(
      FileColumnWindowPolicy.selectionIndex(
        entries: reversed,
        selection: selected.id
      ) == 999
    )
  }

  @Test("large file columns realize viewport-scale row work")
  func largeFileColumnsRealizeViewportScaleRowWork() {
    let directory = URL(fileURLWithPath: "/tmp/large")
    let entries = makeEntries(count: 1_000)
    let renderer = DefaultRenderer()

    let artifacts = renderer.render(
      FileColumn(
        directory: directory,
        entries: entries,
        selection: entries[0].id,
        isActive: true
      ),
      context: .init(identity: Identity(components: ["Column"])),
      proposal: .init(width: 30, height: 8)
    )
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(rendered.contains("file-0.swift"))
    #expect(!rendered.contains("file-999.swift"))
    #expect(artifacts.diagnostics.counts.resolvedNodes < 80)
    #expect(artifacts.diagnostics.counts.measuredNodes < 80)
    #expect(artifacts.diagnostics.counts.placedNodes < 80)
  }

  private func makeEntries(count: Int) -> [BrowserItem] {
    let directory = URL(fileURLWithPath: "/tmp/large")
    let directoryID = DirectoryID(identity: .path(directory.path))
    return (0..<count).map { index in
      let url = directory.appendingPathComponent("file-\(index).swift")
      let identity = FileSystemIdentity.path(url.path)
      return BrowserItem(
        id: BrowserItemID(identity: identity),
        directoryID: directoryID,
        name: url.lastPathComponent,
        url: url,
        kind: .file,
        listingMetadata: ItemMetadata(identity: identity)
      )
    }
  }
}

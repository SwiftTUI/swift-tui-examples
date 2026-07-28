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

  @Test("the active column bars its selection only, never its header")
  func activeColumnAccentBars() {
    let entries = makeEntries(count: 3)
    let artifacts = DefaultRenderer().render(
      FileColumn(
        directory: URL(fileURLWithPath: "/tmp/large"),
        entries: entries,
        selection: entries[1].id,
        isActive: true,
        contentWidth: 30
      ),
      context: .init(identity: Identity(components: ["ActiveColumn"])),
      proposal: .init(width: 30, height: 10)
    )
    let cells = artifacts.rasterSurface.cells

    // Row 0 is the column header, row 1 the divider, rows 2... the entries.
    // The header stays plain — only the selected entry is barred.
    #expect(!isBarred(cells[0], width: 30))
    #expect(isBarred(cells[3], width: 30))
    #expect(!isBarred(cells[2], width: 30))
    #expect(!isBarred(cells[4], width: 30))
  }

  @Test("an inactive column bars nothing")
  func inactiveColumnHasNoAccentBars() {
    let entries = makeEntries(count: 3)
    let artifacts = DefaultRenderer().render(
      FileColumn(
        directory: URL(fileURLWithPath: "/tmp/large"),
        entries: entries,
        selection: entries[1].id,
        isActive: false,
        contentWidth: 30
      ),
      context: .init(identity: Identity(components: ["InactiveColumn"])),
      proposal: .init(width: 30, height: 10)
    )

    #expect(
      artifacts.rasterSurface.cells.allSatisfy { !isBarred($0, width: 30) }
    )
  }

  @Test("ordinary entries read in the primary foreground, not the separator tone")
  func unselectedRowsUsePrimaryForeground() throws {
    let primary = try #require(probeForeground(SemanticShapeStyle(.foreground)))
    let separator = try #require(probeForeground(SemanticShapeStyle(.separator)))
    #expect(primary != separator)

    let entries = makeEntries(count: 3)
    let artifacts = DefaultRenderer().render(
      FileColumn(
        directory: URL(fileURLWithPath: "/tmp/large"),
        entries: entries,
        selection: entries[1].id,
        isActive: true,
        contentWidth: 30
      ),
      context: .init(identity: Identity(components: ["PrimaryRows"])),
      proposal: .init(width: 30, height: 10)
    )
    let cells = artifacts.rasterSurface.cells

    // Row 0 is the header, row 1 the divider, row 3 the barred selection —
    // rows 2 and 4 are the ordinary entries this covers.
    for row in [2, 4] {
      let glyphs = cells[row].filter { $0.character != " " }
      #expect(!glyphs.isEmpty)
      #expect(glyphs.allSatisfy { $0.style?.foregroundColor == primary })
    }
  }

  /// The color a semantic role resolves to under the renderer's own theme,
  /// harvested by rendering a single glyph in it. Naming the hex here instead
  /// would pin the assertion to a palette this demo does not own.
  private func probeForeground(_ style: SemanticShapeStyle) -> Color? {
    DefaultRenderer().render(
      Text("X").foregroundStyle(style),
      context: .init(
        identity: Identity(components: ["Probe", "\(style.role)"])
      ),
      proposal: .init(width: 1, height: 1)
    )
    .rasterSurface.cells.first?.first?.style?.foregroundColor
  }

  /// Whether every cell across the column carries the accent bar, which is
  /// painted by padding the label out and reversing it rather than by wrapping
  /// the row in a background decoration — two such decorations cost ~9 ms of
  /// this column's 50 ms interaction budget at 10,000 entries.
  private func isBarred(_ row: [RasterCell], width: Int) -> Bool {
    guard row.count >= width else {
      return false
    }
    return row.prefix(width).allSatisfy {
      $0.style?.emphasis.contains(.reverse) == true
    }
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

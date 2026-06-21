import Foundation
import SwiftTUI
import Testing

@testable import Layouts

/// SwiftTUI-side exporter for the cross-engine layout-comparison sweep
/// (docs/plans/2026-06-21-001-...). Env-gated so it never runs in the normal
/// `layouts` gate — set `LAYOUT_EXPORT=1` to emit one JSON per catalog entry.
///
/// Each entry is rendered headlessly through the same `DefaultRenderer` path the
/// behaviour tests use (zero-flake, no terminal). We emit:
///   - `contentBBoxCells`: the bounding box of non-blank cells, in the SAME
///     cell space the SwiftUI side normalizes to (pixels ÷ scale ÷ 10) — the
///     directly-comparable content-extent signal.
///   - `lines`: the plain-text cell grid (a recognizable SwiftTUI render that
///     doubles as a text contact-sheet panel until the @_spi raster seam lands).
///
/// Output: /tmp/layout-probe/swifttui/<id>.json
@MainActor
@Suite struct LayoutComparisonExport {
  static let cols = 60
  static let rows = 30
  static let outDir = "/tmp/layout-probe/swifttui"

  @Test("Export SwiftTUI content geometry for every catalog entry")
  func exportAllEntries() throws {
    guard ProcessInfo.processInfo.environment["LAYOUT_EXPORT"] != nil else {
      return  // no-op in the normal gate
    }
    try? FileManager.default.createDirectory(atPath: Self.outDir, withIntermediateDirectories: true)

    for entry in LayoutCatalog.all {
      let raster = render(entry.makeView(), width: Self.cols, height: Self.rows, id: entry.id).rasterSurface
      let bbox = Self.contentBBox(lines: raster.lines)

      // Every entry must produce *some* output (the marker is guaranteed present).
      #expect(bbox != nil, "\(entry.id): rendered blank (no non-space cells)")

      let dto = SwiftTUIExportJSON(
        id: entry.id,
        marker: entry.marker,
        canvasCells: .init(width: Self.cols, height: Self.rows),
        contentBBoxCells: bbox,
        lines: raster.lines
      )
      let enc = JSONEncoder()
      enc.outputFormatting = [.prettyPrinted, .sortedKeys]
      try enc.encode(dto).write(to: URL(fileURLWithPath: "\(Self.outDir)/\(entry.id).json"))
    }
  }

  /// Bounding box of non-blank cells. `lines` preserves leading whitespace
  /// (left grid offset), so first/last non-space columns give the x-extent.
  static func contentBBox(lines: [String]) -> BBoxJSON? {
    var minCol = Int.max, maxCol = -1, minRow = Int.max, maxRow = -1
    for (y, line) in lines.enumerated() {
      let chars = Array(line)
      guard let first = chars.firstIndex(where: { $0 != " " }),
            let last = chars.lastIndex(where: { $0 != " " })
      else { continue }
      minCol = min(minCol, first)
      maxCol = max(maxCol, last)
      minRow = min(minRow, y)
      maxRow = max(maxRow, y)
    }
    guard maxRow >= 0, maxCol >= minCol else { return nil }
    return BBoxJSON(x: minCol, y: minRow, width: maxCol - minCol + 1, height: maxRow - minRow + 1)
  }
}

struct SwiftTUIExportJSON: Encodable {
  let id: String
  let marker: String
  let canvasCells: WHJSON
  let contentBBoxCells: BBoxJSON?
  let lines: [String]
}

struct WHJSON: Encodable { let width: Int; let height: Int }
struct BBoxJSON: Encodable { let x: Int; let y: Int; let width: Int; let height: Int }

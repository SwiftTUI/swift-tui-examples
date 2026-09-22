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
///   - `contentBBoxCells`: the bounding box of visible cells, in the SAME
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
      let raster = render(entry.makeView(), width: Self.cols, height: Self.rows, id: entry.id)
        .rasterSurface
      let bbox = Self.contentBBox(raster: raster)

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

  /// Final cell paint relative to the comparison tier's opaque black canvas
  /// and white default text. Untouched/default-style spaces are not content.
  /// Cell indices preserve terminal width (including wide-glyph continuations)
  /// and the surface size clips paint to the exported comparison canvas.
  static func contentBBox(
    raster: RasterSurface,
    canvas: Color = .black,
    foreground: Color = .white
  ) -> BBoxJSON? {
    var minCol = Int.max
    var maxCol = -1
    var minRow = Int.max
    var maxRow = -1
    func differs(_ color: Color, from other: Color) -> Bool {
      color.alpha > 0
        && (color.red != other.red || color.green != other.green || color.blue != other.blue)
    }
    func visible(_ cell: RasterCell, row: [RasterCell]) -> Bool {
      let style = cell.style ?? ResolvedTextStyle()
      guard style.opacity > 0 else { return false }
      let reversed = style.emphasis.contains(.reverse)
      let background =
        reversed ? (style.foregroundColor ?? foreground) : (style.backgroundColor ?? canvas)
      let ink = reversed ? (style.backgroundColor ?? canvas) : (style.foregroundColor ?? foreground)
      if differs(background, from: canvas) { return true }
      if let lead = cell.continuationLeadX, row.indices.contains(lead), !row[lead].isContinuation {
        return visible(row[lead], row: row)
      }
      let hasInk =
        cell.character != " " || style.underlineStyle != nil || style.strikethroughStyle != nil
      return hasInk && differs(ink, from: canvas)
    }
    for (y, row) in raster.cells.prefix(max(0, raster.size.height)).enumerated() {
      for (x, cell) in row.prefix(max(0, raster.size.width)).enumerated()
      where visible(cell, row: row) {
        minCol = min(minCol, x)
        maxCol = max(maxCol, x)
        minRow = min(minRow, y)
        maxRow = max(maxRow, y)
      }
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

struct WHJSON: Encodable {
  let width: Int
  let height: Int
}
struct BBoxJSON: Encodable, Equatable {
  let x: Int
  let y: Int
  let width: Int
  let height: Int
}

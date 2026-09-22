import SwiftTUI
import Testing

@MainActor
struct LayoutComparisonBoundsTests {
  @Test func emptyAndCanvasColoredSpacesAreBlank() {
    let cells = [
      [
        RasterCell(), RasterCell(style: .init(backgroundColor: .black)),
        RasterCell(style: .init(backgroundColor: .red, opacity: 0)),
        RasterCell(style: .init(backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 0))),
      ]
    ]
    #expect(bounds(cells) == nil)
  }

  @Test func coloredSpacesAndGlyphsContributeTheirUnion() {
    let cells = [
      [RasterCell(), RasterCell(style: .init(backgroundColor: .red)), RasterCell()],
      [RasterCell(), RasterCell(), RasterCell(character: "X")],
    ]
    #expect(bounds(cells) == BBoxJSON(x: 1, y: 0, width: 2, height: 2))
  }

  @Test func fillOnlyRectangleAndClippedFill() {
    let raster = render(Rectangle().fill(Color.red).frame(width: 4, height: 2), width: 8, height: 4)
      .rasterSurface
    #expect(
      LayoutComparisonExport.contentBBox(raster: raster)
        == BBoxJSON(x: 0, y: 0, width: 4, height: 2))
    let clipped = RasterSurface(size: .init(width: 2, height: 1), cells: raster.cells)
    #expect(
      LayoutComparisonExport.contentBBox(raster: clipped)
        == BBoxJSON(x: 0, y: 0, width: 2, height: 1))
  }

  @Test func wideGlyphUsesCellCoordinatesAndContinuation() {
    let raster = render(Text(" 界"), width: 8, height: 2).rasterSurface
    #expect(
      LayoutComparisonExport.contentBBox(raster: raster)
        == BBoxJSON(x: 1, y: 0, width: 2, height: 1))
    let narrow = RasterSurface(size: .init(width: 2, height: 2), cells: raster.cells)
    #expect(
      LayoutComparisonExport.contentBBox(raster: narrow)
        == BBoxJSON(x: 1, y: 0, width: 1, height: 1))
  }

  @Test func glyphExtentStaysStableAndReverseSpacesPaint() {
    let raster = render(Text("  hello"), width: 12, height: 2).rasterSurface
    #expect(
      LayoutComparisonExport.contentBBox(raster: raster)
        == BBoxJSON(x: 2, y: 0, width: 5, height: 1))
    #expect(
      bounds([[RasterCell(style: .init(emphasis: .reverse))]])
        == BBoxJSON(x: 0, y: 0, width: 1, height: 1))
  }

  private func bounds(_ cells: [[RasterCell]]) -> BBoxJSON? {
    LayoutComparisonExport.contentBBox(
      raster: RasterSurface(
        size: .init(width: cells.first?.count ?? 0, height: cells.count), cells: cells))
  }
}

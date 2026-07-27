import Foundation
import Testing

@testable import GIFEditorCore

@Suite("ToolOps")
struct ToolOpsTests {

  @Test("Pen writes the requested index and leaves other pixels untouched")
  func penWritesOneCell() {
    var buffer = PixelBuffer(size: PixelSize(width: 3, height: 3))
    buffer[PixelPoint(x: 0, y: 0)] = 7
    let result = ToolOps.pen(on: buffer, at: PixelPoint(x: 1, y: 1), color: 4)
    #expect(result[PixelPoint(x: 1, y: 1)] == 4)
    #expect(result[PixelPoint(x: 0, y: 0)] == 7)
    #expect(result[PixelPoint(x: 2, y: 2)] == nil)
  }

  @Test("Eraser clears to nil")
  func eraserClears() {
    var buffer = PixelBuffer(size: PixelSize(width: 2, height: 1))
    buffer[PixelPoint(x: 0, y: 0)] = 9
    let result = ToolOps.erase(on: buffer, at: PixelPoint(x: 0, y: 0))
    #expect(result[PixelPoint(x: 0, y: 0)] == nil)
  }

  @Test("Flood fill recolors a 4-connected region but stops at boundaries")
  func floodFillStopsAtBoundary() {
    var buffer = PixelBuffer(size: PixelSize(width: 4, height: 3), fill: 0)
    // Vertical wall at x=2 splits the buffer into two regions.
    for y in 0..<3 {
      buffer[PixelPoint(x: 2, y: y)] = 1
    }
    let result = ToolOps.fill(
      on: buffer,
      at: PixelPoint(x: 0, y: 0),
      color: 5
    )
    // Left half recolored to 5.
    #expect(result[PixelPoint(x: 0, y: 0)] == 5)
    #expect(result[PixelPoint(x: 1, y: 2)] == 5)
    // Wall preserved.
    #expect(result[PixelPoint(x: 2, y: 0)] == 1)
    // Right half untouched.
    #expect(result[PixelPoint(x: 3, y: 0)] == 0)
  }

  @Test("Gradient interpolates between endpoints in palette space")
  func gradientPaintsInterpolatedColors() {
    let palette = ColorPalette(
      colors: [
        .transparent,
        EditorColor(rgbHex: 0xFF0000),  // red @ slot 1
        EditorColor(rgbHex: 0x000000),  // black @ slot 2
      ]
    )
    let buffer = PixelBuffer(size: PixelSize(width: 4, height: 1))
    let result = ToolOps.gradient(
      on: buffer,
      from: PixelPoint(x: 0, y: 0),
      to: PixelPoint(x: 3, y: 0),
      startColor: EditorColor(rgbHex: 0xFF0000),
      endColor: EditorColor(rgbHex: 0x000000),
      palette: palette
    )
    // Endpoints land exactly on their respective palette slots; the
    // mid-row should bias toward whichever palette entry is closer to
    // the interpolated RGB.
    #expect(result[PixelPoint(x: 0, y: 0)] == 1)  // red
    #expect(result[PixelPoint(x: 3, y: 0)] == 2)  // black
  }

  @Test("Bresenham line connects two points without gaps")
  func lineConnectsDiagonal() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 5))
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 0, y: 0),
      to: PixelPoint(x: 4, y: 4),
      color: 3
    )
    // Diagonal from (0,0) → (4,4) should land on the major diagonal.
    for i in 0...4 {
      #expect(result[PixelPoint(x: i, y: i)] == 3)
    }
  }

  @Test("Line with thickness 3 paints a centered 3×3 stamp at every step")
  func lineWithThickness3StampsAcrossDiagonal() {
    let buffer = PixelBuffer(size: PixelSize(width: 7, height: 7))
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 3, y: 3),
      to: PixelPoint(x: 3, y: 3),
      color: 5,
      thickness: 3
    )
    // 3×3 stamp centered on (3,3) covers (2..4, 2..4).
    for y in 2...4 {
      for x in 2...4 {
        #expect(result[PixelPoint(x: x, y: y)] == 5)
      }
    }
    // Corners outside the stamp must remain blank.
    #expect(result[PixelPoint(x: 0, y: 0)] == nil)
    #expect(result[PixelPoint(x: 5, y: 3)] == nil)
  }

  @Test("Even thickness 2 stamp biases one cell down/right of the center")
  func lineWithThickness2BiasesDownAndRight() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 5))
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 2, y: 2),
      to: PixelPoint(x: 2, y: 2),
      color: 4,
      thickness: 2
    )
    // 2×2 stamp at (2,2) covers (2,2),(3,2),(2,3),(3,3) — biased +x/+y.
    #expect(result[PixelPoint(x: 2, y: 2)] == 4)
    #expect(result[PixelPoint(x: 3, y: 2)] == 4)
    #expect(result[PixelPoint(x: 2, y: 3)] == 4)
    #expect(result[PixelPoint(x: 3, y: 3)] == 4)
    #expect(result[PixelPoint(x: 1, y: 2)] == nil)
    #expect(result[PixelPoint(x: 2, y: 1)] == nil)
  }

  @Test("Thick eraser strokes (color: nil) clear every cell under the brush")
  func thickEraserStrokeClearsUnderBrush() {
    let buffer = PixelBuffer(size: PixelSize(width: 7, height: 7), fill: 8)
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 1, y: 3),
      to: PixelPoint(x: 5, y: 3),
      color: nil,
      thickness: 3
    )
    // The 3-wide horizontal stroke at y=3 erases rows y=2..4 across x=1..5
    // (each step's 3×3 stamp covers ±1 around the center).
    for y in 2...4 {
      for x in 0...5 {
        #expect(result[PixelPoint(x: x, y: y)] == nil)
      }
    }
    // Cells outside the stamp band stay filled.
    #expect(result[PixelPoint(x: 0, y: 0)] == 8)
    #expect(result[PixelPoint(x: 0, y: 6)] == 8)
  }

  @Test("Thick line clipped to selection does not paint outside the rect")
  func thickLineRespectsSelection() {
    let buffer = PixelBuffer(size: PixelSize(width: 8, height: 8))
    let selection = Selection(rect: PixelRect(x: 2, y: 2, width: 4, height: 4))
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 4, y: 4),
      to: PixelPoint(x: 4, y: 4),
      color: 7,
      thickness: 5,
      selection: selection
    )
    // The 5×5 stamp centered on (4,4) would cover (2..6, 2..6); clipping
    // to the 4×4 selection at (2,2) trims the right and bottom cells.
    for y in 2..<6 {
      for x in 2..<6 {
        #expect(result[PixelPoint(x: x, y: y)] == 7)
      }
    }
    // Outside the selection — must remain blank even though the brush
    // intersected those cells.
    #expect(result[PixelPoint(x: 6, y: 4)] == nil)
    #expect(result[PixelPoint(x: 4, y: 6)] == nil)
    #expect(result[PixelPoint(x: 1, y: 4)] == nil)
  }

  @Test("Default thickness 1 keeps single-pixel behavior")
  func defaultThicknessIsOnePixel() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 5))
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 2, y: 2),
      to: PixelPoint(x: 2, y: 2),
      color: 1
    )
    #expect(result[PixelPoint(x: 2, y: 2)] == 1)
    // No stamping into neighbors.
    #expect(result[PixelPoint(x: 1, y: 2)] == nil)
    #expect(result[PixelPoint(x: 3, y: 2)] == nil)
    #expect(result[PixelPoint(x: 2, y: 1)] == nil)
    #expect(result[PixelPoint(x: 2, y: 3)] == nil)
  }

  @Test("Copy/paste round-trips a region's pixel values")
  func copyPasteRoundTrip() {
    var buffer = PixelBuffer(size: PixelSize(width: 4, height: 2))
    buffer[PixelPoint(x: 0, y: 0)] = 1
    buffer[PixelPoint(x: 1, y: 0)] = 2
    let clipboard = ToolOps.copy(
      from: buffer,
      rect: PixelRect(x: 0, y: 0, width: 2, height: 1)
    )!

    let blank = PixelBuffer(size: PixelSize(width: 4, height: 2))
    let pasted = ToolOps.paste(
      onto: blank,
      clipboard: clipboard,
      at: PixelPoint(x: 2, y: 1)
    )
    #expect(pasted[PixelPoint(x: 2, y: 1)] == 1)
    #expect(pasted[PixelPoint(x: 3, y: 1)] == 2)
    // Untouched cells stay nil.
    #expect(pasted[PixelPoint(x: 0, y: 0)] == nil)
  }

  @Test("Move cuts a rectangular region and pastes opaque pixels at the offset")
  func moveCutsRectAndPastesAtOffset() {
    var buffer = PixelBuffer(size: PixelSize(width: 5, height: 3))
    buffer[PixelPoint(x: 0, y: 0)] = 9
    buffer[PixelPoint(x: 1, y: 1)] = 1
    buffer[PixelPoint(x: 2, y: 1)] = 2
    buffer[PixelPoint(x: 4, y: 1)] = 8

    let result = ToolOps.move(
      on: buffer,
      rect: PixelRect(x: 1, y: 1, width: 2, height: 1),
      byX: 2,
      y: 0
    )

    #expect(result[PixelPoint(x: 0, y: 0)] == 9)
    #expect(result[PixelPoint(x: 1, y: 1)] == nil)
    #expect(result[PixelPoint(x: 2, y: 1)] == nil)
    #expect(result[PixelPoint(x: 3, y: 1)] == 1)
    #expect(result[PixelPoint(x: 4, y: 1)] == 2)
  }

  // MARK: - Rectangle

  @Test("Rectangle outline paints the border and leaves the interior blank")
  func rectangleOutlineIsHollow() {
    let buffer = PixelBuffer(size: PixelSize(width: 6, height: 6))
    let result = ToolOps.rectangle(
      on: buffer,
      from: PixelPoint(x: 1, y: 1),
      to: PixelPoint(x: 4, y: 4),
      color: 3
    )
    for x in 1...4 {
      #expect(result[PixelPoint(x: x, y: 1)] == 3)
      #expect(result[PixelPoint(x: x, y: 4)] == 3)
    }
    for y in 1...4 {
      #expect(result[PixelPoint(x: 1, y: y)] == 3)
      #expect(result[PixelPoint(x: 4, y: y)] == 3)
    }
    for y in 2...3 {
      for x in 2...3 {
        #expect(result[PixelPoint(x: x, y: y)] == nil)
      }
    }
    #expect(result[PixelPoint(x: 0, y: 0)] == nil)
    #expect(result[PixelPoint(x: 5, y: 5)] == nil)
    #expect(result.pixels.compactMap { $0 }.count == 12)
  }

  @Test("Filled rectangle paints every cell inside the span")
  func rectangleFilledPaintsInterior() {
    let buffer = PixelBuffer(size: PixelSize(width: 6, height: 6))
    let result = ToolOps.rectangle(
      on: buffer,
      from: PixelPoint(x: 1, y: 1),
      to: PixelPoint(x: 4, y: 4),
      color: 3,
      filled: true
    )
    for y in 1...4 {
      for x in 1...4 {
        #expect(result[PixelPoint(x: x, y: y)] == 3)
      }
    }
    #expect(result.pixels.compactMap { $0 }.count == 16)
  }

  @Test("Rectangle corners are order-independent")
  func rectangleCornersAreOrderIndependent() {
    let buffer = PixelBuffer(size: PixelSize(width: 7, height: 5))
    let a = PixelPoint(x: 1, y: 3)
    let b = PixelPoint(x: 5, y: 0)
    for filled in [false, true] {
      let forward = ToolOps.rectangle(on: buffer, from: a, to: b, color: 2, filled: filled)
      let backward = ToolOps.rectangle(on: buffer, from: b, to: a, color: 2, filled: filled)
      #expect(forward == backward)
    }
  }

  @Test("A zero-area rectangle drag paints exactly one pixel")
  func rectangleDegenerateIsSinglePixel() {
    let buffer = PixelBuffer(size: PixelSize(width: 4, height: 4))
    let corner = PixelPoint(x: 2, y: 1)
    for filled in [false, true] {
      let result = ToolOps.rectangle(
        on: buffer, from: corner, to: corner, color: 6, filled: filled
      )
      #expect(result[corner] == 6)
      #expect(result.pixels.compactMap { $0 }.count == 1)
    }
  }

  @Test("A one-pixel-wide rectangle collapses to a straight run, filled or not")
  func rectangleOnePixelWideBox() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 6))
    let a = PixelPoint(x: 2, y: 1)
    let b = PixelPoint(x: 2, y: 4)
    let outline = ToolOps.rectangle(on: buffer, from: a, to: b, color: 4)
    let filled = ToolOps.rectangle(on: buffer, from: a, to: b, color: 4, filled: true)
    #expect(outline == filled)
    for y in 1...4 {
      #expect(outline[PixelPoint(x: 2, y: y)] == 4)
    }
    #expect(outline.pixels.compactMap { $0 }.count == 4)
  }

  @Test("Rectangle outline thickness stamps the square brush along the edges")
  func rectangleOutlineThicknessStraddlesTheEdge() {
    let buffer = PixelBuffer(size: PixelSize(width: 9, height: 9))
    let result = ToolOps.rectangle(
      on: buffer,
      from: PixelPoint(x: 3, y: 3),
      to: PixelPoint(x: 5, y: 5),
      color: 1,
      thickness: 3
    )
    // A 3×3 brush centered on every cell of the 3×3 box's border covers
    // the whole 5×5 block around it — half the brush sits outside.
    for y in 2...6 {
      for x in 2...6 {
        #expect(result[PixelPoint(x: x, y: y)] == 1)
      }
    }
    #expect(result[PixelPoint(x: 1, y: 4)] == nil)
    #expect(result[PixelPoint(x: 7, y: 4)] == nil)
  }

  @Test("Rectangle clipped to a selection leaves every outside cell untouched")
  func rectangleRespectsSelection() {
    let buffer = PixelBuffer(size: PixelSize(width: 8, height: 8), fill: 0)
    let selection = Selection(rect: PixelRect(x: 2, y: 2, width: 3, height: 3))
    for filled in [false, true] {
      let result = ToolOps.rectangle(
        on: buffer,
        from: PixelPoint(x: 0, y: 0),
        to: PixelPoint(x: 7, y: 7),
        color: 5,
        filled: filled,
        selection: selection
      )
      for y in 0..<8 {
        for x in 0..<8 where !selection.rect.contains(PixelPoint(x: x, y: y)) {
          #expect(result[PixelPoint(x: x, y: y)] == 0)
        }
      }
    }
  }

  @Test("Rectangle with a nil color erases instead of painting")
  func rectangleWithNilColorErases() {
    let buffer = PixelBuffer(size: PixelSize(width: 4, height: 4), fill: 7)
    let result = ToolOps.rectangle(
      on: buffer,
      from: PixelPoint(x: 1, y: 1),
      to: PixelPoint(x: 2, y: 2),
      color: nil,
      filled: true
    )
    #expect(result[PixelPoint(x: 1, y: 1)] == nil)
    #expect(result[PixelPoint(x: 2, y: 2)] == nil)
    #expect(result[PixelPoint(x: 0, y: 0)] == 7)
    #expect(result.pixels.compactMap { $0 }.count == 12)
  }

  // MARK: - Ellipse

  @Test("Ellipse outline is hollow and touches the box edge midpoints")
  func ellipseOutlineIsHollow() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 5))
    let result = ToolOps.ellipse(
      on: buffer,
      from: PixelPoint(x: 0, y: 0),
      to: PixelPoint(x: 4, y: 4),
      color: 9
    )
    // Box corners stay clear; edge midpoints sit on the curve.
    #expect(result[PixelPoint(x: 0, y: 0)] == nil)
    #expect(result[PixelPoint(x: 4, y: 0)] == nil)
    #expect(result[PixelPoint(x: 0, y: 4)] == nil)
    #expect(result[PixelPoint(x: 4, y: 4)] == nil)
    #expect(result[PixelPoint(x: 2, y: 0)] == 9)
    #expect(result[PixelPoint(x: 2, y: 4)] == 9)
    #expect(result[PixelPoint(x: 0, y: 2)] == 9)
    #expect(result[PixelPoint(x: 4, y: 2)] == 9)
    // Interior is empty.
    #expect(result[PixelPoint(x: 2, y: 2)] == nil)
    #expect(result[PixelPoint(x: 1, y: 1)] == nil)
    #expect(result.pixels.compactMap { $0 }.count == 12)
  }

  @Test("Filled ellipse spans the outline and keeps the box corners clear")
  func ellipseFilledCoversInterior() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 5))
    let result = ToolOps.ellipse(
      on: buffer,
      from: PixelPoint(x: 0, y: 0),
      to: PixelPoint(x: 4, y: 4),
      color: 9,
      filled: true
    )
    #expect(result[PixelPoint(x: 2, y: 2)] == 9)
    #expect(result[PixelPoint(x: 1, y: 1)] == 9)
    #expect(result[PixelPoint(x: 0, y: 0)] == nil)
    #expect(result[PixelPoint(x: 4, y: 4)] == nil)
    // 3 + 5 + 5 + 5 + 3 cells.
    #expect(result.pixels.compactMap { $0 }.count == 21)
  }

  @Test(
    "Ellipse is identical under horizontal and vertical mirroring",
    arguments: [1, 2, 3, 4, 5, 8, 11], [1, 2, 3, 5, 6, 9]
  )
  func ellipseIsMirrorSymmetric(width: Int, height: Int) {
    let buffer = PixelBuffer(size: PixelSize(width: width, height: height))
    for filled in [false, true] {
      let result = ToolOps.ellipse(
        on: buffer,
        from: PixelPoint(x: 0, y: 0),
        to: PixelPoint(x: width - 1, y: height - 1),
        color: 1,
        filled: filled
      )
      for y in 0..<height {
        for x in 0..<width {
          let value = result[PixelPoint(x: x, y: y)]
          #expect(value == result[PixelPoint(x: width - 1 - x, y: y)])
          #expect(value == result[PixelPoint(x: x, y: height - 1 - y)])
        }
      }
      // A symmetric-but-empty buffer would pass vacuously.
      #expect(result.pixels.contains { $0 != nil })
    }
  }

  @Test("Ellipse corners are order-independent")
  func ellipseCornersAreOrderIndependent() {
    let buffer = PixelBuffer(size: PixelSize(width: 9, height: 7))
    let a = PixelPoint(x: 1, y: 5)
    let b = PixelPoint(x: 7, y: 0)
    for filled in [false, true] {
      let forward = ToolOps.ellipse(on: buffer, from: a, to: b, color: 3, filled: filled)
      let backward = ToolOps.ellipse(on: buffer, from: b, to: a, color: 3, filled: filled)
      #expect(forward == backward)
    }
  }

  @Test("Degenerate ellipse boxes collapse to a pixel or a straight run")
  func ellipseDegenerateBoxes() {
    let buffer = PixelBuffer(size: PixelSize(width: 6, height: 6))

    let dot = ToolOps.ellipse(
      on: buffer, from: PixelPoint(x: 3, y: 2), to: PixelPoint(x: 3, y: 2), color: 5
    )
    #expect(dot[PixelPoint(x: 3, y: 2)] == 5)
    #expect(dot.pixels.compactMap { $0 }.count == 1)

    let column = ToolOps.ellipse(
      on: buffer, from: PixelPoint(x: 2, y: 1), to: PixelPoint(x: 2, y: 4), color: 5
    )
    for y in 1...4 {
      #expect(column[PixelPoint(x: 2, y: y)] == 5)
    }
    #expect(column.pixels.compactMap { $0 }.count == 4)

    let row = ToolOps.ellipse(
      on: buffer, from: PixelPoint(x: 1, y: 3), to: PixelPoint(x: 4, y: 3), color: 5
    )
    for x in 1...4 {
      #expect(row[PixelPoint(x: x, y: 3)] == 5)
    }
    #expect(row.pixels.compactMap { $0 }.count == 4)
  }

  @Test("Ellipse clipped to a selection leaves every outside cell untouched")
  func ellipseRespectsSelection() {
    let buffer = PixelBuffer(size: PixelSize(width: 9, height: 9), fill: 0)
    let selection = Selection(rect: PixelRect(x: 3, y: 3, width: 3, height: 3))
    let filled = ToolOps.ellipse(
      on: buffer,
      from: PixelPoint(x: 0, y: 0),
      to: PixelPoint(x: 8, y: 8),
      color: 6,
      filled: true,
      selection: selection
    )
    for y in 0..<9 {
      for x in 0..<9 {
        let expected: PaletteIndex? = selection.rect.contains(PixelPoint(x: x, y: y)) ? 6 : 0
        #expect(filled[PixelPoint(x: x, y: y)] == expected)
      }
    }

    let leftHalf = Selection(rect: PixelRect(x: 0, y: 0, width: 3, height: 9))
    let outline = ToolOps.ellipse(
      on: buffer,
      from: PixelPoint(x: 0, y: 0),
      to: PixelPoint(x: 8, y: 8),
      color: 6,
      selection: leftHalf
    )
    #expect(outline[PixelPoint(x: 0, y: 4)] == 6)
    #expect(outline[PixelPoint(x: 8, y: 4)] == 0)
  }

  @Test("Shapes drawn entirely off-canvas are a no-op")
  func shapesFullyOffCanvasAreNoOps() {
    let buffer = PixelBuffer(size: PixelSize(width: 4, height: 4), fill: 1)
    let far = PixelPoint(x: -900_000, y: -900_000)
    let alsoFar = PixelPoint(x: -800_000, y: -800_000)
    for filled in [false, true] {
      #expect(
        ToolOps.rectangle(on: buffer, from: far, to: alsoFar, color: 7, filled: filled) == buffer
      )
      #expect(
        ToolOps.ellipse(on: buffer, from: far, to: alsoFar, color: 7, filled: filled) == buffer
      )
    }
  }

  @Test("Extreme corner coordinates clamp instead of overflowing")
  func shapesClampExtremeCorners() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 5))
    let low = PixelPoint(x: Int.min + 1, y: Int.min + 1)
    let high = PixelPoint(x: Int.max - 1, y: Int.max - 1)
    let box = ToolOps.rectangle(on: buffer, from: low, to: high, color: 2, filled: true)
    #expect(box.pixels.allSatisfy { $0 == 2 })
    let disc = ToolOps.ellipse(on: buffer, from: low, to: high, color: 2, filled: true)
    #expect(disc.pixels.allSatisfy { $0 == 2 })
  }

  // MARK: - Flip

  @Test("Flipping twice restores the buffer, whole or selection-scoped")
  func flipTwiceIsIdentity() {
    let buffer = Self.patterned(width: 7, height: 4)
    #expect(ToolOps.flipHorizontal(on: ToolOps.flipHorizontal(on: buffer)) == buffer)
    #expect(ToolOps.flipVertical(on: ToolOps.flipVertical(on: buffer)) == buffer)

    let rect = PixelRect(x: 1, y: 1, width: 4, height: 2)
    #expect(
      ToolOps.flipHorizontal(on: ToolOps.flipHorizontal(on: buffer, rect: rect), rect: rect)
        == buffer
    )
    #expect(
      ToolOps.flipVertical(on: ToolOps.flipVertical(on: buffer, rect: rect), rect: rect)
        == buffer
    )
  }

  @Test("Flip moves transparent cells rather than dropping or filling them")
  func flipMovesTransparency() {
    var buffer = PixelBuffer(size: PixelSize(width: 3, height: 2), fill: 4)
    buffer[PixelPoint(x: 0, y: 0)] = nil

    let horizontal = ToolOps.flipHorizontal(on: buffer)
    #expect(horizontal[PixelPoint(x: 2, y: 0)] == nil)
    #expect(horizontal[PixelPoint(x: 0, y: 0)] == 4)
    #expect(horizontal.pixels.compactMap { $0 }.count == 5)

    let vertical = ToolOps.flipVertical(on: buffer)
    #expect(vertical[PixelPoint(x: 0, y: 1)] == nil)
    #expect(vertical[PixelPoint(x: 0, y: 0)] == 4)
    #expect(vertical.pixels.compactMap { $0 }.count == 5)
  }

  @Test("Flipping a selection mirrors inside the rect and nowhere else")
  func flipSelectionLeavesOutsideUntouched() {
    let buffer = Self.patterned(width: 6, height: 5)
    let rect = PixelRect(x: 1, y: 1, width: 3, height: 3)
    let flipped = ToolOps.flipHorizontal(on: buffer, rect: rect)
    for y in 0..<5 {
      for x in 0..<6 where !rect.contains(PixelPoint(x: x, y: y)) {
        #expect(flipped[PixelPoint(x: x, y: y)] == buffer[PixelPoint(x: x, y: y)])
      }
    }
    // Inside the rect, column x mirrors to (minX + maxX - 1) - x = 4 - x.
    for y in 1..<4 {
      for x in 1..<4 {
        #expect(flipped[PixelPoint(x: x, y: y)] == buffer[PixelPoint(x: 4 - x, y: y)])
      }
    }
  }

  @Test("A flip rect fully outside the canvas is a no-op")
  func flipOffCanvasIsNoOp() {
    let buffer = Self.patterned(width: 4, height: 4)
    let away = PixelRect(x: 20, y: 20, width: 3, height: 3)
    #expect(ToolOps.flipHorizontal(on: buffer, rect: away) == buffer)
    #expect(ToolOps.flipVertical(on: buffer, rect: away) == buffer)
  }

  // MARK: - Rotate

  @Test("Four quarter turns of a square region are the identity")
  func rotateFourTimesIsIdentity() {
    let buffer = Self.patterned(width: 5, height: 5)

    var clockwise = buffer
    for _ in 0..<4 {
      clockwise = ToolOps.rotateClockwise(on: clockwise)
    }
    #expect(clockwise == buffer)

    let rect = PixelRect(x: 1, y: 1, width: 3, height: 3)
    var counter = buffer
    for _ in 0..<4 {
      counter = ToolOps.rotateCounterClockwise(on: counter, rect: rect)
    }
    #expect(counter == buffer)
  }

  @Test("A counter-clockwise turn undoes a clockwise one on a square region")
  func rotateRoundTripsOnSquareRegions() {
    let buffer = Self.patterned(width: 6, height: 6)
    let rect = PixelRect(x: 2, y: 1, width: 4, height: 4)
    #expect(
      ToolOps.rotateCounterClockwise(
        on: ToolOps.rotateClockwise(on: buffer, rect: rect), rect: rect
      ) == buffer
    )
    #expect(ToolOps.rotateClockwise(on: ToolOps.rotateCounterClockwise(on: buffer)) == buffer)
  }

  @Test("Clockwise rotation sends the top-left corner to the top-right")
  func rotateClockwiseMovesCorners() {
    var buffer = PixelBuffer(size: PixelSize(width: 3, height: 3))
    buffer[PixelPoint(x: 0, y: 0)] = 1
    buffer[PixelPoint(x: 2, y: 0)] = 2
    let turned = ToolOps.rotateClockwise(on: buffer)
    #expect(turned[PixelPoint(x: 2, y: 0)] == 1)
    #expect(turned[PixelPoint(x: 2, y: 2)] == 2)
    #expect(turned[PixelPoint(x: 0, y: 0)] == nil)

    let back = ToolOps.rotateCounterClockwise(on: buffer)
    #expect(back[PixelPoint(x: 0, y: 2)] == 1)
    #expect(back[PixelPoint(x: 0, y: 0)] == 2)
  }

  @Test("Rotation moves transparent cells rather than dropping or filling them")
  func rotatePreservesTransparency() {
    var buffer = PixelBuffer(size: PixelSize(width: 2, height: 2), fill: 3)
    buffer[PixelPoint(x: 0, y: 0)] = nil
    let turned = ToolOps.rotateClockwise(on: buffer)
    #expect(turned[PixelPoint(x: 1, y: 0)] == nil)
    #expect(turned[PixelPoint(x: 0, y: 0)] == 3)
    #expect(turned.pixels.compactMap { $0 }.count == 3)
  }

  @Test("A nil rect rotates the whole buffer, matching an explicit canvas rect")
  func rotateNilRectMeansWholeBuffer() {
    let buffer = Self.patterned(width: 4, height: 2)
    let whole = PixelRect(x: 0, y: 0, width: 4, height: 2)
    #expect(ToolOps.rotateClockwise(on: buffer) == ToolOps.rotateClockwise(on: buffer, rect: whole))
  }

  @Test("A non-square selection rotates about its centre and clips the overhang")
  func rotateNonSquareSelectionClipsAboutTheCentre() {
    var buffer = PixelBuffer(size: PixelSize(width: 6, height: 6), fill: 99)
    var value: PaletteIndex = 1
    for y in 1..<3 {
      for x in 1..<5 {
        buffer[PixelPoint(x: x, y: y)] = value
        value += 1
      }
    }
    // Selection holds  1 2 3 4
    //                  5 6 7 8
    let rect = PixelRect(x: 1, y: 1, width: 4, height: 2)
    let turned = ToolOps.rotateClockwise(on: buffer, rect: rect)

    // Only the centred 2×2 block stays inside the region after the
    // quarter turn; the outer two columns turn past the top and bottom
    // edges and are dropped, and the cells nothing lands on are cleared.
    #expect(turned[PixelPoint(x: 3, y: 1)] == 2)
    #expect(turned[PixelPoint(x: 3, y: 2)] == 3)
    #expect(turned[PixelPoint(x: 2, y: 1)] == 6)
    #expect(turned[PixelPoint(x: 2, y: 2)] == 7)
    #expect(turned[PixelPoint(x: 1, y: 1)] == nil)
    #expect(turned[PixelPoint(x: 4, y: 1)] == nil)
    #expect(turned[PixelPoint(x: 1, y: 2)] == nil)
    #expect(turned[PixelPoint(x: 4, y: 2)] == nil)

    // Nothing outside the selection moves.
    for y in 0..<6 {
      for x in 0..<6 where !rect.contains(PixelPoint(x: x, y: y)) {
        #expect(turned[PixelPoint(x: x, y: y)] == 99)
      }
    }

    // The clipping rule is lossy, so the turn is not self-inverse.
    #expect(ToolOps.rotateCounterClockwise(on: turned, rect: rect) != buffer)
  }

  @Test("An odd-perimeter selection biases the half-cell centre down/right")
  func rotateOddPerimeterSelectionBiasesDownRight() {
    var buffer = PixelBuffer(size: PixelSize(width: 4, height: 4))
    var value: PaletteIndex = 1
    for y in 0..<2 {
      for x in 0..<3 {
        buffer[PixelPoint(x: x, y: y)] = value
        value += 1
      }
    }
    // Selection holds  1 2 3
    //                  4 5 6
    let rect = PixelRect(x: 0, y: 0, width: 3, height: 2)
    let turned = ToolOps.rotateClockwise(on: buffer, rect: rect)

    // width + height is odd, so the turned coordinates land between
    // cells and round down/right: destinations shift one column right,
    // which drops the last source column and empties the first
    // destination column.
    #expect(turned[PixelPoint(x: 2, y: 0)] == 1)
    #expect(turned[PixelPoint(x: 2, y: 1)] == 2)
    #expect(turned[PixelPoint(x: 1, y: 0)] == 4)
    #expect(turned[PixelPoint(x: 1, y: 1)] == 5)
    #expect(turned[PixelPoint(x: 0, y: 0)] == nil)
    #expect(turned[PixelPoint(x: 0, y: 1)] == nil)
  }

  @Test("A rotate rect fully outside the canvas is a no-op")
  func rotateOffCanvasIsNoOp() {
    let buffer = Self.patterned(width: 4, height: 4)
    let away = PixelRect(x: -20, y: -20, width: 3, height: 3)
    #expect(ToolOps.rotateClockwise(on: buffer, rect: away) == buffer)
    #expect(ToolOps.rotateCounterClockwise(on: buffer, rect: away) == buffer)
  }

  // MARK: - Clear / cut

  @Test("Clear empties the rect and nothing else")
  func clearEmptiesOnlyTheRect() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 4), fill: 2)
    let rect = PixelRect(x: 1, y: 1, width: 2, height: 2)
    let result = ToolOps.clear(on: buffer, rect: rect)
    for y in 0..<4 {
      for x in 0..<5 {
        let expected: PaletteIndex? = rect.contains(PixelPoint(x: x, y: y)) ? nil : 2
        #expect(result[PixelPoint(x: x, y: y)] == expected)
      }
    }
    #expect(ToolOps.clear(on: buffer).pixels.allSatisfy { $0 == nil })
  }

  @Test("Cut is copy then clear: the clipboard keeps what the canvas loses")
  func cutIsCopyThenClear() {
    var buffer = PixelBuffer(size: PixelSize(width: 4, height: 3))
    buffer[PixelPoint(x: 1, y: 1)] = 5
    buffer[PixelPoint(x: 2, y: 1)] = 6
    let rect = PixelRect(x: 1, y: 1, width: 2, height: 1)

    let clipboard = ToolOps.copy(from: buffer, rect: rect)!
    let cut = ToolOps.clear(on: buffer, rect: rect)
    #expect(cut[PixelPoint(x: 1, y: 1)] == nil)
    #expect(cut[PixelPoint(x: 2, y: 1)] == nil)

    let restored = ToolOps.paste(onto: cut, clipboard: clipboard, at: PixelPoint(x: 1, y: 1))
    #expect(restored == buffer)
  }

  @Test("A clear rect fully outside the canvas is a no-op")
  func clearOffCanvasIsNoOp() {
    let buffer = PixelBuffer(size: PixelSize(width: 3, height: 3), fill: 1)
    let away = PixelRect(x: 10, y: 10, width: 2, height: 2)
    #expect(ToolOps.clear(on: buffer, rect: away) == buffer)
  }

  // MARK: - Mirror-X symmetry

  @Test("mirroredX reflects across the region's vertical centre line")
  func mirroredXAxisConvention() {
    let odd = PixelRect(x: 0, y: 0, width: 7, height: 1)
    #expect(ToolOps.mirroredX(PixelPoint(x: 3, y: 2), in: odd) == PixelPoint(x: 3, y: 2))
    #expect(ToolOps.mirroredX(PixelPoint(x: 0, y: 0), in: odd) == PixelPoint(x: 6, y: 0))

    let even = PixelRect(x: 0, y: 0, width: 8, height: 1)
    #expect(ToolOps.mirroredX(PixelPoint(x: 3, y: 0), in: even) == PixelPoint(x: 4, y: 0))
    // No column maps to itself when the region width is even.
    for x in 0..<8 {
      #expect(ToolOps.mirroredX(PixelPoint(x: x, y: 0), in: even).x != x)
    }
  }

  @Test("Mirror-X on an even-width canvas pairs columns across the seam")
  func mirrorXEvenWidthPairsColumns() {
    let buffer = PixelBuffer(size: PixelSize(width: 8, height: 3))
    let dot = PixelPoint(x: 1, y: 1)
    let result = ToolOps.mirrorXLine(on: buffer, from: dot, to: dot, color: 4)
    #expect(result[dot] == 4)
    #expect(result[PixelPoint(x: 6, y: 1)] == 4)
    #expect(result.pixels.compactMap { $0 }.count == 2)
  }

  @Test("Mirror-X on an odd-width canvas leaves the centre column self-mapping")
  func mirrorXOddWidthCentreColumnMapsToItself() {
    let buffer = PixelBuffer(size: PixelSize(width: 7, height: 5))
    let top = PixelPoint(x: 3, y: 1)
    let bottom = PixelPoint(x: 3, y: 3)

    // The centre column reflects onto itself, so the stroke is painted
    // once, not doubled.
    let mirrored = ToolOps.mirrorXLine(on: buffer, from: top, to: bottom, color: 2)
    let plain = ToolOps.line(on: buffer, from: top, to: bottom, color: 2)
    #expect(mirrored == plain)
    #expect(mirrored.pixels.compactMap { $0 }.count == 3)

    // An off-centre stroke on the same canvas still pairs up.
    let offCentre = PixelPoint(x: 1, y: 0)
    let paired = ToolOps.mirrorXLine(on: buffer, from: offCentre, to: offCentre, color: 2)
    #expect(paired[offCentre] == 2)
    #expect(paired[PixelPoint(x: 5, y: 0)] == 2)
    #expect(paired.pixels.compactMap { $0 }.count == 2)
  }

  @Test("Mirror-X strokes are an exact reflection of one another")
  func mirrorXStrokeIsExactReflection() {
    let buffer = PixelBuffer(size: PixelSize(width: 9, height: 6))
    let result = ToolOps.mirrorXLine(
      on: buffer,
      from: PixelPoint(x: 0, y: 0),
      to: PixelPoint(x: 3, y: 5),
      color: 7
    )
    for y in 0..<6 {
      for x in 0..<9 {
        #expect(result[PixelPoint(x: x, y: y)] == result[PixelPoint(x: 8 - x, y: y)])
      }
    }
    #expect(result[PixelPoint(x: 0, y: 0)] == 7)
    #expect(result[PixelPoint(x: 8, y: 0)] == 7)
  }

  @Test("Mirror-X with an even brush keeps both footprints exact reflections")
  func mirrorXEvenThicknessIsExactReflection() {
    let buffer = PixelBuffer(size: PixelSize(width: 10, height: 4))
    let dot = PixelPoint(x: 2, y: 1)
    let result = ToolOps.mirrorXLine(on: buffer, from: dot, to: dot, color: 3, thickness: 2)
    for y in 0..<4 {
      for x in 0..<10 {
        #expect(result[PixelPoint(x: x, y: y)] == result[PixelPoint(x: 9 - x, y: y)])
      }
    }
    // The brush footprint is x 2…3; its reflection is x 6…7.
    for y in 1...2 {
      #expect(result[PixelPoint(x: 2, y: y)] == 3)
      #expect(result[PixelPoint(x: 3, y: y)] == 3)
      #expect(result[PixelPoint(x: 6, y: y)] == 3)
      #expect(result[PixelPoint(x: 7, y: y)] == 3)
    }
    #expect(result.pixels.compactMap { $0 }.count == 8)
  }

  @Test("Mirror-X honours the selection clip on both halves of the stroke")
  func mirrorXRespectsSelection() {
    let buffer = PixelBuffer(size: PixelSize(width: 9, height: 3))
    let selection = Selection(rect: PixelRect(x: 0, y: 0, width: 4, height: 3))
    let dot = PixelPoint(x: 1, y: 1)
    let result = ToolOps.mirrorXLine(
      on: buffer, from: dot, to: dot, color: 5, selection: selection
    )
    #expect(result[dot] == 5)
    // The mirrored half lands at x = 7, outside the selection.
    #expect(result[PixelPoint(x: 7, y: 1)] == nil)
    #expect(result.pixels.compactMap { $0 }.count == 1)
  }

  @Test("Mirror-X can reflect about a region other than the whole canvas")
  func mirrorXHonoursAnExplicitAxisRegion() {
    let buffer = PixelBuffer(size: PixelSize(width: 9, height: 3))
    let region = PixelRect(x: 2, y: 0, width: 4, height: 3)
    let dot = PixelPoint(x: 2, y: 1)
    let result = ToolOps.mirrorXLine(on: buffer, from: dot, to: dot, color: 8, axisRegion: region)
    // The region spans columns 2…5, so column 2 reflects onto column 5.
    #expect(result[dot] == 8)
    #expect(result[PixelPoint(x: 5, y: 1)] == 8)
    #expect(result.pixels.compactMap { $0 }.count == 2)
  }

  // MARK: - Fixtures

  /// A buffer with a distinct value in every cell plus regular
  /// transparent holes, so a transform can be checked cell by cell and
  /// cannot pass by accidentally moving identical values around.
  private static func patterned(width: Int, height: Int) -> PixelBuffer {
    var buffer = PixelBuffer(size: PixelSize(width: width, height: height))
    for y in 0..<height {
      for x in 0..<width {
        let n = y * width + x
        buffer[PixelPoint(x: x, y: y)] = n % 5 == 0 ? nil : PaletteIndex(n % 251 + 1)
      }
    }
    return buffer
  }
}

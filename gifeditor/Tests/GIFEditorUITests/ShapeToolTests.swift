import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

/// The two shape tools and the mirror-X drawing modifier, from the two
/// paths a user actually has: the keyboard's anchor-then-commit and a
/// pointer drag.
///
/// `ToolOps.rectangle`, `ToolOps.ellipse` and `ToolOps.mirrorXLine` are
/// already covered pixel-for-pixel in `ToolOpsTests`, so nothing here
/// re-asserts what a midpoint ellipse looks like. What is unproven is the
/// wiring: that both paths reach the same op with the same arguments,
/// that a shape is one undo step rather than none or two, and that the
/// commit declares an invalidation narrow enough to be worth having and
/// wide enough to be correct.
@MainActor
@Suite("GIF editor shape tools")
struct ShapeToolTests {

  // MARK: - Keyboard path

  @Test("Two presses span a rectangle between the anchor and the cursor")
  func rectangleCommitsFromTwoPresses() {
    let model = blankModel()
    model.primaryColorIndex = 3
    model.selectTool(.rectangle)

    model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 1)
    model.applyToolAtCursor()
    #expect(model.pendingShapeAnchor == GIFEditorCore.PixelPoint(x: 1, y: 1))
    // The anchor alone is not an edit: nothing is painted until the
    // second press names the far corner.
    #expect(!model.isDirty)

    model.cursor = GIFEditorCore.PixelPoint(x: 4, y: 3)
    model.applyToolAtCursor()

    #expect(model.pendingShapeAnchor == nil)
    #expect(
      model.currentLayer.pixels
        == ToolOps.rectangle(
          on: PixelBuffer(size: canvasSize),
          from: GIFEditorCore.PixelPoint(x: 1, y: 1),
          to: GIFEditorCore.PixelPoint(x: 4, y: 3),
          color: 3
        )
    )
  }

  @Test("Two presses inscribe an ellipse in the same two corners")
  func ellipseCommitsFromTwoPresses() {
    let model = blankModel()
    model.primaryColorIndex = 5
    model.selectTool(.ellipse)

    model.cursor = GIFEditorCore.PixelPoint(x: 0, y: 0)
    model.applyToolAtCursor()
    model.cursor = GIFEditorCore.PixelPoint(x: 5, y: 5)
    model.applyToolAtCursor()

    #expect(
      model.currentLayer.pixels
        == ToolOps.ellipse(
          on: PixelBuffer(size: canvasSize),
          from: GIFEditorCore.PixelPoint(x: 0, y: 0),
          to: GIFEditorCore.PixelPoint(x: 5, y: 5),
          color: 5
        )
    )
  }

  @Test("The filled toggle is what picks the solid shape, and it toggles back")
  func filledToggleSelectsTheSolidShape() {
    let model = blankModel()
    model.primaryColorIndex = 2
    model.selectTool(.rectangle)
    model.toggleShapeFill()
    #expect(model.shapeFillsInterior)

    model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 1)
    model.applyToolAtCursor()
    model.cursor = GIFEditorCore.PixelPoint(x: 4, y: 4)
    model.applyToolAtCursor()

    let filled = ToolOps.rectangle(
      on: PixelBuffer(size: canvasSize),
      from: GIFEditorCore.PixelPoint(x: 1, y: 1),
      to: GIFEditorCore.PixelPoint(x: 4, y: 4),
      color: 2,
      filled: true
    )
    #expect(model.currentLayer.pixels == filled)
    // The interior is the whole point of the flag, so assert it directly
    // rather than only through the op — an outline that happened to equal
    // itself would satisfy the comparison above.
    #expect(model.currentLayer.pixels[GIFEditorCore.PixelPoint(x: 2, y: 2)] == 2)

    model.toggleShapeFill()
    #expect(!model.shapeFillsInterior)
  }

  @Test("The brush size is the outline's thickness")
  func brushSizeThickensTheOutline() {
    let model = blankModel()
    model.primaryColorIndex = 7
    model.selectTool(.rectangle)
    model.increaseBrushSize()
    #expect(model.brushSize == 2)

    model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 1)
    model.applyToolAtCursor()
    model.cursor = GIFEditorCore.PixelPoint(x: 4, y: 4)
    model.applyToolAtCursor()

    #expect(
      model.currentLayer.pixels
        == ToolOps.rectangle(
          on: PixelBuffer(size: canvasSize),
          from: GIFEditorCore.PixelPoint(x: 1, y: 1),
          to: GIFEditorCore.PixelPoint(x: 4, y: 4),
          color: 7,
          thickness: 2
        )
    )
  }

  @Test("An active marquee clips a shape the way it clips a fill")
  func selectionClipsTheShape() {
    let model = blankModel()
    model.primaryColorIndex = 4
    let clip = PixelRect(x: 2, y: 0, width: 2, height: 6)
    model.selection = Selection(rect: clip)
    model.selectTool(.rectangle)

    model.cursor = GIFEditorCore.PixelPoint(x: 0, y: 0)
    model.applyToolAtCursor()
    model.cursor = GIFEditorCore.PixelPoint(x: 5, y: 5)
    model.applyToolAtCursor()

    #expect(
      model.currentLayer.pixels
        == ToolOps.rectangle(
          on: PixelBuffer(size: canvasSize),
          from: GIFEditorCore.PixelPoint(x: 0, y: 0),
          to: GIFEditorCore.PixelPoint(x: 5, y: 5),
          color: 4,
          selection: Selection(rect: clip)
        )
    )
    // Outside the marquee, untouched.
    #expect(model.currentLayer.pixels[GIFEditorCore.PixelPoint(x: 0, y: 0)] == nil)
  }

  // MARK: - Pointer path

  @Test("A drag spans the same shape the two presses do")
  func dragMatchesTheKeyboardPath() {
    let start = GIFEditorCore.PixelPoint(x: 1, y: 0)
    let end = GIFEditorCore.PixelPoint(x: 5, y: 4)

    let dragged = blankModel()
    dragged.primaryColorIndex = 6
    dragged.selectTool(.ellipse)
    dragged.beginCanvasDrag(at: start)
    dragged.updateCanvasDrag(startingAt: start, from: start, to: end)
    dragged.endCanvasDrag(startingAt: start, from: end, to: end)

    let pressed = blankModel()
    pressed.primaryColorIndex = 6
    pressed.selectTool(.ellipse)
    pressed.cursor = start
    pressed.applyToolAtCursor()
    pressed.cursor = end
    pressed.applyToolAtCursor()

    #expect(dragged.currentLayer.pixels == pressed.currentLayer.pixels)
    #expect(dragged.pendingShapeAnchor == nil)
    #expect(dragged.cursor == end)
  }

  @Test("A shape drag is one undo step, and so are two presses")
  func eachShapeIsOneUndoStep() {
    let start = GIFEditorCore.PixelPoint(x: 0, y: 1)
    let end = GIFEditorCore.PixelPoint(x: 4, y: 4)

    let dragged = blankModel()
    dragged.selectTool(.rectangle)
    dragged.beginCanvasDrag(at: start)
    dragged.updateCanvasDrag(startingAt: start, from: start, to: end)
    dragged.endCanvasDrag(startingAt: start, from: end, to: end)

    #expect(dragged.canUndo)
    dragged.undo()
    #expect(dragged.currentLayer.pixels == PixelBuffer(size: canvasSize))
    #expect(!dragged.canUndo)
    #expect(!dragged.isDirty)

    let pressed = blankModel()
    pressed.selectTool(.rectangle)
    pressed.cursor = start
    pressed.applyToolAtCursor()
    pressed.cursor = end
    pressed.applyToolAtCursor()

    #expect(pressed.canUndo)
    pressed.undo()
    #expect(pressed.currentLayer.pixels == PixelBuffer(size: canvasSize))
    #expect(!pressed.canUndo)
  }

  @Test("A shape drag that never moves paints the single pixel under it")
  func degenerateShapeDragPaintsOnePixel() {
    let point = GIFEditorCore.PixelPoint(x: 2, y: 3)
    let model = blankModel()
    model.primaryColorIndex = 8
    model.selectTool(.rectangle)

    model.beginCanvasDrag(at: point)
    model.endCanvasDrag(startingAt: point, from: nil, to: point)

    #expect(model.currentLayer.pixels[point] == 8)
    #expect(model.currentLayer.pixels.pixels.compactMap { $0 }.count == 1)
  }

  @Test("Switching tools abandons a half-finished shape")
  func selectingAnotherToolClearsTheAnchor() {
    let model = blankModel()
    model.selectTool(.rectangle)
    model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 1)
    model.applyToolAtCursor()
    #expect(model.pendingShapeAnchor != nil)

    model.selectTool(.pen)

    #expect(model.pendingShapeAnchor == nil)
    #expect(!model.isDirty)
  }

  // MARK: - Mirror-X

  @Test("Mirror-X paints the reflected stroke as well, and only while it is on")
  func mirrorXPaintsBothSidesAndToggles() {
    let model = blankModel()
    model.primaryColorIndex = 3
    model.toggleStrokeMirrorX()
    #expect(model.strokesMirrorX)

    model.cursor = GIFEditorCore.PixelPoint(x: 0, y: 2)
    model.applyToolAtCursor()

    let painted = model.currentLayer.pixels
    #expect(painted[GIFEditorCore.PixelPoint(x: 0, y: 2)] == 3)
    // 6 columns: column 0 reflects onto column 5.
    #expect(painted[GIFEditorCore.PixelPoint(x: 5, y: 2)] == 3)

    model.toggleStrokeMirrorX()
    #expect(!model.strokesMirrorX)

    model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 0)
    model.applyToolAtCursor()

    #expect(model.currentLayer.pixels[GIFEditorCore.PixelPoint(x: 1, y: 0)] == 3)
    #expect(model.currentLayer.pixels[GIFEditorCore.PixelPoint(x: 4, y: 0)] == nil)
  }

  @Test("A mirrored drag leaves every row symmetric about the canvas centre")
  func mirroredDragIsSymmetric() {
    let model = blankModel()
    model.primaryColorIndex = 2
    model.toggleStrokeMirrorX()

    let start = GIFEditorCore.PixelPoint(x: 0, y: 0)
    let end = GIFEditorCore.PixelPoint(x: 2, y: 5)
    model.beginCanvasDrag(at: start)
    model.updateCanvasDrag(startingAt: start, from: start, to: end)
    model.endCanvasDrag(startingAt: start, from: end, to: end)

    let pixels = model.currentLayer.pixels
    var paintedAnything = false
    for y in 0..<canvasSize.height {
      for x in 0..<canvasSize.width {
        let mirrored = GIFEditorCore.PixelPoint(x: canvasSize.width - 1 - x, y: y)
        let value = pixels[GIFEditorCore.PixelPoint(x: x, y: y)]
        paintedAnything = paintedAnything || value != nil
        #expect(value == pixels[mirrored], "(\(x),\(y)) has no mirror at (\(mirrored.x),\(y))")
      }
    }
    // An empty layer is symmetric too, which would make the sweep above
    // pass without the stroke having happened.
    #expect(paintedAnything)
  }

  @Test("A mirrored eraser stroke clears both sides")
  func mirrorXAppliesToTheEraser() {
    var layer = PixelBuffer(size: canvasSize, fill: 1)
    layer[GIFEditorCore.PixelPoint(x: 3, y: 3)] = 2
    let model = EditingSession(
      document: GIFDocument(
        size: canvasSize,
        frames: [EditorFrame(layers: [EditorLayer(name: "Layer 1", pixels: layer)])]
      )
    )
    model.selectTool(.eraser)
    model.toggleStrokeMirrorX()

    model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 4)
    model.applyToolAtCursor()

    #expect(model.currentLayer.pixels[GIFEditorCore.PixelPoint(x: 1, y: 4)] == nil)
    #expect(model.currentLayer.pixels[GIFEditorCore.PixelPoint(x: 4, y: 4)] == nil)
  }

  @Test("Mirror-X is the same op the pure function performs")
  func mirrorXMatchesTheToolOp() {
    let model = blankModel()
    model.primaryColorIndex = 9
    model.increaseBrushSize()
    model.toggleStrokeMirrorX()

    let start = GIFEditorCore.PixelPoint(x: 1, y: 1)
    let end = GIFEditorCore.PixelPoint(x: 2, y: 4)
    model.beginCanvasDrag(at: start)
    model.endCanvasDrag(startingAt: start, from: start, to: end)

    var expected = ToolOps.mirrorXLine(
      on: PixelBuffer(size: canvasSize), from: start, to: start, color: 9, thickness: 2)
    expected = ToolOps.mirrorXLine(
      on: expected, from: start, to: end, color: 9, thickness: 2)
    #expect(model.currentLayer.pixels == expected)
  }

  // MARK: - Invalidation

  /// A shape commit is an ordinary pixel write, so it must invalidate the
  /// frame it painted and nothing else. With the oracle on, "nothing
  /// else" is checked against "and the frames it skipped were still
  /// right" rather than merely counted.
  @Test("A shape commit recomposites exactly the frame it painted")
  func shapeCommitRecompositesOneFrame() {
    let model = EditingSession(document: filledDocument(frames: 4))
    model.compositeOracleEnabled = true
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount
    model.selectFrame(at: 2)
    model.primaryColorIndex = 6
    model.selectTool(.rectangle)

    model.cursor = GIFEditorCore.PixelPoint(x: 0, y: 0)
    model.applyToolAtCursor()
    model.cursor = GIFEditorCore.PixelPoint(x: 3, y: 3)
    model.applyToolAtCursor()
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline + 1)
    #expect(after[2] != before[2])
    #expect([after[0], after[1], after[3]] == [before[0], before[1], before[3]])
  }

  @Test("A mirrored stroke recomposites exactly the frame it painted")
  func mirroredStrokeRecompositesOneFrame() {
    let model = EditingSession(document: filledDocument(frames: 3))
    model.compositeOracleEnabled = true
    _ = model.compositedFrames()
    let baseline = model.compositeRecomputeCount
    model.selectFrame(at: 1)
    model.toggleStrokeMirrorX()
    model.primaryColorIndex = 7
    model.cursor = GIFEditorCore.PixelPoint(x: 0, y: 0)

    model.applyToolAtCursor()
    _ = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline + 1)
  }

  // MARK: - Fixtures

  private var canvasSize: GIFEditorCore.PixelSize {
    GIFEditorCore.PixelSize(width: 6, height: 6)
  }

  private func blankModel() -> EditingSession {
    EditingSession(document: GIFDocument.blank(size: canvasSize))
  }

  /// `count` single-layer frames, each flooded with a distinct opaque
  /// slot, so a composite served staler than it should have been shows up
  /// as the wrong colour rather than as an empty frame.
  private func filledDocument(frames count: Int) -> GIFDocument {
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)
    let frames = (0..<count).map { index in
      EditorFrame(
        layers: [
          EditorLayer(
            name: "Layer 1",
            pixels: PixelBuffer(size: size, fill: PaletteIndex(1 + index))
          )
        ],
        delayCentiseconds: 9
      )
    }
    return GIFDocument(size: size, frames: frames)
  }
}

import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

/// Flip, rotate and cut — the four commands that rewrite a *region*
/// rather than a point.
///
/// The geometry is `ToolOpsTests`' problem. What is this layer's problem
/// is the question all four have to answer identically and could each
/// answer differently: *what happens when nothing is selected?* The
/// editor's answer is "the whole current layer", which is what
/// ``EditingSession/copySelection()`` already did, so every test below
/// runs its command twice — once inside a marquee and once with none.
@MainActor
@Suite("GIF editor transform commands")
struct TransformCommandTests {

  // MARK: - Flip

  @Test("Flipping with a marquee rewrites the marquee and nothing else")
  func flipHorizontallyHonoursTheSelection() {
    let original = countedLayer()
    let model = model(with: original)
    let region = PixelRect(x: 1, y: 1, width: 3, height: 2)
    model.selection = Selection(rect: region)

    model.flipHorizontally()

    #expect(model.currentLayer.pixels == ToolOps.flipHorizontal(on: original, rect: region))
    // Outside the marquee the layer is untouched, which the op equality
    // above would also satisfy if the op were a no-op — so name a cell.
    #expect(
      model.currentLayer.pixels[GIFEditorCore.PixelPoint(x: 0, y: 0)]
        == original[GIFEditorCore.PixelPoint(x: 0, y: 0)]
    )
    #expect(model.statusMessage == "Flipped selection left ↔ right")
  }

  @Test("Flipping with no marquee rewrites the whole layer")
  func flipHorizontallyFallsBackToTheLayer() {
    let original = countedLayer()
    let model = model(with: original)
    #expect(model.selection == nil)

    model.flipHorizontally()

    #expect(model.currentLayer.pixels == ToolOps.flipHorizontal(on: original, rect: nil))
    #expect(model.currentLayer.pixels != original)
    #expect(model.statusMessage == "Flipped layer left ↔ right")
  }

  @Test("Flipping vertically honours the same region rule")
  func flipVerticallyHonoursTheSameRule() {
    let original = countedLayer()
    let region = PixelRect(x: 2, y: 0, width: 2, height: 4)

    let selected = model(with: original)
    selected.selection = Selection(rect: region)
    selected.flipVertically()
    #expect(selected.currentLayer.pixels == ToolOps.flipVertical(on: original, rect: region))

    let wholeLayer = model(with: original)
    wholeLayer.flipVertically()
    #expect(wholeLayer.currentLayer.pixels == ToolOps.flipVertical(on: original, rect: nil))
    #expect(wholeLayer.statusMessage == "Flipped layer top ↔ bottom")
  }

  @Test("A flip is one undo step")
  func flipIsOneUndoStep() {
    let original = countedLayer()
    let model = model(with: original)

    model.flipHorizontally()
    #expect(model.canUndo)

    model.undo()

    #expect(model.currentLayer.pixels == original)
    #expect(!model.canUndo)
    #expect(!model.isDirty)
  }

  // MARK: - Rotate

  @Test("A square marquee turns losslessly, and the two directions undo each other")
  func rotatingASquareRegionIsReversible() {
    let original = countedLayer()
    let region = PixelRect(x: 1, y: 0, width: 3, height: 3)
    let model = model(with: original)
    model.selection = Selection(rect: region)

    model.rotateClockwise()
    let turned = model.currentLayer.pixels
    #expect(turned == ToolOps.rotateClockwise(on: original, rect: region))
    #expect(turned != original)
    #expect(model.statusMessage == "Rotated selection a quarter turn clockwise")

    model.rotateCounterClockwise()

    #expect(model.currentLayer.pixels == original)
  }

  @Test("Rotating with no marquee turns the whole layer")
  func rotatingFallsBackToTheLayer() {
    let original = countedLayer()
    let model = model(with: original)

    model.rotateCounterClockwise()

    #expect(model.currentLayer.pixels == ToolOps.rotateCounterClockwise(on: original, rect: nil))
    #expect(model.statusMessage == "Rotated layer a quarter turn counter-clockwise")
  }

  @Test("A rotation is one undo step even when it loses pixels off a non-square edge")
  func rotationIsOneUndoStep() {
    let original = countedLayer()
    let model = model(with: original)
    // 6×4: not square, so the turn clips and is not self-inverse. Undo is
    // the only thing that can give those pixels back, which is exactly
    // why the step has to be recorded.
    model.rotateClockwise()
    #expect(model.canUndo)

    model.undo()

    #expect(model.currentLayer.pixels == original)
    #expect(!model.canUndo)
  }

  // MARK: - Cut

  @Test("Cutting a marquee takes it to the clipboard and clears it")
  func cutTakesTheSelectionAndClearsIt() {
    let original = countedLayer()
    let model = model(with: original)
    let region = PixelRect(x: 1, y: 1, width: 2, height: 2)
    model.selection = Selection(rect: region)

    model.cutSelection()

    #expect(model.clipboard == ToolOps.copy(from: original, rect: region))
    #expect(model.currentLayer.pixels == ToolOps.clear(on: original, rect: region))
    #expect(model.currentLayer.pixels[GIFEditorCore.PixelPoint(x: 1, y: 1)] == nil)
    #expect(model.statusMessage == "Cut selection")
  }

  @Test("Cutting with no marquee takes the whole layer")
  func cutFallsBackToTheLayer() {
    let original = countedLayer()
    let model = model(with: original)

    model.cutSelection()

    #expect(model.clipboard == original)
    #expect(model.currentLayer.pixels == PixelBuffer(size: original.size))
    #expect(model.statusMessage == "Cut layer")
  }

  @Test("A cut is one undo step, and undoing it keeps what was cut")
  func cutIsOneUndoStepAndKeepsTheClipboard() {
    let original = countedLayer()
    let model = model(with: original)
    model.selection = Selection(rect: PixelRect(x: 0, y: 0, width: 2, height: 2))

    model.cutSelection()
    let taken = model.clipboard
    #expect(taken != nil)
    #expect(model.canUndo)

    model.undo()

    #expect(model.currentLayer.pixels == original)
    #expect(!model.canUndo)
    // Undo restores the pixels, not the pasteboard: taking the cut back
    // out of the clipboard would throw away the half of the operation the
    // author is usually in the middle of using.
    #expect(model.clipboard == taken)
  }

  @Test("Cut then paste at the same corner puts the pixels back")
  func cutRoundTripsThroughPaste() {
    let original = countedLayer()
    let model = model(with: original)
    let region = PixelRect(x: 2, y: 1, width: 3, height: 2)
    model.selection = Selection(rect: region)

    model.cutSelection()
    model.cursor = GIFEditorCore.PixelPoint(x: region.minX, y: region.minY)
    model.paste()

    #expect(model.currentLayer.pixels == original)
  }

  // MARK: - Invalidation

  /// All four rewrite pixels on one layer of one frame, so all four must
  /// invalidate exactly that frame — with the oracle on, so "the other
  /// three were served from cache" is checked against "and they were
  /// still correct".
  @Test("Each transform recomposites exactly the frame it changed")
  func transformsRecompositeOneFrame() {
    for transform in Self.transforms {
      let model = EditingSession(document: filledDocument(frames: 4))
      model.compositeOracleEnabled = true
      let before = model.compositedFrames()
      let baseline = model.compositeRecomputeCount
      model.selectFrame(at: 1)
      model.selection = Selection(rect: PixelRect(x: 0, y: 0, width: 2, height: 2))

      transform.run(model)
      let after = model.compositedFrames()

      #expect(
        model.compositeRecomputeCount == baseline + 1,
        "\(transform.name) recomposited more than the frame it changed"
      )
      #expect(after[1] != before[1], "\(transform.name) changed nothing")
      #expect([after[0], after[2], after[3]] == [before[0], before[2], before[3]])
    }
  }

  /// Named closures rather than a `[(String, (EditingSession) -> Void)]`
  /// so a failure message can say which verb failed.
  private struct Transform {
    let name: String
    let run: @MainActor (EditingSession) -> Void
  }

  private static let transforms: [Transform] = [
    Transform(name: "flip horizontally") { $0.flipHorizontally() },
    Transform(name: "flip vertically") { $0.flipVertically() },
    Transform(name: "rotate clockwise") { $0.rotateClockwise() },
    Transform(name: "rotate counter-clockwise") { $0.rotateCounterClockwise() },
    Transform(name: "cut") { $0.cutSelection() },
  ]

  // MARK: - Fixtures

  /// A layer where every cell holds a different palette index, so any
  /// rearrangement of it is visible and no two cells can alias.
  private func countedLayer() -> PixelBuffer {
    let size = GIFEditorCore.PixelSize(width: 6, height: 4)
    var buffer = PixelBuffer(size: size)
    for y in 0..<size.height {
      for x in 0..<size.width {
        buffer[GIFEditorCore.PixelPoint(x: x, y: y)] = PaletteIndex(1 + y * size.width + x)
      }
    }
    return buffer
  }

  private func model(with layer: PixelBuffer) -> EditingSession {
    EditingSession(
      document: GIFDocument(
        size: layer.size,
        frames: [EditorFrame(layers: [EditorLayer(name: "Layer 1", pixels: layer)])]
      )
    )
  }

  private func filledDocument(frames count: Int) -> GIFDocument {
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)
    let frames = (0..<count).map { index -> EditorFrame in
      var pixels = PixelBuffer(size: size, fill: PaletteIndex(1 + index))
      // A flooded frame is invariant under every transform here, so give
      // each one an asymmetric mark to move.
      pixels[GIFEditorCore.PixelPoint(x: 0, y: 0)] = PaletteIndex(20 + index)
      return EditorFrame(
        layers: [EditorLayer(name: "Layer 1", pixels: pixels)],
        delayCentiseconds: 9
      )
    }
    return GIFDocument(size: size, frames: frames)
  }
}

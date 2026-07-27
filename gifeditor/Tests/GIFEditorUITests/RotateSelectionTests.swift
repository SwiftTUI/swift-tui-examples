import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

/// What rotation has to answer that flipping never did: *a quarter turn
/// of a non-square marquee lands somewhere else*.
///
/// A `w × h` marquee turns into an `h × w` one, so the pixels and the
/// marquee describing them stop agreeing the instant the turn happens
/// unless the command moves both. `TransformCommandTests` owns the
/// region rule the four transforms share; this suite owns the half of
/// the rule only rotation has — and, because a marquee is editor state
/// rather than document state, the fact that both halves live in one
/// undo step.
@MainActor
@Suite("GIF editor rotate-selection commands")
struct RotateSelectionTests {

  // MARK: - The marquee follows its pixels

  @Test("A non-square marquee turns losslessly and the marquee lands with the pixels")
  func rotatingANonSquareMarqueeMovesTheMarquee() {
    let original = countedLayer()
    let model = model(with: original)
    let region = PixelRect(x: 1, y: 1, width: 4, height: 2)
    model.selection = Selection(rect: region)
    let carried = values(of: original, in: region)

    model.rotateClockwise()

    let turned = model.currentLayer.pixels
    #expect(turned == ToolOps.quarterTurnClockwise(on: original, rect: region).buffer)
    // The 4×2 became a 2×4 pinned to the same corner, and the marquee is
    // pointing at it rather than at the ground the pixels left.
    #expect(model.selection?.rect == PixelRect(x: 1, y: 1, width: 2, height: 4))
    // Lossless: every pixel that was in the region is still on the layer,
    // and it is inside the marquee, which is the check that catches a
    // rect that moved somewhere the pixels did not.
    #expect(Set(turned.pixels.compactMap { $0 }).isSuperset(of: carried))
    #expect(values(of: turned, in: model.selection!.rect) == carried)
    #expect(model.statusMessage == "Rotated selection a quarter turn clockwise")
  }

  @Test("Turning back returns both the pixels and the marquee")
  func rotatingBackRestoresThePixelsAndTheMarquee() {
    // The ground the turn lands on is transparent here, so "the layer
    // came back" means no pixel was lost rather than no pixel was
    // overwritten — the distinction `ToolOpsTests` pins.
    let region = PixelRect(x: 1, y: 1, width: 4, height: 2)
    let original = isolatedLayer(region: region)
    let model = model(with: original)
    model.selection = Selection(rect: region)

    model.rotateClockwise()
    #expect(model.currentLayer.pixels != original)
    model.rotateCounterClockwise()

    #expect(model.currentLayer.pixels == original)
    #expect(model.selection?.rect == region)
  }

  @Test("Four turns of a non-square marquee are the identity")
  func fourTurnsOfANonSquareMarqueeAreTheIdentity() {
    let region = PixelRect(x: 0, y: 0, width: 3, height: 2)
    let original = isolatedLayer(region: region)
    let model = model(with: original)
    model.selection = Selection(rect: region)

    for _ in 0..<4 {
      model.rotateClockwise()
    }

    #expect(model.currentLayer.pixels == original)
    #expect(model.selection?.rect == region)
  }

  @Test("A flip leaves the marquee exactly where it was")
  func flippingLeavesTheMarqueeAlone() {
    let original = countedLayer()
    let model = model(with: original)
    let region = PixelRect(x: 1, y: 1, width: 4, height: 2)
    model.selection = Selection(rect: region)

    model.flipHorizontally()
    #expect(model.selection?.rect == region)

    model.flipVertically()
    #expect(model.selection?.rect == region)
  }

  @Test("With no marquee a turn leaves the selection unset")
  func rotatingTheWholeLayerLeavesTheSelectionUnset() {
    let original = countedLayer()
    let model = model(with: original)
    #expect(model.selection == nil)

    model.rotateClockwise()

    // The whole of a non-square layer cannot turn without resizing the
    // document, so this stays the clipping case — and there is no
    // marquee to re-point at anything.
    #expect(model.selection == nil)
    #expect(model.currentLayer.pixels == ToolOps.rotateClockwise(on: original, rect: nil))
    #expect(model.statusMessage == "Rotated layer a quarter turn clockwise")
  }

  // MARK: - One undo step

  @Test("One undo step puts back both the pixels and the marquee")
  func rotationIsOneUndoStepForPixelsAndSelection() {
    let original = countedLayer()
    let model = model(with: original)
    let region = PixelRect(x: 1, y: 1, width: 4, height: 2)
    model.selection = Selection(rect: region)

    model.rotateClockwise()
    #expect(model.canUndo)
    #expect(model.selection?.rect != region)

    model.undo()

    #expect(model.currentLayer.pixels == original)
    #expect(model.selection?.rect == region)
    // A second step would mean the marquee and the pixels could be left
    // disagreeing halfway through an undo.
    #expect(!model.canUndo)
    #expect(!model.isDirty)
  }

  @Test("Redo re-applies the marquee move with the pixels")
  func redoReappliesBothHalves() {
    let original = countedLayer()
    let model = model(with: original)
    let region = PixelRect(x: 1, y: 1, width: 4, height: 2)
    model.selection = Selection(rect: region)

    model.rotateClockwise()
    let turned = model.currentLayer.pixels
    let turnedRegion = model.selection?.rect
    model.undo()
    model.redo()

    #expect(model.currentLayer.pixels == turned)
    #expect(model.selection?.rect == turnedRegion)
  }

  // MARK: - Invalidation

  @Test("A turn that writes outside the marquee still recomposites one frame")
  func rotatingANonSquareMarqueeRecompositesOneFrame() {
    // The turned region reaches rows the marquee never covered, so this
    // is the case where a `.frameContent` stamp could plausibly be too
    // narrow. It is not: the write is still one layer of one frame.
    let model = EditorViewModel(document: filledDocument(frames: 3))
    model.compositeOracleEnabled = true
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount
    model.selectFrame(at: 1)
    model.selection = Selection(rect: PixelRect(x: 0, y: 0, width: 4, height: 2))

    model.rotateClockwise()
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline + 1)
    #expect(after[1] != before[1])
    #expect([after[0], after[2]] == [before[0], before[2]])
  }

  // MARK: - Fixtures

  /// A 6×6 layer where every cell holds a different palette index, so
  /// any rearrangement is visible and no two cells can alias.
  private func countedLayer() -> PixelBuffer {
    let size = GIFEditorCore.PixelSize(width: 6, height: 6)
    var buffer = PixelBuffer(size: size)
    for y in 0..<size.height {
      for x in 0..<size.width {
        buffer[GIFEditorCore.PixelPoint(x: x, y: y)] = PaletteIndex(1 + y * size.width + x)
      }
    }
    return buffer
  }

  /// A 6×6 layer that is transparent everywhere except `region`.
  private func isolatedLayer(region: PixelRect) -> PixelBuffer {
    var buffer = PixelBuffer(size: GIFEditorCore.PixelSize(width: 6, height: 6))
    var value: PaletteIndex = 1
    for y in region.minY..<region.maxY {
      for x in region.minX..<region.maxX {
        buffer[GIFEditorCore.PixelPoint(x: x, y: y)] = value
        value += 1
      }
    }
    return buffer
  }

  private func values(of buffer: PixelBuffer, in rect: PixelRect) -> Set<PaletteIndex> {
    var found: Set<PaletteIndex> = []
    for y in rect.minY..<rect.maxY {
      for x in rect.minX..<rect.maxX {
        if let value = buffer[GIFEditorCore.PixelPoint(x: x, y: y)] {
          found.insert(value)
        }
      }
    }
    return found
  }

  private func model(with layer: PixelBuffer) -> EditorViewModel {
    EditorViewModel(
      document: GIFDocument(
        size: layer.size,
        frames: [EditorFrame(layers: [EditorLayer(name: "Layer 1", pixels: layer)])]
      )
    )
  }

  private func filledDocument(frames count: Int) -> GIFDocument {
    let size = GIFEditorCore.PixelSize(width: 6, height: 4)
    let frames = (0..<count).map { index -> EditorFrame in
      var pixels = PixelBuffer(size: size, fill: PaletteIndex(1 + index))
      // A flooded frame is invariant under a turn, so give each one an
      // asymmetric mark to move.
      pixels[GIFEditorCore.PixelPoint(x: 0, y: 0)] = PaletteIndex(20 + index)
      return EditorFrame(
        layers: [EditorLayer(name: "Layer 1", pixels: pixels)],
        delayCentiseconds: 9
      )
    }
    return GIFDocument(size: size, frames: frames)
  }
}

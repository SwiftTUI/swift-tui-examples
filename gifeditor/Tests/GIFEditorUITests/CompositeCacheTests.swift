import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

/// Cache-behavior tests for `EditorViewModel.compositedFrames()`.
///
/// The cache key stopped being the frame's content and became a mutation
/// stamp, so "does this edit recomposite?" is no longer decidable by
/// reading the key — it is a property of the write path. These tests pin
/// it from both sides: `compositeRecomputeCount` for how much work a given
/// edit costs, and the composited colors themselves (plus
/// `compositeOracleEnabled`) for whether the answer is still right.
@MainActor
@Suite("GIF editor composite cache")
struct CompositeCacheTests {
  // MARK: - The core property

  @Test("A second composite pass with no mutation in between recomputes nothing")
  func repeatedPassWithoutMutationRecomputesNothing() {
    let model = EditorViewModel(document: filledDocument(frames: 4))

    let first = model.compositedFrames()
    #expect(model.compositeRecomputeCount == 4)

    let second = model.compositedFrames()

    #expect(model.compositeRecomputeCount == 4)
    #expect(second == first)
  }

  @Test("Painting one frame of a four-frame document recomposites exactly one frame")
  func paintingRecompositesOnlyTheEditedFrame() {
    let model = EditorViewModel(document: filledDocument(frames: 4))
    _ = model.compositedFrames()
    let baseline = model.compositeRecomputeCount
    model.selectFrame(at: 1)
    model.primaryColorIndex = 9
    model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 1)

    model.applyToolAtCursor()
    let composites = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline + 1)
    let palette = model.document.palette
    #expect(composites[1][paintedIndex] == palette[9])
    #expect(composites[1][0] == palette[2])
    #expect(composites[0] == Array(repeating: palette[1], count: area))
    #expect(composites[3] == Array(repeating: palette[4], count: area))
  }

  // MARK: - Frame list edits

  @Test("Inserting a blank frame recomposites only the new frame")
  func insertingAFrameLeavesSurvivorsCached() {
    let model = EditorViewModel(document: filledDocument(frames: 3))
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount

    model.insertBlankFrameAfterCurrent()
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline + 1)
    #expect(after.count == 4)
    #expect([after[0], after[2], after[3]] == before)
    #expect(after[1] == Array(repeating: nil, count: area))
  }

  @Test("Duplicating a frame recomposites only the copy")
  func duplicatingAFrameLeavesSurvivorsCached() {
    let model = EditorViewModel(document: filledDocument(frames: 3))
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount

    model.duplicateCurrentFrame()
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline + 1)
    #expect([after[0], after[2], after[3]] == before)
    #expect(after[1] == before[0])
  }

  @Test("Deleting a frame recomposites nothing")
  func deletingAFrameRecompositesNothing() {
    let model = EditorViewModel(document: filledDocument(frames: 3))
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount
    model.selectFrame(at: 1)

    model.deleteCurrentFrame()
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline)
    #expect(after == [before[0], before[2]])
  }

  @Test("Moving a frame recomposites nothing, including the frame that moved")
  func movingAFrameRecompositesNothing() {
    let model = EditorViewModel(document: filledDocument(frames: 3))
    // Paint first so the moved frame carries a stamp rather than the
    // unstamped default — a move must not disturb either.
    model.primaryColorIndex = 9
    model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 1)
    model.applyToolAtCursor()
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount

    model.moveCurrentFrame(by: 2)
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline)
    #expect(after == [before[1], before[2], before[0]])
  }

  // MARK: - Layer edits

  @Test("Toggling layer visibility recomposites only the current frame")
  func layerVisibilityToggleRecompositesOnlyTheCurrentFrame() {
    let model = EditorViewModel(document: filledDocument(frames: 3))
    model.selectFrame(at: 2)
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount

    model.toggleCurrentLayerVisibility()
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline + 1)
    #expect([after[0], after[1]] == [before[0], before[1]])
    #expect(after[2] == Array(repeating: nil, count: area))
  }

  @Test("Adding and deleting a layer each recomposite only the current frame")
  func layerAddAndDeleteRecompositeOnlyTheCurrentFrame() {
    let model = EditorViewModel(document: filledDocument(frames: 3))
    model.selectFrame(at: 1)
    let before = model.compositedFrames()
    var expected = model.compositeRecomputeCount

    model.addLayer()
    expected += 1
    let afterAdd = model.compositedFrames()

    #expect(model.compositeRecomputeCount == expected)
    // The new layer is fully transparent, so the composite is unchanged —
    // but it is a *recomputed* unchanged composite, not a cache hit.
    #expect(afterAdd == before)

    model.deleteCurrentLayer()
    expected += 1
    let afterDelete = model.compositedFrames()

    #expect(model.compositeRecomputeCount == expected)
    #expect(afterDelete == before)
  }

  // MARK: - Document-wide edits

  @Test("Resizing the canvas recomposites every frame")
  func resizeRecompositesEveryFrame() {
    let model = EditorViewModel(document: filledDocument(frames: 3))
    _ = model.compositedFrames()
    let baseline = model.compositeRecomputeCount

    model.resizeCanvas(to: GIFEditorCore.PixelSize(width: 6, height: 6))
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline + 3)
    #expect(after[0].count == 36)
    // Resize pads with transparency and keeps the original top-left block.
    let palette = model.document.palette
    #expect(after[0][0] == palette[1])
    #expect(after[0][35] == nil)
  }

  @Test("Frame delay edits recomposite nothing and leave composites correct")
  func frameDelayEditsRecompositeNothing() {
    let model = EditorViewModel(document: filledDocument(frames: 3))
    model.compositeOracleEnabled = true
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount

    // Delay is playback timing; `flattenedColors(for:)` never reads it, so
    // neither write site stamps. The oracle audits every hit below.
    model.adjustCurrentFrameDelay(by: 5)
    #expect(model.compositedFrames() == before)
    model.setAllFrameDelaysToCurrent()
    #expect(model.compositedFrames() == before)

    #expect(model.compositeRecomputeCount == baseline)
    #expect(model.document.frames.allSatisfy { $0.delayCentiseconds == 6 })
  }

  // MARK: - Undo / redo

  @Test("Undo and redo produce correct composites")
  func undoAndRedoProduceCorrectComposites() {
    let model = EditorViewModel(document: filledDocument(frames: 3))
    model.compositeOracleEnabled = true
    let clean = model.compositedFrames()
    model.selectFrame(at: 2)
    model.primaryColorIndex = 9
    model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 1)

    model.applyToolAtCursor()
    let painted = model.compositedFrames()
    #expect(painted != clean)

    model.undo()

    #expect(model.compositedFrames() == clean)
    // Second pass is all cache hits, so the oracle re-derives and checks
    // every frame of the restored document.
    #expect(model.compositedFrames() == clean)

    model.redo()

    #expect(model.compositedFrames() == painted)
    #expect(model.compositedFrames() == painted)
  }

  @Test("Undo recomposites the whole document, deliberately")
  func undoInvalidatesEveryFrame() {
    let model = EditorViewModel(document: filledDocument(frames: 3))
    _ = model.compositedFrames()
    model.primaryColorIndex = 9
    model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 1)
    model.applyToolAtCursor()
    _ = model.compositedFrames()
    let baseline = model.compositeRecomputeCount

    model.undo()
    _ = model.compositedFrames()

    // A restore swaps the whole document, so per-frame stamps taken
    // against the outgoing one mean nothing and every frame recomputes.
    #expect(model.compositeRecomputeCount == baseline + 3)
  }

  // MARK: - Oracle

  @Test("A representative edit sequence passes the composite soundness oracle")
  func oracleAcceptsARepresentativeEditSequence() {
    let model = EditorViewModel(document: filledDocument(frames: 3))
    model.compositeOracleEnabled = true
    model.primaryColorIndex = 9

    // Each step: one pass to refresh, one pass where every frame is a
    // cache hit and is therefore re-derived and compared by the oracle. If
    // any write site declared the wrong invalidation, the second pass
    // traps rather than returning a stale frame.
    func settle() {
      _ = model.compositedFrames()
      let hits = model.compositeRecomputeCount
      _ = model.compositedFrames()
      #expect(model.compositeRecomputeCount == hits)
    }

    settle()

    model.cursor = GIFEditorCore.PixelPoint(x: 0, y: 0)
    model.applyToolAtCursor()
    settle()

    model.beginCanvasDrag(at: GIFEditorCore.PixelPoint(x: 0, y: 0))
    model.updateCanvasDrag(
      startingAt: GIFEditorCore.PixelPoint(x: 0, y: 0),
      from: GIFEditorCore.PixelPoint(x: 0, y: 0),
      to: GIFEditorCore.PixelPoint(x: 3, y: 3)
    )
    model.endCanvasDrag(
      startingAt: GIFEditorCore.PixelPoint(x: 0, y: 0),
      from: GIFEditorCore.PixelPoint(x: 3, y: 3),
      to: GIFEditorCore.PixelPoint(x: 3, y: 3)
    )
    settle()

    model.addLayer()
    settle()

    model.selectTool(.fill)
    model.cursor = GIFEditorCore.PixelPoint(x: 2, y: 2)
    model.applyToolAtCursor()
    settle()

    model.toggleCurrentLayerVisibility()
    settle()

    model.deleteCurrentLayer()
    settle()

    model.insertBlankFrameAfterCurrent()
    settle()

    model.duplicateCurrentFrame()
    settle()

    model.moveCurrentFrame(by: -1)
    settle()

    model.adjustCurrentFrameDelay(by: 3)
    settle()

    model.setAllFrameDelaysToCurrent()
    settle()

    model.deleteCurrentFrame()
    settle()

    model.resizeCanvas(to: GIFEditorCore.PixelSize(width: 6, height: 6))
    settle()

    model.undo()
    settle()

    model.redo()
    settle()
  }

  // MARK: - Fixtures

  private let side = 4
  private var area: Int { side * side }
  /// Flat index of `(1, 1)` in a `side × side` buffer.
  private var paintedIndex: Int { side + 1 }

  /// `count` single-layer frames, each flooded with a distinct opaque
  /// palette slot, so a stale composite shows up as the wrong color rather
  /// than as an empty frame.
  private func filledDocument(frames count: Int) -> GIFDocument {
    let size = GIFEditorCore.PixelSize(width: side, height: side)
    let frames = (0..<count).map { index in
      EditorFrame(
        layers: [
          EditorLayer(
            name: "Layer 1",
            pixels: PixelBuffer(size: size, fill: PaletteIndex(index + 1))
          )
        ],
        delayCentiseconds: index + 1
      )
    }
    return GIFDocument(size: size, frames: frames)
  }
}

import GIFEditorCore

/// Semantic requests that may change or navigate an Editing session.
///
/// Input adapters translate keys, menu items, and pointer gestures into this
/// closed vocabulary. File lifecycle and display-only commands deliberately
/// do not appear here.
public enum EditingIntent: Hashable, Sendable {
  case undo
  case redo

  case applyActiveTool
  case selectTool(ActiveTool)
  case setFillRespectsSelection(Bool)
  case setGradientRespectsSelection(Bool)
  case toggleShapeFill
  case toggleStrokeMirrorX
  case clearSelection
  case swapPrimaryAndSecondary
  case setPrimaryColor(PaletteIndex)
  case setSecondaryColor(PaletteIndex)
  case increaseBrushSize
  case decreaseBrushSize
  case moveCursor(dx: Int, dy: Int)

  case beginCanvasDrag(PixelPoint)
  case updateCanvasDrag(anchor: PixelPoint, previous: PixelPoint?, point: PixelPoint)
  case endCanvasDrag(anchor: PixelPoint, previous: PixelPoint?, point: PixelPoint)

  case nextFrame
  case previousFrame
  case firstFrame
  case lastFrame
  case selectFrame(Int)
  case insertBlankFrame
  case duplicateFrame
  case deleteFrame
  case moveCurrentFrame(Int)
  case moveFrame(source: Int, destination: Int)
  case moveFrameToStart
  case moveFrameToEnd
  case adjustFrameDelay(Int)
  case setFrameDelay(Int)
  case resetFrameDelay
  case beginDelayScrub
  case updateDelayScrub(Int)
  case endDelayScrub
  case setFrameDisposal(EditorFrame.FrameDisposal)
  case cycleFrameDisposal
  case setLoopCount(Int)
  case adjustLoopCount(Int)
  case toggleLoopsForever
  case setAllFrameDelaysToCurrent

  case addLayer
  case selectLayerBelow
  case selectLayerAbove
  case selectLayer(Int)
  case toggleCurrentLayerVisibility
  case toggleLayerVisibility(Int)
  case deleteCurrentLayer
  case deleteLayer(Int)

  case copySelection
  case cutSelection
  case paste
  case flipHorizontally
  case flipVertically
  case rotateClockwise
  case rotateCounterClockwise

  case setPaletteColor(EditorColor, at: PaletteIndex)
  case appendPaletteColor(EditorColor)
  case removePaletteSlot(PaletteIndex)
  case compactPalette
  case sortPalette

  case resizeCanvas(PixelSize)
  case cycleCanvasSize

  case togglePlayback
  case startPlayback
  case stopPlayback
  case advancePlaybackFrame
}

/// Immutable view of all state owned by an Editing session.
public struct EditingSessionState: Hashable, Sendable {
  public let document: GIFDocument
  public let currentFrameIndex: Int
  public let currentLayerIndex: Int
  public let cursor: PixelPoint
  public let selection: Selection?
  public let clipboard: PixelBuffer?

  public let tool: ActiveTool
  public let primaryColorIndex: PaletteIndex
  public let secondaryColorIndex: PaletteIndex
  public let brushSize: Int
  public let fillRespectsSelection: Bool
  public let gradientRespectsSelection: Bool
  public let shapeFillsInterior: Bool
  public let strokesMirrorX: Bool

  public let pendingMarqueeAnchor: PixelPoint?
  public let pendingGradientAnchor: PixelPoint?
  public let pendingShapeAnchor: PixelPoint?
  public let isPlaybackActive: Bool
  public let isScrubbingDelay: Bool

  public let canUndo: Bool
  public let canRedo: Bool
  public let isDirty: Bool
  public let generation: EditingGeneration
  public let statusMessage: String
}

public enum EditingResult: Hashable, Sendable {
  case changed
  case updated
  case unchanged
}

/// Result plus the immutable state produced by an Editing intent.
public struct EditingOutcome: Hashable, Sendable {
  public let result: EditingResult
  public let state: EditingSessionState
}

extension EditingSession {
  public var state: EditingSessionState {
    EditingSessionState(
      document: document,
      currentFrameIndex: currentFrameIndex,
      currentLayerIndex: currentLayerIndex,
      cursor: cursor,
      selection: selection,
      clipboard: clipboard,
      tool: tool,
      primaryColorIndex: primaryColorIndex,
      secondaryColorIndex: secondaryColorIndex,
      brushSize: brushSize,
      fillRespectsSelection: fillRespectsSelection,
      gradientRespectsSelection: gradientRespectsSelection,
      shapeFillsInterior: shapeFillsInterior,
      strokesMirrorX: strokesMirrorX,
      pendingMarqueeAnchor: pendingMarqueeAnchor,
      pendingGradientAnchor: pendingGradientAnchor,
      pendingShapeAnchor: pendingShapeAnchor,
      isPlaybackActive: isPlaybackActive,
      isScrubbingDelay: isScrubbingDelay,
      canUndo: canUndo,
      canRedo: canRedo,
      isDirty: isDirty,
      generation: generation,
      statusMessage: statusMessage
    )
  }

  @discardableResult
  public func dispatch(_ intent: EditingIntent) -> EditingOutcome {
    let before = state

    switch intent {
    case .undo: undo()
    case .redo: redo()
    case .applyActiveTool: applyToolAtCursor()
    case .selectTool(let tool): selectTool(tool)
    case .setFillRespectsSelection(let value): fillRespectsSelection = value
    case .setGradientRespectsSelection(let value): gradientRespectsSelection = value
    case .toggleShapeFill: toggleShapeFill()
    case .toggleStrokeMirrorX: toggleStrokeMirrorX()
    case .clearSelection: clearSelection()
    case .swapPrimaryAndSecondary: swapPrimaryAndSecondary()
    case .setPrimaryColor(let index): setPrimaryColor(index)
    case .setSecondaryColor(let index): setSecondaryColor(index)
    case .increaseBrushSize: increaseBrushSize()
    case .decreaseBrushSize: decreaseBrushSize()
    case .moveCursor(let dx, let dy): moveCursor(dx: dx, dy: dy)

    case .beginCanvasDrag(let point):
      beginCanvasDrag(at: point)
    case .updateCanvasDrag(let anchor, let previous, let point):
      updateCanvasDrag(startingAt: anchor, from: previous, to: point)
    case .endCanvasDrag(let anchor, let previous, let point):
      endCanvasDrag(startingAt: anchor, from: previous, to: point)

    case .nextFrame: nextFrame()
    case .previousFrame: previousFrame()
    case .firstFrame: goToFirstFrame()
    case .lastFrame: goToLastFrame()
    case .selectFrame(let index): selectFrame(at: index)
    case .insertBlankFrame: insertBlankFrameAfterCurrent()
    case .duplicateFrame: duplicateCurrentFrame()
    case .deleteFrame: deleteCurrentFrame()
    case .moveCurrentFrame(let delta): moveCurrentFrame(by: delta)
    case .moveFrame(let source, let destination): moveFrame(from: source, to: destination)
    case .moveFrameToStart: moveCurrentFrameToStart()
    case .moveFrameToEnd: moveCurrentFrameToEnd()
    case .adjustFrameDelay(let delta): adjustCurrentFrameDelay(by: delta)
    case .setFrameDelay(let delay): setCurrentFrameDelay(delay)
    case .resetFrameDelay: resetCurrentFrameDelay()
    case .beginDelayScrub: beginDelayScrub()
    case .updateDelayScrub(let delta): updateDelayScrub(by: delta)
    case .endDelayScrub: endDelayScrub()
    case .setFrameDisposal(let disposal): setCurrentFrameDisposal(disposal)
    case .cycleFrameDisposal: cycleCurrentFrameDisposal()
    case .setLoopCount(let count): setLoopCount(count)
    case .adjustLoopCount(let delta): adjustLoopCount(by: delta)
    case .toggleLoopsForever: toggleLoopsForever()
    case .setAllFrameDelaysToCurrent: setAllFrameDelaysToCurrent()

    case .addLayer: addLayer()
    case .selectLayerBelow: selectLayerBelow()
    case .selectLayerAbove: selectLayerAbove()
    case .selectLayer(let index): selectLayer(at: index)
    case .toggleCurrentLayerVisibility: toggleCurrentLayerVisibility()
    case .toggleLayerVisibility(let index): toggleLayerVisibility(at: index)
    case .deleteCurrentLayer: deleteCurrentLayer()
    case .deleteLayer(let index): deleteLayer(at: index)

    case .copySelection: copySelection()
    case .cutSelection: cutSelection()
    case .paste: paste()
    case .flipHorizontally: flipHorizontally()
    case .flipVertically: flipVertically()
    case .rotateClockwise: rotateClockwise()
    case .rotateCounterClockwise: rotateCounterClockwise()

    case .setPaletteColor(let color, let index): setPaletteColor(color, at: index)
    case .appendPaletteColor(let color): appendPaletteColor(color)
    case .removePaletteSlot(let index): removePaletteSlot(at: index)
    case .compactPalette: compactPalette()
    case .sortPalette: sortPalette()

    case .resizeCanvas(let size): resizeCanvas(to: size)
    case .cycleCanvasSize: cycleCanvasSize()

    case .togglePlayback: togglePlayback()
    case .startPlayback: startPlayback()
    case .stopPlayback: stopPlayback()
    case .advancePlaybackFrame: _ = advancePlaybackFrame()
    }

    let after = state
    let result: EditingResult
    if before.generation != after.generation {
      result = .changed
    } else if before != after {
      result = .updated
    } else {
      result = .unchanged
    }
    return EditingOutcome(result: result, state: after)
  }
}

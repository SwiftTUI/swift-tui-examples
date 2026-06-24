import Foundation
import GIFEditorCore
import SwiftTUI

/// Reference-type owner of the editor's mutable state. The view tree
/// reads `document` as a value type via @State, but mutating ops live
/// here so individual views don't need to thread the document around.
///
/// Kept @MainActor — the editor is single-window, single-threaded, and
/// every mutation is driven from a UI event.
///
/// The view model is a coordinator: it owns the document and selection
/// context (cursor, frame/layer index, tool state) and delegates the
/// three cross-cutting concerns to focused collaborators —
/// `EditorHistory` for undo/redo, `CanvasDragController` for pointer
/// drags, and `GIFDocumentIO` for save/encode. Those collaborators never
/// touch the view tree, so the coordinator stays the single mutation
/// surface the views bind to.
@MainActor
public final class EditorViewModel {
  // MARK: - Document

  public private(set) var document: GIFDocument

  // MARK: - History

  private var history = EditorHistory()

  public var canUndo: Bool {
    history.canUndo
  }

  public var canRedo: Bool {
    history.canRedo
  }

  public var isDirty: Bool {
    history.isDirty
  }

  // MARK: - Selection state

  public var currentFrameIndex: Int = 0 {
    didSet {
      currentFrameIndex = currentFrameIndex.clamped(to: 0...max(0, document.frames.count - 1))
      // The new frame may have fewer layers than the previous one;
      // currentLayerIndex's own didSet doesn't fire when only the frame
      // changes, so re-clamp explicitly here.
      clampCurrentLayerIndex()
    }
  }

  public var currentLayerIndex: Int = 0 {
    didSet {
      clampCurrentLayerIndex()
    }
  }

  private func clampCurrentLayerIndex() {
    let upper = max(0, document.frames[currentFrameIndex].layers.count - 1)
    let clamped = currentLayerIndex.clamped(to: 0...upper)
    if currentLayerIndex != clamped {
      currentLayerIndex = clamped
    }
  }

  // MARK: - Tool state

  public var tool: EditorTool = .pen
  public var primaryColorIndex: PaletteIndex = 1
  public var secondaryColorIndex: PaletteIndex = 2
  /// Pencil-style square brush diameter applied to pen and eraser
  /// strokes. Clamped to 1...8 to keep stamps tractable on the small
  /// canvas sizes the editor supports.
  public var brushSize: Int = 1 {
    didSet {
      brushSize = brushSize.clamped(to: 1...8)
    }
  }
  /// When true (default), the bucket fill is clipped to the active
  /// marquee selection. Toggle off via the options bar when you want
  /// a fill to ignore the selection and flood the entire matching
  /// region.
  public var fillRespectsSelection: Bool = true
  /// Mirror of `fillRespectsSelection` for the gradient tool. Toggle
  /// off via the options bar when you want the gradient to span the
  /// whole canvas regardless of the active marquee.
  public var gradientRespectsSelection: Bool = true
  public var cursor: GIFEditorCore.PixelPoint = .zero {
    didSet {
      cursor.x = cursor.x.clamped(to: 0...max(0, document.size.width - 1))
      cursor.y = cursor.y.clamped(to: 0...max(0, document.size.height - 1))
    }
  }
  public var selection: Selection? = nil
  public var clipboard: PixelBuffer? = nil
  public private(set) var isPlaybackActive: Bool = false

  // MARK: - Pending interactions

  /// Marquee tool's first corner, captured on `Space` or `Enter` and
  /// committed into a `selection` by pressing either key again.
  public var pendingMarqueeAnchor: GIFEditorCore.PixelPoint? = nil
  /// Gradient tool's first endpoint.
  public var pendingGradientAnchor: GIFEditorCore.PixelPoint? = nil

  /// Pointer-drag state machine for the canvas. Holds the transient
  /// select-move snapshot; all of its mutation routes back through this
  /// view model via `CanvasDragContext`.
  private var dragController = CanvasDragController()

  // MARK: - Status / feedback

  public var statusMessage: String = ""

  public init(document: GIFDocument) {
    self.document = document
  }

  // MARK: - History

  public func undo() {
    guard let result = history.undo(current: snapshotState()) else {
      announce("Nothing to undo")
      return
    }

    restore(result.snapshot)
    announce("Undid \(result.label)")
  }

  public func redo() {
    guard let result = history.redo(current: snapshotState()) else {
      announce("Nothing to redo")
      return
    }

    restore(result.snapshot)
    announce("Redid \(result.label)")
  }

  // MARK: - Frame & layer accessors

  public var currentFrame: EditorFrame {
    document.frames[currentFrameIndex]
  }

  public var currentLayer: EditorLayer {
    currentFrame.layers[currentLayerIndex]
  }

  // MARK: - Tool dispatch

  /// Applies the active tool at the cursor. Pen-style tools paint
  /// directly; multi-stage tools (marquee, gradient) advance through
  /// their internal state machines.
  public func applyToolAtCursor() {
    switch tool {
    case .pen:
      recordUndoableEdit("Paint pixel") {
        strokeCurrentLayer(from: cursor, to: cursor, color: primaryColorIndex)
      }
      announce("Painted at \(cursor.x),\(cursor.y)")
    case .eraser:
      recordUndoableEdit("Erase pixel") {
        strokeCurrentLayer(from: cursor, to: cursor, color: nil)
      }
      announce("Erased \(cursor.x),\(cursor.y)")
    case .fill:
      recordUndoableEdit("Fill region") {
        mutateCurrentLayer { buffer in
          ToolOps.fill(
            on: buffer,
            at: cursor,
            color: primaryColorIndex,
            selection: fillRespectsSelection ? selection : nil
          )
        }
      }
      announce("Filled region")
    case .gradient:
      if let anchor = pendingGradientAnchor {
        recordUndoableEdit("Apply gradient") {
          mutateCurrentLayer { buffer in
            ToolOps.gradient(
              on: buffer,
              from: anchor,
              to: cursor,
              startColor: document.palette[primaryColorIndex],
              endColor: document.palette[secondaryColorIndex],
              palette: document.palette,
              selection: gradientRespectsSelection ? selection : nil
            )
          }
        }
        pendingGradientAnchor = nil
        announce("Gradient committed")
      } else {
        pendingGradientAnchor = cursor
        announce("Gradient: anchor at \(cursor.x),\(cursor.y), move and press Space again")
      }
    case .marquee:
      if let anchor = pendingMarqueeAnchor {
        selection = Selection(rect: PixelRect.bounding(anchor, cursor))
        pendingMarqueeAnchor = nil
        announce("Selection committed")
      } else {
        pendingMarqueeAnchor = cursor
        announce("Marquee: anchor at \(cursor.x),\(cursor.y), move and press Space again")
      }
    case .select:
      announce(
        selection == nil ? "Select: drag to move layer pixels" : "Select: drag to move selection")
    case .eyedropper:
      // Walk top-to-bottom and pick the first opaque pixel on any
      // visible layer at the cursor.
      for layer in currentFrame.layers.reversed() where layer.isVisible {
        if let idx = layer.pixels[cursor], let actualIdx = idx as PaletteIndex? {
          primaryColorIndex = actualIdx
          announce("Picked color slot \(Int(actualIdx))")
          return
        }
      }
      announce("Nothing to pick at \(cursor.x),\(cursor.y)")
    }
  }

  public func selectTool(_ newTool: EditorTool) {
    tool = newTool
    pendingMarqueeAnchor = nil
    pendingGradientAnchor = nil
    dragController.reset()
    announce("Tool: \(newTool.label)")
  }

  public func clearSelection() {
    selection = nil
    pendingMarqueeAnchor = nil
    dragController.reset()
    announce("Selection cleared")
  }

  public func swapPrimaryAndSecondary() {
    let tmp = primaryColorIndex
    primaryColorIndex = secondaryColorIndex
    secondaryColorIndex = tmp
  }

  public func setPrimaryColor(_ index: PaletteIndex) {
    primaryColorIndex = index
    announce("Primary: slot \(Int(index))")
  }

  public func setSecondaryColor(_ index: PaletteIndex) {
    secondaryColorIndex = index
    announce("Secondary: slot \(Int(index))")
  }

  // MARK: - Brush

  public func increaseBrushSize() {
    let previous = brushSize
    brushSize = min(8, previous + 1)
    if brushSize == previous {
      announce("Brush at maximum (\(brushSize))")
    } else {
      announce("Brush size: \(brushSize)")
    }
  }

  public func decreaseBrushSize() {
    let previous = brushSize
    brushSize = max(1, previous - 1)
    if brushSize == previous {
      announce("Brush at minimum (\(brushSize))")
    } else {
      announce("Brush size: \(brushSize)")
    }
  }

  // MARK: - Cursor

  public func moveCursor(dx: Int, dy: Int) {
    cursor = GIFEditorCore.PixelPoint(x: cursor.x + dx, y: cursor.y + dy)
  }

  // MARK: - Canvas drag

  public func beginCanvasDrag(at point: GIFEditorCore.PixelPoint) {
    dragController.begin(at: point, context: self)
  }

  public func updateCanvasDrag(
    startingAt anchor: GIFEditorCore.PixelPoint,
    from previous: GIFEditorCore.PixelPoint?,
    to point: GIFEditorCore.PixelPoint
  ) {
    dragController.update(startingAt: anchor, from: previous, to: point, context: self)
  }

  public func endCanvasDrag(
    startingAt anchor: GIFEditorCore.PixelPoint,
    from previous: GIFEditorCore.PixelPoint?,
    to point: GIFEditorCore.PixelPoint
  ) {
    dragController.end(startingAt: anchor, from: previous, to: point, context: self)
  }

  // MARK: - Frames

  public func nextFrame() {
    if document.frames.count > 1 {
      currentFrameIndex = (currentFrameIndex + 1) % document.frames.count
      announce("Frame \(currentFrameIndex + 1)/\(document.frames.count)")
    }
  }

  public func previousFrame() {
    if document.frames.count > 1 {
      currentFrameIndex =
        (currentFrameIndex - 1 + document.frames.count) % document.frames.count
      announce("Frame \(currentFrameIndex + 1)/\(document.frames.count)")
    }
  }

  /// Jumps to the first frame. Used by the timeline's `◀◀` button.
  public func goToFirstFrame() {
    guard document.frames.count > 1 else { return }
    currentFrameIndex = 0
    announce("Frame 1/\(document.frames.count)")
  }

  /// Jumps to the last frame. Used by the timeline's `▶▶` button.
  public func goToLastFrame() {
    guard document.frames.count > 1 else { return }
    currentFrameIndex = document.frames.count - 1
    announce("Frame \(currentFrameIndex + 1)/\(document.frames.count)")
  }

  /// Selects the frame at `index`, clamping to valid range. Used when
  /// the user clicks a specific timeline thumbnail.
  public func selectFrame(at index: Int) {
    guard document.frames.indices.contains(index) else { return }
    currentFrameIndex = index
    announce("Frame \(index + 1)/\(document.frames.count)")
  }

  public func insertBlankFrameAfterCurrent() {
    recordUndoableEdit("Insert blank frame") {
      let layer = EditorLayer(name: "Layer 1", pixels: PixelBuffer(size: document.size))
      let frame = EditorFrame(
        layers: [layer],
        delayCentiseconds: currentFrame.delayCentiseconds
      )
      document.frames.insert(frame, at: currentFrameIndex + 1)
      currentFrameIndex += 1
    }
    announce("Inserted blank frame")
  }

  public func duplicateCurrentFrame() {
    recordUndoableEdit("Duplicate frame") {
      let copy = currentFrame
      let dup = EditorFrame(
        layers: copy.layers.map {
          EditorLayer(name: $0.name, isVisible: $0.isVisible, pixels: $0.pixels)
        },
        delayCentiseconds: copy.delayCentiseconds,
        disposal: copy.disposal
      )
      document.frames.insert(dup, at: currentFrameIndex + 1)
      currentFrameIndex += 1
    }
    announce("Duplicated frame")
  }

  public func deleteCurrentFrame() {
    guard document.frames.count > 1 else {
      announce("Can't delete the last frame")
      return
    }
    recordUndoableEdit("Delete frame") {
      document.frames.remove(at: currentFrameIndex)
      // Always assign so currentFrameIndex.didSet runs and re-clamps
      // currentLayerIndex against the new current frame, even when the
      // numeric value of currentFrameIndex doesn't shift.
      currentFrameIndex = min(currentFrameIndex, document.frames.count - 1)
    }
    announce("Deleted frame")
  }

  public func adjustCurrentFrameDelay(by delta: Int) {
    var updatedDelay = currentFrame.delayCentiseconds
    recordUndoableEdit("Adjust frame delay") {
      var frame = currentFrame
      frame.delayCentiseconds = max(1, frame.delayCentiseconds + delta)
      updatedDelay = frame.delayCentiseconds
      document.frames[currentFrameIndex] = frame
    }
    announce("Frame delay: \(updatedDelay)cs")
  }

  public func setAllFrameDelaysToCurrent() {
    let target = currentFrame.delayCentiseconds
    recordUndoableEdit("Equalize frame delays") {
      for i in document.frames.indices {
        document.frames[i].delayCentiseconds = target
      }
    }
    announce("All frame delays = \(target)cs")
  }

  // MARK: - Playback

  public var currentPlaybackDelay: Duration {
    .milliseconds(max(1, currentFrame.delayCentiseconds) * 10)
  }

  public func togglePlayback() {
    if isPlaybackActive {
      stopPlayback()
    } else {
      startPlayback()
    }
  }

  public func startPlayback() {
    guard document.frames.count > 1 else {
      isPlaybackActive = false
      announce("Playback needs at least two frames")
      return
    }
    isPlaybackActive = true
    announce("Playback started")
  }

  public func stopPlayback() {
    guard isPlaybackActive else { return }
    isPlaybackActive = false
    announce("Playback paused")
  }

  @discardableResult
  public func advancePlaybackFrame() -> Bool {
    guard isPlaybackActive else { return false }
    guard document.frames.count > 1 else {
      isPlaybackActive = false
      announce("Playback stopped")
      return false
    }
    currentFrameIndex = (currentFrameIndex + 1) % document.frames.count
    announce("Playing frame \(currentFrameIndex + 1)/\(document.frames.count)")
    return true
  }

  // MARK: - Layers

  public func addLayer() {
    recordUndoableEdit("Add layer") {
      let layer = EditorLayer(
        name: "Layer \(currentFrame.layers.count + 1)",
        pixels: PixelBuffer(size: document.size)
      )
      document.frames[currentFrameIndex].layers.append(layer)
      currentLayerIndex = document.frames[currentFrameIndex].layers.count - 1
    }
    announce("New layer")
  }

  public func selectLayerBelow() {
    if currentLayerIndex > 0 {
      currentLayerIndex -= 1
      announce("Layer \(currentLayerIndex + 1)/\(currentFrame.layers.count)")
    }
  }

  public func selectLayerAbove() {
    if currentLayerIndex < currentFrame.layers.count - 1 {
      currentLayerIndex += 1
      announce("Layer \(currentLayerIndex + 1)/\(currentFrame.layers.count)")
    }
  }

  public func toggleCurrentLayerVisibility() {
    toggleLayerVisibility(at: currentLayerIndex)
  }

  public func deleteCurrentLayer() {
    deleteLayer(at: currentLayerIndex)
  }

  /// Selects the layer at `index`, clamping to valid range. Used by
  /// the layers panel row body click target.
  public func selectLayer(at index: Int) {
    guard currentFrame.layers.indices.contains(index) else { return }
    currentLayerIndex = index
    announce("Layer \(index + 1)/\(currentFrame.layers.count)")
  }

  /// Toggles the visibility of the layer at `index` independent of
  /// the current selection. Used by the per-row visibility button.
  public func toggleLayerVisibility(at index: Int) {
    guard currentFrame.layers.indices.contains(index) else { return }
    var isVisible = currentFrame.layers[index].isVisible
    recordUndoableEdit("Toggle layer visibility") {
      var layer = currentFrame.layers[index]
      layer.isVisible.toggle()
      isVisible = layer.isVisible
      document.frames[currentFrameIndex].layers[index] = layer
    }
    announce(isVisible ? "Layer shown" : "Layer hidden")
  }

  /// Deletes the layer at `index`. Refuses to delete the last layer
  /// in the frame (the editor invariant requires at least one).
  public func deleteLayer(at index: Int) {
    guard currentFrame.layers.indices.contains(index) else { return }
    guard currentFrame.layers.count > 1 else {
      announce("Can't delete the last layer in a frame")
      return
    }
    recordUndoableEdit("Delete layer") {
      document.frames[currentFrameIndex].layers.remove(at: index)
      if currentLayerIndex >= currentFrame.layers.count {
        currentLayerIndex = currentFrame.layers.count - 1
      } else if currentLayerIndex > index {
        currentLayerIndex -= 1
      }
    }
    announce("Deleted layer")
  }

  // MARK: - Clipboard

  public func copySelection() {
    let buffer = currentLayer.pixels
    if let selection {
      clipboard = ToolOps.copy(from: buffer, rect: selection.rect)
    } else {
      clipboard = buffer
    }
    announce(clipboard != nil ? "Copied" : "Nothing to copy")
  }

  public func paste() {
    guard let clipboard else {
      announce("Clipboard empty")
      return
    }
    recordUndoableEdit("Paste") {
      mutateCurrentLayer { buffer in
        ToolOps.paste(onto: buffer, clipboard: clipboard, at: cursor)
      }
    }
    announce("Pasted at \(cursor.x),\(cursor.y)")
  }

  // MARK: - Canvas resize

  /// Square-canvas presets cycled through by `cycleCanvasSize()`.
  public static let canvasSizeProgression: [Int] = [16, 24, 32, 48, 64]

  /// Advances the canvas through the standard size progression (each
  /// dimension `16 → 24 → 32 → 48 → 64 → 16 → …`). Used by both the
  /// `Ctrl+R` keybinding and the File → Resize Canvas menu item so
  /// they remain bit-identical.
  public func cycleCanvasSize() {
    let current = document.size.width
    let next =
      Self.canvasSizeProgression.first { $0 > current }
      ?? Self.canvasSizeProgression[0]
    resizeCanvas(to: GIFEditorCore.PixelSize(width: next, height: next))
  }

  public func resizeCanvas(to size: GIFEditorCore.PixelSize) {
    recordUndoableEdit("Resize canvas") {
      document.size = size
      for frameIndex in document.frames.indices {
        for layerIndex in document.frames[frameIndex].layers.indices {
          var layer = document.frames[frameIndex].layers[layerIndex]
          layer.pixels = layer.pixels.resized(to: size)
          document.frames[frameIndex].layers[layerIndex] = layer
        }
      }
      cursor = GIFEditorCore.PixelPoint(
        x: min(cursor.x, size.width - 1),
        y: min(cursor.y, size.height - 1)
      )
      selection = nil
    }
    announce("Canvas resized to \(size.width)×\(size.height)")
  }

  // MARK: - Save / load

  public var defaultSaveURL: URL {
    GIFDocumentIO.defaultSaveURL(for: document)
  }

  public static func saveURL(from pathText: String) -> URL? {
    GIFDocumentIO.saveURL(from: pathText)
  }

  @discardableResult
  public func save(to target: URL, overwriteExisting: Bool) -> Bool {
    switch GIFDocumentIO.save(
      document: document, to: target, overwriteExisting: overwriteExisting)
    {
    case .needsOverwriteConfirmation:
      announce("Confirm overwrite before saving")
      return false
    case .saved:
      document.path = target
      history.markClean()
      announce("Saved to \(target.path)")
      return true
    case .failed(let error):
      announce("Save failed: \(error)")
      return false
    }
  }

  // MARK: - Edit / history helpers

  private func recordUndoableEdit(_ label: String, _ edit: () -> Void) {
    if history.hasActiveGroup {
      edit()
      return
    }

    let before = snapshotState()
    edit()
    history.recordSingleEdit(from: before, label: label, current: document)
  }

  private func snapshotState() -> EditorSnapshot {
    EditorSnapshot(
      document: document,
      currentFrameIndex: currentFrameIndex,
      currentLayerIndex: currentLayerIndex,
      cursor: cursor,
      selection: selection,
      historyGeneration: history.currentHistoryGeneration
    )
  }

  private func restore(_ snapshot: EditorSnapshot) {
    document = snapshot.document
    currentFrameIndex = snapshot.currentFrameIndex
    currentLayerIndex = snapshot.currentLayerIndex
    cursor = snapshot.cursor
    selection = snapshot.selection
    pendingMarqueeAnchor = nil
    pendingGradientAnchor = nil
    dragController.reset()
    history.adoptRestored(generation: snapshot.historyGeneration)
  }

  /// Replaces the current layer's pixel buffer with the result of
  /// `transform`. Callers own history grouping.
  private func mutateCurrentLayer(_ transform: (PixelBuffer) -> PixelBuffer) {
    var layer = currentLayer
    layer.pixels = transform(layer.pixels)
    document.frames[currentFrameIndex].layers[currentLayerIndex] = layer
  }

  /// Sets the one-line status feedback shown in the footer. Internal
  /// (not `private`) so it also serves as the `CanvasDragContext`
  /// witness the drag controller announces through.
  func announce(_ message: String) {
    statusMessage = message
  }
}

// MARK: - CanvasDragContext

extension EditorViewModel: CanvasDragContext {
  var canvasSize: GIFEditorCore.PixelSize {
    document.size
  }

  var currentLayerPixels: PixelBuffer {
    currentLayer.pixels
  }

  func strokeCurrentLayer(
    from start: GIFEditorCore.PixelPoint,
    to end: GIFEditorCore.PixelPoint,
    color: PaletteIndex?
  ) {
    mutateCurrentLayer { buffer in
      ToolOps.line(
        on: buffer,
        from: start,
        to: end,
        color: color,
        thickness: brushSize
      )
    }
  }

  func replaceCurrentLayerPixels(with pixels: PixelBuffer) {
    mutateCurrentLayer { _ in pixels }
  }

  func beginUndoGroup(_ label: String) {
    history.beginGroup(label, before: snapshotState())
  }

  func finishUndoGroup() {
    history.finishGroup(current: document)
  }
}

// Local clamp helper since `Comparable.clamped(to:)` isn't in stdlib.
// `fileprivate` (not `private`) because the helper is shared between this
// file's class body and extension — `private` on a top-level extension
// scopes to that extension alone, not the file.
extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

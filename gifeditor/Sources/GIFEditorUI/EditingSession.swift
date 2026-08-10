import Foundation
import GIFEditorCore
import SwiftTUI

/// Stable identity of one committed authoring state.
public struct EditingGeneration: Hashable, Sendable {
  fileprivate let value: Int
}

/// Immutable bytes-source for a project save.
///
/// The generation travels beside the document so the completion can
/// acknowledge exactly what was written even if editing continued meanwhile.
public struct EditingSaveSnapshot: Hashable, Sendable {
  public let document: GIFDocument
  public let generation: EditingGeneration
  fileprivate let sessionIdentity: UUID
  fileprivate let sequence: UInt64
}

/// Whether a completed save still describes the session's current state.
public enum EditingSaveAcknowledgement: Hashable, Sendable {
  case current
  case superseded
  case rejected
}

/// Reference-type owner of the editor's mutable state. The view tree
/// reads `document` as a value type via @State, but mutating ops live
/// here so individual views don't need to thread the document around.
///
/// Kept @MainActor — the editor is single-window, single-threaded, and
/// every mutation is driven from a UI event.
///
/// It owns only one document's editing state and history. Document
/// replacement, persistence, recovery, recents, and quit policy belong
/// to `DocumentLifecycle`.
@MainActor
public final class EditingSession {
  // MARK: - Document

  /// Backing store for `document`. Written by `init` and by
  /// `mutateDocument(invalidating:_:)` and by nothing else — `document`
  /// itself is get-only, so the compiler rejects any edit that skips the
  /// write path and its composite-cache invalidation.
  private var storedDocument: GIFDocument

  public var document: GIFDocument {
    storedDocument
  }

  // MARK: - Composite cache

  /// Identity of one memoized composite: which frame, at which revision of
  /// that frame's content, against which revision of the document-wide
  /// inputs, at which canvas size. Every field is a scalar, so building a
  /// key costs a handful of words no matter how many pixels the frame holds.
  private struct CompositeCacheKey: Hashable {
    let frameID: UUID
    let frameRevision: UInt64
    let paletteRevision: UInt64
    let size: GIFEditorCore.PixelSize
  }

  /// Memoized per-frame composited colors.
  ///
  /// The key used to *be* the content — frame, palette and size by value.
  /// That was correct by construction, but `EditorFrame`, `EditorLayer` and
  /// `PixelBuffer` all hash element-by-element, so every key cost one hash
  /// of every pixel of every layer. `compositedFrames()` runs once per
  /// `EditorView` body evaluation and keys every frame, so the price scaled
  /// with `frames × layers × area` **per render**: invisible at a 32×32
  /// ceiling, a cliff at 256×256.
  ///
  /// The key is a mutation stamp instead, and the invariant that replaces
  /// "the key is the content" is:
  ///
  /// > every write into the document either stamps the frame whose drawn
  /// > content changed, or bumps `paletteRevision`.
  ///
  /// That burden is structural rather than remembered:
  /// `mutateDocument(invalidating:_:)` is the only path that can write the
  /// document and it makes callers name their invalidation. Its cost is
  /// that a *no-op* edit (painting the colour already under the cursor)
  /// now recomposites one frame where the content key would have hit —
  /// one frame of waste on an edit that was already doing pointless work.
  /// `compositeOracleEnabled` buys the old correct-by-construction
  /// guarantee back for tests.
  ///
  /// Because keys carry frame *identity*, a frame insert, delete or move
  /// leaves every surviving frame's composite valid: their ids are stable
  /// and their content is untouched.
  ///
  /// Rebuilt to the live frame set on each `compositedFrames()` call, so it
  /// stays bounded to the frame count and stale intermediate-stroke entries
  /// are evicted.
  private var compositeCache: [CompositeCacheKey: [EditorColor?]] = [:]

  /// Per-frame content stamps, keyed by `EditorFrame.id`.
  ///
  /// Deliberately here and not a field on `EditorFrame`: a stamp on the
  /// document type would join the synthesized `==`/`hash`, and
  /// `EditorHistory` decides "did this edit change anything?" from exactly
  /// that comparison — a bump on a no-op edit would start recording empty
  /// undo entries. It would also join `Codable` and put a meaningless
  /// field in the project-file format. The revision is a cache concern,
  /// not document state.
  ///
  /// A frame with no entry has not been written since the document
  /// arrived and reads as revision 0; `nextRevision()` never returns 0, so
  /// an unstamped frame can never alias a stamped one.
  private var frameRevisions: [UUID: UInt64] = [:]

  /// Stamp for the composite inputs that are not per-frame content: the
  /// palette, and any wholesale replacement of the document (undo/redo,
  /// canvas resize). It is part of every key, so one bump invalidates every
  /// frame at once — which is what those edits need, and, deliberately, is
  /// not what an ordinary paint does. A stroke still recomposites exactly
  /// the frame it painted.
  private var paletteRevision: UInt64 = 0

  /// Monotonic source for both stamps, shared so a stamp value is unique
  /// across the view model rather than only within one frame's history.
  private var revisionCounter: UInt64 = 0

  /// Number of frames actually recomposited since this view model was
  /// created. Test-facing: it turns "that edit recomposited exactly one
  /// frame" into an assertion instead of a guess.
  private(set) var compositeRecomputeCount: Int = 0

  /// When true, every cache *hit* is re-derived from
  /// `document.flattenedColors(for:)` and compared, trapping on mismatch —
  /// a soundness oracle for the stamp invariant above.
  ///
  /// Off by default and deliberately not `#if DEBUG`: tests and interactive
  /// dev runs are both debug builds, and recomputing on every hit would
  /// defeat the cache exactly where the editor is used by hand. Tests that
  /// want the guarantee flip it on.
  var compositeOracleEnabled: Bool = false

  // MARK: - History

  private var history = EditorHistory()
  /// Save receipts are valid only within this document session and in
  /// monotonically increasing request order.
  private var persistenceIdentity = UUID()
  private var nextSaveSequence: UInt64 = 0
  private var latestAcknowledgedSaveSequence: UInt64 = 0

  public var canUndo: Bool {
    history.canUndo
  }

  public var canRedo: Bool {
    history.canRedo
  }

  public var isDirty: Bool {
    history.isDirty
  }

  public var generation: EditingGeneration {
    EditingGeneration(value: history.currentHistoryGeneration)
  }

  public func makeSaveSnapshot() -> EditingSaveSnapshot {
    nextSaveSequence &+= 1
    return EditingSaveSnapshot(
      document: document,
      generation: generation,
      sessionIdentity: persistenceIdentity,
      sequence: nextSaveSequence
    )
  }

  /// Applies a durable-save receipt without guessing which state was saved.
  @discardableResult
  public func acknowledgeSave(
    _ snapshot: EditingSaveSnapshot
  ) -> EditingSaveAcknowledgement {
    guard snapshot.sessionIdentity == persistenceIdentity,
      snapshot.sequence >= latestAcknowledgedSaveSequence
    else {
      return .rejected
    }
    latestAcknowledgedSaveSequence = snapshot.sequence
    history.markClean(generation: snapshot.generation.value)
    return snapshot.generation == generation ? .current : .superseded
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

  public var tool: ActiveTool = .pen
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
  /// When true the shape tools lay a solid block instead of a
  /// brush-width outline. The brush size is the outline's thickness, so
  /// it stops having any effect while this is on — a filled shape has no
  /// stroke to widen.
  public var shapeFillsInterior: Bool = false
  /// When true, every pen and eraser stroke is laid twice: once as drawn
  /// and once reflected across the canvas's vertical centre line.
  ///
  /// A modifier on drawing rather than a tool of its own, which is what
  /// makes it compose: the brush size, the eraser, the keyboard's
  /// press-to-paint and the pointer's drag all reach the same
  /// ``strokeCurrentLayer(from:to:color:)``, so one flag mirrors all four.
  ///
  /// The axis is the *canvas*, not the selection. A selection clips what
  /// is painted; the axis decides where the reflection lands, and tying
  /// the two together would move the mirror line every time the marquee
  /// moved — so a symmetric drawing would stop being symmetric the moment
  /// the author selected something.
  public var strokesMirrorX: Bool = false
  public var cursor: GIFEditorCore.PixelPoint = .zero {
    didSet {
      cursor.x = cursor.x.clamped(to: 0...max(0, document.size.width - 1))
      cursor.y = cursor.y.clamped(to: 0...max(0, document.size.height - 1))
    }
  }
  /// Whether the canvas draws the cursor mark over the artwork.
  ///
  /// The mark answers "where will the next keyboard edit land?", which only
  /// matters while the keyboard is doing the moving — so ``moveCursor(dx:dy:)``
  /// shows it and the pointer's canvas-drag entry points hide it. A pointer
  /// gesture needs no mark: the pointer itself is at the target, and a click
  /// should paint without leaving a marker behind. Hidden at start because
  /// no keyboard move has happened yet.
  public private(set) var isCursorMarkVisible: Bool = false
  public var selection: Selection? = nil
  public var clipboard: PixelBuffer? = nil
  public private(set) var isPlaybackActive: Bool = false

  // MARK: - Pending interactions

  /// Marquee tool's first corner, captured on `Space` or `Enter` and
  /// committed into a `selection` by pressing either key again.
  public var pendingMarqueeAnchor: GIFEditorCore.PixelPoint? = nil
  /// Gradient tool's first endpoint.
  public var pendingGradientAnchor: GIFEditorCore.PixelPoint? = nil
  /// The shape tools' first corner, captured exactly as the gradient's
  /// endpoint is and committed by the second press or the drag's release.
  public var pendingShapeAnchor: GIFEditorCore.PixelPoint? = nil

  /// Pointer-drag state machine for the canvas. Holds the transient
  /// select-move snapshot; all of its mutation routes back through this
  /// view model via `CanvasDragContext`.
  private var dragController = CanvasDragController()

  // MARK: - Status / feedback

  public var statusMessage: String = ""

  public init(
    document: GIFDocument,
    initialStatusMessage: String = "",
    startsDirty: Bool = false
  ) {
    // Nothing to stamp: the composite cache starts empty, so the first
    // `compositedFrames()` call misses on every frame and computes it.
    // Documents arrive here from `GIFLoader`, the project decoder,
    // `GIFDocument.blank`, or a recovered autosave.
    storedDocument = document
    statusMessage = initialStatusMessage
    // A recovered document differs from whatever is on disk before the
    // author touches anything, so it arrives dirty.
    if startsDirty {
      history.markDirty()
    }
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

  /// Composited colors for every frame, in frame order, memoized on the
  /// per-frame mutation stamps.
  ///
  /// The editor re-evaluates its whole body on every refresh — cursor moves,
  /// tool/selection changes, and, during a stroke, once per rendered
  /// frame — and the timeline needs a thumbnail for every frame. Recompositing
  /// all frames each time is `O(frames × layers × area)`; here only the frames
  /// whose content changed since the last call recompute, so a stroke pays to
  /// composite one frame and reads the rest from cache. Building the keys is
  /// `O(frames)` in scalars, independent of canvas area.
  ///
  /// Index `i` of the result corresponds to `document.frames[i]`.
  func compositedFrames() -> [[EditorColor?]] {
    let document = self.document
    let size = document.size
    let paletteRevision = self.paletteRevision
    var rebuilt: [CompositeCacheKey: [EditorColor?]] = [:]
    rebuilt.reserveCapacity(document.frames.count)
    let result = document.frames.map { frame -> [EditorColor?] in
      let key = CompositeCacheKey(
        frameID: frame.id,
        frameRevision: frameRevisions[frame.id] ?? 0,
        paletteRevision: paletteRevision,
        size: size
      )
      if let cached = rebuilt[key] ?? compositeCache[key] {
        rebuilt[key] = cached
        assertCompositeIsCurrent(cached, for: frame, in: document)
        return cached
      }
      let colors = document.flattenedColors(for: frame)
      compositeRecomputeCount += 1
      rebuilt[key] = colors
      return colors
    }
    compositeCache = rebuilt
    return result
  }

  /// Soundness oracle for the stamp invariant: on a cache hit, re-derive
  /// the composite and trap if it disagrees, so a write site that declared
  /// the wrong invalidation fails loudly instead of silently rendering a
  /// stale frame. No-op unless `compositeOracleEnabled` is set.
  private func assertCompositeIsCurrent(
    _ cached: [EditorColor?],
    for frame: EditorFrame,
    in document: GIFDocument
  ) {
    guard compositeOracleEnabled else { return }
    precondition(
      cached == document.flattenedColors(for: frame),
      "Composite cache returned a stale frame — a document write declared the wrong invalidation"
    )
  }

  // MARK: - Tool dispatch

  /// Applies the active tool at the cursor. Pen-style tools paint
  /// directly; multi-stage tools (marquee, gradient) advance through
  /// their internal state machines.
  public func applyToolAtCursor() {
    switch tool {
    case .core(.pen):
      recordUndoableEdit("Paint pixel") {
        strokeCurrentLayer(from: cursor, to: cursor, color: primaryColorIndex)
      }
      announce("Painted at \(cursor.x),\(cursor.y)")
    case .core(.eraser):
      recordUndoableEdit("Erase pixel") {
        strokeCurrentLayer(from: cursor, to: cursor, color: nil)
      }
      announce("Erased \(cursor.x),\(cursor.y)")
    case .core(.fill):
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
    case .core(.gradient):
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
    case .shape(let shape):
      // Anchor-then-commit, the same two-press shape the gradient has.
      // The selection clips the shape when there is one, matching the
      // fill and the gradient — a marquee is the editor's way of saying
      // "only in here".
      if let anchor = pendingShapeAnchor {
        recordUndoableEdit("Draw \(shape.label.lowercased())") {
          mutateCurrentLayer { buffer in
            shape.applied(
              to: buffer,
              from: anchor,
              to: cursor,
              color: primaryColorIndex,
              filled: shapeFillsInterior,
              thickness: brushSize,
              selection: selection
            )
          }
        }
        pendingShapeAnchor = nil
        announce("\(shape.label) committed")
      } else {
        pendingShapeAnchor = cursor
        announce(
          "\(shape.label): anchor at \(cursor.x),\(cursor.y), move and press Space again")
      }
    case .core(.marquee):
      if let anchor = pendingMarqueeAnchor {
        selection = Selection(rect: PixelRect.bounding(anchor, cursor))
        pendingMarqueeAnchor = nil
        announce("Selection committed")
      } else {
        pendingMarqueeAnchor = cursor
        announce("Marquee: anchor at \(cursor.x),\(cursor.y), move and press Space again")
      }
    case .core(.select):
      announce(
        selection == nil ? "Select: drag to move layer pixels" : "Select: drag to move selection")
    case .core(.eyedropper):
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

  public func selectTool(_ newTool: ActiveTool) {
    tool = newTool
    pendingMarqueeAnchor = nil
    pendingGradientAnchor = nil
    pendingShapeAnchor = nil
    dragController.reset()
    announce("Tool: \(newTool.label)")
  }

  /// Flips the shape tools between a brush-width outline and a solid
  /// block. A tool option like ``brushSize``, not a tool of its own —
  /// both shapes read it, and neither needs its own filled twin in the
  /// dock.
  public func toggleShapeFill() {
    shapeFillsInterior.toggle()
    announce(shapeFillsInterior ? "Shapes: filled" : "Shapes: outline")
  }

  /// Turns mirror-X symmetry on and off for pen and eraser strokes.
  public func toggleStrokeMirrorX() {
    strokesMirrorX.toggle()
    announce(strokesMirrorX ? "Mirror-X on" : "Mirror-X off")
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
    isCursorMarkVisible = true
  }

  // MARK: - Canvas drag

  // All three drag entries hide the cursor mark rather than only `begin`:
  // tests and adapters may enter at any of them, and a pointer gesture is a
  // pointer gesture whichever phase reports first.

  public func beginCanvasDrag(at point: GIFEditorCore.PixelPoint) {
    isCursorMarkVisible = false
    dragController.begin(at: point, context: self)
  }

  public func updateCanvasDrag(
    startingAt anchor: GIFEditorCore.PixelPoint,
    from previous: GIFEditorCore.PixelPoint?,
    to point: GIFEditorCore.PixelPoint
  ) {
    isCursorMarkVisible = false
    dragController.update(startingAt: anchor, from: previous, to: point, context: self)
  }

  public func endCanvasDrag(
    startingAt anchor: GIFEditorCore.PixelPoint,
    from previous: GIFEditorCore.PixelPoint?,
    to point: GIFEditorCore.PixelPoint
  ) {
    isCursorMarkVisible = false
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
      let destination = currentFrameIndex + 1
      mutateDocument(invalidating: .frameList) { $0.frames.insert(frame, at: destination) }
      currentFrameIndex = destination
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
      let destination = currentFrameIndex + 1
      mutateDocument(invalidating: .frameList) { $0.frames.insert(dup, at: destination) }
      currentFrameIndex = destination
    }
    announce("Duplicated frame")
  }

  public func deleteCurrentFrame() {
    guard document.frames.count > 1 else {
      announce("Can't delete the last frame")
      return
    }
    recordUndoableEdit("Delete frame") {
      let doomed = currentFrameIndex
      mutateDocument(invalidating: .frameList) { $0.frames.remove(at: doomed) }
      // Always assign so currentFrameIndex.didSet runs and re-clamps
      // currentLayerIndex against the new current frame, even when the
      // numeric value of currentFrameIndex doesn't shift.
      currentFrameIndex = min(currentFrameIndex, document.frames.count - 1)
    }
    announce("Deleted frame")
  }

  /// Moves the current frame `delta` positions through the timeline and
  /// keeps the selection on it — negative moves it earlier, positive
  /// later. The destination is clamped into the frame range, so a move
  /// that would run off either end is announced and left alone instead
  /// of recording an undo step that changes nothing.
  public func moveCurrentFrame(by delta: Int) {
    let destination = (currentFrameIndex + delta)
      .clamped(to: 0...max(0, document.frames.count - 1))
    guard destination != currentFrameIndex else {
      announce(Self.alreadyInPlaceMessage(at: currentFrameIndex, of: document.frames.count))
      return
    }
    recordUndoableEdit("Move frame") {
      let source = currentFrameIndex
      // `.frameList`: the moved frame keeps its id and its pixels, and no
      // other frame is touched, so every composite survives the reorder.
      mutateDocument(invalidating: .frameList) { doc in
        let frame = doc.frames.remove(at: source)
        doc.frames.insert(frame, at: destination)
      }
      // Always assign so currentFrameIndex.didSet runs and re-clamps
      // currentLayerIndex against the frame now under the selection.
      currentFrameIndex = destination
    }
    announce("Moved frame to \(currentFrameIndex + 1)/\(document.frames.count)")
  }

  /// Why a move that goes nowhere went nowhere, read off where the frame
  /// *is* rather than off the sign of the requested step.
  ///
  /// The sign is only meaningful for a relative move: a drag that lands
  /// on a frame's own slot, and a send-to-either-end that was already
  /// there, both ask for a zero step, and describing those as "already
  /// last" — which reading the sign does — is wrong for the first and a
  /// coin toss for the second.
  static func alreadyInPlaceMessage(at index: Int, of count: Int) -> String {
    if index == 0 { return "Frame is already first" }
    if index == count - 1 { return "Frame is already last" }
    return "Frame is already in that slot"
  }

  /// Moves the frame at `source` to `destination`, selecting it on the way.
  ///
  /// Exists so the timeline's drag-to-reorder and the keyboard's move
  /// command are the *same* edit rather than two implementations that have
  /// to be kept in step: the clamping, the undo step and the "selection
  /// follows the frame" behaviour all come from
  /// ``moveCurrentFrame(by:)``. A drag that ends on the frame's own slot
  /// lands on that method's no-op branch and records nothing.
  public func moveFrame(from source: Int, to destination: Int) {
    guard document.frames.indices.contains(source) else { return }
    selectFrame(at: source)
    moveCurrentFrame(by: destination - source)
  }

  /// Sends the current frame to the front of the timeline.
  ///
  /// The keyboard's route to ``moveFrame(from:to:)``, which the drag
  /// reorder already uses: a jump to an absolute slot is what that method
  /// says and what ``moveCurrentFrame(by:)`` — a relative step — does not.
  /// A frame already at the front lands on the no-op branch and records
  /// nothing.
  public func moveCurrentFrameToStart() {
    moveFrame(from: currentFrameIndex, to: 0)
  }

  /// Sends the current frame to the end of the timeline.
  public func moveCurrentFrameToEnd() {
    moveFrame(from: currentFrameIndex, to: max(0, document.frames.count - 1))
  }

  public func adjustCurrentFrameDelay(by delta: Int) {
    writeCurrentFrameDelay(
      currentFrame.delayCentiseconds + delta,
      label: "Adjust frame delay"
    )
  }

  /// Sets the current frame's delay outright. What the timeline's
  /// scrubbable readout drives, where a stepper would make the author
  /// click thirty times to cross a second.
  public func setCurrentFrameDelay(_ delay: Int) {
    writeCurrentFrameDelay(delay, label: "Set frame delay")
  }

  /// The delay a frame is born with — `EditorFrame`'s own default, named
  /// here so the menu's `Reset Delay` and a freshly inserted frame agree
  /// on what "default" means.
  public static let defaultFrameDelayCentiseconds = 10

  /// Puts the current frame's delay back to the default. The absolute
  /// setter's menu route: after a long scrub, stepping back by tens is a
  /// worse way to reach a round number than saying it outright.
  public func resetCurrentFrameDelay() {
    setCurrentFrameDelay(Self.defaultFrameDelayCentiseconds)
  }

  /// The one write site for a frame delay, so the `max(1, …)` floor and
  /// the invalidation scope cannot drift between the stepper, the setter
  /// and the scrub.
  private func writeCurrentFrameDelay(_ delay: Int, label: String) {
    var updatedDelay = currentFrame.delayCentiseconds
    recordUndoableEdit(label) {
      var frame = currentFrame
      frame.delayCentiseconds = max(1, delay)
      updatedDelay = frame.delayCentiseconds
      let index = currentFrameIndex
      // `.nothing`: `flattenedColors(for:)` reads layers and the palette.
      // Delay is playback timing and never reaches a composited color.
      mutateDocument(invalidating: .nothing) { $0.frames[index] = frame }
    }
    announce("Frame delay: \(updatedDelay)cs")
  }

  // MARK: - Delay scrubbing

  /// The delay the in-flight scrub is measured from, and the flag that
  /// says a scrub is open at all.
  ///
  /// A scrub has to be *absolute* rather than incremental: the pointer
  /// reports where it is, not how far it moved since the last sample the
  /// editor happened to process, so accumulating deltas would drift away
  /// from the cursor over a long drag.
  private var delayScrubBaseline: Int?

  public var isScrubbingDelay: Bool {
    delayScrubBaseline != nil
  }

  /// Opens a delay scrub on the current frame.
  ///
  /// The whole drag is one undo group. Without it a scrub across twenty
  /// cells would push twenty undo steps and the author would have to press
  /// undo twenty times to get back to a delay they set once.
  public func beginDelayScrub() {
    guard delayScrubBaseline == nil else { return }
    delayScrubBaseline = currentFrame.delayCentiseconds
    beginUndoGroup("Scrub frame delay")
  }

  /// Sets the delay to the scrub's baseline plus `delta` centiseconds.
  /// No-op unless ``beginDelayScrub()`` opened a scrub.
  public func updateDelayScrub(by delta: Int) {
    guard let baseline = delayScrubBaseline else { return }
    writeCurrentFrameDelay(baseline + delta, label: "Scrub frame delay")
  }

  /// Closes the scrub, committing the whole drag as a single undo step.
  public func endDelayScrub() {
    guard delayScrubBaseline != nil else { return }
    delayScrubBaseline = nil
    finishUndoGroup()
  }

  // MARK: - Frame disposal

  /// Sets how the current frame's region is reset before the next frame
  /// paints.
  ///
  /// See ``exportUsesDeltaFrames`` for why this is not a free choice.
  public func setCurrentFrameDisposal(_ disposal: EditorFrame.FrameDisposal) {
    guard currentFrame.disposal != disposal else {
      announce("Frame disposal is already \(Self.disposalLabel(disposal))")
      return
    }
    recordUndoableEdit("Set frame disposal") {
      let index = currentFrameIndex
      // `.nothing`, for the same reason as the delay: disposal is a
      // statement about how a *decoder* composites frames on playback.
      // `flattenedColors(for:)` composites the editor's own layer stack
      // and never reads it.
      mutateDocument(invalidating: .nothing) { $0.frames[index].disposal = disposal }
    }
    announce(disposalStatus(for: disposal))
  }

  /// Advances the current frame through the four disposal modes. What the
  /// timeline's single disposal button drives.
  public func cycleCurrentFrameDisposal() {
    setCurrentFrameDisposal(Self.disposalCycle(after: currentFrame.disposal))
  }

  /// The order the cycle button walks: `.background` first, because it is
  /// the editor's default and the one coding that keeps delta compression.
  static let disposalOrder: [EditorFrame.FrameDisposal] = [
    .background, .keep, .previous, .unspecified,
  ]

  static func disposalCycle(after current: EditorFrame.FrameDisposal) -> EditorFrame.FrameDisposal {
    guard let position = disposalOrder.firstIndex(of: current) else { return .background }
    return disposalOrder[(position + 1) % disposalOrder.count]
  }

  static func disposalLabel(_ disposal: EditorFrame.FrameDisposal) -> String {
    switch disposal {
    case .unspecified: return "unspecified"
    case .keep: return "keep"
    case .background: return "background"
    case .previous: return "previous"
    }
  }

  /// The same four modes at timeline width. The strip cannot afford
  /// `background`, and the full word is one status line away — see
  /// `TimelineExportSettingsView` for why the column is width-bound.
  static func disposalCode(_ disposal: EditorFrame.FrameDisposal) -> String {
    switch disposal {
    case .unspecified: return "unsp"
    case .keep: return "keep"
    case .background: return "bg"
    case .previous: return "prev"
    }
  }

  /// Whether a GIF export of this document will be delta-coded.
  ///
  /// Asks the encoder rather than restating its rule: this used to be a
  /// hand-copied mirror of `GIFEncoder`'s own test, and two copies of a
  /// predicate that decides file size is two copies that can disagree.
  /// ``GIFEncoder/supportsDeltaCoding(_:)`` is the authority; this is the
  /// name the UI knows it by.
  ///
  /// The consequence is worth stating plainly because it is the surprise
  /// this property exists to prevent: setting one frame to `.keep` makes
  /// the *entire* export fall back to full-canvas frames, which is
  /// typically several times larger. That is a real trade an author may
  /// want to make, but not one they should discover from a file size.
  public var exportUsesDeltaFrames: Bool {
    GIFEncoder.supportsDeltaCoding(document)
  }

  /// Whether an authored disposal — rather than merely having one frame —
  /// is what costs this document its delta coding. Drives the timeline's
  /// warning, which would be noise on a one-frame document that never had
  /// anything to delta against.
  public var authoredDisposalDisablesDeltaCoding: Bool {
    document.frames.count > 1 && !exportUsesDeltaFrames
  }

  private func disposalStatus(for disposal: EditorFrame.FrameDisposal) -> String {
    let base = "Frame disposal: \(Self.disposalLabel(disposal))"
    guard authoredDisposalDisablesDeltaCoding else { return base }
    return base + " — export falls back to full frames (larger file)"
  }

  // MARK: - Loop count

  /// The largest loop count a GIF can declare. The `NETSCAPE2.0`
  /// application extension carries it as a little-endian `UInt16`, and the
  /// encoder writes it with `UInt16(clamping:)` — clamping here too means
  /// the number the author sees is the number the file will hold.
  public static let maximumLoopCount = Int(UInt16.max)

  /// Sets how many times an exported GIF plays. **Zero means forever**,
  /// which is the format's own encoding and the one piece of this API that
  /// cannot be guessed from the type.
  public func setLoopCount(_ count: Int) {
    let clamped = count.clamped(to: 0...Self.maximumLoopCount)
    guard clamped != document.loopCount else {
      announce("Playback is already set to \(Self.loopDescription(clamped))")
      return
    }
    recordUndoableEdit("Set loop count") {
      // `.nothing`: the loop count is written into the GIF's application
      // extension and read by players. No composited color depends on it.
      mutateDocument(invalidating: .nothing) { $0.loopCount = clamped }
    }
    announce("Plays \(Self.loopDescription(clamped))")
  }

  /// Steps the loop count. Stepping down from `1` lands on `0`, which is
  /// the format's spelling of "forever" — the UI says so rather than
  /// leaving the author to infer it from a zero.
  public func adjustLoopCount(by delta: Int) {
    setLoopCount(document.loopCount + delta)
  }

  /// Flips between looping forever and a finite count, remembering the
  /// finite one so the toggle is reversible.
  public func toggleLoopsForever() {
    if document.loopCount == 0 {
      setLoopCount(lastFiniteLoopCount)
    } else {
      lastFiniteLoopCount = document.loopCount
      setLoopCount(0)
    }
  }

  /// The finite count ``toggleLoopsForever()`` returns to. Seeded at 1 —
  /// "play once" — because that is what a GIF with no loop block means.
  private var lastFiniteLoopCount: Int = GIFLoader.playsOnce

  /// A loop count as prose. Matches the CLI's `info` wording so the two
  /// surfaces describe the same file the same way.
  static func loopDescription(_ count: Int) -> String {
    switch count {
    case 0: return "forever"
    case 1: return "once"
    default: return "\(count) times"
    }
  }

  /// The same count at timeline width: `forever`, `once`, or `N×`.
  ///
  /// `forever` and `once` are kept as words even though they are the two
  /// longest — spelling out the zero is the entire point of the control,
  /// and `0` in a strip would be read as "never". Only the numeric case is
  /// abbreviated, and `65535×` still fits.
  static func loopCode(_ count: Int) -> String {
    switch count {
    case 0: return "forever"
    case 1: return "once"
    default: return "\(count)×"
    }
  }

  public func setAllFrameDelaysToCurrent() {
    let target = currentFrame.delayCentiseconds
    recordUndoableEdit("Equalize frame delays") {
      // `.nothing` for the same reason as `adjustCurrentFrameDelay(by:)`.
      // This is the write site that most rewards the choice: stamping here
      // would recomposite the whole document for a timing change.
      mutateDocument(invalidating: .nothing) { doc in
        for i in doc.frames.indices {
          doc.frames[i].delayCentiseconds = target
        }
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
      let frameIndex = currentFrameIndex
      mutateDocument(invalidating: .frameContent(index: frameIndex)) {
        $0.frames[frameIndex].layers.append(layer)
      }
      currentLayerIndex = document.frames[frameIndex].layers.count - 1
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
      let frameIndex = currentFrameIndex
      mutateDocument(invalidating: .frameContent(index: frameIndex)) {
        $0.frames[frameIndex].layers[index] = layer
      }
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
      let frameIndex = currentFrameIndex
      mutateDocument(invalidating: .frameContent(index: frameIndex)) {
        $0.frames[frameIndex].layers.remove(at: index)
      }
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

  /// Takes the selection (or the whole layer) to the clipboard and clears
  /// it behind itself, as one undoable edit.
  ///
  /// Deliberately the same two `ToolOps` calls a copy and a delete would
  /// make separately — ``ToolOps/copy(from:rect:)`` then
  /// ``ToolOps/clear(on:rect:)`` — so a cut can never take a different
  /// snapshot than `Ctrl+C` would have taken a moment earlier.
  public func cutSelection() {
    let buffer = currentLayer.pixels
    let region = transformRegion
    let regionLabel = transformRegionLabel
    let taken: PixelBuffer?
    if let region {
      taken = ToolOps.copy(from: buffer, rect: region)
    } else {
      taken = buffer
    }
    guard let taken else {
      announce("Nothing to cut")
      return
    }
    clipboard = taken
    recordUndoableEdit("Cut") {
      mutateCurrentLayer { ToolOps.clear(on: $0, rect: region) }
    }
    announce("Cut \(regionLabel)")
  }

  // MARK: - Transforms

  /// The region flip, rotate and cut act on: the marquee when there is
  /// one, and the whole current layer when there is not.
  ///
  /// Stated once, here, because the alternative — "with no selection this
  /// quietly does nothing" — is the worst of the three possible answers,
  /// and because ``copySelection()`` already made the same choice. Four
  /// commands agreeing by construction beats four commands agreeing by
  /// diligence.
  private var transformRegion: PixelRect? {
    selection?.rect
  }

  /// What a transform's status line calls the thing it just changed.
  private var transformRegionLabel: String {
    selection == nil ? "layer" : "selection"
  }

  /// Mirrors the selection (or the layer) about its vertical centre line.
  public func flipHorizontally() {
    applyTransform("Flip horizontally", verb: "Flipped", detail: "left ↔ right") {
      (ToolOps.flipHorizontal(on: $0, rect: $1), $1)
    }
  }

  /// Mirrors the selection (or the layer) about its horizontal centre
  /// line.
  public func flipVertically() {
    applyTransform("Flip vertically", verb: "Flipped", detail: "top ↔ bottom") {
      (ToolOps.flipVertical(on: $0, rect: $1), $1)
    }
  }

  /// Turns the selection (or the layer) a quarter turn clockwise.
  ///
  /// A non-square marquee turns *losslessly* into the transposed rect,
  /// and the marquee moves with its pixels. Only a region too big to turn
  /// on the canvas — the whole of a non-square layer, most of all — falls
  /// back to clipping; see ``ToolOps/quarterTurnCounterClockwise(on:rect:)``.
  public func rotateClockwise() {
    applyTransform("Rotate clockwise", verb: "Rotated", detail: "a quarter turn clockwise") {
      let turn = ToolOps.quarterTurnClockwise(on: $0, rect: $1)
      return (turn.buffer, turn.region)
    }
  }

  /// Turns the selection (or the layer) a quarter turn counter-clockwise.
  public func rotateCounterClockwise() {
    applyTransform(
      "Rotate counter-clockwise", verb: "Rotated", detail: "a quarter turn counter-clockwise"
    ) {
      let turn = ToolOps.quarterTurnCounterClockwise(on: $0, rect: $1)
      return (turn.buffer, turn.region)
    }
  }

  /// The one write site the four transforms share, so the region rule,
  /// the undo step and the invalidation scope cannot drift between them.
  ///
  /// The scope is `.frameContent`, from ``mutateCurrentLayer(_:)``: every
  /// one of these rewrites pixels on exactly one layer of one frame.
  ///
  /// `transform` hands back the region its result occupies as well as the
  /// pixels. A flip hands back the region it was given; a quarter turn of
  /// a non-square region hands back the transposed rect, and the marquee
  /// is re-pointed at it *inside the same undoable edit*. Splitting the
  /// two would leave one undo step that puts the pixels back and another
  /// that puts the marquee back — the state the palette work already
  /// ruled out.
  private func applyTransform(
    _ label: String,
    verb: String,
    detail: String,
    _ transform: (PixelBuffer, PixelRect?) -> (pixels: PixelBuffer, region: PixelRect?)
  ) {
    let region = transformRegion
    let regionLabel = transformRegionLabel
    recordUndoableEdit(label) {
      var turnedRegion = region
      mutateCurrentLayer { buffer in
        let result = transform(buffer, region)
        turnedRegion = result.region
        return result.pixels
      }
      // Only when there was a marquee: with none, the region was the
      // whole layer and there is nothing to keep in step.
      if selection != nil, let turnedRegion {
        selection = Selection(rect: turnedRegion)
      }
    }
    announce("\(verb) \(regionLabel) \(detail)")
  }

  // MARK: - Palette editing

  /// Replaces the color in one used slot, leaving every index alone.
  ///
  /// Routed through `ColorPalette(colors:)` rather than the raw
  /// subscript so the padding tail (which duplicates the last used
  /// color) is re-derived when the *last* used slot is what changed —
  /// the subscript writes a slot verbatim and would leave padding
  /// describing a color the palette no longer holds.
  public func setPaletteColor(_ color: EditorColor, at index: PaletteIndex) {
    let slot = Int(index)
    guard slot < document.palette.usedCount else {
      announce("Slot \(slot) is not in use")
      return
    }
    guard document.palette[index] != color else {
      announce("Slot \(slot) already holds that color")
      return
    }
    var entries = document.palette.usedColors
    entries[slot] = color
    adoptPalette(
      ColorPalette(colors: entries),
      permutation: ColorPalette.identityPermutation,
      label: "Edit palette color"
    )
    announce("Slot \(slot) = \(Self.hexLabel(for: color))")
  }

  /// Appends a color in the first unused slot and selects it as primary.
  public func appendPaletteColor(_ color: EditorColor) {
    var palette = document.palette
    guard let index = palette.append(color) else {
      announce("Palette is full (\(ColorPalette.capacity) slots)")
      return
    }
    adoptPalette(
      palette,
      permutation: ColorPalette.identityPermutation,
      label: "Add palette color"
    )
    primaryColorIndex = index
    announce("Added slot \(Int(index)) = \(Self.hexLabel(for: color))")
  }

  /// Removes a used slot; pixels that referenced it recolor to the
  /// nearest surviving color and everything above it shifts down one.
  public func removePaletteSlot(at index: PaletteIndex) {
    let palette = document.palette
    let slot = Int(index)
    guard slot != Int(ColorPalette.transparentSlot) else {
      announce("Slot 0 is the transparency sentinel and can't be removed")
      return
    }
    guard slot < palette.usedCount, palette.usedCount > 1 else {
      announce("Slot \(slot) is not in use")
      return
    }
    let result = palette.remove(at: index)
    adoptPalette(result.palette, permutation: result.permutation, label: "Remove palette color")
    announce("Removed slot \(slot) — \(result.palette.usedCount) slots in use")
  }

  /// Collapses duplicate colors, keeping the first occurrence of each.
  /// Never changes a rendered pixel: every old index lands on the
  /// surviving slot holding its exact color.
  public func compactPalette() {
    let before = document.palette.usedCount
    let result = document.palette.compact()
    guard result.palette.usedCount < before else {
      announce("Palette has no duplicate colors")
      return
    }
    adoptPalette(result.palette, permutation: result.permutation, label: "Compact palette")
    announce("Compacted \(before) slots to \(result.palette.usedCount)")
  }

  /// Sorts slots `1...` by perceptual brightness. Slot 0 stays pinned.
  ///
  /// Rendering is unaffected — this is the edit whose whole point is
  /// that it renumbers indices without changing a single composited
  /// pixel, which is exactly what the document-wide remap below buys.
  public func sortPalette() {
    let result = document.palette.sorted { Self.luminance(of: $0) < Self.luminance(of: $1) }
    guard result.permutation != ColorPalette.identityPermutation else {
      announce("Palette is already sorted")
      return
    }
    adoptPalette(result.palette, permutation: result.permutation, label: "Sort palette")
    announce("Sorted \(result.palette.usedCount) slots by brightness")
  }

  /// Loads a Lospec `.hex` or GIMP `.gpl` palette from user-entered path
  /// text and adopts it. Returns whether the file parsed.
  @discardableResult
  public func importPalette(fromPath pathText: String) -> Bool {
    guard let url = GIFDocumentIO.saveURL(from: pathText) else {
      announce("Enter a palette path (.hex or .gpl)")
      return false
    }
    return importPalette(contentsOf: url)
  }

  /// Adopts an imported palette, recoloring the artwork into it.
  ///
  /// Two policy calls the parsers deliberately leave to their caller:
  ///
  /// - Neither format carries alpha, so an imported slot 0 is a real
  ///   color. `.transparent` is prepended (unless the file already opens
  ///   with a transparent entry) to keep the document's transparency
  ///   sentinel where every other part of the editor expects it.
  /// - The new colors have nothing to do with the old slot numbers, so
  ///   the index map is "old color → nearest new color" rather than a
  ///   permutation. The artwork keeps looking as close to itself as the
  ///   new palette allows instead of being renumbered at random.
  @discardableResult
  public func importPalette(contentsOf url: URL) -> Bool {
    let imported: ColorPalette
    do {
      imported = try PaletteImport.palette(contentsOf: url)
    } catch {
      announce("Palette import failed: \(error)")
      return false
    }

    var entries = imported.usedColors
    if entries.first?.alpha != 0 {
      entries.insert(.transparent, at: 0)
    }
    let dropped = max(0, entries.count - ColorPalette.capacity)
    let adopted = ColorPalette(colors: entries)

    adoptPalette(
      adopted,
      permutation: Self.nearestColorMap(from: document.palette, to: adopted),
      label: "Import palette"
    )
    primaryColorIndex = primaryColorIndex.clamped(to: 0...PaletteIndex(adopted.usedCount - 1))
    secondaryColorIndex = secondaryColorIndex.clamped(to: 0...PaletteIndex(adopted.usedCount - 1))
    if dropped > 0 {
      announce(
        "Imported \(adopted.usedCount) slots from \(url.lastPathComponent) "
          + "— \(dropped) dropped past \(ColorPalette.capacity)"
      )
    } else {
      announce("Imported \(adopted.usedCount) slots from \(url.lastPathComponent)")
    }
    return true
  }

  /// Adopts `palette` and pushes `permutation` through **everything**
  /// that holds a `PaletteIndex`, as one undoable edit.
  ///
  /// The completeness of that list is the whole correctness argument for
  /// palette editing: `remove`, `compact` and `sorted` renumber slots, so
  /// any holder left un-remapped silently recolors. The holders are every
  /// `PixelBuffer` in every layer of every frame, the primary and
  /// secondary selections, and the clipboard. `nil` pixels carry no index
  /// and need none — which is why ``ColorPalette/transparentSlot`` is
  /// pinned.
  ///
  /// The write declares `.everyFrame`. The palette is a document-wide
  /// input to `flattenedColors(for:)`, so every memoized composite is
  /// stale the instant it changes — including for frames whose pixels
  /// this edit never touched.
  private func adoptPalette(
    _ palette: ColorPalette,
    permutation: [PaletteIndex],
    label: String
  ) {
    precondition(
      permutation.count == ColorPalette.capacity,
      "an index map must cover every palette slot"
    )
    let renumbers = permutation != ColorPalette.identityPermutation

    recordUndoableEdit(label) {
      mutateDocument(invalidating: .everyFrame) { doc in
        doc.palette = palette
        guard renumbers else { return }
        for frameIndex in doc.frames.indices {
          for layerIndex in doc.frames[frameIndex].layers.indices {
            var buffer = doc.frames[frameIndex].layers[layerIndex].pixels
            for i in buffer.pixels.indices {
              if let old = buffer.pixels[i] {
                buffer.pixels[i] = permutation[Int(old)]
              }
            }
            doc.frames[frameIndex].layers[layerIndex].pixels = buffer
          }
        }
      }
      guard renumbers else { return }
      primaryColorIndex = permutation[Int(primaryColorIndex)]
      secondaryColorIndex = permutation[Int(secondaryColorIndex)]
      if var buffer = clipboard {
        for i in buffer.pixels.indices {
          if let old = buffer.pixels[i] {
            buffer.pixels[i] = permutation[Int(old)]
          }
        }
        clipboard = buffer
      }
    }
  }

  /// "old slot → nearest color in the new palette", `capacity` long so it
  /// drives the same remap a permutation does. Transparent old slots are
  /// pinned to ``ColorPalette/transparentSlot`` rather than matched by
  /// distance, since alpha plays no part in `nearestIndex(to:)`.
  private static func nearestColorMap(
    from old: ColorPalette,
    to new: ColorPalette
  ) -> [PaletteIndex] {
    var map = ColorPalette.identityPermutation
    for slot in 0..<old.usedCount {
      let color = old.colors[slot]
      map[slot] =
        color.alpha == 0
        ? ColorPalette.transparentSlot
        : new.nearestIndex(to: color)
    }
    // Old padding duplicates the last used color, so it follows it.
    let lastUsed = map[old.usedCount - 1]
    for slot in old.usedCount..<ColorPalette.capacity {
      map[slot] = lastUsed
    }
    return map
  }

  /// Rec. 601 luma, integer-weighted. Sorting on it puts the palette in
  /// the dark-to-light order an author scanning a ramp expects, and the
  /// weights are exact integers so the ordering is identical on every
  /// platform.
  static func luminance(of color: EditorColor) -> Int {
    299 * Int(color.red) + 587 * Int(color.green) + 114 * Int(color.blue)
  }

  /// `RRGGBB`, uppercase — the spelling both the hex field in the palette
  /// editor and the status line use.
  static func hexLabel(for color: EditorColor) -> String {
    String(
      format: "%02X%02X%02X",
      Int(color.red),
      Int(color.green),
      Int(color.blue)
    )
  }

  // MARK: - Canvas resize

  /// Square-canvas presets cycled through by `cycleCanvasSize()`.
  ///
  /// The progression runs to ``maximumCanvasDimension`` now that the
  /// viewport clips in source-pixel space: a render costs O(visible
  /// cells) rather than O(canvas area), so the sizes above 64 are a
  /// supported working surface rather than a way to stall the editor.
  public static let canvasSizeProgression: [Int] = [16, 24, 32, 48, 64, 96, 128, 192, 256]

  /// Largest dimension the New/Resize UI offers on either axis.
  ///
  /// A *UI* cap, deliberately: the project format stores arbitrary
  /// `width × height` and the loader opens any GIF it is given, so
  /// "open any GIF" stays true while 256 is the size the editor promises
  /// to be pleasant at.
  public static let maximumCanvasDimension: Int = 256

  /// Advances the canvas through the standard size progression (each
  /// dimension `16 → 24 → 32 → 48 → 64 → 96 → 128 → 192 → 256 → 16 → …`).
  /// Used by both the `Ctrl+R` keybinding and the File → Resize Canvas
  /// menu item so they remain bit-identical.
  public func cycleCanvasSize() {
    let current = document.size.width
    let next =
      Self.canvasSizeProgression.first { $0 > current }
      ?? Self.canvasSizeProgression[0]
    resizeCanvas(to: GIFEditorCore.PixelSize(width: next, height: next))
  }

  public func resizeCanvas(to size: GIFEditorCore.PixelSize) {
    recordUndoableEdit("Resize canvas") {
      // `.everyFrame`: the canvas size and every layer buffer in the
      // document change together.
      mutateDocument(invalidating: .everyFrame) { doc in
        doc.size = size
        for frameIndex in doc.frames.indices {
          for layerIndex in doc.frames[frameIndex].layers.indices {
            var layer = doc.frames[frameIndex].layers[layerIndex]
            layer.pixels = layer.pixels.resized(to: size)
            doc.frames[frameIndex].layers[layerIndex] = layer
          }
        }
      }
      // Outside the write path so `cursor.didSet` clamps against the new
      // canvas size, exactly as it did when this ran inline.
      cursor = GIFEditorCore.PixelPoint(
        x: min(cursor.x, size.width - 1),
        y: min(cursor.y, size.height - 1)
      )
      selection = nil
    }
    announce("Canvas resized to \(size.width)×\(size.height)")
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
      primaryColorIndex: primaryColorIndex,
      secondaryColorIndex: secondaryColorIndex,
      clipboard: clipboard,
      historyGeneration: history.currentHistoryGeneration
    )
  }

  private func restore(_ snapshot: EditorSnapshot) {
    // `.everyFrame`: undo/redo swaps the whole document, so every stamp
    // taken against the outgoing one describes content that is gone —
    // including the frame ids that survive the swap.
    mutateDocument(invalidating: .everyFrame) { $0 = snapshot.document }
    currentFrameIndex = snapshot.currentFrameIndex
    currentLayerIndex = snapshot.currentLayerIndex
    cursor = snapshot.cursor
    selection = snapshot.selection
    // The palette-index holders travel with the document they index
    // into: undoing a sort has to put the colour selection back on the
    // slot it named before the renumber, not leave it on the slot the
    // sort moved that colour to.
    primaryColorIndex = snapshot.primaryColorIndex
    secondaryColorIndex = snapshot.secondaryColorIndex
    clipboard = snapshot.clipboard
    pendingMarqueeAnchor = nil
    pendingGradientAnchor = nil
    pendingShapeAnchor = nil
    dragController.reset()
    history.adoptRestored(generation: snapshot.historyGeneration)
  }

  /// Replaces the current layer's pixel buffer with the result of
  /// `transform`. Callers own history grouping.
  ///
  /// This is the main pixel path — every pen, eraser, fill, gradient and
  /// paste edit lands here, as does the drag controller through
  /// `CanvasDragContext` — so it is also the write site the composite
  /// cache's per-frame stamp exists for.
  private func mutateCurrentLayer(_ transform: (PixelBuffer) -> PixelBuffer) {
    let frameIndex = currentFrameIndex
    let layerIndex = currentLayerIndex
    var layer = currentLayer
    // `transform` runs before the write path is entered: the gradient tool
    // reads `document.palette` from inside it, and the write path is where
    // the document is being replaced.
    layer.pixels = transform(layer.pixels)
    mutateDocument(invalidating: .frameContent(index: frameIndex)) {
      $0.frames[frameIndex].layers[layerIndex] = layer
    }
  }

  // MARK: - Document write path

  /// What a document write can invalidate in the composite cache. Naming
  /// one is mandatory at every write site, so keeping the mutation stamps
  /// honest is a decision the author makes while editing rather than a
  /// follow-up step to remember afterwards.
  private enum CompositeInvalidation {
    /// The drawn content of exactly one frame changed — its pixels, its
    /// layer stack, or a layer's visibility.
    case frameContent(index: Int)
    /// The frame *list* was reordered, extended, or shortened. Frame ids
    /// are stable and no surviving frame's content was touched, so every
    /// surviving composite stays valid and only dead stamps are pruned.
    case frameList
    /// Every frame's composite is invalid: the palette changed, the canvas
    /// was resized, or the whole document was replaced.
    case everyFrame
    /// Nothing `GIFDocument.flattenedColors(for:)` reads — frame delay,
    /// disposal, the file path, the loop count.
    case nothing
  }

  /// The one write path into the document.
  ///
  /// `storedDocument` is written here and in `init` and nowhere else, and
  /// `document` is get-only, so the compiler rejects any edit that skips
  /// this method and its invalidation argument. That is what makes the
  /// stamp discipline structural instead of a convention.
  ///
  /// The edit runs against a local copy that is written back afterwards.
  /// That costs one shallow (copy-on-write) array copy per edit — bytes,
  /// against a composite's `layers × area` — and buys two things: `body`
  /// may read `document` freely, where an `inout` on the stored property
  /// would turn any such read into a simultaneous-access trap; and the
  /// invalidation always resolves frame indices against the document the
  /// edit produced.
  private func mutateDocument(
    invalidating scope: CompositeInvalidation,
    _ body: (inout GIFDocument) -> Void
  ) {
    var updated = storedDocument
    body(&updated)
    storedDocument = updated
    invalidateComposites(scope)
  }

  private func invalidateComposites(_ scope: CompositeInvalidation) {
    switch scope {
    case .frameContent(let index):
      guard storedDocument.frames.indices.contains(index) else { return }
      frameRevisions[storedDocument.frames[index].id] = nextRevision()
    case .frameList:
      pruneFrameRevisions()
    case .everyFrame:
      paletteRevision = nextRevision()
      pruneFrameRevisions()
    case .nothing:
      break
    }
  }

  /// Drops stamps for frames the document no longer holds so a long
  /// session of frame deletes can't accumulate dead entries. Safe to drop
  /// a stamp back to the unstamped default: `compositeCache` is itself
  /// rebuilt to the live frame set on the next `compositedFrames()` call,
  /// and the only route by which a removed frame id comes back — undo /
  /// redo — bumps `paletteRevision` and invalidates everything anyway.
  private func pruneFrameRevisions() {
    guard !frameRevisions.isEmpty else { return }
    let live = Set(storedDocument.frames.map(\.id))
    frameRevisions = frameRevisions.filter { live.contains($0.key) }
  }

  /// Next stamp value. Monotonic and never 0, so a stamped frame can never
  /// alias one that has never been written.
  private func nextRevision() -> UInt64 {
    revisionCounter += 1
    return revisionCounter
  }

  /// Sets the one-line status feedback shown in the footer. Internal
  /// (not `private`) so it also serves as the `CanvasDragContext`
  /// witness the drag controller announces through.
  func announce(_ message: String) {
    statusMessage = message
  }
}

// MARK: - CanvasDragContext

extension EditingSession: CanvasDragContext {
  var canvasSize: GIFEditorCore.PixelSize {
    document.size
  }

  var currentLayerPixels: PixelBuffer {
    currentLayer.pixels
  }

  /// The one place a pen or eraser stroke reaches the document, from
  /// either the keyboard's press-to-paint or the pointer's drag — which
  /// is what makes ``strokesMirrorX`` a single branch here rather than a
  /// flag every call site has to remember to honour.
  func strokeCurrentLayer(
    from start: GIFEditorCore.PixelPoint,
    to end: GIFEditorCore.PixelPoint,
    color: PaletteIndex?
  ) {
    mutateCurrentLayer { buffer in
      guard strokesMirrorX else {
        return ToolOps.line(
          on: buffer,
          from: start,
          to: end,
          color: color,
          thickness: brushSize
        )
      }
      return ToolOps.mirrorXLine(
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

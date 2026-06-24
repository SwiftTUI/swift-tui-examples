import GIFEditorCore

/// The editing surface a `CanvasDragController` drives during a pointer
/// drag. `EditorViewModel` conforms to it, exposing just the cursor,
/// tool, selection, layer, and history primitives the drag state machine
/// needs — the controller never touches the document or history stack
/// directly, so the coordinator stays the single owner of those.
///
/// `@MainActor` so every requirement runs on the UI actor the editor
/// lives on; `AnyObject` so the controller mutates the live coordinator
/// in place rather than a copy (the view model is the reference box the
/// view tree binds to).
@MainActor
protocol CanvasDragContext: AnyObject {
  var tool: EditorTool { get }
  var cursor: GIFEditorCore.PixelPoint { get set }
  var selection: Selection? { get set }
  var primaryColorIndex: PaletteIndex { get }
  var pendingMarqueeAnchor: GIFEditorCore.PixelPoint? { get set }
  var pendingGradientAnchor: GIFEditorCore.PixelPoint? { get set }

  var canvasSize: GIFEditorCore.PixelSize { get }
  var currentLayerPixels: PixelBuffer { get }

  func strokeCurrentLayer(
    from start: GIFEditorCore.PixelPoint,
    to end: GIFEditorCore.PixelPoint,
    color: PaletteIndex?
  )
  func replaceCurrentLayerPixels(with pixels: PixelBuffer)
  func beginUndoGroup(_ label: String)
  func finishUndoGroup()
  func applyToolAtCursor()
  func announce(_ message: String)
}

/// Pointer-drag interaction state machine for the canvas.
///
/// Owns only the transient drag bookkeeping (`activeSelectMove`); all
/// document mutation and history grouping is delegated back through a
/// `CanvasDragContext`. The per-tool dispatch is the same logic that used
/// to live inline on `EditorViewModel` — pen/eraser stamp through the
/// context, marquee/gradient advance their anchors, and select moves a
/// snapshot of the original pixels so each drag step re-derives from the
/// untouched layer rather than compounding.
///
/// `@MainActor` like the editor it drives: every entry runs on the UI
/// event that triggered the drag and only ever calls back into the
/// `@MainActor` view model.
@MainActor
struct CanvasDragController {
  private struct ActiveSelectMove {
    var layerPixels: PixelBuffer
    var selection: Selection?
    var sourceRect: PixelRect
  }

  private var activeSelectMove: ActiveSelectMove?

  /// Clears any in-progress select move. Called when the active tool or
  /// selection changes out from under a drag.
  mutating func reset() {
    activeSelectMove = nil
  }

  // MARK: - Drag lifecycle

  mutating func begin(at point: GIFEditorCore.PixelPoint, context: some CanvasDragContext) {
    context.cursor = point
    switch context.tool {
    case .pen:
      context.beginUndoGroup("Paint stroke")
      context.strokeCurrentLayer(from: point, to: point, color: context.primaryColorIndex)
      context.announce("Painting \(point.x),\(point.y)")
    case .eraser:
      context.beginUndoGroup("Erase stroke")
      context.strokeCurrentLayer(from: point, to: point, color: nil)
      context.announce("Erasing \(point.x),\(point.y)")
    case .fill, .eyedropper:
      context.announce("Target \(point.x),\(point.y)")
    case .gradient:
      context.beginUndoGroup("Apply gradient")
      context.pendingGradientAnchor = point
      context.announce("Gradient anchor \(point.x),\(point.y)")
    case .marquee:
      context.pendingMarqueeAnchor = point
      context.selection = Selection(rect: PixelRect.bounding(point, point))
      context.announce("Selecting from \(point.x),\(point.y)")
    case .select:
      context.beginUndoGroup("Move pixels")
      beginSelectMove(context: context)
      updateSelectMove(startingAt: point, to: point, context: context)
      context.announce(selectMoveStatus(to: point, from: point))
    }
  }

  mutating func update(
    startingAt anchor: GIFEditorCore.PixelPoint,
    from previous: GIFEditorCore.PixelPoint?,
    to point: GIFEditorCore.PixelPoint,
    context: some CanvasDragContext
  ) {
    context.cursor = point
    switch context.tool {
    case .pen:
      context.strokeCurrentLayer(
        from: previous ?? anchor, to: point, color: context.primaryColorIndex)
      context.announce("Painting \(point.x),\(point.y)")
    case .eraser:
      context.strokeCurrentLayer(from: previous ?? anchor, to: point, color: nil)
      context.announce("Erasing \(point.x),\(point.y)")
    case .fill, .eyedropper:
      context.announce("Target \(point.x),\(point.y)")
    case .gradient:
      context.pendingGradientAnchor = anchor
      context.announce("Gradient \(anchor.x),\(anchor.y) -> \(point.x),\(point.y)")
    case .marquee:
      context.pendingMarqueeAnchor = anchor
      context.selection = Selection(rect: PixelRect.bounding(anchor, point))
      context.announce("Selection \(anchor.x),\(anchor.y) -> \(point.x),\(point.y)")
    case .select:
      if activeSelectMove == nil {
        context.beginUndoGroup("Move pixels")
        beginSelectMove(context: context)
      }
      updateSelectMove(startingAt: anchor, to: point, context: context)
      context.announce(selectMoveStatus(to: point, from: anchor))
    }
  }

  mutating func end(
    startingAt anchor: GIFEditorCore.PixelPoint,
    from previous: GIFEditorCore.PixelPoint?,
    to point: GIFEditorCore.PixelPoint,
    context: some CanvasDragContext
  ) {
    if previous == nil {
      begin(at: anchor, context: context)
    }

    context.cursor = point
    switch context.tool {
    case .pen:
      if let previous, previous != point {
        context.strokeCurrentLayer(from: previous, to: point, color: context.primaryColorIndex)
      }
      context.finishUndoGroup()
      context.announce("Painted to \(point.x),\(point.y)")
    case .eraser:
      if let previous, previous != point {
        context.strokeCurrentLayer(from: previous, to: point, color: nil)
      }
      context.finishUndoGroup()
      context.announce("Erased to \(point.x),\(point.y)")
    case .fill, .eyedropper:
      context.applyToolAtCursor()
    case .gradient:
      context.pendingGradientAnchor = anchor
      context.applyToolAtCursor()
      context.finishUndoGroup()
    case .marquee:
      context.pendingMarqueeAnchor = anchor
      context.applyToolAtCursor()
    case .select:
      if activeSelectMove == nil {
        context.beginUndoGroup("Move pixels")
        beginSelectMove(context: context)
      }
      updateSelectMove(startingAt: anchor, to: point, context: context)
      let status = selectMoveStatus(to: point, from: anchor)
      activeSelectMove = nil
      context.finishUndoGroup()
      context.announce(status)
    }
  }

  // MARK: - Select move

  private mutating func beginSelectMove(context: some CanvasDragContext) {
    let size = context.canvasSize
    let wholeLayer = PixelRect(x: 0, y: 0, width: size.width, height: size.height)
    activeSelectMove = ActiveSelectMove(
      layerPixels: context.currentLayerPixels,
      selection: context.selection,
      sourceRect: context.selection?.rect ?? wholeLayer
    )
  }

  private func updateSelectMove(
    startingAt anchor: GIFEditorCore.PixelPoint,
    to point: GIFEditorCore.PixelPoint,
    context: some CanvasDragContext
  ) {
    guard let move = activeSelectMove else { return }

    let dx = point.x - anchor.x
    let dy = point.y - anchor.y
    context.replaceCurrentLayerPixels(
      with: ToolOps.move(
        on: move.layerPixels,
        rect: move.sourceRect,
        byX: dx,
        y: dy
      )
    )

    if let selection = move.selection {
      context.selection = Selection(rect: selection.rect.offsetBy(dx: dx, dy: dy))
    }
  }

  private func selectMoveStatus(
    to point: GIFEditorCore.PixelPoint,
    from anchor: GIFEditorCore.PixelPoint
  ) -> String {
    let dx = point.x - anchor.x
    let dy = point.y - anchor.y
    let target = activeSelectMove?.selection == nil ? "layer" : "selection"
    return "Move \(target) Δ\(dx),\(dy)"
  }
}

// `fileprivate` (not `private`) so the drag controller's methods in this
// file can use it — `private` on a top-level extension scopes to the
// extension alone.
extension PixelRect {
  fileprivate func offsetBy(dx: Int, dy: Int) -> PixelRect {
    PixelRect(x: minX + dx, y: minY + dy, width: size.width, height: size.height)
  }
}

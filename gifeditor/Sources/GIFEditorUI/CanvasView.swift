import GIFEditorCore
import SwiftTUI

/// Renders one composited frame as a Canvas-backed grid of colored cells.
///
/// `cells` is the row-major composited buffer (`document.flattenedColors`)
/// — passing the data in this shape rather than the layer model itself
/// keeps the view ignorant of compositing rules and lets the parent
/// reuse a single flatten pass for both the canvas and the timeline
/// thumbnail.
///
/// `viewport` decides *which* of those cells are drawn and at what scale.
/// Leaving it `nil` selects ``CanvasViewport/wholeCanvas(_:)`` — the 1:1
/// identity window — so a caller that does not zoom renders exactly what it
/// rendered before the viewport existed.
///
/// `ghosts` are the onion-skin layers, in far-to-near order. They are blended
/// *beneath* `cells` and are display-only: an opaque pixel of the current
/// frame hides them completely, so with onion skin on every painted cell is
/// byte-identical to onion skin off and only the transparent ones change.
struct CanvasView: View {
  let size: GIFEditorCore.PixelSize
  let cells: [EditorColor?]
  let cursor: GIFEditorCore.PixelPoint
  let selection: Selection?
  let pendingMarqueeAnchor: GIFEditorCore.PixelPoint?
  let pendingGradientAnchor: GIFEditorCore.PixelPoint?
  var hover: GIFEditorCore.PixelPoint? = nil
  var mode: CanvasPixelGridMode = .verticalHalfBlock
  var viewport: CanvasViewport? = nil
  var ghosts: [CanvasGhostLayer] = []

  var body: some View {
    CanvasSurfaceView(
      size: size,
      cells: cells,
      cursor: cursor,
      selection: selection,
      pendingMarqueeAnchor: pendingMarqueeAnchor,
      pendingGradientAnchor: pendingGradientAnchor,
      hover: hover,
      mode: mode,
      viewport: viewport ?? .wholeCanvas(size),
      ghosts: ghosts
    )
    .border(.separator, set: .single)
  }
}

struct CanvasSurfaceView: View {
  let size: GIFEditorCore.PixelSize
  let cells: [EditorColor?]
  let cursor: GIFEditorCore.PixelPoint
  let selection: Selection?
  let pendingMarqueeAnchor: GIFEditorCore.PixelPoint?
  let pendingGradientAnchor: GIFEditorCore.PixelPoint?
  var hover: GIFEditorCore.PixelPoint? = nil
  var mode: CanvasPixelGridMode = .verticalHalfBlock
  var viewport: CanvasViewport
  /// Onion-skin layers, farthest ghost first. Empty when onion skin is off,
  /// which is the only state that has to cost nothing.
  var ghosts: [CanvasGhostLayer] = []

  var body: some View {
    // Resolve the pixel colors once and share them between the base grid and
    // the overlay. `resolvedPixels` is a pure function of `cells`/`viewport`, so
    // a single evaluation is byte-identical to the two reads it replaces — and
    // it halves the per-render color-resolution cost (paid on every drag
    // refresh and every hover that crosses a pixel boundary).
    let resolved = resolvedPixels
    let logical = viewport.logicalSize
    return ZStack(alignment: .topLeading) {
      Canvas.pixelGrid(
        width: logical.width,
        height: logical.height,
        pixels: resolved,
        mode: mode
      )

      Canvas(
        CanvasOverlayDrawing(
          viewport: viewport,
          logicalSize: logical,
          pixels: resolved,
          cursor: cursor,
          selection: selection,
          pendingMarqueeAnchor: pendingMarqueeAnchor,
          pendingGradientAnchor: pendingGradientAnchor,
          hover: hover,
          mode: mode
        )
      )
      .frame(width: logical.width, height: mode.cellHeight(for: logical.height))
    }
    .frame(width: logical.width, height: mode.cellHeight(for: logical.height))
  }

  /// The logical pixel array handed to `Canvas.pixelGrid`.
  ///
  /// Cull, then scale: the loop walks *logical* coordinates, each of which maps
  /// back to the source pixel it samples. That makes the cost O(visible cells)
  /// — the array can never grow with the canvas area, only with the cell budget
  /// the layout system handed the canvas region — where the pre-viewport
  /// version materialized the whole canvas on every body evaluation and left
  /// the clipping to an enclosing `ScrollView`.
  var resolvedPixels: [Color?] {
    let logical = viewport.logicalSize
    var output: [Color?] = []
    output.reserveCapacity(logical.area)
    for y in 0..<logical.height {
      for x in 0..<logical.width {
        output.append(
          fillColor(
            at: viewport.sourcePoint(forLogicalX: x, y: y),
            logicalX: x,
            logicalY: y
          )
        )
      }
    }
    return output
  }

  /// Resolves the color a pixel paints. Falls back to a checkerboard
  /// background pattern for transparent cells so the user can tell
  /// transparent from "actually painted in their bg color".
  ///
  /// The checker parity is taken from the *logical* coordinate, not the source
  /// pixel: at `Z ≥ 2` a source-space parity would replicate along with the
  /// pixel and grow each check into a `Z × Z` slab. Logical parity keeps one
  /// check to one cell at every zoom.
  ///
  /// Onion-skin ghosts are resolved here, in the same call that resolves the
  /// real pixel and against the same already-culled source point — so the
  /// per-render cost stays `O(visible cells × ghosts)` and never picks up a
  /// term in the canvas area. Resolving whole ghost frames and blending
  /// afterwards would have reinstated exactly the area-proportional cost the
  /// viewport exists to delete.
  ///
  /// Ghosts go *under* the current frame: an opaque current-frame pixel
  /// returns before the ghost loop is even reached, so the ghosts can only
  /// ever fill in what the current frame leaves transparent.
  private func fillColor(
    at point: GIFEditorCore.PixelPoint,
    logicalX: Int,
    logicalY: Int
  ) -> Color {
    let index = size.contains(point) ? size.indexOf(point) : nil
    if let index, let color = cells[index] {
      return color.toTerminalColor()
    }
    // Checkerboard for transparent.
    let shade = ((logicalX + logicalY) & 1) == 0 ? 0.18 : 0.10
    var resolved = Color(red: shade, green: shade, blue: shade, alpha: 1.0)
    guard let index, !ghosts.isEmpty else {
      return resolved
    }
    // Far to near, so the nearest neighbour ends up on top.
    for ghost in ghosts {
      guard
        ghost.cells.indices.contains(index),
        let color = ghost.cells[index]
      else {
        continue
      }
      resolved = ghost.ghostColor(for: color).composited(over: resolved)
    }
    return resolved
  }
}

private struct CanvasOverlayDrawing: CanvasDrawing, Equatable {
  var viewport: CanvasViewport
  /// Extent of `pixels`, which is in *logical* (post-zoom) row-major order.
  var logicalSize: GIFEditorCore.PixelSize
  var pixels: [Color?]
  var cursor: GIFEditorCore.PixelPoint
  var selection: Selection?
  var pendingMarqueeAnchor: GIFEditorCore.PixelPoint?
  var pendingGradientAnchor: GIFEditorCore.PixelPoint?
  var hover: GIFEditorCore.PixelPoint?
  var mode: CanvasPixelGridMode

  func draw(into context: inout CanvasContext) {
    if let hover, hover != cursor {
      mark(hover, kind: .hover, into: &context)
    }
    if let selection {
      drawSelection(selection.rect, into: &context)
    }
    if let anchor = pendingMarqueeAnchor {
      mark(anchor, kind: .anchor(color: .yellow), into: &context)
    }
    if let anchor = pendingGradientAnchor {
      mark(anchor, kind: .anchor(color: .green), into: &context)
    }
    mark(cursor, kind: .cursor, into: &context)
  }

  // MARK: - Point marks

  /// Marks one source pixel.
  ///
  /// At `1×` a source pixel owns a single cell (`.fullCell`) or one half of one
  /// (`.verticalHalfBlock`), so the mark is solid — byte-identical to the
  /// pre-viewport overlay. At `Z ≥ 2` a source pixel is at least two cells
  /// wide, so the mark becomes a one-cell **bracket**: `▌` down the block's
  /// left column and `▐` down its right column. The bar glyphs split those
  /// cells vertically, so even the narrowest magnified block (2 cells at `2×`)
  /// still shows half of the pixel underneath, and `4×` shows three quarters.
  /// That is the "zooming in must never hide the pixel under the cursor" rule;
  /// a filled box would have failed it exactly where zoom is most useful.
  ///
  /// Hover and the pending marquee/gradient anchors are single-pixel marks too,
  /// so they take the same treatment — one rule instead of three special cases.
  private func mark(
    _ point: GIFEditorCore.PixelPoint,
    kind: OverlayMark,
    into context: inout CanvasContext
  ) {
    guard viewport.contains(point) else {
      return
    }
    let block = viewport.cellRect(forSource: point, mode: mode)
    guard viewport.zoom.magnification >= 2 else {
      let logicalY = viewport.logicalOrigin(forSource: point).y
      write(
        block.origin,
        character: kind.solidCharacter(
          mode: mode,
          isTopHalf: viewport.halfBlockGlyphIsTop(forLogicalY: logicalY)
        ),
        color: kind.color,
        into: &context
      )
      return
    }
    for y in block.origin.y..<block.maxY {
      write(CellPoint(x: block.origin.x, y: y), character: "▌", color: kind.color, into: &context)
      write(CellPoint(x: block.maxX - 1, y: y), character: "▐", color: kind.color, into: &context)
    }
  }

  // MARK: - Selection

  /// Strokes the selection's outline.
  ///
  /// Only the rect's four edges are walked, clipped to the visible rect — the
  /// pre-viewport version scanned the selection's whole area and discarded the
  /// interior, which is the same area-proportional per-render cost the viewport
  /// exists to remove.
  private func drawSelection(
    _ rect: PixelRect,
    into context: inout CanvasContext
  ) {
    guard let visible = rect.intersected(with: viewport.sourceRect()) else {
      return
    }
    forEachBorderPixel(of: rect, clippedTo: visible) { point, edge in
      guard viewport.zoom.magnification >= 2 else {
        mark(point, kind: .selection, into: &context)
        return
      }
      stroke(edge, at: point, into: &context)
    }
  }

  /// Visits every border pixel of `rect` that falls inside `visible`, once per
  /// edge it belongs to. Horizontal runs come first so the vertical strokes win
  /// at the corners, which reads as a continuous box.
  private func forEachBorderPixel(
    of rect: PixelRect,
    clippedTo visible: PixelRect,
    _ body: (GIFEditorCore.PixelPoint, SelectionEdge) -> Void
  ) {
    if (visible.minY..<visible.maxY).contains(rect.minY) {
      for x in visible.minX..<visible.maxX {
        body(GIFEditorCore.PixelPoint(x: x, y: rect.minY), .top)
      }
    }
    let bottom = rect.maxY - 1
    if bottom != rect.minY, (visible.minY..<visible.maxY).contains(bottom) {
      for x in visible.minX..<visible.maxX {
        body(GIFEditorCore.PixelPoint(x: x, y: bottom), .bottom)
      }
    }
    if (visible.minX..<visible.maxX).contains(rect.minX) {
      for y in visible.minY..<visible.maxY {
        body(GIFEditorCore.PixelPoint(x: rect.minX, y: y), .left)
      }
    }
    let right = rect.maxX - 1
    if right != rect.minX, (visible.minX..<visible.maxX).contains(right) {
      for y in visible.minY..<visible.maxY {
        body(GIFEditorCore.PixelPoint(x: right, y: y), .right)
      }
    }
  }

  /// Strokes one outward-facing edge of a magnified selection-border pixel.
  ///
  /// Bracketing every border pixel the way ``mark(_:kind:into:)`` does would
  /// double the outline — each pixel would get *both* a left and a right bar —
  /// so at `Z ≥ 2` the selection instead draws only the half-cell facing out of
  /// the rect. The result is a one-cell-thick box hugging the selection, with
  /// the pixels underneath still readable.
  private func stroke(
    _ edge: SelectionEdge,
    at point: GIFEditorCore.PixelPoint,
    into context: inout CanvasContext
  ) {
    let block = viewport.cellRect(forSource: point, mode: mode)
    let color = OverlayMark.selection.color
    switch edge {
    case .top:
      for x in block.origin.x..<block.maxX {
        write(CellPoint(x: x, y: block.origin.y), character: "▀", color: color, into: &context)
      }
    case .bottom:
      for x in block.origin.x..<block.maxX {
        write(CellPoint(x: x, y: block.maxY - 1), character: "▄", color: color, into: &context)
      }
    case .left:
      for y in block.origin.y..<block.maxY {
        write(CellPoint(x: block.origin.x, y: y), character: "▌", color: color, into: &context)
      }
    case .right:
      for y in block.origin.y..<block.maxY {
        write(CellPoint(x: block.maxX - 1, y: y), character: "▐", color: color, into: &context)
      }
    }
  }

  // MARK: - Cell writes

  private func write(
    _ cell: CellPoint,
    character: Character,
    color: Color,
    into context: inout CanvasContext
  ) {
    context.setCell(
      at: cell,
      character: character,
      foreground: color,
      background: backgroundColor(behind: cell, character: character)
    )
  }

  /// The color the part of the cell the glyph does *not* paint should show.
  ///
  /// Resolved in logical space, which is what makes it zoom-agnostic: at `1×`
  /// half-block this reproduces the old `y ± 1` source-pixel pairing; at
  /// `Z ≥ 2` both logical rows of a cell belong to the same source pixel, so
  /// either row answers; and under a `fit` downsample the two rows are again
  /// genuinely different source pixels and the pairing is again what you want.
  private func backgroundColor(behind cell: CellPoint, character: Character) -> Color? {
    switch mode {
    case .fullCell:
      return logicalColor(x: cell.x, y: cell.y)
    case .verticalHalfBlock:
      // `▀` paints the upper half, so the lower logical row shows through;
      // every other glyph leaves the upper row visible.
      let top = cell.y * 2
      return logicalColor(x: cell.x, y: character == "▀" ? top + 1 : top)
    }
  }

  private func logicalColor(x: Int, y: Int) -> Color? {
    guard x >= 0, y >= 0, x < logicalSize.width, y < logicalSize.height else {
      return nil
    }
    let index = y * logicalSize.width + x
    guard pixels.indices.contains(index) else {
      return nil
    }
    return pixels[index]
  }
}

private enum SelectionEdge: Equatable {
  case top
  case bottom
  case left
  case right
}

private enum OverlayMark: Equatable {
  case cursor
  case hover
  case selection
  case anchor(color: Color)

  var color: Color {
    switch self {
    case .cursor: .cyan
    case .hover: .magenta
    case .selection: .blue
    case .anchor(let color): color
    }
  }

  /// The glyph used at `1×`, where a source pixel owns one cell (`.fullCell`)
  /// or one half of one (`.verticalHalfBlock`).
  func solidCharacter(mode: CanvasPixelGridMode, isTopHalf: Bool) -> Character {
    switch mode {
    case .fullCell:
      switch self {
      case .cursor: "◆"
      case .hover: "·"
      case .selection: "□"
      case .anchor: "◇"
      }
    case .verticalHalfBlock:
      isTopHalf ? "▀" : "▄"
    }
  }
}

struct InteractiveCanvasView: View {
  let size: GIFEditorCore.PixelSize
  let cells: [EditorColor?]
  let model: EditorViewModel
  let refresh: @MainActor @Sendable () -> Void
  var mode: CanvasPixelGridMode = .verticalHalfBlock
  var viewport: CanvasViewport? = nil
  /// Onion-skin layers, farthest ghost first. Display only — the drag
  /// handlers below address source pixels through the viewport and the model,
  /// and never read these.
  var ghosts: [CanvasGhostLayer] = []

  @State private var dragAnchor: GIFEditorCore.PixelPoint?
  @State private var lastDragPoint: GIFEditorCore.PixelPoint?
  @State private var hover: GIFEditorCore.PixelPoint?

  var body: some View {
    let viewport = self.viewport ?? .wholeCanvas(size)
    return EnvironmentReader(\.pointerInputCapabilities) { pointerInputCapabilities in
      CanvasSurfaceView(
        size: size,
        cells: cells,
        cursor: model.cursor,
        selection: model.selection,
        pendingMarqueeAnchor: model.pendingMarqueeAnchor,
        pendingGradientAnchor: model.pendingGradientAnchor,
        hover: hover,
        mode: mode,
        viewport: viewport,
        ghosts: ghosts
      )
      .contentShape(
        canvasPointerTargetPath(viewport.cellSize(mode: mode))
      )
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
          .onChanged { value in
            handleDragChange(value, viewport: viewport)
          }
          .onEnded { value in
            handleDragEnd(value, viewport: viewport)
          }
      )
      .onPointerHover { phase in
        updateHover(
          phase,
          precision: pointerInputCapabilities.precision,
          viewport: viewport
        )
      }
      .focusable(true, interactions: .edit)
    }
  }

  private func handleDragChange(_ value: DragGesture.Value, viewport: CanvasViewport) {
    let anchor =
      dragAnchor
      ?? viewport.sourcePoint(
        forLocalCell: value.startLocation,
        precision: value.pointer.precision,
        mode: mode
      )
    let current = viewport.sourcePoint(
      forLocalCell: value.location,
      precision: value.pointer.precision,
      mode: mode
    )

    if dragAnchor == nil {
      dragAnchor = anchor
      model.beginCanvasDrag(at: anchor)
    }
    model.updateCanvasDrag(startingAt: anchor, from: lastDragPoint, to: current)
    lastDragPoint = current
    hover = current
    refresh()
  }

  private func handleDragEnd(_ value: DragGesture.Value, viewport: CanvasViewport) {
    let anchor =
      dragAnchor
      ?? viewport.sourcePoint(
        forLocalCell: value.startLocation,
        precision: value.pointer.precision,
        mode: mode
      )
    let current = viewport.sourcePoint(
      forLocalCell: value.location,
      precision: value.pointer.precision,
      mode: mode
    )

    model.endCanvasDrag(startingAt: anchor, from: lastDragPoint, to: current)
    dragAnchor = nil
    lastDragPoint = nil
    hover = current
    refresh()
  }

  private func updateHover(
    _ phase: HoverPhase,
    precision: PointerPrecision,
    viewport: CanvasViewport
  ) {
    switch phase {
    case .entered(let location), .moved(let location):
      hover = viewport.sourcePoint(
        forLocalCell: location,
        precision: precision,
        mode: mode
      )
    case .exited:
      hover = nil
    }
  }
}

private func canvasPointerTargetPath(_ size: CellSize) -> Path {
  let width = max(0, size.width)
  let height = max(0, size.height)
  var path = Path()
  guard width > 0, height > 0 else {
    return path
  }
  path.move(to: .zero)
  path.addLine(to: Point(x: Double(width), y: 0))
  path.addLine(to: Point(x: Double(width), y: Double(height)))
  path.addLine(to: Point(x: 0, y: Double(height)))
  path.close()
  return path
}

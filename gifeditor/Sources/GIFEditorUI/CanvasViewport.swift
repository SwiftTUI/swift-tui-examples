import GIFEditorCore
import SwiftTUI

/// The zoom steps the editor offers.
///
/// Integer multiples only: `Canvas.pixelGrid` maps *logical* pixels to cells
/// 1:1 (`.fullCell`) or 2:1 vertically (`.verticalHalfBlock`), so a
/// non-integer zoom would have to invent sub-pixel colours the terminal
/// cannot show. `fit` is the other direction — an integer *downsample* that
/// squeezes the whole canvas into the available cells so you can navigate a
/// large document before diving back in at `x1`/`x2`/`x4`.
enum CanvasZoomLevel: Equatable, Sendable, CaseIterable {
  case fit
  case x1
  case x2
  case x4

  /// Ordered coarse → fine, so `-` walks left and `=` walks right.
  static let ascending: [CanvasZoomLevel] = [.fit, .x1, .x2, .x4]

  /// Short status-strip label.
  var label: String {
    switch self {
    case .fit: "fit"
    case .x1: "1x"
    case .x2: "2x"
    case .x4: "4x"
    }
  }

  var next: CanvasZoomLevel {
    let ordered = Self.ascending
    guard let index = ordered.firstIndex(of: self) else { return .x1 }
    return ordered[min(index + 1, ordered.count - 1)]
  }

  var previous: CanvasZoomLevel {
    let ordered = Self.ascending
    guard let index = ordered.firstIndex(of: self) else { return .x1 }
    return ordered[max(index - 1, 0)]
  }
}

/// How source pixels map onto the logical pixels handed to `Canvas.pixelGrid`.
///
/// Exactly one of the two directions is ever active: magnifying replicates one
/// source pixel into a `factor × factor` block of logical pixels, reducing
/// samples every `stride`-th source pixel into a single logical pixel. Keeping
/// them in one enum (rather than two independent integers) makes the illegal
/// "magnify *and* reduce" state unrepresentable.
enum CanvasZoom: Equatable, Sendable {
  /// Each source pixel becomes a `factor × factor` block of logical pixels.
  case magnified(Int)
  /// Every `stride`-th source pixel becomes one logical pixel.
  case reduced(Int)

  /// Logical pixels emitted per source pixel along each axis. Always ≥ 1.
  var magnification: Int {
    switch self {
    case .magnified(let factor): max(1, factor)
    case .reduced: 1
    }
  }

  /// Source pixels collapsed into one logical pixel along each axis. Always ≥ 1.
  var sampleStride: Int {
    switch self {
    case .magnified: 1
    case .reduced(let stride): max(1, stride)
    }
  }
}

/// Everything outside the viewport's own state that its commands need: the
/// document extent, the measured cell budget of the canvas region, and the
/// active grid mode.
///
/// Bundled into one value so the keyboard commands can take a single
/// parameter instead of threading three unrelated arguments through every
/// mutator.
struct CanvasViewportContext: Equatable, Sendable {
  var canvasSize: GIFEditorCore.PixelSize
  var cellBudget: CellSize
  var mode: CanvasPixelGridMode

  init(
    canvasSize: GIFEditorCore.PixelSize,
    cellBudget: CellSize,
    mode: CanvasPixelGridMode
  ) {
    self.canvasSize = canvasSize
    self.cellBudget = cellBudget
    self.mode = mode
  }

  /// Logical pixels the region can show, i.e. the cell budget expanded by the
  /// grid mode's vertical subdivision.
  var logicalBudget: GIFEditorCore.PixelSize {
    GIFEditorCore.PixelSize(
      width: max(1, cellBudget.width),
      height: max(1, cellBudget.height) * CanvasViewport.ySubdivisions(for: mode)
    )
  }
}

/// The `@State`-owned half of the canvas viewport: what the *user* chose.
///
/// The resolved extent is deliberately not stored here. It is a function of
/// the cell budget the layout system hands the canvas region, which is only
/// known inside a `GeometryReader`; storing it would mean writing `@State`
/// from inside layout. Instead this value stays small and authored, and
/// `resolved(in:)` derives the concrete ``CanvasViewport`` on every render.
struct CanvasViewportState: Equatable, Sendable {
  var level: CanvasZoomLevel
  /// Top-left source pixel the user has panned to. Clamped on resolve, so an
  /// out-of-range value here is harmless rather than a rendering fault.
  var origin: GIFEditorCore.PixelPoint

  init(
    level: CanvasZoomLevel = .x1,
    origin: GIFEditorCore.PixelPoint = .zero
  ) {
    self.level = level
    self.origin = origin
  }

  /// Cell budget assumed before the first render has measured the real one.
  ///
  /// Only the keyboard commands ever see this: rendering always uses the live
  /// `GeometryProxy` size. A wrong guess therefore costs at most one
  /// mis-sized pan step before the first measurement lands.
  static let fallbackCellBudget = CellSize(width: 32, height: 16)

  func resolved(in context: CanvasViewportContext) -> CanvasViewport {
    CanvasViewport.resolved(level: level, origin: origin, in: context)
  }

  /// Moves the visible rect by `dx`/`dy` half-viewports.
  mutating func pan(dx: Int, dy: Int, in context: CanvasViewportContext) {
    let viewport = resolved(in: context)
    let stepX = max(1, viewport.visibleSize.width / 2)
    let stepY = max(1, viewport.visibleSize.height / 2)
    origin = CanvasViewport.clampedOrigin(
      GIFEditorCore.PixelPoint(
        x: viewport.origin.x + dx * stepX,
        y: viewport.origin.y + dy * stepY
      ),
      visibleSize: viewport.visibleSize,
      canvasSize: context.canvasSize
    )
  }

  /// Steps one zoom level finer, re-anchoring on the cursor.
  mutating func zoomIn(cursor: GIFEditorCore.PixelPoint, in context: CanvasViewportContext) {
    setLevel(level.next, cursor: cursor, in: context)
  }

  /// Steps one zoom level coarser, re-anchoring on the cursor.
  mutating func zoomOut(cursor: GIFEditorCore.PixelPoint, in context: CanvasViewportContext) {
    setLevel(level.previous, cursor: cursor, in: context)
  }

  mutating func fitToWindow(cursor: GIFEditorCore.PixelPoint, in context: CanvasViewportContext) {
    setLevel(.fit, cursor: cursor, in: context)
  }

  /// Changes zoom and re-centres on the cursor, so a zoom never throws away
  /// the thing the user was looking at.
  mutating func setLevel(
    _ newLevel: CanvasZoomLevel,
    cursor: GIFEditorCore.PixelPoint,
    in context: CanvasViewportContext
  ) {
    level = newLevel
    let visible = CanvasViewport.resolved(level: newLevel, origin: origin, in: context).visibleSize
    origin = CanvasViewport.clampedOrigin(
      GIFEditorCore.PixelPoint(
        x: cursor.x - visible.width / 2,
        y: cursor.y - visible.height / 2
      ),
      visibleSize: visible,
      canvasSize: context.canvasSize
    )
  }

  /// Scrolls the minimum amount that brings `cursor` back into view.
  ///
  /// Called after every cursor-moving key so keyboard drawing can never paint
  /// off-screen. Minimum-scroll (rather than re-centring) keeps the canvas
  /// still while the cursor walks around inside the visible rect, which is the
  /// behaviour every text editor has trained users to expect.
  mutating func follow(cursor: GIFEditorCore.PixelPoint, in context: CanvasViewportContext) {
    let viewport = resolved(in: context)
    var next = viewport.origin
    let visible = viewport.visibleSize
    if cursor.x < next.x {
      next.x = cursor.x
    } else if cursor.x >= next.x + visible.width {
      next.x = cursor.x - visible.width + 1
    }
    if cursor.y < next.y {
      next.y = cursor.y
    } else if cursor.y >= next.y + visible.height {
      next.y = cursor.y - visible.height + 1
    }
    origin = CanvasViewport.clampedOrigin(
      next,
      visibleSize: visible,
      canvasSize: context.canvasSize
    )
  }
}

/// Mutable carrier for the canvas region's measured cell budget.
///
/// The budget is only knowable inside a `GeometryReader`, which realizes its
/// content *during layout*. Writing `@State` from there would re-enter the
/// layout pass it was measured in, so the measurement lands in this reference
/// box instead — the same Reference Box pattern `EditorView` already uses to
/// hold its view model.
///
/// Rendering never reads this: it uses the live `GeometryProxy` and is
/// therefore always exact. Only the keyboard pan/zoom/follow commands read it,
/// and they run one frame after the measurement that fed it, so the worst case
/// is a single mis-sized pan immediately after a terminal resize.
@MainActor
final class CanvasCellBudgetBox {
  private var measured: CellSize?

  init() {}

  func record(_ size: CellSize) {
    measured = size
  }

  var current: CellSize {
    measured ?? CanvasViewportState.fallbackCellBudget
  }
}

/// The viewport commands the key bindings drive.
///
/// Bundled as closures so `EditorKeyBindings` never has to know that the
/// viewport lives in an `EditorView` `@State` — or that the cell budget it
/// needs comes from a box written during layout.
struct CanvasViewportCommands: Sendable {
  var zoomIn: @MainActor @Sendable () -> Void
  var zoomOut: @MainActor @Sendable () -> Void
  var fitToWindow: @MainActor @Sendable () -> Void
  /// Pans by whole half-viewports along each axis.
  var pan: @MainActor @Sendable (Int, Int) -> Void
  /// Re-scrolls so the model's cursor is inside the visible rect.
  var followCursor: @MainActor @Sendable () -> Void

  /// No-op commands, for the binding call sites that have no viewport to
  /// drive (tests and harnesses). Keeps those call sites from having to
  /// invent a viewport just to press an unrelated key.
  static let inert = CanvasViewportCommands(
    zoomIn: {},
    zoomOut: {},
    fitToWindow: {},
    pan: { _, _ in },
    followCursor: {}
  )
}

/// A resolved window onto the canvas: which source pixels are visible, at what
/// scale, and the three mappings that connect source pixels, the logical pixel
/// array handed to `Canvas.pixelGrid`, and terminal cells.
///
/// Everything that used to hardcode "one source pixel is one logical pixel,
/// and half-block halves the row index" routes through here instead. The
/// renderer culls in *source* space (``sourceRect()``) and only then
/// replicates, so per-render cost is bounded by the cell budget rather than by
/// the canvas area.
struct CanvasViewport: Equatable, Sendable {
  var zoom: CanvasZoom
  /// Top-left visible source pixel.
  var origin: GIFEditorCore.PixelPoint
  /// Visible extent measured in *source* pixels.
  var visibleSize: GIFEditorCore.PixelSize

  init(
    zoom: CanvasZoom,
    origin: GIFEditorCore.PixelPoint,
    visibleSize: GIFEditorCore.PixelSize
  ) {
    self.zoom = zoom
    self.origin = origin
    self.visibleSize = visibleSize
  }

  /// The identity viewport: whole canvas, 1:1. Rendering through this is
  /// byte-identical to the pre-viewport canvas, which is what makes it a
  /// usable default for call sites that do not zoom (tests, thumbnails).
  static func wholeCanvas(_ size: GIFEditorCore.PixelSize) -> CanvasViewport {
    CanvasViewport(zoom: .magnified(1), origin: .zero, visibleSize: size)
  }

  static func ySubdivisions(for mode: CanvasPixelGridMode) -> Int {
    switch mode {
    case .fullCell: 1
    case .verticalHalfBlock: 2
    }
  }

  // MARK: - Resolution

  static func resolved(
    level: CanvasZoomLevel,
    origin: GIFEditorCore.PixelPoint,
    in context: CanvasViewportContext
  ) -> CanvasViewport {
    let canvasSize = context.canvasSize
    let budget = context.logicalBudget
    let zoom = resolvedZoom(level: level, canvasSize: canvasSize, logicalBudget: budget)
    let visibleSize = GIFEditorCore.PixelSize(
      width: visibleExtent(
        budget: budget.width,
        canvas: canvasSize.width,
        zoom: zoom
      ),
      height: visibleExtent(
        budget: budget.height,
        canvas: canvasSize.height,
        zoom: zoom
      )
    )
    return CanvasViewport(
      zoom: zoom,
      origin: clampedOrigin(origin, visibleSize: visibleSize, canvasSize: canvasSize),
      visibleSize: visibleSize
    )
  }

  private static func resolvedZoom(
    level: CanvasZoomLevel,
    canvasSize: GIFEditorCore.PixelSize,
    logicalBudget: GIFEditorCore.PixelSize
  ) -> CanvasZoom {
    switch level {
    case .x1: return .magnified(1)
    case .x2: return .magnified(2)
    case .x4: return .magnified(4)
    case .fit:
      // Smallest integer stride that fits the whole canvas. Bounded by the
      // canvas extent so a zero-sized budget cannot spin.
      let limit = max(1, max(canvasSize.width, canvasSize.height))
      var stride = 1
      while stride < limit {
        let width = (canvasSize.width + stride - 1) / stride
        let height = (canvasSize.height + stride - 1) / stride
        if width <= logicalBudget.width && height <= logicalBudget.height {
          break
        }
        stride += 1
      }
      return stride <= 1 ? .magnified(1) : .reduced(stride)
    }
  }

  private static func visibleExtent(
    budget: Int,
    canvas: Int,
    zoom: CanvasZoom
  ) -> Int {
    let unclamped =
      switch zoom {
      case .magnified(let factor): budget / max(1, factor)
      case .reduced(let stride): budget * max(1, stride)
      }
    // At least one source pixel stays visible even when the region is
    // narrower than a single magnified pixel; an empty grid would make the
    // canvas silently disappear instead of degrading.
    return max(1, min(canvas, unclamped))
  }

  static func clampedOrigin(
    _ origin: GIFEditorCore.PixelPoint,
    visibleSize: GIFEditorCore.PixelSize,
    canvasSize: GIFEditorCore.PixelSize
  ) -> GIFEditorCore.PixelPoint {
    GIFEditorCore.PixelPoint(
      x: min(max(0, origin.x), max(0, canvasSize.width - visibleSize.width)),
      y: min(max(0, origin.y), max(0, canvasSize.height - visibleSize.height))
    )
  }

  // MARK: - Extents

  /// The visible rect in source-pixel space. The renderer iterates this, and
  /// only this — nothing outside it is ever resolved to a colour.
  func sourceRect() -> PixelRect {
    PixelRect(origin: origin, size: visibleSize)
  }

  /// Size of the logical pixel array handed to `Canvas.pixelGrid`.
  ///
  /// This is the cull-then-scale invariant in one expression: it is derived
  /// from ``visibleSize`` (already clipped to the cell budget) and never from
  /// the canvas extent.
  var logicalSize: GIFEditorCore.PixelSize {
    switch zoom {
    case .magnified(let factor):
      let z = max(1, factor)
      return GIFEditorCore.PixelSize(
        width: visibleSize.width * z,
        height: visibleSize.height * z
      )
    case .reduced(let stride):
      let d = max(1, stride)
      return GIFEditorCore.PixelSize(
        width: max(1, (visibleSize.width + d - 1) / d),
        height: max(1, (visibleSize.height + d - 1) / d)
      )
    }
  }

  /// Terminal-cell extent of the rendered grid.
  func cellSize(mode: CanvasPixelGridMode) -> CellSize {
    let logical = logicalSize
    return CellSize(width: logical.width, height: mode.cellHeight(for: logical.height))
  }

  func contains(_ point: GIFEditorCore.PixelPoint) -> Bool {
    sourceRect().contains(point)
  }

  // MARK: - source ↔ logical

  /// The source pixel a logical pixel samples.
  func sourcePoint(forLogicalX x: Int, y: Int) -> GIFEditorCore.PixelPoint {
    let magnification = zoom.magnification
    let stride = zoom.sampleStride
    return GIFEditorCore.PixelPoint(
      x: origin.x + (x / magnification) * stride,
      y: origin.y + (y / magnification) * stride
    )
  }

  /// Top-left logical pixel of the block a source pixel occupies.
  func logicalOrigin(forSource point: GIFEditorCore.PixelPoint) -> GIFEditorCore.PixelPoint {
    let magnification = zoom.magnification
    let stride = zoom.sampleStride
    return GIFEditorCore.PixelPoint(
      x: ((point.x - origin.x) / stride) * magnification,
      y: ((point.y - origin.y) / stride) * magnification
    )
  }

  // MARK: - source → cell

  /// The cell rectangle one source pixel paints.
  ///
  /// At `.verticalHalfBlock` and `1×` this is a *half* cell tall, which is why
  /// it is expressed as a `CellRect` of height 1 whose glyph covers only one
  /// half — the overlay picks the half via ``halfBlockGlyphIsTop(forLogicalY:)``.
  func cellRect(forSource point: GIFEditorCore.PixelPoint, mode: CanvasPixelGridMode) -> CellRect {
    let subdivisions = Self.ySubdivisions(for: mode)
    let logical = logicalOrigin(forSource: point)
    let blockWidth = zoom.magnification
    let blockHeight = zoom.magnification
    let topCell = floorDiv(logical.y, subdivisions)
    let bottomCell = floorDiv(logical.y + blockHeight - 1, subdivisions)
    return CellRect(
      origin: CellPoint(x: logical.x, y: topCell),
      size: CellSize(width: blockWidth, height: bottomCell - topCell + 1)
    )
  }

  /// Top-left cell of a source pixel's block. Replaces the old hardcoded
  /// `point.y / 2`.
  func cellPoint(forSource point: GIFEditorCore.PixelPoint, mode: CanvasPixelGridMode) -> CellPoint
  {
    cellRect(forSource: point, mode: mode).origin
  }

  /// Whether a logical row lands on the upper half of its cell. Meaningless in
  /// `.fullCell`, where the caller ignores it.
  func halfBlockGlyphIsTop(forLogicalY y: Int) -> Bool {
    y.isMultiple(of: 2)
  }

  // MARK: - cell → source (the pointer inverse)

  /// Maps a pointer location in the canvas surface's local cell space back to
  /// the source pixel under it.
  ///
  /// Replaces the free `canvasPixelPoint(forLocalCell:precision:mode:size:)`.
  /// The mapping is `origin + floor(local / Z)` with the half-block vertical
  /// subdivision folded into the y term, and a clamp into the visible rect so
  /// a pointer that leaves the surface still yields an addressable pixel.
  func sourcePoint(
    forLocalCell point: Point,
    precision: PointerPrecision,
    mode: CanvasPixelGridMode
  ) -> GIFEditorCore.PixelPoint {
    let location = Self.pointerLocation(point, precision: precision)
    let logical = logicalSize
    let subdivisions = Self.ySubdivisions(for: mode)
    let logicalX = Self.logicalIndex(location.x, subdivisions: 1, count: logical.width)
    let logicalY = Self.logicalIndex(
      location.y,
      subdivisions: subdivisions,
      count: logical.height
    )
    return sourcePoint(forLogicalX: logicalX, y: logicalY)
  }

  /// The local-cell point that addresses a given logical pixel — the inverse
  /// direction, used by the pointer round-trip tests and by nothing in
  /// production. Returns the logical pixel's top-left corner.
  func localCellPoint(forLogicalX x: Int, y: Int, mode: CanvasPixelGridMode) -> Point {
    let subdivisions = Self.ySubdivisions(for: mode)
    return Point(x: Double(x), y: Double(y) / Double(subdivisions))
  }

  private static func pointerLocation(_ point: Point, precision: PointerPrecision) -> Point {
    switch precision {
    case .cell:
      // Cell-only hosts cannot address a half row, so anchor on the cell's
      // own origin rather than letting a mid-cell coordinate round downward
      // into whichever half the host happened to report.
      Point(point.containingCell)
    case .subCell:
      point
    }
  }

  private static func logicalIndex(
    _ value: Double,
    subdivisions: Int,
    count: Int
  ) -> Int {
    guard count > 1 else {
      return 0
    }
    let scaled = (value * Double(subdivisions)).rounded(.down)
    guard scaled.isFinite else {
      return scaled.sign == .minus || scaled.isNaN ? 0 : count - 1
    }
    return min(max(0, Int(scaled)), count - 1)
  }
}

/// Floor division that keeps negative logical rows on the correct cell.
///
/// `-1 / 2` is `0` in Swift, which would put a logical row above the grid on
/// the same cell as row `0` and let an off-surface pointer paint the top row.
private func floorDiv(_ value: Int, _ divisor: Int) -> Int {
  let quotient = value / divisor
  return (value % divisor != 0 && (value < 0) != (divisor < 0)) ? quotient - 1 : quotient
}

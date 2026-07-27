import Foundation

/// The core editing tools, plus eyedropper as a read-only picker.
public enum EditorTool: String, Hashable, Sendable, CaseIterable, Codable {
  case pen
  case eraser
  case fill
  case gradient
  case marquee
  case select
  case eyedropper

  public var label: String {
    switch self {
    case .pen: return "Pen"
    case .eraser: return "Eraser"
    case .fill: return "Fill"
    case .gradient: return "Gradient"
    case .marquee: return "Marquee"
    case .select: return "Select"
    case .eyedropper: return "Eyedropper"
    }
  }

  /// 1-letter glyph used by the keyboard help screen — mirrors the
  /// keypress shortcut that selects the tool (`P` for pen, `E` for
  /// eraser, etc.). This stays in place for the help table even though
  /// the redesigned tool dock uses richer unicode icons via
  /// ``iconGlyph`` instead.
  public var glyph: String {
    switch self {
    case .pen: return "P"
    case .eraser: return "E"
    case .fill: return "B"
    case .gradient: return "G"
    case .marquee: return "M"
    case .select: return "V"
    case .eyedropper: return "I"
    }
  }

  /// Single-cell unicode icon used by the redesigned tool dock. Picked
  /// from the Basic Multilingual Plane so every cell is exactly 1
  /// terminal column wide in Apple Terminal, iTerm2, Ghostty, and
  /// Kitty — which keeps the half-block canvas grid aligned with the
  /// surrounding chrome.
  public var iconGlyph: String {
    switch self {
    case .pen: return "✎"  // U+270E pencil
    case .eraser: return "⌫"  // U+232B erase to the left
    case .fill: return "⬢"  // U+2B22 solid hexagon
    case .gradient: return "◐"  // U+25D0 half-filled circle
    case .marquee: return "▭"  // U+25AD rectangle outline
    case .select: return "✥"  // U+2725 four club-spoked asterisk
    case .eyedropper: return "⊙"  // U+2299 circled dot
    }
  }
}

/// A rectangular selection. Tools that respect selection (fill,
/// gradient) are clipped to it; tools that don't (pen, eraser) ignore
/// it.
public struct Selection: Hashable, Sendable, Codable {
  public var rect: PixelRect

  public init(rect: PixelRect) {
    self.rect = rect
  }
}

/// Implementations of the editor tools. Every function takes a buffer
/// and returns the edited buffer — that lets the view model wrap each
/// edit in an undoable command without the tool itself knowing about
/// undo. Tools never throw; out-of-range arguments are clamped/ignored.
public enum ToolOps {

  /// Pen: write `color` at `point`.
  public static func pen(
    on buffer: PixelBuffer,
    at point: PixelPoint,
    color: PaletteIndex
  ) -> PixelBuffer {
    var copy = buffer
    copy[point] = color
    return copy
  }

  /// Eraser: clear the pixel at `point` to transparent (`nil`).
  public static func erase(
    on buffer: PixelBuffer,
    at point: PixelPoint
  ) -> PixelBuffer {
    var copy = buffer
    copy[point] = nil
    return copy
  }

  /// 4-connected flood fill starting at `point`. Replaces every cell
  /// matching the seed value with `color`. Confined to `selection` when
  /// non-nil.
  public static func fill(
    on buffer: PixelBuffer,
    at point: PixelPoint,
    color: PaletteIndex,
    selection: Selection? = nil
  ) -> PixelBuffer {
    guard buffer.size.contains(point) else { return buffer }
    let seed = buffer[point]
    if seed == color { return buffer }
    var copy = buffer
    var stack: [PixelPoint] = [point]
    let canvas = buffer.bounds
    guard let bounds = (selection?.rect ?? canvas).intersected(with: canvas)
    else { return buffer }
    while let p = stack.popLast() {
      if !bounds.contains(p) { continue }
      if copy[p] != seed { continue }
      copy.setUnchecked(p, to: color)
      stack.append(PixelPoint(x: p.x - 1, y: p.y))
      stack.append(PixelPoint(x: p.x + 1, y: p.y))
      stack.append(PixelPoint(x: p.x, y: p.y - 1))
      stack.append(PixelPoint(x: p.x, y: p.y + 1))
    }
    return copy
  }

  /// Linear gradient between `startColor` and `endColor` along the line
  /// from `start` to `end`, written into the layer (or selection if
  /// non-nil) by nearest-color matching against `palette`. The encoder
  /// is index-based, so we project each cell's parametric `t` onto the
  /// nearest palette entry of the interpolated RGB color.
  public static func gradient(
    on buffer: PixelBuffer,
    from start: PixelPoint,
    to end: PixelPoint,
    startColor: EditorColor,
    endColor: EditorColor,
    palette: ColorPalette,
    selection: Selection? = nil
  ) -> PixelBuffer {
    var copy = buffer
    let dx = Double(end.x - start.x)
    let dy = Double(end.y - start.y)
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return copy }

    let canvas = buffer.bounds
    guard let bounds = (selection?.rect ?? canvas).intersected(with: canvas)
    else { return copy }

    for y in bounds.minY..<bounds.maxY {
      for x in bounds.minX..<bounds.maxX {
        let px = Double(x - start.x)
        let py = Double(y - start.y)
        let raw = (px * dx + py * dy) / lengthSquared
        let t = max(0.0, min(1.0, raw))
        let blended = EditorColor(
          red: lerp(startColor.red, endColor.red, t),
          green: lerp(startColor.green, endColor.green, t),
          blue: lerp(startColor.blue, endColor.blue, t),
          alpha: lerp(startColor.alpha, endColor.alpha, t)
        )
        let idx = palette.nearestIndex(to: blended)
        copy.setUnchecked(PixelPoint(x: x, y: y), to: idx)
      }
    }
    return copy
  }

  /// Bresenham line — used by pen/eraser strokes when consecutive
  /// pointer samples would otherwise leave gaps. Pass `nil` to clear.
  ///
  /// `thickness` stamps a centered `thickness × thickness` square
  /// (pencil-style square brush) at every Bresenham step, so a thick
  /// stroke is gap-free even on diagonals. `thickness == 1` paints a
  /// single pixel per step (the original behavior). When `selection` is
  /// non-nil, the stamp is clipped to the selection rect.
  public static func line(
    on buffer: PixelBuffer,
    from a: PixelPoint,
    to b: PixelPoint,
    color: PaletteIndex?,
    thickness: Int = 1,
    selection: Selection? = nil
  ) -> PixelBuffer {
    var copy = buffer
    drawLine(
      into: &copy,
      from: a,
      to: b,
      color: color,
      diameter: max(1, thickness),
      bounds: selection?.rect
    )
    return copy
  }

  /// The Bresenham walk behind ``line(on:from:to:color:thickness:selection:)``,
  /// stamping in place so the shape tools can lay several strokes into
  /// one buffer without copying it per stroke.
  private static func drawLine(
    into buffer: inout PixelBuffer,
    from a: PixelPoint,
    to b: PixelPoint,
    color: PaletteIndex?,
    diameter: Int,
    bounds: PixelRect?
  ) {
    var x0 = a.x
    var y0 = a.y
    let x1 = b.x
    let y1 = b.y
    let dx = abs(x1 - x0)
    let sx = x0 < x1 ? 1 : -1
    let dy = -abs(y1 - y0)
    let sy = y0 < y1 ? 1 : -1
    var error = dx + dy
    while true {
      stamp(
        into: &buffer,
        at: PixelPoint(x: x0, y: y0),
        diameter: diameter,
        color: color,
        bounds: bounds
      )
      if x0 == x1 && y0 == y1 { break }
      let e2 = 2 * error
      if e2 >= dy {
        if x0 == x1 { break }
        error += dy
        x0 += sx
      }
      if e2 <= dx {
        if y0 == y1 { break }
        error += dx
        y0 += sy
      }
    }
  }

  /// Stamps a centered `diameter × diameter` square of `color` into
  /// `buffer`, clipped to `bounds` when non-nil. For even diameters the
  /// square is biased one cell down/right of the geometric center (so a
  /// 2×2 stamp at (3,3) covers (3,3)…(4,4)), keeping every diameter
  /// stamping at least one pixel exactly at the requested center.
  private static func stamp(
    into buffer: inout PixelBuffer,
    at center: PixelPoint,
    diameter: Int,
    color: PaletteIndex?,
    bounds: PixelRect?
  ) {
    let lowOffset = (diameter - 1) / 2
    let highOffset = diameter / 2
    for dy in -lowOffset...highOffset {
      let y = center.y + dy
      for dx in -lowOffset...highOffset {
        let x = center.x + dx
        if let bounds, !bounds.contains(x: x, y: y) { continue }
        buffer[PixelPoint(x: x, y: y)] = color
      }
    }
  }

  /// Copies the rectangular region of `buffer` selected by `rect` into
  /// a new buffer the size of the rect. Returns `nil` if the rect is
  /// fully outside the buffer.
  public static func copy(from buffer: PixelBuffer, rect: PixelRect) -> PixelBuffer? {
    buffer.cropped(to: rect)
  }

  /// Pastes `clipboard` onto `buffer` with the clipboard's top-left at
  /// `origin`. Transparent (nil) clipboard pixels do not overwrite.
  public static func paste(
    onto buffer: PixelBuffer,
    clipboard: PixelBuffer,
    at origin: PixelPoint
  ) -> PixelBuffer {
    var copy = buffer
    copy.stamp(clipboard, at: origin, respectingTransparency: true)
    return copy
  }

  /// Moves the pixels in `rect` by the requested offset. When `rect`
  /// is nil, the whole layer moves. Source cells are cleared first,
  /// then opaque pixels from the original buffer are stamped at the
  /// destination, so overlapping moves are evaluated all at once.
  public static func move(
    on buffer: PixelBuffer,
    rect: PixelRect? = nil,
    byX dx: Int,
    y dy: Int
  ) -> PixelBuffer {
    guard dx != 0 || dy != 0 else {
      return buffer
    }

    let canvas = buffer.bounds
    guard let source = (rect ?? canvas).intersected(with: canvas) else {
      return buffer
    }

    var copy = buffer
    for y in source.minY..<source.maxY {
      for x in source.minX..<source.maxX {
        copy.setUnchecked(PixelPoint(x: x, y: y), to: nil)
      }
    }

    for y in source.minY..<source.maxY {
      for x in source.minX..<source.maxX {
        let sourcePoint = PixelPoint(x: x, y: y)
        guard let value = buffer[sourcePoint] else {
          continue
        }

        let destination = PixelPoint(x: x + dx, y: y + dy)
        if buffer.size.contains(destination) {
          copy.setUnchecked(destination, to: value)
        }
      }
    }
    return copy
  }

  // MARK: - Shapes

  /// Axis-aligned rectangle spanning the two corner points, inclusive of
  /// both. Pass `nil` for `color` to erase instead of paint.
  ///
  /// `a` and `b` are corners rather than an origin/extent pair, so the
  /// operation is order-independent — dragging bottom-right to top-left
  /// paints exactly the cells a top-left to bottom-right drag would.
  /// A degenerate drag (`a == b`) is a 1×1 rect, i.e. a single pixel.
  ///
  /// `filled` swaps the hollow outline for a solid block. Outline
  /// strokes reuse the centered square brush from
  /// ``line(on:from:to:color:thickness:selection:)``, so a `thickness`
  /// above 1 straddles the edge exactly as a freehand stroke along that
  /// edge would — half the brush sits outside the rect. `thickness` has
  /// no meaning for a filled rect and is ignored there. When
  /// `selection` is non-nil, every write is clipped to its rect.
  public static func rectangle(
    on buffer: PixelBuffer,
    from a: PixelPoint,
    to b: PixelPoint,
    color: PaletteIndex?,
    filled: Bool = false,
    thickness: Int = 1,
    selection: Selection? = nil
  ) -> PixelBuffer {
    let rect = drawingRect(from: a, to: b, in: buffer.size)
    var copy = buffer

    if filled {
      guard let clip = clipRect(of: buffer, selection: selection) else { return buffer }
      for y in rect.minY..<rect.maxY {
        fillSpan(
          into: &copy, y: y, from: rect.minX, through: rect.maxX - 1,
          color: color, clip: clip
        )
      }
      return copy
    }

    let diameter = max(1, thickness)
    let bounds = selection?.rect
    let left = rect.minX
    let right = rect.maxX - 1
    let top = rect.minY
    let bottom = rect.maxY - 1
    let corners = [
      PixelPoint(x: left, y: top),
      PixelPoint(x: right, y: top),
      PixelPoint(x: right, y: bottom),
      PixelPoint(x: left, y: bottom),
    ]
    for index in corners.indices {
      drawLine(
        into: &copy,
        from: corners[index],
        to: corners[(index + 1) % corners.count],
        color: color,
        diameter: diameter,
        bounds: bounds
      )
    }
    return copy
  }

  /// Ellipse inscribed in the rect spanned by the two corner points,
  /// rasterised with an integer midpoint (Bresenham) sweep. Pass `nil`
  /// for `color` to erase instead of paint.
  ///
  /// Like ``rectangle(on:from:to:color:filled:thickness:selection:)``
  /// the corners are order-independent, a degenerate drag is a single
  /// pixel, and a one-pixel-wide or one-pixel-tall box collapses to a
  /// straight run. The sweep emits its points as mirrored quadruples
  /// about the box centre, so the painted set is exactly invariant under
  /// both horizontal and vertical mirroring of the box — no
  /// floating-point sampling, no lopsided edge. `filled` spans each row
  /// between the outline's extremes, which inherits the same symmetry.
  public static func ellipse(
    on buffer: PixelBuffer,
    from a: PixelPoint,
    to b: PixelPoint,
    color: PaletteIndex?,
    filled: Bool = false,
    thickness: Int = 1,
    selection: Selection? = nil
  ) -> PixelBuffer {
    let rect = drawingRect(from: a, to: b, in: buffer.size)
    let outline = ellipseOutlinePoints(in: rect)
    var copy = buffer

    if filled {
      guard let clip = clipRect(of: buffer, selection: selection) else { return buffer }
      let rows = rect.size.height
      var lowX = [Int](repeating: Int.max, count: rows)
      var highX = [Int](repeating: Int.min, count: rows)
      for point in outline {
        let row = point.y - rect.minY
        guard row >= 0, row < rows else { continue }
        lowX[row] = min(lowX[row], point.x)
        highX[row] = max(highX[row], point.x)
      }
      for row in 0..<rows where lowX[row] <= highX[row] {
        fillSpan(
          into: &copy, y: rect.minY + row, from: lowX[row], through: highX[row],
          color: color, clip: clip
        )
      }
      return copy
    }

    let diameter = max(1, thickness)
    let bounds = selection?.rect
    for point in outline {
      stamp(into: &copy, at: point, diameter: diameter, color: color, bounds: bounds)
    }
    return copy
  }

  // MARK: - Transforms

  /// Mirrors `rect` (the whole buffer when nil) about its vertical
  /// centre line. Transparent cells move like any other value, so a
  /// flipped-then-flipped-again region is the original region.
  public static func flipHorizontal(
    on buffer: PixelBuffer,
    rect: PixelRect? = nil
  ) -> PixelBuffer {
    flip(on: buffer, rect: rect, horizontally: true)
  }

  /// Mirrors `rect` (the whole buffer when nil) about its horizontal
  /// centre line. Transparent cells move like any other value.
  public static func flipVertical(
    on buffer: PixelBuffer,
    rect: PixelRect? = nil
  ) -> PixelBuffer {
    flip(on: buffer, rect: rect, horizontally: false)
  }

  /// Rotates `rect` (the whole buffer when nil) a quarter turn
  /// clockwise about the centre of that region. See
  /// ``rotateCounterClockwise(on:rect:)`` for the non-square rule.
  public static func rotateClockwise(
    on buffer: PixelBuffer,
    rect: PixelRect? = nil
  ) -> PixelBuffer {
    rotateQuarterTurn(on: buffer, rect: rect, clockwise: true)
  }

  /// Rotates `rect` (the whole buffer when nil) a quarter turn
  /// counter-clockwise about the centre of that region.
  ///
  /// **Non-square regions.** The buffer has a fixed size, so a quarter
  /// turn of a `w × h` region would need an `h × w` region to land in.
  /// Rather than refusing the edit, the rule is uniform for every
  /// region: *rotate about the region's centre and clip*. Pixels that
  /// turn past the region edge are dropped, and cells inside the region
  /// that nothing rotates onto are cleared to transparent. The
  /// alternative — rejecting non-square selections — would also reject
  /// a whole-canvas rotate on any non-square canvas, which is the one
  /// case users reach for most.
  ///
  /// Consequences worth knowing:
  ///
  /// * A square region rotates losslessly: four clockwise turns are the
  ///   identity, and a counter-clockwise turn undoes a clockwise one.
  /// * A non-square region loses the pixels that turn past its edge, so
  ///   the operation is not self-inverse — only the undo stack restores
  ///   them.
  /// * When `w + h` is odd the region centre falls on a half cell. The
  ///   destination is then biased one cell down/right, the same bias
  ///   the even-diameter square brush in
  ///   ``line(on:from:to:color:thickness:selection:)`` already uses.
  public static func rotateCounterClockwise(
    on buffer: PixelBuffer,
    rect: PixelRect? = nil
  ) -> PixelBuffer {
    rotateQuarterTurn(on: buffer, rect: rect, clockwise: false)
  }

  /// Clears `rect` (the whole buffer when nil) to transparent — the
  /// delete half of *delete selection*, and the second half of a cut
  /// once ``copy(from:rect:)`` has taken the clipboard snapshot. Kept
  /// separate so the view model can record one undoable edit for a cut
  /// and reuse the same op for a plain delete.
  public static func clear(
    on buffer: PixelBuffer,
    rect: PixelRect? = nil
  ) -> PixelBuffer {
    let canvas = buffer.bounds
    guard let bounds = (rect ?? canvas).intersected(with: canvas) else { return buffer }
    var copy = buffer
    for y in bounds.minY..<bounds.maxY {
      for x in bounds.minX..<bounds.maxX {
        // `bounds` is intersected with the canvas, so this is in range.
        copy.setUnchecked(PixelPoint(x: x, y: y), to: nil)
      }
    }
    return copy
  }

  // MARK: - Mirror-X symmetry

  /// Reflects `point` across the vertical centre line of `region`: the
  /// column `x` maps to `region.minX + region.maxX - 1 - x`.
  ///
  /// The axis sits *between* columns when the region width is even (no
  /// column maps to itself) and *through* the middle column when it is
  /// odd (that one column maps to itself).
  public static func mirroredX(_ point: PixelPoint, in region: PixelRect) -> PixelPoint {
    PixelPoint(x: region.minX + region.maxX - 1 - point.x, y: point.y)
  }

  /// Mirror-X symmetry stroke: lays the stroke `a`→`b` and, in the same
  /// edit, its reflection across the vertical centre line of
  /// `axisRegion` (the whole canvas when nil).
  ///
  /// This is the symmetry *mode* expressed as a pure function, so the
  /// view model opts in per stroke by calling this instead of
  /// ``line(on:from:to:color:thickness:selection:)`` — no mode flag has
  /// to reach into the tool itself.
  ///
  /// Two details the axis convention forces:
  ///
  /// * **Odd region width.** The centre column maps to itself, so a
  ///   stroke that stays on it reflects onto itself. The mirrored pass
  ///   is skipped in that case; because both passes would paint the
  ///   same cells with the same value, the result is identical either
  ///   way — the skip just makes the self-mapping explicit.
  /// * **Even brush diameter.** The square brush stamps one cell
  ///   down/right of its centre, so the mirrored stroke's centre shifts
  ///   one column left. That makes the two brush footprints exact
  ///   reflections of each other instead of leaving the mirrored one a
  ///   column off.
  public static func mirrorXLine(
    on buffer: PixelBuffer,
    from a: PixelPoint,
    to b: PixelPoint,
    color: PaletteIndex?,
    thickness: Int = 1,
    selection: Selection? = nil,
    axisRegion: PixelRect? = nil
  ) -> PixelBuffer {
    var copy = buffer
    let diameter = max(1, thickness)
    let bounds = selection?.rect
    let region = axisRegion ?? buffer.bounds
    drawLine(
      into: &copy, from: a, to: b, color: color, diameter: diameter, bounds: bounds
    )

    let shift = diameter % 2 == 0 ? 1 : 0
    let mirrorA = PixelPoint(x: mirroredX(a, in: region).x - shift, y: a.y)
    let mirrorB = PixelPoint(x: mirroredX(b, in: region).x - shift, y: b.y)
    guard mirrorA != a || mirrorB != b else { return copy }
    drawLine(
      into: &copy, from: mirrorA, to: mirrorB, color: color, diameter: diameter,
      bounds: bounds
    )
    return copy
  }

  // MARK: - Helpers

  /// How far outside the canvas a shape corner may sit before it is
  /// clamped. Generous enough that no realistic drag reaches it, small
  /// enough that `PixelRect.bounding` and the midpoint-ellipse error
  /// terms — all plain `Int` arithmetic — stay far inside `Int` range.
  /// A corner beyond the clamp is already off-canvas by orders of
  /// magnitude, so clamping it changes nothing visible.
  private static let maxOvershoot = 4096

  /// The canvas, narrowed to `selection` when one is active. `nil` when
  /// the selection lies entirely off-canvas — nothing can be painted.
  private static func clipRect(of buffer: PixelBuffer, selection: Selection?) -> PixelRect? {
    let canvas = buffer.bounds
    guard let selection else { return canvas }
    return selection.rect.intersected(with: canvas)
  }

  /// Bounding rect of two corner points, order-independent, with the
  /// corners first clamped to ``maxOvershoot`` outside the canvas.
  private static func drawingRect(
    from a: PixelPoint,
    to b: PixelPoint,
    in size: PixelSize
  ) -> PixelRect {
    PixelRect.bounding(clamped(a, to: size), clamped(b, to: size))
  }

  private static func clamped(_ point: PixelPoint, to size: PixelSize) -> PixelPoint {
    PixelPoint(
      x: min(max(point.x, -maxOvershoot), size.width + maxOvershoot),
      y: min(max(point.y, -maxOvershoot), size.height + maxOvershoot)
    )
  }

  /// Paints the inclusive run `lowX...highX` on row `y`, trimmed to
  /// `clip`. `clip` is always a sub-rect of the canvas, so the trimmed
  /// run is in range and can be written unchecked.
  private static func fillSpan(
    into buffer: inout PixelBuffer,
    y: Int,
    from lowX: Int,
    through highX: Int,
    color: PaletteIndex?,
    clip: PixelRect
  ) {
    guard y >= clip.minY, y < clip.maxY else { return }
    let low = max(lowX, clip.minX)
    let high = min(highX, clip.maxX - 1)
    guard low <= high else { return }
    for x in low...high {
      buffer.setUnchecked(PixelPoint(x: x, y: y), to: color)
    }
  }

  /// Outline points of the ellipse inscribed in `rect`, from Zingl's
  /// integer rectangular-parameter midpoint ellipse.
  ///
  /// Each iteration emits the same point mirrored into all four
  /// quadrants, and both the x pair and the y pair keep a constant sum
  /// (`minX + maxX - 1` and `minY + maxY - 1`) as they step inward. The
  /// emitted set is therefore closed under horizontal and vertical
  /// mirroring by construction rather than by luck of rounding — which
  /// is the whole reason for a midpoint sweep over sampling
  /// `x²/a² + y²/b² ≤ 1`. Every point lies inside `rect`; callers still
  /// clip to the canvas. Points may repeat on degenerate boxes, which
  /// is harmless for both the stamped and the span-filled paths.
  private static func ellipseOutlinePoints(in rect: PixelRect) -> [PixelPoint] {
    var left = rect.minX
    var right = rect.maxX - 1
    var top = rect.minY
    var bottom = rect.maxY - 1
    let a = right - left  // horizontal diameter − 1
    let b = bottom - top  // vertical diameter − 1
    let oddHeight = b & 1

    var dx = 4 * (1 - a) * b * b
    var dy = 4 * (oddHeight + 1) * a * a
    var error = dx + dy + oddHeight * a * a
    let yStep = 8 * a * a
    let xStep = 8 * b * b

    top += (b + 1) / 2  // start on the vertical centre row(s)
    bottom = top - oddHeight

    var points: [PixelPoint] = []
    points.reserveCapacity(4 * (a + b + 2))
    repeat {
      points.append(PixelPoint(x: right, y: top))
      points.append(PixelPoint(x: left, y: top))
      points.append(PixelPoint(x: left, y: bottom))
      points.append(PixelPoint(x: right, y: bottom))
      let doubled = 2 * error
      if doubled <= dy {
        top += 1
        bottom -= 1
        dy += yStep
        error += dy
      }
      if doubled >= dx || 2 * error > dy {
        left += 1
        right -= 1
        dx += xStep
        error += dx
      }
    } while left <= right

    // Flat ellipses (a == 0 or b == 0) leave the tips unplotted above.
    while top - bottom <= b {
      points.append(PixelPoint(x: left - 1, y: top))
      points.append(PixelPoint(x: right + 1, y: top))
      top += 1
      points.append(PixelPoint(x: left - 1, y: bottom))
      points.append(PixelPoint(x: right + 1, y: bottom))
      bottom -= 1
    }
    return points
  }

  private static func flip(
    on buffer: PixelBuffer,
    rect: PixelRect?,
    horizontally: Bool
  ) -> PixelBuffer {
    let canvas = buffer.bounds
    guard let bounds = (rect ?? canvas).intersected(with: canvas) else { return buffer }
    var copy = buffer
    for y in bounds.minY..<bounds.maxY {
      for x in bounds.minX..<bounds.maxX {
        let source = PixelPoint(
          x: horizontally ? bounds.minX + bounds.maxX - 1 - x : x,
          y: horizontally ? y : bounds.minY + bounds.maxY - 1 - y
        )
        // Both points are inside `bounds`, which is inside the canvas.
        copy.setUnchecked(PixelPoint(x: x, y: y), to: buffer[source])
      }
    }
    return copy
  }

  private static func rotateQuarterTurn(
    on buffer: PixelBuffer,
    rect: PixelRect?,
    clockwise: Bool
  ) -> PixelBuffer {
    let canvas = buffer.bounds
    guard let bounds = (rect ?? canvas).intersected(with: canvas) else { return buffer }
    let width = bounds.size.width
    let height = bounds.size.height

    // Doubled coordinates keep the whole mapping in integers: cell
    // (x, y) sits at (2x − centerX2, 2y − centerY2) relative to the
    // region centre, which is a half cell when a side is even.
    let centerX2 = 2 * bounds.minX + (width - 1)
    let centerY2 = 2 * bounds.minY + (height - 1)
    // Non-zero only when `width + height` is odd, i.e. when the turned
    // coordinate lands between cells; it rounds down/right. The sum
    // being halved is always even once this is added, so the division
    // below is exact.
    let bias = (width + height) % 2

    var copy = clear(on: buffer, rect: bounds)
    for y in bounds.minY..<bounds.maxY {
      for x in bounds.minX..<bounds.maxX {
        let u = 2 * x - centerX2
        let v = 2 * y - centerY2
        let turnedU = clockwise ? -v : v
        let turnedV = clockwise ? u : -u
        let destination = PixelPoint(
          x: (turnedU + centerX2 + bias) / 2,
          y: (turnedV + centerY2 + bias) / 2
        )
        guard bounds.contains(destination) else { continue }
        // Inside `bounds`, which is inside the canvas.
        copy.setUnchecked(destination, to: buffer[PixelPoint(x: x, y: y)])
      }
    }
    return copy
  }

  private static func lerp(_ a: UInt8, _ b: UInt8, _ t: Double) -> UInt8 {
    let v = Double(a) + (Double(b) - Double(a)) * t
    return UInt8(max(0.0, min(255.0, v.rounded())))
  }
}

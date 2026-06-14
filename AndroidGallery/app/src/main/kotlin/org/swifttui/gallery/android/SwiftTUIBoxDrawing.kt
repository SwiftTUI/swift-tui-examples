package org.swifttui.gallery.android

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Procedural renderer for Unicode box-drawing characters (U+2500–U+257F), block
 * elements (U+2580–U+259F), and braille patterns (U+2800–U+28FF) — a Kotlin port
 * of the SwiftUI host's `BoxDrawingRenderer`.
 *
 * These glyphs are designed to fill the em-square and tile seamlessly between
 * adjacent cells, but fonts ship them at the em size while terminal cells add
 * descender/leading height — so font rendering leaves visible gaps between
 * box-drawing rows. Painting them to the exact cell rect guarantees pixel-perfect
 * tiling regardless of font metrics, which matters for borders, the Game-of-Life
 * grid, and the charts.
 *
 * The classification surface (`canRender`, `lineSpec`, `brailleMask`) is pure and
 * unit-tested; the `draw` entry point fills sub-rects of `android.graphics`.
 */
object SwiftTUIBoxDrawing {
  // Lazily created so the pure classification API (canRender/lineSpec/brailleMask
  // and the LINE_SPECS table) can be used — and unit-tested on a plain JVM —
  // without constructing android.graphics objects until something is drawn.
  private val fillPaint by lazy { Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL } }
  private val strokePaint by lazy { Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE } }
  private val path by lazy { Path() }

  enum class LineWeight(val rank: Int) {
    NONE(0),
    LIGHT(1),
    HEAVY(2),
    DOUBLE(3)
  }

  /** North/east/south/west edge weights describing a box-drawing line glyph. */
  data class Spec(
    val n: LineWeight,
    val e: LineWeight,
    val s: LineWeight,
    val w: LineWeight
  )

  fun canRender(codePoint: Int): Boolean =
    codePoint in 0x2500..0x259F || codePoint in 0x2800..0x28FF

  /** The line spec for a U+2500–257F code point, or `null` for the procedural
   *  (dashed/diagonal/arc) glyphs and out-of-range code points. */
  fun lineSpec(codePoint: Int): Spec? = LINE_SPECS[codePoint]

  /** The 8-bit braille dot mask for a U+2800–28FF code point (0 for others). */
  fun brailleMask(codePoint: Int): Int =
    if (codePoint in 0x2800..0x28FF) codePoint - 0x2800 else 0

  /**
   * Paints [codePoint] into [rect] with [color]. Returns true if the glyph was
   * drawn; false if the caller should fall back to font rendering.
   */
  fun draw(canvas: Canvas, codePoint: Int, rect: RectF, color: Int): Boolean {
    fillPaint.color = color
    strokePaint.color = color
    return when (codePoint) {
      in 0x2500..0x257F -> drawBoxDrawing(canvas, codePoint, rect)
      in 0x2580..0x259F -> drawBlockElement(canvas, codePoint, rect)
      in 0x2800..0x28FF -> drawBraille(canvas, codePoint, rect)
      else -> false
    }
  }

  // MARK: - Stroke metrics

  private data class StrokeMetrics(val light: Float, val heavy: Float, val doubleGap: Float)

  private fun strokeMetrics(rect: RectF): StrokeMetrics {
    val unit = max(1f, (min(rect.width(), rect.height()) / 16f).roundToInt().toFloat())
    return StrokeMetrics(light = unit, heavy = unit * 2f, doubleGap = unit)
  }

  // MARK: - Box-drawing lines (U+2500–U+257F)

  private fun drawBoxDrawing(canvas: Canvas, codePoint: Int, rect: RectF): Boolean {
    val spec = LINE_SPECS[codePoint]
    if (spec != null) {
      drawCellLines(canvas, spec, rect)
      return true
    }

    when (codePoint) {
      0x2504 -> drawDashedHorizontal(canvas, rect, LineWeight.LIGHT, 3)
      0x2505 -> drawDashedHorizontal(canvas, rect, LineWeight.HEAVY, 3)
      0x2506 -> drawDashedVertical(canvas, rect, LineWeight.LIGHT, 3)
      0x2507 -> drawDashedVertical(canvas, rect, LineWeight.HEAVY, 3)
      0x2508 -> drawDashedHorizontal(canvas, rect, LineWeight.LIGHT, 4)
      0x2509 -> drawDashedHorizontal(canvas, rect, LineWeight.HEAVY, 4)
      0x250A -> drawDashedVertical(canvas, rect, LineWeight.LIGHT, 4)
      0x250B -> drawDashedVertical(canvas, rect, LineWeight.HEAVY, 4)
      0x254C -> drawDashedHorizontal(canvas, rect, LineWeight.LIGHT, 2)
      0x254D -> drawDashedHorizontal(canvas, rect, LineWeight.HEAVY, 2)
      0x254E -> drawDashedVertical(canvas, rect, LineWeight.LIGHT, 2)
      0x254F -> drawDashedVertical(canvas, rect, LineWeight.HEAVY, 2)
      0x2571 -> drawDiagonal(canvas, rect, descending = false)
      0x2572 -> drawDiagonal(canvas, rect, descending = true)
      0x2573 -> {
        drawDiagonal(canvas, rect, descending = false)
        drawDiagonal(canvas, rect, descending = true)
      }
      0x256D -> drawArc(canvas, rect, Corner.TOP_LEFT)
      0x256E -> drawArc(canvas, rect, Corner.TOP_RIGHT)
      0x256F -> drawArc(canvas, rect, Corner.BOTTOM_RIGHT)
      0x2570 -> drawArc(canvas, rect, Corner.BOTTOM_LEFT)
      else -> return false
    }
    return true
  }

  private enum class Direction { NORTH, EAST, SOUTH, WEST }

  private fun drawCellLines(canvas: Canvas, spec: Spec, rect: RectF) {
    val metrics = strokeMetrics(rect)
    // Draw heavier weights last so they dominate at the centre.
    val edges = listOf(
      spec.n to Direction.NORTH,
      spec.e to Direction.EAST,
      spec.s to Direction.SOUTH,
      spec.w to Direction.WEST
    ).sortedBy { it.first.rank }
    for ((weight, direction) in edges) {
      drawHalfStroke(canvas, weight, direction, rect, metrics)
    }
  }

  private fun drawHalfStroke(
    canvas: Canvas,
    weight: LineWeight,
    direction: Direction,
    rect: RectF,
    metrics: StrokeMetrics
  ) {
    if (weight == LineWeight.NONE) {
      return
    }
    val cx = rect.centerX()
    val cy = rect.centerY()

    fun segment(thickness: Float, offset: Float) {
      val r = when (direction) {
        Direction.NORTH -> RectF(cx - thickness / 2 + offset, rect.top, cx + thickness / 2 + offset, cy + thickness / 2)
        Direction.SOUTH -> RectF(cx - thickness / 2 + offset, cy - thickness / 2, cx + thickness / 2 + offset, rect.bottom)
        Direction.WEST -> RectF(rect.left, cy - thickness / 2 + offset, cx + thickness / 2, cy + thickness / 2 + offset)
        Direction.EAST -> RectF(cx - thickness / 2, cy - thickness / 2 + offset, rect.right, cy + thickness / 2 + offset)
      }
      canvas.drawRect(r, fillPaint)
    }

    when (weight) {
      LineWeight.NONE -> Unit
      LineWeight.LIGHT -> segment(metrics.light, 0f)
      LineWeight.HEAVY -> segment(metrics.heavy, 0f)
      LineWeight.DOUBLE -> {
        val thickness = metrics.light
        val off = (thickness + metrics.doubleGap) / 2f
        segment(thickness, -off)
        segment(thickness, off)
      }
    }
  }

  private fun drawDashedHorizontal(canvas: Canvas, rect: RectF, weight: LineWeight, segments: Int) {
    val metrics = strokeMetrics(rect)
    val thickness = if (weight == LineWeight.HEAVY) metrics.heavy else metrics.light
    val segmentWidth = rect.width() / segments
    val dashWidth = segmentWidth * 0.55f
    val gapWidth = segmentWidth - dashWidth
    val cy = rect.centerY()
    for (i in 0 until segments) {
      val x = rect.left + i * segmentWidth + gapWidth / 2
      canvas.drawRect(x, cy - thickness / 2, x + dashWidth, cy + thickness / 2, fillPaint)
    }
  }

  private fun drawDashedVertical(canvas: Canvas, rect: RectF, weight: LineWeight, segments: Int) {
    val metrics = strokeMetrics(rect)
    val thickness = if (weight == LineWeight.HEAVY) metrics.heavy else metrics.light
    val segmentHeight = rect.height() / segments
    val dashHeight = segmentHeight * 0.55f
    val gapHeight = segmentHeight - dashHeight
    val cx = rect.centerX()
    for (i in 0 until segments) {
      val y = rect.top + i * segmentHeight + gapHeight / 2
      canvas.drawRect(cx - thickness / 2, y, cx + thickness / 2, y + dashHeight, fillPaint)
    }
  }

  private fun drawDiagonal(canvas: Canvas, rect: RectF, descending: Boolean) {
    val metrics = strokeMetrics(rect)
    strokePaint.strokeWidth = metrics.light
    strokePaint.strokeCap = Paint.Cap.SQUARE
    if (descending) {
      canvas.drawLine(rect.left, rect.top, rect.right, rect.bottom, strokePaint)
    } else {
      canvas.drawLine(rect.right, rect.top, rect.left, rect.bottom, strokePaint)
    }
  }

  private enum class Corner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

  private fun drawArc(canvas: Canvas, rect: RectF, corner: Corner) {
    val metrics = strokeMetrics(rect)
    val cx = rect.centerX()
    val cy = rect.centerY()
    val radius = min(rect.width(), rect.height()) * 0.4f
    val kappa = radius * 0.5523f

    strokePaint.strokeWidth = metrics.light
    strokePaint.strokeCap = Paint.Cap.BUTT
    path.reset()

    when (corner) {
      Corner.TOP_LEFT -> {
        path.moveTo(cx, cy + radius)
        path.lineTo(cx, rect.bottom)
        path.moveTo(cx + radius, cy)
        path.lineTo(rect.right, cy)
        path.moveTo(cx, cy + radius)
        path.cubicTo(cx, cy + radius - kappa, cx + radius - kappa, cy, cx + radius, cy)
      }
      Corner.TOP_RIGHT -> {
        path.moveTo(cx, cy + radius)
        path.lineTo(cx, rect.bottom)
        path.moveTo(cx - radius, cy)
        path.lineTo(rect.left, cy)
        path.moveTo(cx - radius, cy)
        path.cubicTo(cx - radius + kappa, cy, cx, cy + radius - kappa, cx, cy + radius)
      }
      Corner.BOTTOM_RIGHT -> {
        path.moveTo(cx, cy - radius)
        path.lineTo(cx, rect.top)
        path.moveTo(cx - radius, cy)
        path.lineTo(rect.left, cy)
        path.moveTo(cx, cy - radius)
        path.cubicTo(cx, cy - radius + kappa, cx - radius + kappa, cy, cx - radius, cy)
      }
      Corner.BOTTOM_LEFT -> {
        path.moveTo(cx, cy - radius)
        path.lineTo(cx, rect.top)
        path.moveTo(cx + radius, cy)
        path.lineTo(rect.right, cy)
        path.moveTo(cx + radius, cy)
        path.cubicTo(cx + radius - kappa, cy, cx, cy - radius + kappa, cx, cy - radius)
      }
    }
    canvas.drawPath(path, strokePaint)
  }

  // MARK: - Block elements (U+2580–U+259F)

  private fun drawBlockElement(canvas: Canvas, codePoint: Int, rect: RectF): Boolean {
    val w = rect.width()
    val h = rect.height()

    fun eighthFromBottom(k: Float) {
      val height = h * k / 8f
      canvas.drawRect(rect.left, rect.bottom - height, rect.right, rect.bottom, fillPaint)
    }

    fun leftFraction(k: Float) {
      val width = w * k / 8f
      canvas.drawRect(rect.left, rect.top, rect.left + width, rect.bottom, fillPaint)
    }

    when (codePoint) {
      0x2580 -> canvas.drawRect(rect.left, rect.top, rect.right, rect.top + h / 2, fillPaint) // ▀
      0x2581 -> eighthFromBottom(1f)
      0x2582 -> eighthFromBottom(2f)
      0x2583 -> eighthFromBottom(3f)
      0x2584 -> eighthFromBottom(4f)
      0x2585 -> eighthFromBottom(5f)
      0x2586 -> eighthFromBottom(6f)
      0x2587 -> eighthFromBottom(7f)
      0x2588 -> canvas.drawRect(rect, fillPaint) // █
      0x2589 -> leftFraction(7f)
      0x258A -> leftFraction(6f)
      0x258B -> leftFraction(5f)
      0x258C -> leftFraction(4f)
      0x258D -> leftFraction(3f)
      0x258E -> leftFraction(2f)
      0x258F -> leftFraction(1f)
      0x2590 -> canvas.drawRect(rect.left + w / 2, rect.top, rect.right, rect.bottom, fillPaint) // ▐
      0x2591 -> drawShade(canvas, rect, ShadeDensity.LIGHT)
      0x2592 -> drawShade(canvas, rect, ShadeDensity.MEDIUM)
      0x2593 -> drawShade(canvas, rect, ShadeDensity.DARK)
      0x2594 -> canvas.drawRect(rect.left, rect.top, rect.right, rect.top + h / 8, fillPaint) // ▔
      0x2595 -> canvas.drawRect(rect.right - w / 8, rect.top, rect.right, rect.bottom, fillPaint) // ▕
      0x2596 -> fillQuadrants(canvas, rect, bottomLeft = true)
      0x2597 -> fillQuadrants(canvas, rect, bottomRight = true)
      0x2598 -> fillQuadrants(canvas, rect, topLeft = true)
      0x2599 -> fillQuadrants(canvas, rect, topLeft = true, bottomLeft = true, bottomRight = true)
      0x259A -> fillQuadrants(canvas, rect, topLeft = true, bottomRight = true)
      0x259B -> fillQuadrants(canvas, rect, topLeft = true, topRight = true, bottomLeft = true)
      0x259C -> fillQuadrants(canvas, rect, topLeft = true, topRight = true, bottomRight = true)
      0x259D -> fillQuadrants(canvas, rect, topRight = true)
      0x259E -> fillQuadrants(canvas, rect, topRight = true, bottomLeft = true)
      0x259F -> fillQuadrants(canvas, rect, topRight = true, bottomLeft = true, bottomRight = true)
      else -> return false
    }
    return true
  }

  private fun fillQuadrants(
    canvas: Canvas,
    rect: RectF,
    topLeft: Boolean = false,
    topRight: Boolean = false,
    bottomLeft: Boolean = false,
    bottomRight: Boolean = false
  ) {
    val halfW = rect.width() / 2
    val halfH = rect.height() / 2
    if (topLeft) canvas.drawRect(rect.left, rect.top, rect.left + halfW, rect.top + halfH, fillPaint)
    if (topRight) canvas.drawRect(rect.left + halfW, rect.top, rect.right, rect.top + halfH, fillPaint)
    if (bottomLeft) canvas.drawRect(rect.left, rect.top + halfH, rect.left + halfW, rect.bottom, fillPaint)
    if (bottomRight) canvas.drawRect(rect.left + halfW, rect.top + halfH, rect.right, rect.bottom, fillPaint)
  }

  private enum class ShadeDensity { LIGHT, MEDIUM, DARK }

  private fun drawShade(canvas: Canvas, rect: RectF, density: ShadeDensity) {
    val pixels = when (density) {
      ShadeDensity.LIGHT -> listOf(0 to 0)
      ShadeDensity.MEDIUM -> listOf(0 to 0, 1 to 1)
      ShadeDensity.DARK -> listOf(0 to 0, 1 to 0, 0 to 1)
    }
    val block = 2f
    var y = rect.top
    while (y < rect.bottom) {
      var x = rect.left
      while (x < rect.right) {
        for ((px, py) in pixels) {
          val dotX = x + px
          val dotY = y + py
          if (dotX < rect.right && dotY < rect.bottom) {
            canvas.drawRect(dotX, dotY, dotX + 1, dotY + 1, fillPaint)
          }
        }
        x += block
      }
      y += block
    }
  }

  // MARK: - Braille (U+2800–U+28FF)

  // Bit -> (column, row) for the 2×4 braille mosaic, in raster order.
  private val brailleSubpixels = arrayOf(
    intArrayOf(0x01, 0, 0), intArrayOf(0x08, 1, 0),
    intArrayOf(0x02, 0, 1), intArrayOf(0x10, 1, 1),
    intArrayOf(0x04, 0, 2), intArrayOf(0x20, 1, 2),
    intArrayOf(0x40, 0, 3), intArrayOf(0x80, 1, 3)
  )

  private fun drawBraille(canvas: Canvas, codePoint: Int, rect: RectF): Boolean {
    val mask = codePoint - 0x2800
    if (mask == 0) {
      // U+2800 BRAILLE PATTERN BLANK is whitespace.
      return true
    }
    val cellWidth = rect.width() / 2f
    val rowHeight = rect.height() / 4f
    for (sub in brailleSubpixels) {
      if (mask and sub[0] != 0) {
        val x = rect.left + sub[1] * cellWidth
        val y = rect.top + sub[2] * rowHeight
        canvas.drawRect(x, y, x + cellWidth, y + rowHeight, fillPaint)
      }
    }
    return true
  }

  // MARK: - Line spec table (U+2500–U+257F full/corner/junction/cross/double/half lines)

  private val LINE_SPECS: Map<Int, Spec> = buildMap {
    val n = LineWeight.NONE
    val l = LineWeight.LIGHT
    val h = LineWeight.HEAVY
    val d = LineWeight.DOUBLE
    // Horizontal & vertical full lines.
    put(0x2500, Spec(n, l, n, l)); put(0x2501, Spec(n, h, n, h))
    put(0x2502, Spec(l, n, l, n)); put(0x2503, Spec(h, n, h, n))
    // Sharp corners.
    put(0x250C, Spec(n, l, l, n)); put(0x250D, Spec(n, h, l, n))
    put(0x250E, Spec(n, l, h, n)); put(0x250F, Spec(n, h, h, n))
    put(0x2510, Spec(n, n, l, l)); put(0x2511, Spec(n, n, l, h))
    put(0x2512, Spec(n, n, h, l)); put(0x2513, Spec(n, n, h, h))
    put(0x2514, Spec(l, l, n, n)); put(0x2515, Spec(l, h, n, n))
    put(0x2516, Spec(h, l, n, n)); put(0x2517, Spec(h, h, n, n))
    put(0x2518, Spec(l, n, n, l)); put(0x2519, Spec(l, n, n, h))
    put(0x251A, Spec(h, n, n, l)); put(0x251B, Spec(h, n, n, h))
    // T-junctions: vertical + right.
    put(0x251C, Spec(l, l, l, n)); put(0x251D, Spec(l, h, l, n))
    put(0x251E, Spec(h, l, l, n)); put(0x251F, Spec(l, l, h, n))
    put(0x2520, Spec(h, l, h, n)); put(0x2521, Spec(h, h, l, n))
    put(0x2522, Spec(l, h, h, n)); put(0x2523, Spec(h, h, h, n))
    // T-junctions: vertical + left.
    put(0x2524, Spec(l, n, l, l)); put(0x2525, Spec(l, n, l, h))
    put(0x2526, Spec(h, n, l, l)); put(0x2527, Spec(l, n, h, l))
    put(0x2528, Spec(h, n, h, l)); put(0x2529, Spec(h, n, l, h))
    put(0x252A, Spec(l, n, h, h)); put(0x252B, Spec(h, n, h, h))
    // T-junctions: down + horizontal.
    put(0x252C, Spec(n, l, l, l)); put(0x252D, Spec(n, l, l, h))
    put(0x252E, Spec(n, h, l, l)); put(0x252F, Spec(n, h, l, h))
    put(0x2530, Spec(n, l, h, l)); put(0x2531, Spec(n, l, h, h))
    put(0x2532, Spec(n, h, h, l)); put(0x2533, Spec(n, h, h, h))
    // T-junctions: up + horizontal.
    put(0x2534, Spec(l, l, n, l)); put(0x2535, Spec(l, l, n, h))
    put(0x2536, Spec(l, h, n, l)); put(0x2537, Spec(l, h, n, h))
    put(0x2538, Spec(h, l, n, l)); put(0x2539, Spec(h, l, n, h))
    put(0x253A, Spec(h, h, n, l)); put(0x253B, Spec(h, h, n, h))
    // Crosses.
    put(0x253C, Spec(l, l, l, l)); put(0x253D, Spec(l, l, l, h))
    put(0x253E, Spec(l, h, l, l)); put(0x253F, Spec(l, h, l, h))
    put(0x2540, Spec(h, l, l, l)); put(0x2541, Spec(l, l, h, l))
    put(0x2542, Spec(h, l, h, l)); put(0x2543, Spec(h, l, l, h))
    put(0x2544, Spec(h, h, l, l)); put(0x2545, Spec(l, l, h, h))
    put(0x2546, Spec(l, h, h, l)); put(0x2547, Spec(h, h, l, h))
    put(0x2548, Spec(l, h, h, h)); put(0x2549, Spec(h, l, h, h))
    put(0x254A, Spec(h, h, h, l)); put(0x254B, Spec(h, h, h, h))
    // Doubles.
    put(0x2550, Spec(n, d, n, d)); put(0x2551, Spec(d, n, d, n))
    put(0x2552, Spec(n, d, l, n)); put(0x2553, Spec(n, l, d, n))
    put(0x2554, Spec(n, d, d, n)); put(0x2555, Spec(n, n, l, d))
    put(0x2556, Spec(n, n, d, l)); put(0x2557, Spec(n, n, d, d))
    put(0x2558, Spec(l, d, n, n)); put(0x2559, Spec(d, l, n, n))
    put(0x255A, Spec(d, d, n, n)); put(0x255B, Spec(l, n, n, d))
    put(0x255C, Spec(d, n, n, l)); put(0x255D, Spec(d, n, n, d))
    put(0x255E, Spec(l, d, l, n)); put(0x255F, Spec(d, l, d, n))
    put(0x2560, Spec(d, d, d, n)); put(0x2561, Spec(l, n, l, d))
    put(0x2562, Spec(d, n, d, l)); put(0x2563, Spec(d, n, d, d))
    put(0x2564, Spec(n, d, l, d)); put(0x2565, Spec(n, l, d, l))
    put(0x2566, Spec(n, d, d, d)); put(0x2567, Spec(l, d, n, d))
    put(0x2568, Spec(d, l, n, l)); put(0x2569, Spec(d, d, n, d))
    put(0x256A, Spec(l, d, l, d)); put(0x256B, Spec(d, l, d, l))
    put(0x256C, Spec(d, d, d, d))
    // Half-lines.
    put(0x2574, Spec(n, n, n, l)); put(0x2575, Spec(l, n, n, n))
    put(0x2576, Spec(n, l, n, n)); put(0x2577, Spec(n, n, l, n))
    put(0x2578, Spec(n, n, n, h)); put(0x2579, Spec(h, n, n, n))
    put(0x257A, Spec(n, h, n, n)); put(0x257B, Spec(n, n, h, n))
    put(0x257C, Spec(n, h, n, l)); put(0x257D, Spec(l, n, h, n))
    put(0x257E, Spec(n, l, n, h)); put(0x257F, Spec(h, n, l, n))
  }
}

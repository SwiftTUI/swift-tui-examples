package org.swifttui.gallery.android

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.RectF
import android.graphics.Typeface
import android.util.Base64
import android.util.LruCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import kotlin.math.max
import kotlin.math.roundToInt

object SwiftTUIRenderer {
  private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    typeface = Typeface.MONOSPACE
  }
  private val backgroundPaint = Paint()
  private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG)
  private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
  private val clearPaint = Paint()
  private val mutedPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = android.graphics.Color.rgb(151, 162, 178)
    typeface = Typeface.MONOSPACE
  }
  // Decoded image-attachment bitmaps, bounded so cycling through image-heavy
  // demos cannot leak for the process lifetime; evicted bitmaps are recycled.
  private val bitmapCache = object : LruCache<String, Bitmap>(8 * 1024 * 1024) {
    override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount

    override fun entryRemoved(
      evicted: Boolean,
      key: String,
      oldValue: Bitmap,
      newValue: Bitmap?
    ) {
      if (oldValue != newValue && !oldValue.isRecycled) {
        oldValue.recycle()
      }
    }
  }

  // Retained grid surface. Cells are painted once and only the damaged rows are
  // repainted on subsequent frames, so a typing/cursor/animation update no
  // longer re-runs drawText for the whole grid.
  private var cacheBitmap: Bitmap? = null
  private var cacheCanvas: Canvas? = null
  private var cacheWidth = 0
  private var cacheHeight = 0
  private var lastRenderedSequence = -1L

  fun drawFrame(
    drawScope: DrawScope,
    frame: SwiftTUIFrame?,
    style: SwiftTUIAndroidStyle,
    lastError: String?
  ) {
    val terminalStyle = frame?.terminalStyle ?: SwiftTUITerminalStyle.Default
    drawScope.drawRect(terminalStyle.backgroundColor.toComposeColor())

    val textSize = style.cellHeightPx * 0.78f
    textPaint.textSize = textSize
    mutedPaint.textSize = textSize
    val baselineOffset =
      (style.cellHeightPx - textPaint.fontMetrics.bottom - textPaint.fontMetrics.top) / 2f

    if (frame == null) {
      drawScope.drawIntoCanvas { canvas ->
        canvas.nativeCanvas.drawText(
          lastError ?: "Starting SwiftTUI gallery...",
          0f,
          baselineOffset,
          mutedPaint
        )
      }
      return
    }

    renderGridToCache(frame, terminalStyle, style, baselineOffset)

    drawScope.drawIntoCanvas { canvas ->
      cacheBitmap?.let { canvas.nativeCanvas.drawBitmap(it, 0f, 0f, null) }

      if (lastError != null) {
        canvas.nativeCanvas.drawText(
          lastError,
          0f,
          drawScope.size.height - style.cellHeightPx,
          mutedPaint
        )
      }
    }

    val focusColor = frame.terminalStyle.tintColor.toComposeColor()
    if (frame.focusPresentation.hasFocusedRegion) {
      drawScope.drawLine(
        color = focusColor,
        start = Offset(0f, drawScope.size.height - 1f),
        end = Offset(drawScope.size.width, drawScope.size.height - 1f),
        strokeWidth = 1f
      )
    }
  }

  private fun renderGridToCache(
    frame: SwiftTUIFrame,
    terminalStyle: SwiftTUITerminalStyle,
    style: SwiftTUIAndroidStyle,
    baselineOffset: Float
  ) {
    val gridWidthPx = max(1, (frame.gridWidth * style.cellWidthPx).roundToInt())
    val gridHeightPx = max(1, (frame.gridHeight * style.cellHeightPx).roundToInt())
    val resized = cacheBitmap == null || cacheWidth != gridWidthPx || cacheHeight != gridHeightPx
    if (resized) {
      cacheBitmap?.recycle()
      val bitmap = Bitmap.createBitmap(gridWidthPx, gridHeightPx, Bitmap.Config.ARGB_8888)
      cacheBitmap = bitmap
      cacheCanvas = Canvas(bitmap)
      cacheWidth = gridWidthPx
      cacheHeight = gridHeightPx
    }
    val canvas = cacheCanvas ?: return
    val backgroundArgb = terminalStyle.backgroundColor.toArgb()

    val plan = SwiftTUIDamagePlan.plan(
      frame = frame,
      previousSequence = lastRenderedSequence,
      sizeChanged = resized
    )

    if (plan.fullRepaint) {
      canvas.drawColor(backgroundArgb, PorterDuff.Mode.SRC)
      if (frame.cells.isEmpty()) {
        drawLegacyRows(canvas, frame, terminalStyle, style, baselineOffset)
      } else {
        drawCells(canvas, frame.cells, terminalStyle, style, baselineOffset)
      }
      drawImages(canvas, frame, style)
    } else {
      clearPaint.color = backgroundArgb
      val damagedCells = ArrayList<SwiftTUICell>()
      for (rowDamage in plan.rows) {
        val top = rowDamage.row * style.cellHeightPx
        val bottom = top + style.cellHeightPx
        for (range in rowDamage.columnRanges) {
          val left = range.first * style.cellWidthPx
          val right = (range.last + 1) * style.cellWidthPx
          canvas.drawRect(left, top, right, bottom, clearPaint)
        }
        for (cell in frame.cells) {
          if (cell.y == rowDamage.row && !cell.isContinuation &&
            rowDamage.intersects(cell.x, cell.x + cell.spanWidth.coerceAtLeast(1))
          ) {
            damagedCells.add(cell)
          }
        }
      }
      drawCells(canvas, damagedCells, terminalStyle, style, baselineOffset)
    }

    lastRenderedSequence = frame.sequence
  }

  private fun drawLegacyRows(
    canvas: Canvas,
    frame: SwiftTUIFrame,
    terminalStyle: SwiftTUITerminalStyle,
    style: SwiftTUIAndroidStyle,
    baselineOffset: Float
  ) {
    textPaint.color = terminalStyle.foregroundColor.toArgb()
    textPaint.typeface = Typeface.MONOSPACE
    textPaint.isUnderlineText = false
    textPaint.isStrikeThruText = false

    frame.rows.forEachIndexed { index, row ->
      canvas.drawText(
        row,
        0f,
        index * style.cellHeightPx + baselineOffset,
        textPaint
      )
    }
  }

  private fun drawCells(
    canvas: Canvas,
    cells: List<SwiftTUICell>,
    terminalStyle: SwiftTUITerminalStyle,
    style: SwiftTUIAndroidStyle,
    baselineOffset: Float
  ) {
    cells.forEach { cell ->
      if (cell.isContinuation) {
        return@forEach
      }

      val rect = cellRect(cell.x, cell.y, cell.spanWidth.coerceAtLeast(1), style)
      val textStyle = cell.style
      val reverse = textStyle?.emphasis?.contains("reverse") == true
      val foreground = if (reverse) {
        textStyle?.backgroundColor ?: terminalStyle.backgroundColor
      } else {
        textStyle?.foregroundColor ?: terminalStyle.foregroundColor
      }
      val background = if (reverse) {
        textStyle?.foregroundColor ?: terminalStyle.foregroundColor
      } else {
        textStyle?.backgroundColor
      }

      if (background != null) {
        backgroundPaint.color = background.toArgb(textStyle?.opacity ?: 1.0)
        canvas.drawRect(rect, backgroundPaint)
      }

      if (cell.character != " " && cell.character.isNotEmpty()) {
        val foregroundArgb = foreground.toArgb(
          opacity = textStyle?.opacity ?: 1.0,
          faint = textStyle?.emphasis?.contains("faint") == true
        )
        // Box-drawing / block / braille glyphs are painted procedurally so they
        // tile seamlessly between cells instead of leaving font gaps.
        val codePoint = cell.character.codePointAt(0)
        val drawnProcedurally =
          cell.character.codePointCount(0, cell.character.length) == 1 &&
            SwiftTUIBoxDrawing.canRender(codePoint) &&
            SwiftTUIBoxDrawing.draw(canvas, codePoint, rect, foregroundArgb)

        if (!drawnProcedurally) {
          configureTextPaint(foregroundArgb = foregroundArgb, style = textStyle)
          canvas.drawText(
            cell.character,
            rect.left,
            rect.top + baselineOffset,
            textPaint
          )
        }
      }

      drawLineDecoration(
        canvas = canvas,
        rect = rect,
        style = textStyle?.underlineStyle,
        fallbackColor = foreground,
        opacity = textStyle?.opacity ?: 1.0,
        y = rect.bottom - 2f
      )
      drawLineDecoration(
        canvas = canvas,
        rect = rect,
        style = textStyle?.strikethroughStyle,
        fallbackColor = foreground,
        opacity = textStyle?.opacity ?: 1.0,
        y = rect.centerY()
      )
    }
  }

  private fun drawImages(
    canvas: Canvas,
    frame: SwiftTUIFrame,
    style: SwiftTUIAndroidStyle
  ) {
    frame.imageAttachments.forEach { attachment ->
      val bitmap = bitmapFor(attachment) ?: return@forEach
      val bounds = attachment.visibleBounds
      if (bounds.width <= 0 || bounds.height <= 0) {
        return@forEach
      }

      val rect = RectF(
        bounds.x * style.cellWidthPx,
        bounds.y * style.cellHeightPx,
        (bounds.x + bounds.width) * style.cellWidthPx,
        (bounds.y + bounds.height) * style.cellHeightPx
      )
      canvas.drawBitmap(bitmap, null, rect, imagePaint)
    }
  }

  private fun configureTextPaint(
    foregroundArgb: Int,
    style: SwiftTUITextStyle?
  ) {
    textPaint.color = foregroundArgb
    textPaint.typeface = typeface(style?.emphasis.orEmpty())
    textPaint.isUnderlineText = false
    textPaint.isStrikeThruText = false
  }

  private fun drawLineDecoration(
    canvas: Canvas,
    rect: RectF,
    style: SwiftTUITextLineStyle?,
    fallbackColor: SwiftTUIColor,
    opacity: Double,
    y: Float
  ) {
    if (style == null) {
      return
    }

    linePaint.color = (style.color ?: fallbackColor).toArgb(opacity)
    linePaint.strokeWidth = if (style.pattern == "double") 2f else 1f
    canvas.drawLine(rect.left, y, rect.right, y, linePaint)
  }

  private fun cellRect(
    x: Int,
    y: Int,
    span: Int,
    style: SwiftTUIAndroidStyle
  ): RectF =
    RectF(
      x * style.cellWidthPx,
      y * style.cellHeightPx,
      (x + span) * style.cellWidthPx,
      (y + 1) * style.cellHeightPx
    )

  private fun typeface(emphasis: Set<String>): Typeface {
    val typefaceStyle = when {
      emphasis.contains("bold") && emphasis.contains("italic") -> Typeface.BOLD_ITALIC
      emphasis.contains("bold") -> Typeface.BOLD
      emphasis.contains("italic") -> Typeface.ITALIC
      else -> Typeface.NORMAL
    }
    return Typeface.create(Typeface.MONOSPACE, typefaceStyle)
  }

  private fun bitmapFor(
    attachment: SwiftTUIImageAttachment
  ): Bitmap? {
    val cacheKey = "${attachment.id}:${attachment.payloadByteCount ?: 0}"
    bitmapCache.get(cacheKey)?.let {
      return it
    }

    val payload = attachment.payloadBase64 ?: return null
    val bytes = runCatching {
      Base64.decode(payload, Base64.DEFAULT)
    }.getOrNull() ?: return null
    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
    bitmapCache.put(cacheKey, bitmap)
    return bitmap
  }
}

fun SwiftTUIColor.toComposeColor(): Color = Color(toArgb())

fun SwiftTUIColor.toArgb(
  opacity: Double = 1.0,
  faint: Boolean = false
): Int {
  val trimmed = hex.removePrefix("#")
  val red = trimmed.component(0)
  val green = trimmed.component(1)
  val blue = trimmed.component(2)
  val alpha = if (trimmed.length >= 8) trimmed.component(3) else 255
  val adjustedAlpha = (alpha * opacity.coerceIn(0.0, 1.0) * if (faint) 0.6 else 1.0)
    .roundToInt()
    .coerceIn(0, 255)
  return android.graphics.Color.argb(adjustedAlpha, red, green, blue)
}

private fun String.component(
  index: Int
): Int {
  val start = index * 2
  if (length < start + 2) {
    return 0
  }
  return substring(start, start + 2).toIntOrNull(16) ?: 0
}

package org.swifttui.gallery.android

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.util.Base64
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import kotlin.math.roundToInt

object SwiftTUIRenderer {
  private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    typeface = Typeface.MONOSPACE
  }
  private val backgroundPaint = Paint()
  private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG)
  private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
  private val mutedPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = android.graphics.Color.rgb(151, 162, 178)
    typeface = Typeface.MONOSPACE
  }
  private val bitmapCache = mutableMapOf<String, Bitmap>()

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

    drawScope.drawIntoCanvas { canvas ->
      val nativeCanvas = canvas.nativeCanvas
      val baselineOffset = (style.cellHeightPx - textPaint.fontMetrics.bottom - textPaint.fontMetrics.top) / 2f

      if (frame == null) {
        nativeCanvas.drawText(
          lastError ?: "Starting SwiftTUI gallery...",
          0f,
          baselineOffset,
          mutedPaint
        )
        return@drawIntoCanvas
      }

      if (frame.cells.isEmpty()) {
        drawLegacyRows(nativeCanvas, frame, terminalStyle, style, baselineOffset)
      } else {
        drawCells(nativeCanvas, frame, terminalStyle, style, baselineOffset)
      }
      drawImages(nativeCanvas, frame, style)

      if (lastError != null) {
        nativeCanvas.drawText(
          lastError,
          0f,
          drawScope.size.height - style.cellHeightPx,
          mutedPaint
        )
      }
    }

    val focusColor = frame?.terminalStyle?.tintColor?.toComposeColor() ?: Color(0xFF56B6C2)
    if (frame?.focusPresentation?.hasFocusedRegion == true) {
      drawScope.drawLine(
        color = focusColor,
        start = Offset(0f, drawScope.size.height - 1f),
        end = Offset(drawScope.size.width, drawScope.size.height - 1f),
        strokeWidth = 1f
      )
    }
  }

  private fun drawLegacyRows(
    nativeCanvas: android.graphics.Canvas,
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
      nativeCanvas.drawText(
        row,
        0f,
        index * style.cellHeightPx + baselineOffset,
        textPaint
      )
    }
  }

  private fun drawCells(
    nativeCanvas: android.graphics.Canvas,
    frame: SwiftTUIFrame,
    terminalStyle: SwiftTUITerminalStyle,
    style: SwiftTUIAndroidStyle,
    baselineOffset: Float
  ) {
    frame.cells.forEach { cell ->
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
        nativeCanvas.drawRect(rect, backgroundPaint)
      }

      if (cell.character != " ") {
        configureTextPaint(
          foreground = foreground,
          style = textStyle
        )
        nativeCanvas.drawText(
          cell.character,
          rect.left,
          rect.top + baselineOffset,
          textPaint
        )
      }

      drawLineDecoration(
        nativeCanvas = nativeCanvas,
        rect = rect,
        style = textStyle?.underlineStyle,
        fallbackColor = foreground,
        opacity = textStyle?.opacity ?: 1.0,
        y = rect.bottom - 2f
      )
      drawLineDecoration(
        nativeCanvas = nativeCanvas,
        rect = rect,
        style = textStyle?.strikethroughStyle,
        fallbackColor = foreground,
        opacity = textStyle?.opacity ?: 1.0,
        y = rect.centerY()
      )
    }
  }

  private fun drawImages(
    nativeCanvas: android.graphics.Canvas,
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
      nativeCanvas.drawBitmap(bitmap, null, rect, imagePaint)
    }
  }

  private fun configureTextPaint(
    foreground: SwiftTUIColor,
    style: SwiftTUITextStyle?
  ) {
    textPaint.color = foreground.toArgb(style?.opacity ?: 1.0, faint = style?.emphasis?.contains("faint") == true)
    textPaint.typeface = typeface(style?.emphasis.orEmpty())
    textPaint.isUnderlineText = false
    textPaint.isStrikeThruText = false
  }

  private fun drawLineDecoration(
    nativeCanvas: android.graphics.Canvas,
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
    nativeCanvas.drawLine(rect.left, y, rect.right, y, linePaint)
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
    bitmapCache[cacheKey]?.let {
      return it
    }

    val payload = attachment.payloadBase64 ?: return null
    val bytes = runCatching {
      Base64.decode(payload, Base64.DEFAULT)
    }.getOrNull() ?: return null
    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
    bitmapCache[cacheKey] = bitmap
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

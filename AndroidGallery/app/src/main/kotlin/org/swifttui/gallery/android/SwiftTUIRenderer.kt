package org.swifttui.gallery.android

import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas

object SwiftTUIRenderer {
  private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = android.graphics.Color.rgb(229, 235, 245)
    typeface = Typeface.MONOSPACE
  }
  private val mutedPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = android.graphics.Color.rgb(151, 162, 178)
    typeface = Typeface.MONOSPACE
  }

  fun drawFrame(
    drawScope: DrawScope,
    frame: SwiftTUIFrame?,
    style: SwiftTUIAndroidStyle,
    lastError: String?
  ) {
    drawScope.drawRect(Color(0xFF101318))

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

      frame.rows.forEachIndexed { index, row ->
        nativeCanvas.drawText(
          row,
          0f,
          index * style.cellHeightPx + baselineOffset,
          textPaint
        )
      }

      if (lastError != null) {
        nativeCanvas.drawText(
          lastError,
          0f,
          drawScope.size.height - style.cellHeightPx,
          mutedPaint
        )
      }
    }

    val focused = frame?.focusedIdentity
    if (focused != null) {
      drawScope.drawLine(
        color = Color(0xFF4F8CFF),
        start = Offset(0f, drawScope.size.height - 1f),
        end = Offset(drawScope.size.width, drawScope.size.height - 1f),
        strokeWidth = 1f
      )
    }
  }
}


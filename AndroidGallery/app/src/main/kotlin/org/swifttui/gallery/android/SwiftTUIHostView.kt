package org.swifttui.gallery.android

import android.view.KeyEvent as AndroidKeyEvent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.KeyEvent as ComposeKeyEvent
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.floor
import kotlin.math.max

data class SwiftTUIAndroidStyle(
  val cellWidthPx: Float,
  val cellHeightPx: Float
) {
  companion object {
    @Composable
    fun default(): SwiftTUIAndroidStyle {
      val density = LocalDensity.current
      return SwiftTUIAndroidStyle(
        cellWidthPx = with(density) { 9.dp.toPx() },
        cellHeightPx = with(density) { 18.dp.toPx() }
      )
    }
  }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun SwiftTUIHostView(
  state: SwiftTUIHostState,
  modifier: Modifier = Modifier,
  style: SwiftTUIAndroidStyle = SwiftTUIAndroidStyle.default()
) {
  val focusRequester = remember { FocusRequester() }
  var measuredSize by remember { mutableStateOf(IntSize.Zero) }
  val frame = state.frame

  LaunchedEffect(Unit) {
    focusRequester.requestFocus()
  }

  LaunchedEffect(measuredSize, style) {
    if (measuredSize.width > 0 && measuredSize.height > 0) {
      val columns = floor(measuredSize.width / style.cellWidthPx).toInt().coerceAtLeast(1)
      val rows = floor(measuredSize.height / style.cellHeightPx).toInt().coerceAtLeast(1)
      state.resize(
        columns = columns,
        rows = rows,
        cellPixelWidth = style.cellWidthPx.toDouble(),
        cellPixelHeight = style.cellHeightPx.toDouble()
      )
    }
  }

  Layout(
    modifier = modifier
      .focusRequester(focusRequester)
      .focusable()
      .pointerInput(style) {
        detectTapGestures(
          onPress = { offset ->
            state.sendInput(offset.toSgrMouseBytes(style, MousePress.Down))
            tryAwaitRelease()
            state.sendInput(offset.toSgrMouseBytes(style, MousePress.Up))
          }
        )
      }
      .onKeyEvent { event ->
        val bytes = event.toSwiftTUIInputBytes()
        if (bytes == null) {
          false
        } else {
          state.sendInput(bytes)
          true
        }
      }
      .onSizeChanged { size ->
        measuredSize = size
      },
    content = {
      Box(modifier = Modifier.fillMaxSize()) {
        Canvas(modifier = Modifier.fillMaxSize()) {
          SwiftTUIRenderer.drawFrame(
            drawScope = this,
            frame = frame,
            style = style,
            lastError = state.lastError
          )
        }
        SwiftTUIAccessibilityOverlay(
          frame = frame,
          style = style,
          modifier = Modifier.fillMaxSize()
        )
      }
    }
  ) { measurables, constraints ->
    val preferredColumns = frame?.preferredGridWidth ?: frame?.gridWidth ?: 80
    val preferredRows = frame?.preferredGridHeight ?: frame?.gridHeight ?: 24
    val preferredWidth = max(1, (preferredColumns * style.cellWidthPx).toInt())
    val preferredHeight = max(1, (preferredRows * style.cellHeightPx).toInt())

    val width = if (constraints.hasBoundedWidth) {
      constraints.maxWidth
    } else {
      preferredWidth.coerceAtLeast(constraints.minWidth)
    }
    val height = if (constraints.hasBoundedHeight) {
      constraints.maxHeight
    } else {
      preferredHeight.coerceAtLeast(constraints.minHeight)
    }

    val placeable = measurables.first().measure(Constraints.fixed(width, height))
    layout(width, height) {
      placeable.place(0, 0)
    }
  }
}

private fun ComposeKeyEvent.toSwiftTUIInputBytes(): ByteArray? {
  if (type != KeyEventType.KeyDown) {
    return null
  }

  val escapeSequence = when (key) {
    Key.Enter -> "\n"
    Key.Backspace -> "\u007F"
    Key.Tab -> "\t"
    Key.DirectionUp -> "\u001B[A"
    Key.DirectionDown -> "\u001B[B"
    Key.DirectionRight -> "\u001B[C"
    Key.DirectionLeft -> "\u001B[D"
    Key.Escape -> "\u001B"
    else -> null
  }
  if (escapeSequence != null) {
    return escapeSequence.encodeToByteArray()
  }

  val unicodeChar = nativeKeyEvent.unicodeChar
  if (unicodeChar == 0 || nativeKeyEvent.action != AndroidKeyEvent.ACTION_DOWN) {
    return null
  }
  return String(Character.toChars(unicodeChar)).encodeToByteArray()
}

private enum class MousePress {
  Down,
  Up
}

private fun Offset.toSgrMouseBytes(
  style: SwiftTUIAndroidStyle,
  press: MousePress
): ByteArray {
  val column = floor(x / style.cellWidthPx).toInt().coerceAtLeast(0) + 1
  val row = floor(y / style.cellHeightPx).toInt().coerceAtLeast(0) + 1
  val suffix = when (press) {
    MousePress.Down -> "M"
    MousePress.Up -> "m"
  }
  return "\u001B[<0;$column;$row$suffix".encodeToByteArray()
}

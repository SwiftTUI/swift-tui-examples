package org.swifttui.gallery.android

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.KeyEvent as ComposeKeyEvent
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.roundToInt

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
  val imeFocusRequester = remember { FocusRequester() }
  var measuredSize by remember { mutableStateOf(IntSize.Zero) }
  val frame = state.frame
  val currentFrame by rememberUpdatedState(frame)
  val currentStyle by rememberUpdatedState(style)
  val uriHandler = LocalUriHandler.current
  val keyboardController = LocalSoftwareKeyboardController.current
  var imeValue by remember { mutableStateOf(TextFieldValue("")) }

  val prefersTextInput = frame?.focusPresentation?.prefersTextInput == true

  LaunchedEffect(Unit) {
    focusRequester.requestFocus()
  }

  // Show the soft keyboard whenever the focused view wants text input, and put
  // focus on the invisible IME sink so committed text reaches the runtime.
  LaunchedEffect(prefersTextInput) {
    if (prefersTextInput) {
      imeValue = TextFieldValue("")
      imeFocusRequester.requestFocus()
      keyboardController?.show()
    } else {
      focusRequester.requestFocus()
      keyboardController?.hide()
    }
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
      // Press / drag / release: a tap is down+up (a click); finger movement
      // becomes SGR motion drags, matching the SwiftUI host's touchesMoved ->
      // .dragged mapping. A tap on a hyperlink cell opens the destination.
      // Keyed on Unit (not style) so a style change mid-gesture cannot cancel
      // the coroutine and drop the release; the latest metrics are read through
      // `currentStyle`.
      .pointerInput(Unit) {
        awaitEachGesture {
          val down = awaitFirstDown(requireUnconsumed = false)
          val downColumn = SwiftTUIInput.cellColumn(down.position.x, currentStyle.cellWidthPx)
          val downRow = SwiftTUIInput.cellRow(down.position.y, currentStyle.cellHeightPx)
          state.sendInput(SwiftTUIInput.mouseDown(downColumn, downRow))
          // The down is left unconsumed so `focusable()` can claim focus on tap;
          // drag moves and the release are consumed to own the gesture.

          var lastColumn = downColumn
          var lastRow = downRow
          var moved = false

          while (true) {
            val event = awaitPointerEvent()
            // Skip events that don't carry our pointer (e.g. a concurrent mouse
            // scroll) rather than ending the drag with a spurious release.
            val change = event.changes.firstOrNull { it.id == down.id } ?: continue
            if (change.pressed) {
              val column = SwiftTUIInput.cellColumn(change.position.x, currentStyle.cellWidthPx)
              val row = SwiftTUIInput.cellRow(change.position.y, currentStyle.cellHeightPx)
              if (column != lastColumn || row != lastRow) {
                moved = true
                lastColumn = column
                lastRow = row
                state.sendInput(SwiftTUIInput.mouseDrag(column, row))
              }
              change.consume()
            } else {
              state.sendInput(SwiftTUIInput.mouseUp(lastColumn, lastRow))
              change.consume()
              if (!moved) {
                val link = currentFrame?.cellAt(downColumn, downRow)?.hyperlink
                if (!link.isNullOrBlank()) {
                  runCatching { uriHandler.openUri(link) }
                }
              }
              break
            }
          }
        }
      }
      // Mouse-wheel / trackpad scroll -> SGR wheel notches.
      .pointerInput(Unit) {
        awaitPointerEventScope {
          while (true) {
            val event = awaitPointerEvent()
            if (event.type != PointerEventType.Scroll) {
              continue
            }
            val change = event.changes.firstOrNull() ?: continue
            val column = SwiftTUIInput.cellColumn(change.position.x, currentStyle.cellWidthPx)
            val row = SwiftTUIInput.cellRow(change.position.y, currentStyle.cellHeightPx)
            // Compose scrollDelta: +y scrolls down. verticalScroll treats a
            // positive deltaLines as wheel-up, so negate.
            val bytes = SwiftTUIInput.verticalScroll(
              column = column,
              row = row,
              deltaLines = -change.scrollDelta.y.roundToInt()
            )
            if (bytes.isNotEmpty()) {
              state.sendInput(bytes)
              change.consume()
            }
          }
        }
      }
      .onKeyEvent { event ->
        when {
          event.isPasteShortcut() -> {
            if (event.type == KeyEventType.KeyDown) {
              state.paste()
            }
            true
          }
          else -> {
            val bytes = event.toSwiftTUIInputBytes()
            if (bytes == null) {
              false
            } else {
              state.sendInput(bytes)
              true
            }
          }
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
        // Invisible IME sink: gives the soft keyboard a target and forwards
        // committed text as input bytes. Autocorrect/suggestions are disabled
        // so the terminal sees exactly what was typed.
        BasicTextField(
          value = imeValue,
          onValueChange = { newValue ->
            val bytes = SwiftTUIIme.bytesForEdit(imeValue.text, newValue.text)
            if (bytes.isNotEmpty()) {
              state.sendInput(bytes)
            }
            imeValue = newValue
          },
          enabled = prefersTextInput,
          keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None,
            autoCorrectEnabled = false,
            keyboardType = KeyboardType.Ascii,
            imeAction = ImeAction.Default
          ),
          modifier = Modifier
            .size(1.dp)
            .alpha(0f)
            .focusRequester(imeFocusRequester)
        )
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

// Ctrl+V or Shift+Insert pastes the system clipboard as a bracketed paste,
// rather than sending the raw Ctrl-V control byte.
private fun ComposeKeyEvent.isPasteShortcut(): Boolean =
  (isCtrlPressed && key == Key.V) || (isShiftPressed && key == Key.Insert)

private fun ComposeKeyEvent.toSwiftTUIInputBytes(): ByteArray? {
  if (type != KeyEventType.KeyDown) {
    return null
  }

  val escapeSequence = when (key) {
    Key.Enter, Key.NumPadEnter -> "\r"
    Key.Backspace -> ""
    Key.Tab -> if (isShiftPressed) "[Z" else "\t"
    Key.DirectionUp -> "[A"
    Key.DirectionDown -> "[B"
    Key.DirectionRight -> "[C"
    Key.DirectionLeft -> "[D"
    Key.MoveHome -> "[H"
    Key.MoveEnd -> "[F"
    Key.PageUp -> "[5~"
    Key.PageDown -> "[6~"
    Key.Delete -> "[3~"
    Key.Insert -> "[2~"
    Key.Escape -> ""
    else -> null
  }
  if (escapeSequence != null) {
    return escapeSequence.encodeToByteArray()
  }

  val unicodeChar = nativeKeyEvent.unicodeChar
  if (unicodeChar == 0) {
    return null
  }

  // Ctrl+<letter> -> ASCII control byte (Ctrl-A == 0x01), matching terminals.
  if (isCtrlPressed && !isAltPressed) {
    val lower = unicodeChar.toChar().lowercaseChar()
    if (lower in 'a'..'z') {
      return byteArrayOf((lower.code - 'a'.code + 1).toByte())
    }
  }

  val text = String(Character.toChars(unicodeChar))
  // Alt acts as Meta: prefix the character with ESC.
  return if (isAltPressed) {
    ("" + text).encodeToByteArray()
  } else {
    text.encodeToByteArray()
  }
}

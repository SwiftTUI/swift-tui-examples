package sh.swifttui.android.host

import kotlin.math.abs
import kotlin.math.floor

/**
 * Pure, Android-free encoders that turn pointer, key, and paste intent into the
 * terminal byte sequences SwiftTUI's `TerminalInputParser` understands.
 *
 * The Android host delivers input to the runtime as raw terminal bytes — the
 * exact same path a real terminal uses — so drag, scroll, and paste need no
 * Swift-side support: they are just the right SGR (1006) and bracketed-paste
 * byte sequences. Keeping these helpers free of Android types lets them run as
 * plain JVM unit tests.
 *
 * SGR button encoding (matches `TerminalInputParser.decodeMouse`):
 * - base code `button & 0b11`: 0 primary, 1 middle, 2 secondary, 3 none.
 * - `| 32` motion flag → drag/move.
 * - `| 64` wheel flag → scroll; base code selects direction
 *   (0 up, 1 down, 2 left, 3 right).
 * - modifier bits: shift `4`, alt `8`, ctrl `16`.
 * - terminator `M` = press, `m` = release (motion/wheel always use `M`).
 */
object SwiftTUIInput {
  const val BUTTON_PRIMARY = 0
  const val MOTION_FLAG = 32
  const val WHEEL_FLAG = 64

  const val MODIFIER_SHIFT = 4
  const val MODIFIER_ALT = 8
  const val MODIFIER_CTRL = 16

  private const val ESC = ""
  private const val PASTE_START = "$ESC[200~"
  private const val PASTE_END = "$ESC[201~"

  /** 1-based terminal column for a horizontal pixel offset. */
  fun cellColumn(xPx: Float, cellWidthPx: Float): Int =
    floor(xPx / cellWidthPx.coerceAtLeast(1f)).toInt().coerceAtLeast(0) + 1

  /** 1-based terminal row for a vertical pixel offset. */
  fun cellRow(yPx: Float, cellHeightPx: Float): Int =
    floor(yPx / cellHeightPx.coerceAtLeast(1f)).toInt().coerceAtLeast(0) + 1

  /** Raw SGR mouse report. `pressed` chooses the `M`/`m` terminator. */
  fun sgrMouse(
    button: Int,
    column: Int,
    row: Int,
    pressed: Boolean,
    modifiers: Int = 0
  ): ByteArray {
    val terminator = if (pressed) "M" else "m"
    val encodedButton = button or modifiers
    return "$ESC[<$encodedButton;${column.coerceAtLeast(1)};${row.coerceAtLeast(1)}$terminator"
      .encodeToByteArray()
  }

  fun mouseDown(column: Int, row: Int, modifiers: Int = 0): ByteArray =
    sgrMouse(BUTTON_PRIMARY, column, row, pressed = true, modifiers = modifiers)

  fun mouseUp(column: Int, row: Int, modifiers: Int = 0): ByteArray =
    sgrMouse(BUTTON_PRIMARY, column, row, pressed = false, modifiers = modifiers)

  /** Primary-button drag (motion with the button held). */
  fun mouseDrag(column: Int, row: Int, modifiers: Int = 0): ByteArray =
    sgrMouse(BUTTON_PRIMARY or MOTION_FLAG, column, row, pressed = true, modifiers = modifiers)

  /**
   * One vertical wheel notch. `up = true` reports wheel-up (SGR button 64),
   * which the runtime decodes as `scrolled(deltaY: -1)`.
   */
  fun wheel(column: Int, row: Int, up: Boolean, modifiers: Int = 0): ByteArray {
    val base = if (up) 0 else 1
    return sgrMouse(WHEEL_FLAG or base, column, row, pressed = true, modifiers = modifiers)
  }

  /**
   * Encodes a vertical scroll gesture as a run of wheel notches at `column`,
   * `row`. A natural touch swipe upward (negative `deltaLines`) scrolls content
   * down → wheel-down notches; a downward swipe → wheel-up. The magnitude is
   * clamped so a single fling cannot flood the input queue.
   */
  fun verticalScroll(
    column: Int,
    row: Int,
    deltaLines: Int,
    maxNotches: Int = 16,
    modifiers: Int = 0
  ): ByteArray {
    if (deltaLines == 0) {
      return ByteArray(0)
    }
    val up = deltaLines > 0
    val notches = abs(deltaLines).coerceAtMost(maxNotches)
    val builder = StringBuilder()
    repeat(notches) {
      builder.append(wheel(column, row, up, modifiers).decodeToString())
    }
    return builder.toString().encodeToByteArray()
  }

  /**
   * Wraps `text` in a bracketed-paste sequence. Control bytes (other than tab
   * and newline) are stripped so pasted content cannot smuggle the paste-end
   * marker or other escape sequences into the input stream.
   */
  fun bracketedPaste(text: String): ByteArray {
    if (text.isEmpty()) {
      return ByteArray(0)
    }
    val sanitized = buildString {
      for (character in text) {
        val code = character.code
        val isAllowedControl = character == '\n' || character == '\t'
        if (code in 0x00..0x1F && !isAllowedControl) {
          continue
        }
        if (code == 0x7F) {
          continue
        }
        append(character)
      }
    }
    if (sanitized.isEmpty()) {
      return ByteArray(0)
    }
    return "$PASTE_START$sanitized$PASTE_END".encodeToByteArray()
  }
}

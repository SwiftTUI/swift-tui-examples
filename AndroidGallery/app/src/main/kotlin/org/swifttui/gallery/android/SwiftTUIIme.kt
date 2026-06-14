package org.swifttui.gallery.android

/**
 * Pure, Android-free translation of soft-keyboard (IME) edits into terminal
 * input bytes.
 *
 * The Android client hosts an invisible text buffer so the system soft keyboard
 * has something to edit; every edit is diffed against the previous buffer and
 * the delta is forwarded to the runtime as bytes. This matches the SwiftUI
 * host, which routes `UIKeyInput.insertText` / `deleteBackward` — committed text
 * only, no marked/pre-edit composition.
 */
object SwiftTUIIme {
  private const val BACKSPACE = 0x7F.toByte()

  /**
   * Bytes to emit when the IME buffer changes from [old] to [new].
   *
   * - Appended text (common keystroke) → the new suffix as UTF-8.
   * - A pure deletion → one DEL (0x7F) per removed trailing character.
   * - A replacement (selection edit) → DELs for the removed tail, then the
   *   inserted suffix, so the runtime's text reducer ends in the same state.
   *
   * Newlines are normalized to carriage returns, which the text-input reducer
   * treats as submit/return.
   */
  fun bytesForEdit(old: String, new: String): ByteArray {
    if (old == new) {
      return ByteArray(0)
    }

    val shared = commonPrefixLength(old, new)
    val removed = old.length - shared
    val insertedSuffix = new.substring(shared)

    val output = ArrayList<Byte>(removed + insertedSuffix.length)
    repeat(removed) { output.add(BACKSPACE) }
    for (byte in normalizeNewlines(insertedSuffix).encodeToByteArray()) {
      output.add(byte)
    }
    return output.toByteArray()
  }

  private fun commonPrefixLength(a: String, b: String): Int {
    val limit = minOf(a.length, b.length)
    var index = 0
    while (index < limit && a[index] == b[index]) {
      index++
    }
    return index
  }

  private fun normalizeNewlines(text: String): String =
    text.replace("\r\n", "\r").replace('\n', '\r')
}

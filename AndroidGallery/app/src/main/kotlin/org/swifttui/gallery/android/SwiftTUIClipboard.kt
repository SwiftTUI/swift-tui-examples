package org.swifttui.gallery.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context

/**
 * The system clipboard, behind a small interface so [SwiftTUIHostState] stays
 * testable without Android. `write` receives text the running app placed on the
 * clipboard (drained from the host across the ABI); `read` backs paste.
 */
interface SwiftTUIClipboard {
  fun read(): String?

  fun write(text: String)
}

class AndroidSystemClipboard(
  context: Context
) : SwiftTUIClipboard {
  private val appContext = context.applicationContext
  private val manager =
    appContext.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager

  override fun read(): String? {
    val clip = manager?.primaryClip ?: return null
    if (clip.itemCount == 0) {
      return null
    }
    return clip.getItemAt(0)?.coerceToText(appContext)?.toString()?.takeIf { it.isNotEmpty() }
  }

  override fun write(text: String) {
    manager?.setPrimaryClip(ClipData.newPlainText("SwiftTUI", text))
  }
}

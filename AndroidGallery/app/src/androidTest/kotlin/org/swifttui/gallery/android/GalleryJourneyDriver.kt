package org.swifttui.gallery.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color
import android.os.ParcelFileDescriptor
import android.os.PersistableBundle
import android.os.SystemClock
import android.util.Log
import android.view.InputDevice
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.core.view.WindowInsetsCompat
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlin.math.abs
import org.junit.Assert.assertTrue
import sh.swifttui.android.host.SwiftTUIAccessibilityNode
import sh.swifttui.android.host.SwiftTUIAccessibilityValue
import sh.swifttui.android.host.SwiftTUIFrame
import sh.swifttui.android.host.SwiftTUIHostState
import sh.swifttui.android.host.SwiftTUIImageAttachment

/**
 * Drives the gallery through the public Android host for the connected
 * journeys. Frames and semantics come from [AndroidGalleryTestProbe]. Input is
 * a real touch, a hardware key event, or an action on the Android
 * accessibility tree. Screenshots and notes go under the app's external files
 * directory.
 *
 * Every wait is a bounded condition wait through the Compose rule. The rule's
 * test clock drives the host's frame polling and the coroutines the gallery
 * launches, so they only make progress while the rule is waiting; a wall-clock
 * sleep would observe nothing.
 */
internal class GalleryJourneyDriver(
  private val compose: AndroidComposeTestRule<*, MainActivity>,
  private val logTag: String,
  private val artifactDirectory: String
) {
  private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

  fun step(message: String) {
    Log.i(logTag, message)
  }

  // The public frame

  val frame: SwiftTUIFrame?
    get() = AndroidGalleryTestProbe.snapshot?.frame

  fun snapshot(): AndroidGalleryTestProbe.Snapshot =
    requireNotNull(AndroidGalleryTestProbe.snapshot) { "the gallery has not composed" }

  fun hostState(): SwiftTUIHostState = snapshot().hostState

  /** The text rows of the current public frame, top to bottom. */
  fun renderedRows(): List<String> =
    frame?.cells.orEmpty()
      .filterNot { it.isContinuation }
      .groupBy { it.y }
      .toSortedMap()
      .values
      .map { row -> row.sortedBy { it.x }.joinToString("") { it.character }.trimEnd() }

  /**
   * Whether the frame shows [text], ignoring whitespace: a long path wraps
   * across rows, and the wrap must not change what was shown.
   */
  fun showsText(text: String): Boolean {
    val rendered = renderedRows().joinToString("").filterNot { it.isWhitespace() }
    return rendered.contains(text.filterNot { it.isWhitespace() })
  }

  fun visibleNodes(): List<SwiftTUIAccessibilityNode> =
    frame?.accessibilityNodes.orEmpty().filterNot { it.hidden }

  fun focusedNode(): SwiftTUIAccessibilityNode? = visibleNodes().lastOrNull { it.isFocused }

  fun textValue(label: String): String? =
    visibleNodes().singleOrNull { it.label == label }?.textValue

  fun describeFrame(): String {
    val current = frame ?: return "No public frame."
    val nodes = visibleNodes().filter { it.label != null || it.textValue != null }
      .joinToString("; ") { node ->
        "${node.role}:${node.label}@${node.rect.x},${node.rect.y}" +
          (if (node.isFocused) ":focused" else "") +
          (node.textValue?.let { ":<${it.printable()}>" } ?: "")
      }
    return "Frame ${current.sequence} ${current.gridWidth}x${current.gridHeight} " +
      "prefersTextInput=${current.focusPresentation.prefersTextInput} nodes=[$nodes]"
  }

  // Waiting

  /** Waits for [condition], failing with [description] and the current frame's state. */
  fun waitUntil(description: String, timeoutMillis: Long = WAIT_TIMEOUT_MILLIS, condition: () -> Boolean) {
    try {
      compose.waitUntil(timeoutMillis) { condition() }
    } catch (timeout: ComposeTimeoutException) {
      throw AssertionError(
        "Timed out after $timeoutMillis ms waiting for $description. ${describeFrame()} " +
          "rows=${renderedRows().filter { it.isNotBlank() }}",
        timeout
      )
    }
  }

  /**
   * Runs [polls] iterations of the host's 33 ms poll loop on the test clock,
   * one main-thread task per poll so the app never blocks for all of them.
   */
  fun advancePolls(polls: Int) {
    repeat(polls) { compose.mainClock.advanceTimeBy(POLL_INTERVAL_MILLIS) }
    compose.waitForIdle()
  }

  fun waitForGallery() {
    waitUntil("the gallery's first frame") { platformNodes(PALETTE_LABEL).isNotEmpty() }
    step("gallery visible")
  }

  /** The one visible node with [label], once its place in the grid has stopped changing. */
  fun stableNode(label: String): SwiftTUIAccessibilityNode {
    var match: SwiftTUIAccessibilityNode? = null
    var stableSignature: String? = null
    var stableSince = 0L
    waitUntil("exactly one stable '$label' node") {
      val current = frame
      match = visibleNodes().singleOrNull { it.label == label }
      val node = match
      if (current == null || node == null) {
        stableSignature = null
        return@waitUntil false
      }
      val signature = "${current.gridWidth}x${current.gridHeight}:${node.role}:${node.rect}"
      val now = SystemClock.uptimeMillis()
      if (signature != stableSignature) {
        stableSignature = signature
        stableSince = now
        false
      } else {
        now - stableSince >= STABILITY_MILLIS
      }
    }
    return requireNotNull(match)
  }

  // Touch and hardware keys

  /** Touches the middle of the part of [node] that lies inside the host's grid. */
  fun touch(node: SwiftTUIAccessibilityNode) {
    val snapshot = snapshot()
    val current = requireNotNull(snapshot.frame) { "the host has no frame" }
    val left = node.rect.x.coerceAtLeast(0)
    val top = node.rect.y.coerceAtLeast(0)
    val right = (node.rect.x + node.rect.width).coerceAtMost(current.gridWidth)
    val bottom = (node.rect.y + node.rect.height).coerceAtMost(current.gridHeight)
    assertTrue("'${node.label}' ${node.rect} must be on screen to be touched", left < right && top < bottom)
    val hostBounds = compose.onNodeWithTag(HOST_TEST_TAG, useUnmergedTree = true)
      .fetchSemanticsNode().boundsInRoot
    val point = Offset(
      hostBounds.left + (left + right) / 2f * snapshot.style.cellWidthPx,
      hostBounds.top + (top + bottom) / 2f * snapshot.style.cellHeightPx
    )
    assertTrue("'${node.label}' touch must lie inside the public host", hostBounds.contains(point))
    step("touch '${node.label}' grid=${node.rect} root=(${point.x}, ${point.y})")

    val origin = IntArray(2)
    compose.activity.window.decorView.getLocationOnScreen(origin)
    var downTime = 0L
    fun event(action: Int, eventTime: Long): MotionEvent =
      MotionEvent.obtain(downTime, eventTime, action, point.x + origin[0], point.y + origin[1], 0)
        .apply { source = InputDevice.SOURCE_TOUCHSCREEN }
    // After a clipboard write, Android 13 and later show a clipboard preview
    // in the bottom-left corner for a few seconds. It is a system window, and
    // a pointer injected at it is refused before any app sees it. Wait it out.
    waitUntil("a touch on '${node.label}' to reach the gallery's own window") {
      downTime = SystemClock.uptimeMillis()
      val down = event(MotionEvent.ACTION_DOWN, downTime)
      try {
        instrumentation.sendPointerSync(down)
        true
      } catch (refused: IllegalArgumentException) {
        false
      } finally {
        down.recycle()
      }
    }
    event(MotionEvent.ACTION_UP, SystemClock.uptimeMillis()).also { up ->
      instrumentation.sendPointerSync(up)
      up.recycle()
    }
  }

  /** Injects one hardware key press, with Ctrl and/or Shift held. */
  fun key(keyCode: Int, ctrl: Boolean = false, shift: Boolean = false) {
    var metaState = 0
    if (ctrl) metaState = metaState or KeyEvent.META_CTRL_ON or KeyEvent.META_CTRL_LEFT_ON
    if (shift) metaState = metaState or KeyEvent.META_SHIFT_ON or KeyEvent.META_SHIFT_LEFT_ON
    val automation = instrumentation.uiAutomation
    val downTime = SystemClock.uptimeMillis()
    fun event(action: Int): KeyEvent = KeyEvent(
      downTime,
      SystemClock.uptimeMillis(),
      action,
      keyCode,
      0,
      metaState,
      KeyCharacterMap.VIRTUAL_KEYBOARD,
      0,
      KeyEvent.FLAG_FROM_SYSTEM or KeyEvent.FLAG_VIRTUAL_HARD_KEY,
      InputDevice.SOURCE_KEYBOARD
    )
    val name = KeyEvent.keyCodeToString(keyCode)
    assertTrue("$name down should inject", automation.injectInputEvent(event(KeyEvent.ACTION_DOWN), true))
    assertTrue("$name up should inject", automation.injectInputEvent(event(KeyEvent.ACTION_UP), true))
  }

  /** Types [letters] (A to Z only) as hardware key presses. */
  fun typeLetters(letters: String) {
    letters.uppercase().forEach { letter ->
      val keyCode = KeyEvent.keyCodeFromString("KEYCODE_$letter")
      assertTrue("unsupported hardware letter '$letter'", keyCode != KeyEvent.KEYCODE_UNKNOWN)
      key(keyCode)
    }
  }

  /**
   * Waits until a text control has focus, the invisible IME sink owns Compose
   * focus, and the soft keyboard has finished coming up.
   */
  fun waitForImeSinkFocused() {
    waitUntil("the invisible IME sink to own focus") {
      frame?.focusPresentation?.prefersTextInput == true &&
        compose.onAllNodes(hasSetTextAction() and isFocused(), useUnmergedTree = true)
          .fetchSemanticsNodes().size == 1
    }
    waitForSoftKeyboardSettled()
  }

  // A soft keyboard handles hardware letter keys itself and commits their
  // text. While it comes up for a newly focused control its input session is
  // restarted, and a key pressed before that is committed to the session being
  // replaced and lost. On a device that shows a soft keyboard, wait until it
  // is showing and the host's grid has stopped resizing around it.
  private fun waitForSoftKeyboardSettled() {
    val activity = compose.activity
    if (activity.resources.configuration.keyboard != Configuration.KEYBOARD_NOKEYS) {
      return
    }
    var stableGrid: String? = null
    var stableSince = 0L
    waitUntil("the soft keyboard to show and the grid to stop resizing") {
      val insets = activity.window.decorView.rootWindowInsets
      val shown = insets != null &&
        WindowInsetsCompat.toWindowInsetsCompat(insets).isVisible(WindowInsetsCompat.Type.ime())
      val grid = frame?.let { "${it.gridWidth}x${it.gridHeight}" }
      val now = SystemClock.uptimeMillis()
      if (!shown || grid == null) {
        stableGrid = null
        false
      } else if (grid != stableGrid) {
        stableGrid = grid
        stableSince = now
        false
      } else {
        now - stableSince >= STABILITY_MILLIS
      }
    }
  }

  /** Presses Tab until the focused node satisfies [matches]; the runtime scrolls it into view. */
  fun tabUntilFocused(
    description: String,
    maxPresses: Int,
    matches: (SwiftTUIAccessibilityNode) -> Boolean
  ): SwiftTUIAccessibilityNode {
    repeat(maxPresses + 1) { press ->
      focusedNode()?.takeIf(matches)?.let { node ->
        step("$description focused after $press Tab presses")
        return node
      }
      val before = frame?.focusedIdentity
      key(KeyEvent.KEYCODE_TAB)
      waitUntil("Tab press ${press + 1} to move focus toward $description") {
        frame?.focusedIdentity != before
      }
    }
    throw AssertionError("$description never took focus in $maxPresses Tab presses. ${describeFrame()}")
  }

  // The Android accessibility tree

  /** The Android virtual accessibility nodes the host publishes for [description]. */
  fun platformNodes(description: String): List<AccessibilityNodeInfo> {
    val result = mutableListOf<AccessibilityNodeInfo>()
    fun visit(node: AccessibilityNodeInfo?) {
      if (node == null) return
      // The default app still consumes android-host 0.22.1, which leaves cached
      // virtual-node bounds stale when the host moves without a runtime frame.
      // STUI-1536 fixes invalidation in the host source; retain this workaround
      // until the app adopts a released AAR containing that fix. The host's
      // device regression reads fresh bounds without refreshing nodes.
      if (node.contentDescription?.toString() == description && node.refresh()) result.add(node)
      for (index in 0 until node.childCount) visit(node.getChild(index))
    }
    visit(instrumentation.uiAutomation.rootInActiveWindow)
    return result
  }

  /**
   * Performs the click action on the virtual accessibility node the host
   * publishes for [label], as a screen reader's double tap does. Unlike a
   * touch, this reaches a control that lies outside the visible grid.
   */
  fun accessibilityClick(label: String) {
    waitUntil("the accessibility click on '$label' to be queued") {
      val node = platformNodes(label).singleOrNull() ?: return@waitUntil false
      // False means the host did not queue the action, so asking again cannot
      // activate the control twice.
      node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }
    step("accessibility click on '$label'")
  }

  // Tabs

  /**
   * Activates the tab titled [title] through the Android accessibility tree,
   * the route an assistive technology uses, and waits until [shown] appears.
   */
  fun selectTab(title: String, shown: String) {
    waitUntil("the '$title' tab in the Android accessibility tree") {
      platformNodes(title).size == 1
    }
    val tab = platformNodes(title).single()
    assertTrue("the '$title' tab advertises activation", tab.isClickable)
    assertTrue(
      "the '$title' tab accepts activation",
      tab.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    )
    waitUntil("the '$title' tab content") { showsText(shown) }
    step("'$title' tab selected")
  }

  /**
   * Selects the tab titled [title] the way a user with a keyboard does: opens
   * the palette by touch, filters it to [filter] with hardware keys, touches
   * the tab's command, and waits for the node labelled [landmark].
   */
  fun selectTabWithPalette(filter: String, title: String, landmark: String) {
    touch(stableNode(PALETTE_LABEL))
    waitUntil("the palette filter to take focus") {
      visibleNodes().any { it.label == PALETTE_FILTER_LABEL && it.isFocused }
    }
    waitForImeSinkFocused()
    typeLetters(filter)
    waitUntil("the palette filter to read '$filter'") { textValue(PALETTE_FILTER_LABEL) == filter }
    touch(stableNode(title))
    waitUntil("the $title tab to show '$landmark'") {
      visibleNodes().none { it.label == PALETTE_FILTER_LABEL } &&
        visibleNodes().any { it.label == landmark }
    }
    step("$title tab selected")
  }

  // The rendered surface

  fun hostImage(): ImageBitmap =
    compose.onNodeWithTag(HOST_TEST_TAG, useUnmergedTree = true).captureToImage()

  /** The pixel rectangle [attachment] occupies inside [hostImage]. */
  fun pixelBounds(attachment: SwiftTUIImageAttachment): Rect {
    val style = snapshot().style
    return Rect(
      left = attachment.visibleBounds.x * style.cellWidthPx,
      top = attachment.visibleBounds.y * style.cellHeightPx,
      right = (attachment.visibleBounds.x + attachment.visibleBounds.width) * style.cellWidthPx,
      bottom = (attachment.visibleBounds.y + attachment.visibleBounds.height) * style.cellHeightPx
    )
  }

  /** The image attachments in the current frame that have the journey PNG's pixel size. */
  fun journeyImages(): List<SwiftTUIImageAttachment> =
    frame?.imageAttachments.orEmpty().filter { attachment ->
      attachment.pixelSize?.let { it.width == JourneyPng.WIDTH && it.height == JourneyPng.HEIGHT } == true
    }

  /**
   * Waits until the host surface shows the journey PNG's two flat halves
   * inside [image]: the runtime decoded the file and the host painted it.
   */
  fun waitForRenderedJourneyPng(image: SwiftTUIImageAttachment) {
    var left = 0
    var right = 0
    waitUntil("the journey PNG's pixels on the host surface") {
      val pixels = hostImage().toPixelMap()
      val bounds = pixelBounds(image)
      fun sample(normalizedX: Float): Int {
        val x = (bounds.left + bounds.width * normalizedX).toInt().coerceIn(0, pixels.width - 1)
        val y = (bounds.top + bounds.height * 0.5f).toInt().coerceIn(0, pixels.height - 1)
        return pixels[x, y].toArgb()
      }
      left = sample(0.25f)
      right = sample(0.75f)
      closeTo(left, JourneyPng.LEFT_COLOR) && closeTo(right, JourneyPng.RIGHT_COLOR)
    }
    step("rendered halves left=0x${left.toUInt().toString(16)} right=0x${right.toUInt().toString(16)}")
  }

  private fun closeTo(actual: Int, expected: Int): Boolean =
    abs(Color.red(actual) - Color.red(expected)) <= COLOR_TOLERANCE &&
      abs(Color.green(actual) - Color.green(expected)) <= COLOR_TOLERANCE &&
      abs(Color.blue(actual) - Color.blue(expected)) <= COLOR_TOLERANCE

  // System UI

  /**
   * Asks the system UI to close its transient windows, the clipboard preview
   * among them, so the preview of this test's last copy cannot cover the next
   * test's first touch.
   */
  fun closeSystemDialogs() {
    val output = instrumentation.uiAutomation
      .executeShellCommand("am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS")
    ParcelFileDescriptor.AutoCloseInputStream(output).use { it.readBytes() }
  }

  // Artifacts

  fun writeArtifact(name: String, image: ImageBitmap) {
    File(artifactDirectory(), name).outputStream().use { output ->
      image.asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, output)
    }
  }

  /**
   * Records the whole screen, as the user sees it: the host, the soft
   * keyboard, a system window such as the clipboard preview, or another app
   * in front. An artifact, not an assertion.
   */
  fun writeScreenArtifact(name: String) {
    val screen = instrumentation.uiAutomation.takeScreenshot()
    if (screen == null) {
      step("no screenshot available for $name")
      return
    }
    File(artifactDirectory(), name).outputStream().use { output ->
      screen.compress(Bitmap.CompressFormat.PNG, 100, output)
    }
  }

  fun writeArtifact(name: String, text: String) {
    File(artifactDirectory(), name).writeText(text)
  }

  /**
   * Under Gradle's connected test task the runner names a device directory
   * that the Android Gradle plugin copies into
   * `build/outputs/connected_android_test_additional_output` before it removes
   * the app. A bare `am instrument` run keeps the files with the app instead,
   * in its external files directory.
   */
  private fun artifactDirectory(): File {
    val collected = InstrumentationRegistry.getArguments().getString("additionalTestOutputDir")
    val base = collected?.let(::File) ?: instrumentation.targetContext.getExternalFilesDir(null)
    return File(base, artifactDirectory).apply { mkdirs() }
  }

  companion object {
    const val HOST_TEST_TAG = "swiftTUIHost"
    const val PALETTE_LABEL = "⌃K Palette"
    const val PALETTE_FILTER_LABEL = "Filter commands…"
    const val FILE_DROP_TAB = "File Drop"
    const val FILE_DROP_HINT = "Drag a file from Finder onto this terminal to see its path."
    // Generous: the pinned host types a paste into a focused control one key
    // at a time, and each key is a runtime frame.
    const val WAIT_TIMEOUT_MILLIS = 40_000L
    const val STABILITY_MILLIS = 500L
    const val POLL_INTERVAL_MILLIS = 33L
    const val COLOR_TOLERANCE = 24
  }
}

internal val SwiftTUIAccessibilityNode.textValue: String?
  get() = (value as? SwiftTUIAccessibilityValue.TextValue)?.value

internal fun String.printable(): String =
  replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t").replace("\u001B", "\\e")

/**
 * The Android system clipboard as the gallery process sees it. From API 29 only
 * the focused app or the default IME may read the clipboard; an instrumentation
 * test runs inside the app's process, so these reads work while the gallery
 * activity has window focus and return nothing otherwise.
 */
internal class SystemClipboardProbe(private val context: Context) {
  data class State(
    /** Whether a primary clip exists at all. */
    val present: Boolean,
    val itemCount: Int,
    /** The first item's text; `null` for an absent clip or a non-text item. */
    val text: String?,
    val mimeTypes: List<String>,
    /** When the clip was set, in `System.currentTimeMillis()`; 0 when absent. */
    val timestamp: Long
  )

  private val manager: ClipboardManager
    get() = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

  /**
   * Sets the primary clip. An emulator's system UI does not show its clipboard
   * preview for a clip that asks for that, which keeps the preview from
   * covering the gallery after the test's own writes. Other devices ignore it.
   */
  fun set(clip: ClipData) = onMain {
    clip.description.extras = PersistableBundle().apply { putBoolean(SUPPRESS_PREVIEW_EXTRA, true) }
    manager.setPrimaryClip(clip)
  }

  fun setText(text: String) = set(ClipData.newPlainText("clipboard journey", text))

  fun clear() = onMain { manager.clearPrimaryClip() }

  fun state(): State = onMain {
    val clip = manager.primaryClip
    val description = manager.primaryClipDescription
    State(
      present = manager.hasPrimaryClip(),
      itemCount = clip?.itemCount ?: 0,
      text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString(),
      mimeTypes = description?.let { d -> (0 until d.mimeTypeCount).map { d.getMimeType(it) } }.orEmpty(),
      timestamp = description?.timestamp ?: 0L
    )
  }

  private fun <T> onMain(block: () -> T): T {
    var result: Result<T>? = null
    InstrumentationRegistry.getInstrumentation().runOnMainSync { result = runCatching(block) }
    return requireNotNull(result).getOrThrow()
  }

  private companion object {
    const val SUPPRESS_PREVIEW_EXTRA = "com.android.systemui.SUPPRESS_CLIPBOARD_OVERLAY"
  }
}

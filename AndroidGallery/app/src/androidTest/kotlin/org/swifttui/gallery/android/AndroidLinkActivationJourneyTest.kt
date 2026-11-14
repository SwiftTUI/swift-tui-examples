package org.swifttui.gallery.android

import android.app.Activity
import android.app.Instrumentation
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import android.view.InputDevice
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.math.floor
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import sh.swifttui.android.host.SwiftTUIAccessibilityNode
import sh.swifttui.android.host.SwiftTUIFrame

/**
 * A `Link` authored in the shared gallery reaches Android as one `ACTION_VIEW`
 * intent carrying its exact destination.
 *
 * The destination is controlled: an instrumentation activity monitor stands in
 * for the installed handler, so the journey observes the real intent the host
 * starts without leaving the app or depending on which browser the device has.
 */
@RunWith(AndroidJUnit4::class)
class AndroidLinkActivationJourneyTest {
  @get:Rule
  val compose = createAndroidComposeRule<MainActivity>()

  private val instrumentation: Instrumentation = InstrumentationRegistry.getInstrumentation()
  private val viewIntents = ViewIntentMonitor()

  @Before
  fun interceptViewIntents() {
    instrumentation.addMonitor(viewIntents)
  }

  @After
  fun releaseViewIntents() {
    instrumentation.removeMonitor(viewIntents)
  }

  @Test
  fun runtimeLinkReachesAndroidOnceAndFailuresLeaveTheAppUsable() {
    openFormsTab()
    val link = waitForLink()
    step("runtime link '$LINK_DESTINATION' present in the public frame at cells $link")
    assertEquals("no link may open before it is tapped", 0, viewIntents.attempts)

    // Tap: one intent, the exact destination.
    tap(link.center)
    compose.waitUntil(DISPATCH_TIMEOUT_MILLIS) { viewIntents.delivered.isNotEmpty() }
    val intent = viewIntents.delivered.single()
    assertEquals(Intent.ACTION_VIEW, intent.action)
    assertEquals(LINK_DESTINATION, intent.dataString)
    step("ACTION_VIEW reached Android data=${intent.dataString}")
    // Input is handled in order, so a later tap taking effect bounds how long a
    // second dispatch for the first tap could still be on its way.
    flipFocusedTestsAndAwait("build-only")
    assertEquals("one tap must dispatch exactly once", 1, viewIntents.attempts)
    step("tap dispatched exactly once")

    // Drag: a press on the link that is released elsewhere launches nothing.
    waitForLink().let { drag(from = it.center, to = it.beyond) }
    flipFocusedTestsAndAwait("required")
    assertEquals("a drag must not launch the link", 1, viewIntents.attempts)
    step("drag off the link launched nothing")

    // No handler: the platform refuses the intent and the app carries on.
    viewIntents.hasHandler = false
    tap(waitForLink().center)
    compose.waitUntil(DISPATCH_TIMEOUT_MILLIS) { viewIntents.refused.isNotEmpty() }
    assertEquals(LINK_DESTINATION, viewIntents.refused.single().dataString)
    step("platform reported no handler for ${viewIntents.refused.single().dataString}")
    flipFocusedTestsAndAwait("build-only")
    assertFalse("the activity must survive a missing handler", compose.activity.isFinishing)
    assertFalse(compose.activity.isDestroyed)
    assertEquals(1, viewIntents.delivered.size)
    assertEquals(2, viewIntents.attempts)

    // And a handler that comes back is used again.
    viewIntents.hasHandler = true
    tap(waitForLink().center)
    compose.waitUntil(DISPATCH_TIMEOUT_MILLIS) { viewIntents.delivered.size == 2 }
    assertEquals(LINK_DESTINATION, viewIntents.delivered.last().dataString)
    step("app remained usable after the missing handler")
  }

  private fun openFormsTab() {
    tap(center(waitForNode(PALETTE_LABEL)))
    waitForNode(PALETTE_FILTER_LABEL)
    compose.waitUntil(SEMANTICS_TIMEOUT_MILLIS) {
      compose.onAllNodes(hasSetTextAction() and isFocused(), useUnmergedTree = true)
        .fetchSemanticsNodes().size == 1
    }
    compose.waitForIdle()
    FORMS_FILTER.uppercase().forEach { character ->
      injectHardwareKey(KeyEvent.keyCodeFromString("KEYCODE_$character"))
    }
    tap(center(waitForNode(FORMS_COMMAND_LABEL)))
    waitForNode(FOCUSED_TESTS_TOGGLE_LABEL)
    step("Forms & Containers tab selected")
  }

  /** The run of cells in the public frame that carries the gallery link. */
  private fun waitForLink(): LinkCells {
    var link: LinkCells? = null
    waitForStable("cells linking to $LINK_DESTINATION") { frame ->
      val cells = frame.cells.filter { !it.isContinuation && it.hyperlink == LINK_DESTINATION }
      val row = cells.groupBy { it.y }.maxByOrNull { it.value.size }?.value ?: return@waitForStable null
      val left = row.minOf { it.x }
      val right = row.maxOf { it.x + it.spanWidth.coerceAtLeast(1) }
      link = LinkCells(
        left = left,
        right = right,
        row = row.first().y,
        center = root(columns = (left + right) / 2f, rows = row.first().y + 0.5f),
        beyond = root(
          columns = minOf(right + DRAG_CLEARANCE_COLUMNS, frame.gridWidth - 3) + 0.5f,
          rows = row.first().y + 0.5f
        )
      )
      "$left..$right@${row.first().y}"
    }
    return requireNotNull(link)
  }

  /**
   * Flips the form's toggle and waits for the summary row it drives. The
   * runtime handles input in order, so once this later tap has taken effect,
   * every earlier gesture has been dispatched.
   */
  private fun flipFocusedTestsAndAwait(summary: String) {
    tap(center(waitForNode(FOCUSED_TESTS_TOGGLE_LABEL)))
    try {
      compose.waitUntil(REPAINT_TIMEOUT_MILLIS) {
        frameRows().any { it.contains("Focused tests") && it.contains(summary) }
      }
    } catch (failure: androidx.compose.ui.test.ComposeTimeoutException) {
      throw AssertionError("'Focused tests … $summary' never rendered; rows=${frameRows()}", failure)
    }
  }

  private fun waitForNode(label: String): SwiftTUIAccessibilityNode {
    var match: SwiftTUIAccessibilityNode? = null
    waitForStable("accessibility node '$label'") { frame ->
      match = frame.accessibilityNodes.singleOrNull { !it.hidden && it.label == label }
      match?.let { "${it.role}:${it.rect}" }
    }
    return requireNotNull(match)
  }

  /**
   * Waits until [signature] has returned the same non-null value for
   * [STABILITY_MILLIS], so a touch never targets a layout that is still moving.
   */
  private fun waitForStable(what: String, signature: (SwiftTUIFrame) -> String?) {
    var stable: String? = null
    var since = 0L
    try {
      compose.waitUntil(SEMANTICS_TIMEOUT_MILLIS) {
        val current = presentedFrame()?.let(signature)
        val now = SystemClock.uptimeMillis()
        if (current == null || current != stable) {
          stable = current
          since = now
          false
        } else {
          now - since >= STABILITY_MILLIS
        }
      }
    } catch (failure: androidx.compose.ui.test.ComposeTimeoutException) {
      val frame = AndroidGalleryTestProbe.snapshot?.frame
      throw AssertionError(
        "Missing $what; grid=${frame?.gridWidth}x${frame?.gridHeight} " +
          "labels=${frame?.accessibilityNodes?.mapNotNull { it.label }} rows=${frameRows()}",
        failure
      )
    }
  }

  /**
   * The public frame, once it describes the mounted surface. The scene starts
   * on a default grid before the host reports its size, and a cell position in
   * that first layout is not where the control ends up.
   */
  private fun presentedFrame(): SwiftTUIFrame? {
    val snapshot = AndroidGalleryTestProbe.snapshot ?: return null
    val host = hostBounds()
    val columns = floor(host.width / snapshot.style.cellWidthPx).toInt()
    val rows = floor(host.height / snapshot.style.cellHeightPx).toInt()
    return snapshot.frame?.takeIf { it.gridWidth == columns && it.gridHeight == rows }
  }

  private fun frameRows(): List<String> =
    AndroidGalleryTestProbe.snapshot?.frame?.cells.orEmpty()
      .filterNot { it.isContinuation }
      .groupBy { it.y }
      .toSortedMap()
      .values
      .map { row -> row.sortedBy { it.x }.joinToString("") { it.character }.trimEnd() }
      .filter { it.isNotBlank() }

  private fun hostBounds() =
    compose.onNodeWithTag(HOST_TEST_TAG, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot

  private fun center(node: SwiftTUIAccessibilityNode): Offset =
    root(
      columns = node.rect.x + node.rect.width / 2f,
      rows = node.rect.y + node.rect.height / 2f
    )

  /** Root coordinates of a point given in public-frame cells. */
  private fun root(columns: Float, rows: Float): Offset {
    val style = requireNotNull(AndroidGalleryTestProbe.snapshot).style
    val host = hostBounds()
    return Offset(host.left + columns * style.cellWidthPx, host.top + rows * style.cellHeightPx)
  }

  private fun tap(point: Offset) {
    assertTrue("touch $point must lie inside the public host", hostBounds().contains(point))
    touch(listOf(point))
  }

  private fun drag(from: Offset, to: Offset) {
    assertTrue("drag must start inside the public host", hostBounds().contains(from))
    touch((0..DRAG_STEPS).map { step -> from + (to - from) * (step / DRAG_STEPS.toFloat()) })
  }

  /** Presses at the first point, moves through the rest, and releases at the last. */
  private fun touch(path: List<Offset>) {
    val origin = IntArray(2)
    compose.activity.window.decorView.getLocationOnScreen(origin)
    val downTime = SystemClock.uptimeMillis()
    fun send(action: Int, point: Offset) {
      val event = MotionEvent.obtain(
        downTime, SystemClock.uptimeMillis(), action, point.x + origin[0], point.y + origin[1], 0
      ).apply { source = InputDevice.SOURCE_TOUCHSCREEN }
      instrumentation.sendPointerSync(event)
      event.recycle()
    }
    send(MotionEvent.ACTION_DOWN, path.first())
    path.drop(1).forEach { send(MotionEvent.ACTION_MOVE, it) }
    send(MotionEvent.ACTION_UP, path.last())
  }

  private fun injectHardwareKey(keyCode: Int) {
    assertFalse("unsupported hardware key", keyCode == KeyEvent.KEYCODE_UNKNOWN)
    val downTime = SystemClock.uptimeMillis()
    for (action in listOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
      val event = KeyEvent(
        downTime, SystemClock.uptimeMillis(), action, keyCode, 0, 0,
        KeyCharacterMap.VIRTUAL_KEYBOARD, 0,
        KeyEvent.FLAG_FROM_SYSTEM or KeyEvent.FLAG_VIRTUAL_HARD_KEY,
        InputDevice.SOURCE_KEYBOARD
      )
      assertTrue("hardware key $keyCode should inject", instrumentation.uiAutomation.injectInputEvent(event, true))
    }
  }

  private fun step(message: String) {
    Log.i(TEST_LOG_TAG, message)
  }

  /** A link's cells, with root coordinates on the link and past its end on the same row. */
  private data class LinkCells(
    val left: Int,
    val right: Int,
    val row: Int,
    val center: Offset,
    val beyond: Offset
  ) {
    override fun toString() = "$left..<$right on row $row"
  }

  /**
   * Stands in for the installed `ACTION_VIEW` handler. A started intent is
   * recorded and answered here instead of launching another app; with
   * [hasHandler] off it is refused the way the platform refuses an intent no
   * activity resolves.
   */
  private class ViewIntentMonitor : Instrumentation.ActivityMonitor() {
    val delivered = CopyOnWriteArrayList<Intent>()
    val refused = CopyOnWriteArrayList<Intent>()

    @Volatile
    var hasHandler = true

    val attempts: Int
      get() = delivered.size + refused.size

    override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
      if (intent.action != Intent.ACTION_VIEW) {
        return null
      }
      if (!hasHandler) {
        refused.add(Intent(intent))
        throw ActivityNotFoundException("No Activity found to handle $intent")
      }
      delivered.add(Intent(intent))
      return Instrumentation.ActivityResult(Activity.RESULT_OK, null)
    }
  }

  private companion object {
    const val HOST_TEST_TAG = "swiftTUIHost"
    const val TEST_LOG_TAG = "LinkJourney"
    const val PALETTE_LABEL = "⌃K Palette"
    const val PALETTE_FILTER_LABEL = "Filter commands…"
    const val FORMS_FILTER = "forms"
    const val FORMS_COMMAND_LABEL = "Forms & Containers"
    const val FOCUSED_TESTS_TOGGLE_LABEL = "Include focused tests"
    const val LINK_DESTINATION = "https://github.com/SwiftTUI/swift-tui"
    const val SEMANTICS_TIMEOUT_MILLIS = 20_000L
    const val STABILITY_MILLIS = 500L
    const val REPAINT_TIMEOUT_MILLIS = 10_000L
    const val DISPATCH_TIMEOUT_MILLIS = 10_000L
    const val DRAG_STEPS = 8
    const val DRAG_CLEARANCE_COLUMNS = 6
  }
}

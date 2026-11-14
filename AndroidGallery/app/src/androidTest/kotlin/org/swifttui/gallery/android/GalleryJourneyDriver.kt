package org.swifttui.gallery.android

import android.graphics.Bitmap
import android.graphics.Color
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlin.math.abs
import org.junit.Assert.assertTrue
import sh.swifttui.android.host.SwiftTUIFrame
import sh.swifttui.android.host.SwiftTUIHostState
import sh.swifttui.android.host.SwiftTUIImageAttachment

/**
 * Drives the gallery through the public Android host for the file journeys:
 * reads the published frame, activates a tab through the Android accessibility
 * tree, and records screenshots under the app's external files directory.
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

  fun snapshot(): AndroidGalleryTestProbe.Snapshot =
    requireNotNull(AndroidGalleryTestProbe.snapshot) { "the gallery has not composed" }

  fun frame(): SwiftTUIFrame = requireNotNull(snapshot().frame) { "the host has no frame" }

  fun hostState(): SwiftTUIHostState = snapshot().hostState

  /** The text rows of the current public frame, top to bottom. */
  fun renderedRows(): List<String> =
    AndroidGalleryTestProbe.snapshot?.frame?.cells.orEmpty()
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

  /**
   * Waits through the Compose rule rather than by sleeping: the rule's test
   * clock drives the host's frame polling and the coroutines the gallery
   * launches, so they only make progress while the rule is waiting.
   */
  fun waitUntil(description: String, timeoutMillis: Long = WAIT_TIMEOUT_MILLIS, condition: () -> Boolean) {
    try {
      compose.waitUntil(timeoutMillis) { condition() }
    } catch (timeout: ComposeTimeoutException) {
      throw AssertionError(
        "Timed out after $timeoutMillis ms waiting for $description; " +
          "rows=${renderedRows().filter { it.isNotBlank() }}",
        timeout
      )
    }
  }

  fun waitForGallery() {
    waitUntil("the gallery's first frame") { platformNodes(PALETTE_LABEL).isNotEmpty() }
    step("gallery visible")
  }

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

  /** The Android virtual accessibility nodes the host publishes for [description]. */
  fun platformNodes(description: String): List<AccessibilityNodeInfo> {
    val result = mutableListOf<AccessibilityNodeInfo>()
    fun visit(node: AccessibilityNodeInfo?) {
      if (node == null) return
      if (node.contentDescription?.toString() == description) result.add(node)
      for (index in 0 until node.childCount) visit(node.getChild(index))
    }
    visit(instrumentation.uiAutomation.rootInActiveWindow)
    return result
  }

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
    AndroidGalleryTestProbe.snapshot?.frame?.imageAttachments.orEmpty().filter { attachment ->
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

  fun writeArtifact(name: String, image: ImageBitmap) {
    File(artifactDirectory(), name).outputStream().use { output ->
      image.asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, output)
    }
  }

  /** Records the whole screen: the host, the app's native controls, or another app in front. */
  fun writeScreenArtifact(name: String) {
    val screen = instrumentation.uiAutomation.takeScreenshot() ?: return
    File(artifactDirectory(), name).outputStream().use { output ->
      screen.compress(Bitmap.CompressFormat.PNG, 100, output)
    }
  }

  fun writeArtifact(name: String, text: String) {
    File(artifactDirectory(), name).writeText(text)
  }

  /**
   * Under Gradle's connected test task the runner names a directory it copies
   * back to the build outputs; otherwise the app's external files directory.
   */
  private fun artifactDirectory(): File {
    val collected = InstrumentationRegistry.getArguments().getString("additionalTestOutputDir")
    val base = collected?.let(::File) ?: instrumentation.targetContext.getExternalFilesDir(null)
    return File(base, artifactDirectory).apply { mkdirs() }
  }

  companion object {
    const val HOST_TEST_TAG = "swiftTUIHost"
    const val PALETTE_LABEL = "⌃K Palette"
    const val FILE_DROP_TAB = "File Drop"
    const val FILE_DROP_HINT = "Drag a file from Finder onto this terminal to see its path."
    const val WAIT_TIMEOUT_MILLIS = 30_000L
    const val COLOR_TOLERANCE = 24
  }
}

package org.swifttui.gallery.android

import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Log
import android.view.InputDevice
import android.view.KeyEvent
import android.view.KeyCharacterMap
import android.view.MotionEvent
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlin.math.abs
import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import sh.swifttui.android.host.SwiftTUIAccessibilityNode

@RunWith(AndroidJUnit4::class)
class AndroidPreviewReadinessJourneyTest {
  @get:Rule
  val compose = createAndroidComposeRule<MainActivity>()

  @Test
  fun publicHostRendersInteractsRetainsSemanticsAndAlpha() {
    waitForDescription(PALETTE_LABEL)
    step("initial gallery semantics visible")
    val firstFrame = hostImage()
    assertTrue("the public host should render a non-uniform frame", distinctColorCount(firstFrame) > 16)
    writeArtifact("initial-gallery.png", firstFrame)
    step("initial public-host frame verified")

    val palette = compose.onNodeWithContentDescription(PALETTE_LABEL)
    palette.assert(
      SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    )
    palette.assert(hasClickAction().not())
    step("one-way semantic presentation verified")

    openPaletteWithTouch()
    writeArtifact("palette-open.png", hostImage())
    selectPaletteCommandWithHardwareFilter("counter", COUNTER_COMMAND_LABEL)
    waitForDescription(RESET_COUNTER_LABEL)
    step("Counter tab selected by touch after hardware filtering")

    val counterBefore = hostImage()
    writeArtifact("counter-before.png", counterBefore)
    val counterControls = counterControls()
    val countBefore = cropHash(counterBefore, counterControls.countRegion)
    assertEquals(
      "initial public-frame counter value",
      FUTURE_ZERO_GLYPH,
      counterValueText(counterControls)
    )
    writeCropArtifact("counter-before-count.png", counterBefore, counterControls.countRegion)

    step("dispatching increment touch")
    val increment = compose.onAllNodes(
      hasContentDescription(GENERIC_BUTTON_LABEL),
      useUnmergedTree = true
    )[counterControls.incrementIndex].fetchSemanticsNode().boundsInRoot
    dispatchTouchAt(increment.center, "Counter increment")
    step("increment touch dispatched")

    compose.waitUntil(REPAINT_TIMEOUT_MILLIS) {
      cropHash(hostImage(), counterControls.countRegion) != countBefore &&
        counterValueText(counterControls) == FUTURE_ONE_GLYPH
    }
    val counterIncremented = hostImage()
    val incrementedCount = cropHash(counterIncremented, counterControls.countRegion)
    assertFalse("touch input should repaint the count glyph", incrementedCount == countBefore)
    assertEquals(
      "incremented public-frame counter value",
      FUTURE_ONE_GLYPH,
      counterValueText(counterControls)
    )
    writeArtifact("counter-incremented.png", counterIncremented)
    writeCropArtifact("counter-incremented-count.png", counterIncremented, counterControls.countRegion)
    step("state-changing repaint verified")

    openPaletteWithTouch()
    selectPaletteCommandWithHardwareFilter("images", IMAGES_COMMAND_LABEL)
    waitForDescription(ANIMATED_IMAGE_LABEL)
    step("Images tab selected by touch after hardware filtering")

    val imageSemantics = compose.onNodeWithContentDescription(ANIMATED_IMAGE_LABEL)
    imageSemantics.assert(
      SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Image)
    )
    imageSemantics.assert(hasClickAction().not())
    val animatedImageBounds = imageSemantics.fetchSemanticsNode().boundsInRoot
    val publicAnimatedImage = waitForHostAccessibilityNode(ANIMATED_IMAGE_LABEL)
    assertEquals("Animated image public-frame role", "image", publicAnimatedImage.role)
    assertPublicFrameBoundsMatchCompose(publicAnimatedImage, animatedImageBounds)

    val imagesFrame = hostImage()
    assertTransparentPNGComposited(imagesFrame, publicAnimatedImage)
    writeArtifact("images-alpha.png", imagesFrame)
    step("image alpha compositing verified")

    openPaletteWithTouch()
    selectPaletteCommandWithHardwareFilter("counter", COUNTER_COMMAND_LABEL)
    waitForDescription(RESET_COUNTER_LABEL)
    step("Counter tab reselected by touch after hardware filtering")

    val restoredControls = counterControls()
    compose.waitUntil(REPAINT_TIMEOUT_MILLIS) {
      counterValueText(restoredControls) == FUTURE_ONE_GLYPH
    }
    val counterRestored = hostImage()
    assertEquals(
      "the counter value should survive a Counter -> Images -> Counter tab journey",
      FUTURE_ONE_GLYPH,
      counterValueText(restoredControls)
    )
    writeArtifact("counter-restored.png", counterRestored)
    writeCropArtifact("counter-restored-count.png", counterRestored, restoredControls.countRegion)
    step("retained Counter value verified")
  }

  private fun step(message: String) {
    Log.i(TEST_LOG_TAG, message)
  }

  private fun openPaletteWithTouch() {
    AndroidGalleryTestProbe.snapshot?.frame?.let { frame ->
      step(
        "public-frame Palette lookup sequence=${frame.sequence} " +
          "labels=${frame.accessibilityNodes.mapNotNull { it.label }}"
      )
    }
    val node = waitForHostAccessibilityNode(PALETTE_LABEL)
    val style = requireNotNull(AndroidGalleryTestProbe.snapshot).style
    assertEquals("Palette public-frame role", "button", node.role)
    assertTrue("Palette public-frame rect must be nonempty", node.rect.width > 0 && node.rect.height > 0)
    assertTrue("public host cell metrics must be positive", style.cellWidthPx > 0 && style.cellHeightPx > 0)
    val hostBounds = compose.onNodeWithTag(
      HOST_TEST_TAG,
      useUnmergedTree = true
    ).fetchSemanticsNode().boundsInRoot
    val bounds = Rect(
      left = hostBounds.left + node.rect.x * style.cellWidthPx,
      top = hostBounds.top + node.rect.y * style.cellHeightPx,
      right = hostBounds.left + (node.rect.x + node.rect.width) * style.cellWidthPx,
      bottom = hostBounds.top + (node.rect.y + node.rect.height) * style.cellHeightPx
    )
    val composeBounds = compose.onNodeWithContentDescription(PALETTE_LABEL)
      .fetchSemanticsNode().boundsInRoot
    assertPublicFrameBoundsMatchCompose(node, composeBounds)
    val decorWidth = compose.activity.window.decorView.width.toFloat()
    val decorHeight = compose.activity.window.decorView.height.toFloat()
    assertTrue(
      "the transformed Palette frame must lie inside the Android content surface",
      bounds.left >= 0f && bounds.top >= 0f &&
        bounds.right <= decorWidth && bounds.bottom <= decorHeight
    )
    assertTrue(
      "grid-to-pixel width must use the exact public host metric",
      abs(bounds.width - node.rect.width * style.cellWidthPx) < 0.01f
    )
    assertTrue(
      "grid-to-pixel height must use the exact public host metric",
      abs(bounds.height - node.rect.height * style.cellHeightPx) < 0.01f
    )
    step(
      "Palette public-frame touch root=(${composeBounds.center.x}, ${composeBounds.center.y}) " +
        "grid=${node.rect} bounds=$composeBounds"
    )
    dispatchTouchAt(composeBounds.center, "Palette public frame")
    waitForDescription(PALETTE_FILTER_LABEL)
  }

  private fun waitForHostAccessibilityNode(description: String): SwiftTUIAccessibilityNode {
    var matches: List<SwiftTUIAccessibilityNode> = emptyList()
    var stableSignature: String? = null
    var stableSince = 0L
    compose.waitUntil(SEMANTICS_TIMEOUT_MILLIS) {
      val frame = AndroidGalleryTestProbe.snapshot?.frame
      matches = frame?.accessibilityNodes.orEmpty().filter { node ->
        !node.hidden && node.label == description
      }
      if (frame == null || matches.size != 1) {
        stableSignature = null
        return@waitUntil false
      }
      val node = matches.single()
      val signature = "${frame.gridWidth}x${frame.gridHeight}:${node.role}:${node.label}:${node.rect}"
      val now = SystemClock.uptimeMillis()
      if (signature != stableSignature) {
        stableSignature = signature
        stableSince = now
        false
      } else {
        now - stableSince >= SEMANTICS_STABILITY_MILLIS
      }
    }
    val frame = AndroidGalleryTestProbe.snapshot?.frame
    assertEquals(
      "public frame ${frame?.sequence} should expose exactly one '$description'; " +
        "labels=${frame?.accessibilityNodes?.mapNotNull { it.label }}",
      1,
      matches.size
    )
    return matches.single()
  }

  private fun assertPublicFrameBoundsMatchCompose(
    node: SwiftTUIAccessibilityNode,
    composeBounds: Rect
  ) {
    val snapshot = requireNotNull(AndroidGalleryTestProbe.snapshot)
    val hostBounds = compose.onNodeWithTag(
      HOST_TEST_TAG,
      useUnmergedTree = true
    ).fetchSemanticsNode().boundsInRoot
    val offsetX = (node.rect.x * snapshot.style.cellWidthPx).roundToInt()
    val offsetY = (node.rect.y * snapshot.style.cellHeightPx).roundToInt()
    val width = (node.rect.width * snapshot.style.cellWidthPx).roundToInt()
    val height = (node.rect.height * snapshot.style.cellHeightPx).roundToInt()
    val expected = Rect(
      left = hostBounds.left + offsetX,
      top = hostBounds.top + offsetY,
      right = hostBounds.left + offsetX + width,
      bottom = hostBounds.top + offsetY + height
    )
    assertTrue(
      "the Compose image overlay must use the public frame's exact grid-to-pixel transform; " +
        "public=$expected Compose=$composeBounds",
      expected == composeBounds
    )
  }

  private fun dispatchTouchAt(
    point: androidx.compose.ui.geometry.Offset,
    target: String,
    requireHostContainment: Boolean = true
  ) {
    val hostBounds = compose.onNodeWithTag(
      HOST_TEST_TAG,
      useUnmergedTree = true
    ).fetchSemanticsNode().boundsInRoot
    if (requireHostContainment) {
      assertTrue("$target touch must lie inside the public host", hostBounds.contains(point))
    }
    step(
      "$target touch root=(${point.x}, ${point.y}) " +
        "host=${hostBounds.left},${hostBounds.top}-${hostBounds.right},${hostBounds.bottom} " +
        "local=(${point.x - hostBounds.left}, ${point.y - hostBounds.top})"
    )

    val instrumentation = InstrumentationRegistry.getInstrumentation()
    val downTime = SystemClock.uptimeMillis()
    fun event(action: Int, eventTime: Long): MotionEvent =
      MotionEvent.obtain(
        downTime,
        eventTime,
        action,
        point.x,
        point.y,
        0
      ).apply {
        source = InputDevice.SOURCE_TOUCHSCREEN
      }

    event(MotionEvent.ACTION_DOWN, downTime).also { down ->
      instrumentation.sendPointerSync(down)
      down.recycle()
    }
    val upTime = SystemClock.uptimeMillis()
    event(MotionEvent.ACTION_UP, upTime).also { up ->
      instrumentation.sendPointerSync(up)
      up.recycle()
    }
  }

  private fun selectPaletteCommandWithHardwareFilter(command: String, label: String) {
    val unfilteredFrame = requireNotNull(AndroidGalleryTestProbe.snapshot?.frame)
    val unfilteredImage = hostImage()
    val unfilteredHash = cropHash(
      unfilteredImage,
      Rect(0f, 0f, unfilteredImage.width.toFloat(), unfilteredImage.height.toFloat())
    )
    compose.waitUntil(SEMANTICS_TIMEOUT_MILLIS) {
      compose.onAllNodes(
        hasSetTextAction() and isFocused(),
        useUnmergedTree = true
      ).fetchSemanticsNodes().size == 1
    }
    compose.waitForIdle()
    step("hardware text-input sink focused")
    command.uppercase().forEach { character ->
      val keyCode = KeyEvent.keyCodeFromString("KEYCODE_$character")
      assertFalse("unsupported hardware character '$character'", keyCode == KeyEvent.KEYCODE_UNKNOWN)
      injectHardwareKey(keyCode)
    }
    compose.waitUntil(SEMANTICS_TIMEOUT_MILLIS) {
      compose.onAllNodes(
        hasSetTextAction() and isFocused() and hasText(command, ignoreCase = true),
        useUnmergedTree = true
      ).fetchSemanticsNodes().size == 1
    }
    step("hardware character events reached the public host IME sink")
    compose.waitUntil(REPAINT_TIMEOUT_MILLIS) {
      val image = hostImage()
      AndroidGalleryTestProbe.snapshot?.frame?.sequence != unfilteredFrame.sequence &&
        cropHash(image, Rect(0f, 0f, image.width.toFloat(), image.height.toFloat())) != unfilteredHash
    }
    AndroidGalleryTestProbe.snapshot?.frame?.let { frame ->
      val renderedRows = frame.cells
        .filterNot { it.isContinuation }
        .groupBy { it.y }
        .toSortedMap()
        .values
        .map { row -> row.sortedBy { it.x }.joinToString("") { it.character }.trimEnd() }
        .filter { it.isNotBlank() }
      step(
        "hardware-filtered frame sequence=${frame.sequence} " +
          "labels=${frame.accessibilityNodes.mapNotNull { it.label }} " +
          "rows=$renderedRows"
      )
    }
    step("hardware filtering produced a state-changing public-host repaint")
    writeArtifact("palette-filtered-$command.png", hostImage())
    val publicCommand = waitForHostAccessibilityNode(label)
    assertEquals("filtered command public-frame role", "button", publicCommand.role)
    val composeCommand = compose.onNodeWithContentDescription(label)
    composeCommand.assert(
      SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    )
    composeCommand.assert(hasClickAction().not())
    val composeBounds = composeCommand.fetchSemanticsNode().boundsInRoot
    assertPublicFrameBoundsMatchCompose(publicCommand, composeBounds)
    step("hardware-filtered $label command presented with matching public/Compose bounds")
    dispatchTouchAt(composeBounds.center, "$label filtered palette command")
  }

  private fun injectHardwareKey(keyCode: Int) {
    val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
    val downTime = SystemClock.uptimeMillis()
    fun event(action: Int): KeyEvent = KeyEvent(
      downTime,
      SystemClock.uptimeMillis(),
      action,
      keyCode,
      0,
      0,
      KeyCharacterMap.VIRTUAL_KEYBOARD,
      0,
      KeyEvent.FLAG_FROM_SYSTEM or KeyEvent.FLAG_VIRTUAL_HARD_KEY,
      InputDevice.SOURCE_KEYBOARD
    )
    assertTrue("hardware key-down $keyCode should inject", automation.injectInputEvent(event(KeyEvent.ACTION_DOWN), true))
    assertTrue("hardware key-up $keyCode should inject", automation.injectInputEvent(event(KeyEvent.ACTION_UP), true))
  }

  private fun waitForDescription(description: String) {
    compose.waitUntil(SEMANTICS_TIMEOUT_MILLIS) {
      compose.onAllNodes(
        hasContentDescription(description),
        useUnmergedTree = true
      ).fetchSemanticsNodes().isNotEmpty()
    }
  }

  private fun hostImage(): ImageBitmap =
    compose.onNodeWithTag(HOST_TEST_TAG, useUnmergedTree = true).captureToImage()

  private fun counterControls(): CounterControls {
    val interactions = compose.onAllNodes(
      hasContentDescription(GENERIC_BUTTON_LABEL),
      useUnmergedTree = true
    )
    val nodes = interactions.fetchSemanticsNodes()
    assertTrue("counter should expose its math buttons", nodes.size >= 2)

    val indexed = nodes.mapIndexed { index, node -> index to node.boundsInRoot }
    val topCenter = indexed.minOf { (_, bounds) -> bounds.center.y }
    val topRow = indexed.filter { (_, bounds) -> abs(bounds.center.y - topCenter) < 2f }
    assertEquals("counter should expose decrement and increment on one row", 2, topRow.size)
    val decrement = topRow.minBy { (_, bounds) -> bounds.center.x }
    val increment = topRow.maxBy { (_, bounds) -> bounds.center.x }
    val hostBounds = compose.onNodeWithTag(
      HOST_TEST_TAG,
      useUnmergedTree = true
    ).fetchSemanticsNode().boundsInRoot

    return CounterControls(
      incrementIndex = increment.first,
      countRegion = Rect(
        left = decrement.second.right - hostBounds.left,
        top = maxOf(decrement.second.top, increment.second.top) - hostBounds.top,
        right = increment.second.left - hostBounds.left,
        bottom = minOf(decrement.second.bottom, increment.second.bottom) - hostBounds.top
      )
    )
  }

  private fun cropHash(image: ImageBitmap, rect: Rect): Long {
    val pixels = image.toPixelMap()
    val left = rect.left.toInt().coerceIn(0, pixels.width - 1)
    val top = rect.top.toInt().coerceIn(0, pixels.height - 1)
    val right = rect.right.toInt().coerceIn(left + 1, pixels.width)
    val bottom = rect.bottom.toInt().coerceIn(top + 1, pixels.height)
    var hash = 0xcbf29ce484222325UL
    for (y in top until bottom) {
      for (x in left until right) {
        hash = (hash xor pixels[x, y].toArgb().toUInt().toULong()) * 0x100000001b3UL
      }
    }
    return hash.toLong()
  }

  private fun counterValueText(controls: CounterControls): String {
    val snapshot = requireNotNull(AndroidGalleryTestProbe.snapshot)
    val frame = requireNotNull(snapshot.frame)
    return frame.cells.filter { cell ->
      if (cell.isContinuation || cell.character.isBlank()) {
        return@filter false
      }
      val centerX = (cell.x + cell.spanWidth.coerceAtLeast(1) / 2f) * snapshot.style.cellWidthPx
      val centerY = (cell.y + 0.5f) * snapshot.style.cellHeightPx
      centerX >= controls.countRegion.left && centerX < controls.countRegion.right &&
        centerY >= controls.countRegion.top && centerY < controls.countRegion.bottom
    }.groupBy { it.y }
      .toSortedMap()
      .values
      .joinToString(separator = "\n") { row ->
        row.sortedBy { it.x }.joinToString(separator = "") { it.character }
      }
  }

  private fun distinctColorCount(image: ImageBitmap): Int {
    val pixels = image.toPixelMap()
    val colors = HashSet<Int>()
    for (y in 0 until pixels.height step 8) {
      for (x in 0 until pixels.width step 8) {
        colors += pixels[x, y].toArgb()
        if (colors.size > 16) return colors.size
      }
    }
    return colors.size
  }

  private fun assertTransparentPNGComposited(
    image: ImageBitmap,
    animatedImageNode: SwiftTUIAccessibilityNode
  ) {
    val pixels = image.toPixelMap()
    val snapshot = requireNotNull(AndroidGalleryTestProbe.snapshot)
    val frame = requireNotNull(snapshot.frame)
    val style = snapshot.style

    // The static images are decorative; the authored GIF is the one logical
    // image semantic in this row. Use that public semantic to identify the row,
    // then use the public attachment placements for the PNG and JPEG. This is
    // the same grid-to-pixel transform used by SwiftTUIRenderer.
    val animatedAttachments = frame.imageAttachments.filter { attachment ->
      attachment.visibleBounds == animatedImageNode.rect &&
        attachment.pixelSize?.let { it.width == 70 && it.height == 70 } == true
    }
    assertEquals("the labelled GIF should own exactly one public image attachment", 1, animatedAttachments.size)
    val pngAttachments = frame.imageAttachments.filter { attachment ->
      attachment.pixelSize?.let { it.width == 85 && it.height == 128 } == true &&
        attachment.visibleBounds.x < animatedImageNode.rect.x &&
        attachment.visibleBounds.y < animatedImageNode.rect.y + animatedImageNode.rect.height &&
        attachment.visibleBounds.y + attachment.visibleBounds.height > animatedImageNode.rect.y
    }
    assertEquals("the GIF row should contain exactly one 85x128 PNG attachment", 1, pngAttachments.size)
    val pngAttachment = pngAttachments.single()
    val jpegAttachments = frame.imageAttachments.filter { attachment ->
      attachment.pixelSize?.let { it.width == 70 && it.height == 70 } == true &&
        attachment.visibleBounds.x >= pngAttachment.visibleBounds.x + pngAttachment.visibleBounds.width &&
        attachment.visibleBounds.x + attachment.visibleBounds.width <= animatedImageNode.rect.x &&
        attachment.visibleBounds.y < pngAttachment.visibleBounds.y + pngAttachment.visibleBounds.height &&
        attachment.visibleBounds.y + attachment.visibleBounds.height > pngAttachment.visibleBounds.y
    }
    assertEquals("the PNG-to-GIF interval should contain exactly one JPEG attachment", 1, jpegAttachments.size)
    val jpegAttachment = jpegAttachments.single()
    assertTrue(
      "the PNG and JPEG public attachment placements should leave a surface gap",
      pngAttachment.visibleBounds.x + pngAttachment.visibleBounds.width < jpegAttachment.visibleBounds.x
    )

    fun pixelBounds(attachment: sh.swifttui.android.host.SwiftTUIImageAttachment): Rect =
      Rect(
        left = attachment.visibleBounds.x * style.cellWidthPx,
        top = attachment.visibleBounds.y * style.cellHeightPx,
        right = (attachment.visibleBounds.x + attachment.visibleBounds.width) * style.cellWidthPx,
        bottom = (attachment.visibleBounds.y + attachment.visibleBounds.height) * style.cellHeightPx
      )

    val pngBounds = pixelBounds(pngAttachment)
    assertTrue(
      "the PNG public attachment must lie inside the captured host frame",
      pngBounds.left >= 0f && pngBounds.top >= 0f &&
        pngBounds.right <= pixels.width.toFloat() &&
        pngBounds.bottom <= pixels.height.toFloat()
    )

    fun argbAt(normalizedX: Float, normalizedY: Float): Int {
      val x = (pngBounds.left + pngBounds.width * normalizedX)
        .toInt().coerceIn(0, pixels.width - 1)
      val y = (pngBounds.top + pngBounds.height * normalizedY)
        .toInt().coerceIn(0, pixels.height - 1)
      return pixels[x, y].toArgb()
    }

    // The embedded 85x128 PNG has a 5x5 fully transparent source neighborhood
    // around each 10%-inset coordinate. Its center is opaque red/orange. Sample
    // the surface independently in the attachment-derived PNG/JPEG gap.
    val surfaceX = (
      (pngAttachment.visibleBounds.x + pngAttachment.visibleBounds.width +
        jpegAttachment.visibleBounds.x) / 2f * style.cellWidthPx
      )
      .toInt().coerceIn(0, pixels.width - 1)
    val surfaceY = (pngBounds.top + pngBounds.height * 0.10f)
      .toInt().coerceIn(0, pixels.height - 1)
    val outsideSurfaceColor = pixels[surfaceX, surfaceY].toArgb()
    val transparentSourceCoordinates = listOf(
      0.10f to 0.10f,
      0.90f to 0.10f,
      0.10f to 0.90f,
      0.90f to 0.90f
    )
    transparentSourceCoordinates.forEach { (x, y) ->
      assertEquals(
        "transparent PNG coordinate ($x, $y) should reveal the independently sampled surface",
        outsideSurfaceColor,
        argbAt(x, y)
      )
    }
    val opaqueCenter = argbAt(0.50f, 0.50f)
    assertTrue(
      "the PNG's known opaque center must render non-vacuous red/orange image content; " +
        "center=0x${opaqueCenter.toUInt().toString(16)} surface=0x${outsideSurfaceColor.toUInt().toString(16)}",
      android.graphics.Color.red(opaqueCenter) >= 200 &&
        android.graphics.Color.red(opaqueCenter) > android.graphics.Color.green(opaqueCenter) * 2 &&
        android.graphics.Color.blue(opaqueCenter) < 80 &&
        opaqueCenter != outsideSurfaceColor
    )
  }

  private fun writeArtifact(name: String, image: ImageBitmap) {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val directory = File(context.getExternalFilesDir(null), "preview-readiness").apply {
      mkdirs()
    }
    File(directory, name).outputStream().use { output ->
      image.asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, output)
    }
  }

  private fun writeCropArtifact(name: String, image: ImageBitmap, rect: Rect) {
    val source = image.asAndroidBitmap()
    val left = rect.left.toInt().coerceIn(0, source.width - 1)
    val top = rect.top.toInt().coerceIn(0, source.height - 1)
    val right = rect.right.toInt().coerceIn(left + 1, source.width)
    val bottom = rect.bottom.toInt().coerceIn(top + 1, source.height)
    val crop = Bitmap.createBitmap(source, left, top, right - left, bottom - top)
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val directory = File(context.getExternalFilesDir(null), "preview-readiness").apply {
      mkdirs()
    }
    File(directory, name).outputStream().use { output ->
      crop.compress(Bitmap.CompressFormat.PNG, 100, output)
    }
  }

  private data class CounterControls(
    val incrementIndex: Int,
    val countRegion: Rect
  )

  private companion object {
    const val HOST_TEST_TAG = "swiftTUIHost"
    const val TEST_LOG_TAG = "PreviewJourney"
    const val PALETTE_LABEL = "⌃K Palette"
    const val PALETTE_FILTER_LABEL = "Filter commands…"
    const val RESET_COUNTER_LABEL = "Reset counter"
    const val COUNTER_COMMAND_LABEL = "Counter"
    const val IMAGES_COMMAND_LABEL = "Images"
    const val GENERIC_BUTTON_LABEL = "button"
    const val ANIMATED_IMAGE_LABEL = "Animated GIF preview of the embedded Nyan fixture"
    const val FUTURE_ZERO_GLYPH = "┏━┓\n┃┃┃\n┗━┛"
    const val FUTURE_ONE_GLYPH = "╺┓\n┃\n╺┻╸"
    const val SEMANTICS_TIMEOUT_MILLIS = 20_000L
    const val SEMANTICS_STABILITY_MILLIS = 500L
    const val REPAINT_TIMEOUT_MILLIS = 10_000L
  }
}

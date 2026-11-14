package org.swifttui.gallery.android

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.KeyEvent
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Qualifies clipboard copy and paste through the public Android host against
 * the real system clipboard.
 *
 * Copy is requested by an app action, the mesh crafter's Copy Definition
 * button, and read back from `ClipboardManager`. That button lies to the right
 * of a phone-width grid, where no touch can reach it, so the journey activates
 * it through the host's accessibility node, as a screen reader would. Paste
 * puts text on the system clipboard and presses the host's two paste shortcuts
 * while a text control, and so the invisible IME sink, has focus.
 *
 * Paste policy asserted here: the clipboard's text is pasted; an absent clip,
 * an empty text, and a clip without text (a URI or an Intent) paste nothing.
 */
@RunWith(AndroidJUnit4::class)
class AndroidClipboardJourneyTest {
  @get:Rule
  val compose = createAndroidComposeRule<MainActivity>()

  private val driver by lazy { GalleryJourneyDriver(compose, LOG_TAG, artifactDirectory = ARTIFACT_DIRECTORY) }
  private val clipboard by lazy { SystemClipboardProbe(compose.activity.applicationContext) }

  @After
  fun closeClipboardPreview() {
    driver.closeSystemDialogs()
  }

  @Test
  fun appActionCopyReachesTheSystemClipboardExactlyOnce() {
    awaitGallery("app-action-copy")
    showCopyDefinition()
    val copied = copyDefinition(sentinel = "sentinel before the app copy")
    driver.writeScreenArtifact("app-action-copied.png")

    // The host asks the runtime for a pending copy on every frame poll. The
    // polls after the delivery must not write it again: a rewrite would
    // restamp the clip even though its text is the same.
    driver.advancePolls(SETTLE_POLLS)
    assertEquals("later frame polls must not rewrite the clipboard", copied, clipboard.state())
    driver.step("no duplicate clipboard write across $SETTLE_POLLS later frame polls")
  }

  @Test
  fun pasteShortcutsDeliverSystemClipboardTextToTheFocusedControl() {
    awaitGallery("paste")
    driver.selectTabWithPalette("text", "Text Input", landmark = SEARCH_LABEL)
    driver.touch(driver.stableNode(SEARCH_LABEL))
    driver.waitUntil("the search field to take focus") { driver.focusedNode()?.label == SEARCH_LABEL }
    driver.waitForImeSinkFocused()
    driver.step("search field focused; the invisible IME sink owns Compose focus")
    var expected = SEARCH_INITIAL_TEXT
    assertEquals(expected, driver.textValue(SEARCH_LABEL))

    // Unicode text through each shortcut: accents, CJK, a non-BMP emoji and a
    // ZWJ emoji sequence.
    clipboard.setText(UNICODE_TEXT)
    driver.key(KeyEvent.KEYCODE_V, ctrl = true)
    expected += UNICODE_TEXT
    awaitFocusedText("Ctrl+V to paste Unicode text", expected)
    clipboard.setText(SHIFT_INSERT_TEXT)
    driver.key(KeyEvent.KEYCODE_INSERT, shift = true)
    expected += SHIFT_INSERT_TEXT
    awaitFocusedText("Shift+Insert to paste", expected)
    driver.step("Ctrl+V and Shift+Insert pasted system clipboard text into the focused field")

    // An absent clip, an empty text and non-text content paste nothing. Input is
    // delivered in order, so the marker pasted afterwards lands directly after
    // the earlier text only if none of these inserted anything.
    clipboard.clear()
    assertFalse("the clipboard should be absent", clipboard.state().present)
    driver.key(KeyEvent.KEYCODE_V, ctrl = true)
    clipboard.setText("")
    assertEquals("the clipboard should hold an empty text", "", clipboard.state().text)
    driver.key(KeyEvent.KEYCODE_INSERT, shift = true)
    clipboard.set(ClipData.newRawUri("uri", Uri.parse("content://$MISSING_AUTHORITY/clip/1")))
    assertNull("a URI clip carries no text", clipboard.state().text)
    driver.key(KeyEvent.KEYCODE_V, ctrl = true)
    clipboard.set(ClipData.newIntent("intent", Intent(Intent.ACTION_VIEW, Uri.parse("https://swifttui.sh"))))
    assertNull("an Intent clip carries no text", clipboard.state().text)
    driver.key(KeyEvent.KEYCODE_V, ctrl = true)
    clipboard.setText(MARKER_TEXT)
    driver.key(KeyEvent.KEYCODE_V, ctrl = true)
    expected += MARKER_TEXT
    awaitFocusedText("only the marker to follow the absent, empty and non-text pastes", expected)
    driver.step("absent, empty, URI and Intent clipboard contents pasted nothing")

    // An HTML clip pastes its plain-text alternative, never the markup.
    clipboard.set(ClipData.newHtmlText("html", HTML_PLAIN_TEXT, "<b>$HTML_PLAIN_TEXT</b>"))
    driver.key(KeyEvent.KEYCODE_V, ctrl = true)
    expected += HTML_PLAIN_TEXT
    awaitFocusedText("an HTML clip to paste its plain text", expected)
    driver.writeScreenArtifact("paste-single-line.png")

    // Multiline text into the multiline editor, reached by keyboard focus
    // traversal; the runtime scrolls it into view.
    val editor = driver.tabUntilFocused("the multiline editor", maxPresses = 12) {
      it.role == EDITOR_ROLE
    }
    assertEquals(EDITOR_INITIAL_TEXT, editor.textValue)
    driver.waitForImeSinkFocused()
    clipboard.setText(MULTILINE_TEXT)
    driver.key(KeyEvent.KEYCODE_V, ctrl = true)
    awaitFocusedText("multiline Unicode text in the editor", EDITOR_INITIAL_TEXT + MULTILINE_TEXT)
    assertEquals("the search field keeps its text", expected, driver.textValue(SEARCH_LABEL))
    driver.writeScreenArtifact("paste-multiline.png")
    driver.step("multiline text pasted into the focused editor")

    // Stop and resume the activity with the editor still focused. Nothing is
    // written to the clipboard meanwhile, and the shortcut still pastes.
    clipboard.setText(STOP_SENTINEL)
    val beforeStop = clipboard.state()
    assertEquals(STOP_SENTINEL, beforeStop.text)
    stopAndResume()
    assertEquals("stop and resume must not write the clipboard", beforeStop, clipboard.state())
    driver.key(KeyEvent.KEYCODE_V, ctrl = true)
    awaitFocusedText(
      "Ctrl+V to paste after stop and resume",
      EDITOR_INITIAL_TEXT + MULTILINE_TEXT + STOP_SENTINEL
    )
    driver.step("paste shortcut still reaches the focused editor after stop and resume")
  }

  @Test
  fun clipboardWritesSurviveStopAndNeverEscapeARecreatedHost() {
    awaitGallery("lifecycle")
    showCopyDefinition()
    copyDefinition(sentinel = "sentinel before the first copy")

    // Stop and resume the activity. The host is not disposed: the clipboard
    // stays as the user left it, and the same control still copies.
    clipboard.setText(STOP_SENTINEL)
    val beforeStop = clipboard.state()
    assertEquals(STOP_SENTINEL, beforeStop.text)
    stopAndResume()
    assertEquals("stop and resume must not write the clipboard", beforeStop, clipboard.state())
    copyDefinition(sentinel = "sentinel after resume")
    driver.step("copy still reaches the system clipboard after stop and resume")

    // Recreate the activity. The first host is destroyed with its composition
    // and a new one starts from the app's initial state. Neither may write:
    // the destroyed host's copies were each delivered once already, and the
    // new host has been asked for nothing.
    clipboard.setText(RECREATE_SENTINEL)
    val beforeRecreate = clipboard.state()
    assertEquals(RECREATE_SENTINEL, beforeRecreate.text)
    val firstActivity = compose.activity
    AndroidGalleryTestProbe.snapshot = null
    compose.activityRule.scenario.recreate()
    driver.waitUntil("a new host to present the gallery's initial tab") {
      compose.activity !== firstActivity &&
        driver.visibleNodes().any { it.label == GalleryJourneyDriver.PALETTE_LABEL } &&
        driver.visibleNodes().none { it.label == COPY_BUTTON_LABEL }
    }
    awaitWindowFocus()
    driver.advancePolls(SETTLE_POLLS)
    assertEquals(
      "no clipboard write may escape the destroyed host or come from the new one",
      beforeRecreate,
      clipboard.state()
    )
    driver.step("recreated host presented; the system clipboard is untouched")

    showCopyDefinition()
    copyDefinition(sentinel = "sentinel in the recreated host")
    driver.writeScreenArtifact("copied-after-recreate.png")
    driver.step("copy reaches the system clipboard from the recreated host")
  }

  private fun awaitGallery(journey: String) {
    // Stable means the host has been resized from its initial 80x24 grid.
    driver.stableNode(GalleryJourneyDriver.PALETTE_LABEL)
    awaitWindowFocus()
    recordEnvironment(journey)
  }

  // Clipboard reads are refused unless the app has input focus.
  private fun awaitWindowFocus() {
    driver.waitUntil("the gallery window to have input focus") { compose.activity.hasWindowFocus() }
  }

  // Moves the activity to the stopped state and back, then lets the host poll.
  private fun stopAndResume() {
    val scenario = compose.activityRule.scenario
    scenario.moveToState(Lifecycle.State.CREATED)
    scenario.moveToState(Lifecycle.State.RESUMED)
    awaitWindowFocus()
    driver.advancePolls(SETTLE_POLLS)
    driver.step("activity stopped and resumed")
  }

  private fun showCopyDefinition() {
    driver.selectTabWithPalette("bord", "Borders & Shapes", landmark = COPY_BUTTON_LABEL)
  }

  /**
   * Activates the Copy Definition button and waits for the exact definition on
   * the system clipboard. [sentinel] is placed there first, so the definition
   * can only have come from this copy.
   */
  private fun copyDefinition(sentinel: String): SystemClipboardProbe.State {
    clipboard.setText(sentinel)
    assertEquals(sentinel, clipboard.state().text)
    driver.accessibilityClick(COPY_BUTTON_LABEL)
    driver.waitUntil("the mesh definition on the system clipboard, not ${clipboard.state()}") {
      clipboard.state().text == MESH_DEFINITION
    }
    driver.waitUntil("the app to confirm the copy") {
      driver.visibleNodes().any { it.label == COPY_CONFIRMATION }
    }
    val copied = clipboard.state()
    assertEquals("one plain-text item", 1, copied.itemCount)
    assertEquals(listOf("text/plain"), copied.mimeTypes)
    driver.step("app action copied ${MESH_DEFINITION.length} characters to the system clipboard")
    return copied
  }

  private fun awaitFocusedText(description: String, expected: String) {
    driver.waitUntil("$description: <${expected.printable()}>") {
      driver.focusedNode()?.textValue == expected
    }
  }

  private fun recordEnvironment(journey: String) {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val snapshot = AndroidGalleryTestProbe.snapshot
    val environment = JSONObject()
      .put("journey", journey)
      .put("androidRelease", Build.VERSION.RELEASE)
      .put("apiLevel", Build.VERSION.SDK_INT)
      .put("securityPatch", Build.VERSION.SECURITY_PATCH)
      .put("fingerprint", Build.FINGERPRINT)
      .put("device", "${Build.MANUFACTURER} ${Build.MODEL}")
      .put("abis", Build.SUPPORTED_ABIS.joinToString(","))
      .put(
        "defaultInputMethod",
        Settings.Secure.getString(context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
      )
      .put("application", context.packageName)
      .put("grid", "${snapshot?.frame?.gridWidth}x${snapshot?.frame?.gridHeight}")
      .put("cellPixels", "${snapshot?.style?.cellWidthPx}x${snapshot?.style?.cellHeightPx}")
    driver.step("environment $environment")
    driver.writeArtifact("environment-$journey.json", environment.toString(2) + "\n")
  }

  private companion object {
    const val LOG_TAG = "ClipboardJourney"
    const val ARTIFACT_DIRECTORY = "clipboard-journey"
    const val COPY_BUTTON_LABEL = "Copy Definition"
    const val COPY_CONFIRMATION = "Copied MeshGradient definition."
    const val SEARCH_LABEL = "Search controls"
    const val SEARCH_INITIAL_TEXT = "SwiftTUI"
    const val EDITOR_ROLE = "textEditor"
    const val EDITOR_INITIAL_TEXT = "Try arrow keys, return, backspace, and bracketed paste here."
    const val UNICODE_TEXT = " café 漢字 😀 👩‍💻"
    const val SHIFT_INSERT_TEXT = " +insert"
    const val MARKER_TEXT = " |marker"
    const val HTML_PLAIN_TEXT = " html-plain"
    const val MULTILINE_TEXT = "\nα 1\nβ 2 😀\nγ"
    const val STOP_SENTINEL = " ~resumed"
    const val RECREATE_SENTINEL = "sentinel across recreate"
    const val MISSING_AUTHORITY = "org.swifttui.gallery.android.missing"
    // A third of a second of the host's 33 ms poll loop.
    const val SETTLE_POLLS = 10

    // The gallery's MeshGradientCrafter.definition for its initial state.
    val MESH_DEFINITION = """
      MeshGradient(
        width: 3,
        height: 3,
        points: [
          .init(0.00, 0.00),
          .init(0.50, 0.00),
          .init(1.00, 0.00),
          .init(0.00, 0.50),
          .init(0.50, 0.50),
          .init(1.00, 0.50),
          .init(0.00, 1.00),
          .init(0.50, 1.00),
          .init(1.00, 1.00),
        ],
        colors: [
          .blue,
          .cyan,
          .green,
          .magenta,
          .white,
          .yellow,
          .red,
          .magenta,
          .blue,
        ],
        background: .black,
        smoothsColors: true,
        colorSpace: .perceptual
      )
    """.trimIndent()
  }
}

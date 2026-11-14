package org.swifttui.gallery.android

import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import sh.swifttui.android.host.SwiftTUIInput

/**
 * The runtime half of a file drop on Android: a file path the host sends as a
 * bracketed paste reaches the gallery's `.dropDestination`, and the runtime
 * reads the file behind it.
 *
 * The path is a `file://` URL, the form a terminal emits for a dropped file. It
 * names a real file in the app's cache directory; an Android `content://` URI
 * is not a path and is never sent on this channel.
 */
@RunWith(AndroidJUnit4::class)
class AndroidFileDropJourneyTest {
  @get:Rule
  val compose = createAndroidComposeRule<MainActivity>()

  private val gallery = GalleryJourneyDriver(compose, logTag = "FileDropJourney", artifactDirectory = "file-drop")
  private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
  private val dropDirectory get() = File(instrumentation.targetContext.cacheDir, "file-drop-journey")

  @After
  fun deleteDroppedFiles() {
    dropDirectory.deleteRecursively()
  }

  @Test
  fun aFilePathPastedByTheHostReachesTheDropDestinationAndIsRead() {
    gallery.waitForGallery()
    gallery.selectTab(GalleryJourneyDriver.FILE_DROP_TAB, shown = GalleryJourneyDriver.FILE_DROP_HINT)
    assertEquals("no image before the drop", 0, gallery.journeyImages().size)
    gallery.writeArtifact("before-drop.png", gallery.hostImage())

    // A name with a space, a quote and non-ASCII letters: the URL form carries
    // it through the paste tokenizer unchanged.
    val dropped = File(dropDirectory, "journey it's 写真.png").apply {
      parentFile!!.mkdirs()
      writeBytes(JourneyPng.bytes())
    }
    val url = fileUrl(dropped)
    assertTrue(
      "the drop is a fully percent-encoded file URL: $url",
      url.startsWith("file:///") && url.endsWith("/journey%20it%27s%20%E5%86%99%E7%9C%9F.png")
    )
    gallery.step("dropping $url")
    instrumentation.runOnMainSync {
      gallery.hostState().sendInput(SwiftTUIInput.bracketedPaste(url))
    }

    // The destination received the exact path and showed it ...
    gallery.waitUntil("the dropped path in the File Drop tab") { gallery.showsText(dropped.absolutePath) }
    gallery.step("the destination shows ${dropped.absolutePath}")
    // ... and the runtime decoded the file behind it.
    gallery.waitUntil("the dropped PNG as an image attachment") { gallery.journeyImages().size == 1 }
    val image = gallery.journeyImages().single()
    gallery.step("image attachment $image")
    gallery.waitForRenderedJourneyPng(image)
    gallery.writeArtifact("after-drop.png", gallery.hostImage())
    gallery.writeArtifact("after-drop-rows.txt", gallery.renderedRows().joinToString("\n"))
  }

  /**
   * The `file://` URL of [file] with every byte outside the RFC 3986
   * unreserved set (and `/`) percent-encoded. `Uri.fromFile` is not enough: it
   * leaves `'` as it is, and the runtime's paste tokenizer reads a bare quote
   * in a path as shell quoting.
   */
  private fun fileUrl(file: File): String {
    val url = StringBuilder("file://")
    for (byte in file.absolutePath.encodeToByteArray()) {
      val character = (byte.toInt() and 0xFF).toChar()
      if (character in 'A'..'Z' || character in 'a'..'z' || character in '0'..'9' ||
        character in "-._~/"
      ) {
        url.append(character)
      } else {
        url.append('%').append("%02X".format(byte.toInt() and 0xFF))
      }
    }
    return url.toString()
  }
}

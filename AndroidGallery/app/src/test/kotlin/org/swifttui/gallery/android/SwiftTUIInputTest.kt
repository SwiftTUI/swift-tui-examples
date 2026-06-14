package org.swifttui.gallery.android

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

private const val ESC = ""

class SwiftTUIInputTest {
  @Test
  fun cellCoordinatesAreOneBased() {
    assertEquals(1, SwiftTUIInput.cellColumn(0f, 9f))
    assertEquals(1, SwiftTUIInput.cellColumn(8.9f, 9f))
    assertEquals(2, SwiftTUIInput.cellColumn(9f, 9f))
    assertEquals(1, SwiftTUIInput.cellRow(0f, 18f))
    assertEquals(3, SwiftTUIInput.cellRow(36f, 18f))
  }

  @Test
  fun mousePressAndReleaseUseSgrButtonZero() {
    assertEquals("$ESC[<0;3;5M", SwiftTUIInput.mouseDown(3, 5).decodeToString())
    assertEquals("$ESC[<0;3;5m", SwiftTUIInput.mouseUp(3, 5).decodeToString())
  }

  @Test
  fun dragSetsTheMotionFlag() {
    assertEquals("$ESC[<32;4;6M", SwiftTUIInput.mouseDrag(4, 6).decodeToString())
  }

  @Test
  fun wheelEncodesDirection() {
    assertEquals("$ESC[<64;2;2M", SwiftTUIInput.wheel(2, 2, up = true).decodeToString())
    assertEquals("$ESC[<65;2;2M", SwiftTUIInput.wheel(2, 2, up = false).decodeToString())
  }

  @Test
  fun modifiersAreOredIntoTheButton() {
    // 0 | shift(4) | ctrl(16) = 20
    assertEquals(
      "$ESC[<20;1;1M",
      SwiftTUIInput.mouseDown(
        1,
        1,
        modifiers = SwiftTUIInput.MODIFIER_SHIFT or SwiftTUIInput.MODIFIER_CTRL
      ).decodeToString()
    )
  }

  @Test
  fun verticalScrollEmitsOneNotchPerLineInTheRightDirection() {
    assertEquals(
      "$ESC[<64;1;1M$ESC[<64;1;1M",
      SwiftTUIInput.verticalScroll(1, 1, deltaLines = 2).decodeToString()
    )
    assertEquals(
      "$ESC[<65;1;1M$ESC[<65;1;1M$ESC[<65;1;1M",
      SwiftTUIInput.verticalScroll(1, 1, deltaLines = -3).decodeToString()
    )
  }

  @Test
  fun verticalScrollIsEmptyForZeroAndClampsLargeFlings() {
    assertArrayEquals(ByteArray(0), SwiftTUIInput.verticalScroll(1, 1, deltaLines = 0))
    val clamped = SwiftTUIInput.verticalScroll(1, 1, deltaLines = 100, maxNotches = 4)
    val notches = clamped.decodeToString().split("M").count { it.isNotEmpty() }
    assertEquals(4, notches)
  }

  @Test
  fun bracketedPasteWrapsAndStripsControlBytes() {
    assertEquals(
      "$ESC[200~hello$ESC[201~",
      SwiftTUIInput.bracketedPaste("hello").decodeToString()
    )
    // An embedded ESC (which could smuggle the paste-end marker) is removed.
    assertEquals(
      "$ESC[200~ab$ESC[201~",
      SwiftTUIInput.bracketedPaste("a${ESC}b").decodeToString()
    )
    // Tabs and newlines survive.
    assertTrue(SwiftTUIInput.bracketedPaste("a\tb\nc").decodeToString().contains("a\tb\nc"))
  }

  @Test
  fun bracketedPasteIsEmptyForBlankOrControlOnlyInput() {
    assertArrayEquals(ByteArray(0), SwiftTUIInput.bracketedPaste(""))
    assertArrayEquals(ByteArray(0), SwiftTUIInput.bracketedPaste("$ESC$ESC"))
  }
}

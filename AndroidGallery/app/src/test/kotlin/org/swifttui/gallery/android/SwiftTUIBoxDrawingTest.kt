package org.swifttui.gallery.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SwiftTUIBoxDrawingTest {
  @Test
  fun canRenderCoversBoxBlockAndBraille() {
    assertTrue(SwiftTUIBoxDrawing.canRender(0x2500)) // ─
    assertTrue(SwiftTUIBoxDrawing.canRender(0x2588)) // █
    assertTrue(SwiftTUIBoxDrawing.canRender(0x28FF)) // ⣿
    assertFalse(SwiftTUIBoxDrawing.canRender('A'.code))
    assertFalse(SwiftTUIBoxDrawing.canRender(0x24FF))
    assertFalse(SwiftTUIBoxDrawing.canRender(0x2900))
  }

  @Test
  fun lineSpecDescribesEdgesForCommonGlyphs() {
    val light = SwiftTUIBoxDrawing.LineWeight.LIGHT
    val none = SwiftTUIBoxDrawing.LineWeight.NONE
    val double = SwiftTUIBoxDrawing.LineWeight.DOUBLE

    // ─ horizontal: east + west light.
    assertEquals(SwiftTUIBoxDrawing.Spec(none, light, none, light), SwiftTUIBoxDrawing.lineSpec(0x2500))
    // ┼ cross: all light.
    assertEquals(SwiftTUIBoxDrawing.Spec(light, light, light, light), SwiftTUIBoxDrawing.lineSpec(0x253C))
    // ╔ double down-and-right.
    assertEquals(SwiftTUIBoxDrawing.Spec(none, double, double, none), SwiftTUIBoxDrawing.lineSpec(0x2554))
  }

  @Test
  fun lineSpecIsNullForProceduralAndOutOfRangeGlyphs() {
    assertNull(SwiftTUIBoxDrawing.lineSpec(0x2504)) // dashed -> procedural
    assertNull(SwiftTUIBoxDrawing.lineSpec(0x256D)) // arc -> procedural
    assertNull(SwiftTUIBoxDrawing.lineSpec(0x2588)) // block, not a line
    assertNull(SwiftTUIBoxDrawing.lineSpec('A'.code))
  }

  @Test
  fun brailleMaskIsTheLowEightBits() {
    assertEquals(0, SwiftTUIBoxDrawing.brailleMask(0x2800))
    assertEquals(0xFF, SwiftTUIBoxDrawing.brailleMask(0x28FF))
    assertEquals(0x01, SwiftTUIBoxDrawing.brailleMask(0x2801))
    assertEquals(0, SwiftTUIBoxDrawing.brailleMask('A'.code))
  }
}

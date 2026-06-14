package org.swifttui.gallery.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SwiftTUIDamagePlanTest {
  private fun frame(
    sequence: Long = 1L,
    cells: List<SwiftTUICell> = listOf(cell(0, 0)),
    images: List<SwiftTUIImageAttachment> = emptyList(),
    dirtyRows: List<Int> = emptyList(),
    textDamageRows: List<SwiftTUITextDamageRow> = emptyList(),
    requiresFullTextRepaint: Boolean = false,
    requiresFullGraphicsReplay: Boolean = false,
    gridWidth: Int = 10,
    gridHeight: Int = 5
  ) = SwiftTUIFrame(
    schemaVersion = 2,
    sequence = sequence,
    gridWidth = gridWidth,
    gridHeight = gridHeight,
    preferredGridWidth = null,
    preferredGridHeight = null,
    terminalStyle = SwiftTUITerminalStyle.Default,
    rows = emptyList(),
    cells = cells,
    imageAttachments = images,
    focusedIdentity = null,
    focusPresentation = SwiftTUIFocusPresentation.None,
    accessibilityNodes = emptyList(),
    accessibilityAnnouncements = emptyList(),
    dirtyRows = dirtyRows,
    textDamageRows = textDamageRows,
    requiresFullTextRepaint = requiresFullTextRepaint,
    requiresFullGraphicsReplay = requiresFullGraphicsReplay
  )

  private fun cell(x: Int, y: Int, span: Int = 1) =
    SwiftTUICell(x = x, y = y, character = "a", spanWidth = span, continuationLeadX = null, style = null, hyperlink = null)

  @Test
  fun firstFrameIsAlwaysFull() {
    val plan = SwiftTUIDamagePlan.plan(frame(sequence = 0L), previousSequence = -1L, sizeChanged = false)
    assertTrue(plan.fullRepaint)
  }

  @Test
  fun nonContiguousSequenceForcesFull() {
    val plan = SwiftTUIDamagePlan.plan(
      frame(sequence = 9L, textDamageRows = listOf(SwiftTUITextDamageRow(1, listOf(SwiftTUIRange(0, 3))))),
      previousSequence = 5L,
      sizeChanged = false
    )
    assertTrue(plan.fullRepaint)
  }

  @Test
  fun sizeChangeForcesFull() {
    val plan = SwiftTUIDamagePlan.plan(frame(sequence = 6L), previousSequence = 5L, sizeChanged = true)
    assertTrue(plan.fullRepaint)
  }

  @Test
  fun fullRepaintFlagsForceFull() {
    assertTrue(
      SwiftTUIDamagePlan.plan(
        frame(sequence = 6L, requiresFullTextRepaint = true),
        previousSequence = 5L,
        sizeChanged = false
      ).fullRepaint
    )
    assertTrue(
      SwiftTUIDamagePlan.plan(
        frame(sequence = 6L, requiresFullGraphicsReplay = true),
        previousSequence = 5L,
        sizeChanged = false
      ).fullRepaint
    )
  }

  @Test
  fun imagesForceFull() {
    val image = SwiftTUIImageAttachment(
      id = "img",
      bounds = SwiftTUIRect(0, 0, 2, 2),
      visibleBounds = SwiftTUIRect(0, 0, 2, 2),
      sourceKind = "data",
      sourceIdentifier = null,
      payloadBase64 = null,
      payloadByteCount = null,
      pixelSize = null,
      cellPixelSize = null,
      isResizable = false,
      scalingMode = "stretch"
    )
    val plan = SwiftTUIDamagePlan.plan(
      frame(sequence = 6L, images = listOf(image)),
      previousSequence = 5L,
      sizeChanged = false
    )
    assertTrue(plan.fullRepaint)
  }

  @Test
  fun contiguousTextDamageIsPartialWithInclusiveRanges() {
    val plan = SwiftTUIDamagePlan.plan(
      frame(
        sequence = 6L,
        textDamageRows = listOf(SwiftTUITextDamageRow(2, listOf(SwiftTUIRange(1, 4))))
      ),
      previousSequence = 5L,
      sizeChanged = false
    )
    assertFalse(plan.fullRepaint)
    assertEquals(1, plan.rows.size)
    assertEquals(2, plan.rows[0].row)
    // Swift Range<Int>(1, 4) -> inclusive columns 1..3.
    assertEquals(listOf(1..3), plan.rows[0].columnRanges)
  }

  @Test
  fun dirtyRowsBecomeFullWidthRanges() {
    val plan = SwiftTUIDamagePlan.plan(
      frame(sequence = 6L, dirtyRows = listOf(0), gridWidth = 10),
      previousSequence = 5L,
      sizeChanged = false
    )
    assertFalse(plan.fullRepaint)
    assertEquals(listOf(0..9), plan.rows[0].columnRanges)
  }

  @Test
  fun rowDamageIntersectionMatchesCellSpans() {
    val damage = SwiftTUIDamagePlan.RowDamage(0, listOf(3..5))
    assertTrue(damage.intersects(5, 7))   // cell starts inside the range
    assertTrue(damage.intersects(0, 4))   // cell overlaps the low edge
    assertFalse(damage.intersects(6, 8))  // cell entirely past the range
    assertFalse(damage.intersects(0, 3))  // cell ends before the range starts
  }
}

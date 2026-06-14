package sh.swifttui.android.host

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SwiftTUIFrameTest {
  @Test
  fun parsesStyledCellsAndHyperlinks() {
    val json = """
      {
        "schemaVersion": 2,
        "sequence": 7,
        "gridWidth": 3,
        "gridHeight": 1,
        "terminalStyle": {
          "foregroundColor": {"hex": "#ECEFF4FF"},
          "backgroundColor": {"hex": "#1E222AFF"},
          "tintColor": {"hex": "#56B6C2FF"}
        },
        "rows": ["abc"],
        "cells": [
          {"x": 0, "y": 0, "character": "a", "spanWidth": 1,
           "style": {"emphasis": ["bold"], "opacity": 1.0}},
          {"x": 1, "y": 0, "character": "b", "spanWidth": 1, "hyperlink": "https://swifttui.example"}
        ],
        "focusPresentation": {"semantics": "edit", "prefersTextInput": true, "hasFocusedRegion": true},
        "requiresFullTextRepaint": false,
        "requiresFullGraphicsReplay": false
      }
    """.trimIndent()

    val frame = SwiftTUIFrame.parse(json)

    assertEquals(2, frame.schemaVersion)
    assertEquals(7L, frame.sequence)
    assertEquals(3, frame.gridWidth)
    assertEquals(2, frame.cells.size)
    assertEquals("a", frame.cells[0].character)
    assertTrue(frame.cells[0].style?.emphasis?.contains("bold") == true)
    assertEquals("https://swifttui.example", frame.cells[1].hyperlink)
    assertTrue(frame.focusPresentation.prefersTextInput)
    assertTrue(frame.focusPresentation.hasFocusedRegion)
  }

  @Test
  fun cellAtResolvesColumnsAndWideSpans() {
    val frame = SwiftTUIFrame.parse(
      """
        {
          "sequence": 1, "gridWidth": 5, "gridHeight": 1, "rows": ["W b"],
          "cells": [
            {"x": 0, "y": 0, "character": "W", "spanWidth": 2, "hyperlink": "https://wide"},
            {"x": 1, "y": 0, "character": " ", "spanWidth": 1, "continuationLeadX": 0},
            {"x": 2, "y": 0, "character": "b", "spanWidth": 1, "hyperlink": "https://b"}
          ]
        }
      """.trimIndent()
    )

    // 1-based column 1 and 2 both resolve to the wide lead cell.
    assertEquals("https://wide", frame.cellAt(1, 1)?.hyperlink)
    assertEquals("https://wide", frame.cellAt(2, 1)?.hyperlink)
    assertEquals("https://b", frame.cellAt(3, 1)?.hyperlink)
    assertNull(frame.cellAt(9, 1))
    assertNull(frame.cellAt(1, 2))
  }
}

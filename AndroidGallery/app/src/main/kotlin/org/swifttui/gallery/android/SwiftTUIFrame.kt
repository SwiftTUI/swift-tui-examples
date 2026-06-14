package org.swifttui.gallery.android

import org.json.JSONArray
import org.json.JSONObject

data class SwiftTUIColor(
  val hex: String
)

data class SwiftTUITerminalStyle(
  val foregroundColor: SwiftTUIColor,
  val backgroundColor: SwiftTUIColor,
  val tintColor: SwiftTUIColor
) {
  companion object {
    val Default = SwiftTUITerminalStyle(
      foregroundColor = SwiftTUIColor("#ECEFF4FF"),
      backgroundColor = SwiftTUIColor("#1E222AFF"),
      tintColor = SwiftTUIColor("#56B6C2FF")
    )
  }
}

data class SwiftTUITextLineStyle(
  val pattern: String,
  val color: SwiftTUIColor?
)

data class SwiftTUITextStyle(
  val foregroundColor: SwiftTUIColor?,
  val backgroundColor: SwiftTUIColor?,
  val emphasis: Set<String>,
  val underlineStyle: SwiftTUITextLineStyle?,
  val strikethroughStyle: SwiftTUITextLineStyle?,
  val opacity: Double
)

data class SwiftTUICell(
  val x: Int,
  val y: Int,
  val character: String,
  val spanWidth: Int,
  val continuationLeadX: Int?,
  val style: SwiftTUITextStyle?,
  val hyperlink: String?
) {
  val isContinuation: Boolean
    get() = continuationLeadX != null || spanWidth <= 0
}

data class SwiftTUIRect(
  val x: Int,
  val y: Int,
  val width: Int,
  val height: Int
)

data class SwiftTUIPoint(
  val x: Int,
  val y: Int
)

data class SwiftTUIPixelSize(
  val width: Int,
  val height: Int
)

data class SwiftTUIImageAttachment(
  val id: String,
  val bounds: SwiftTUIRect,
  val visibleBounds: SwiftTUIRect,
  val sourceKind: String,
  val sourceIdentifier: String?,
  val payloadBase64: String?,
  val payloadByteCount: Int?,
  val pixelSize: SwiftTUIPixelSize?,
  val cellPixelSize: SwiftTUIPixelSize?,
  val isResizable: Boolean,
  val scalingMode: String
)

data class SwiftTUIFocusPresentation(
  val focusedIdentity: String?,
  val semantics: String,
  val prefersTextInput: Boolean,
  val hasFocusedRegion: Boolean
) {
  companion object {
    val None = SwiftTUIFocusPresentation(
      focusedIdentity = null,
      semantics = "none",
      prefersTextInput = false,
      hasFocusedRegion = false
    )
  }
}

data class SwiftTUIAccessibilityNode(
  val id: String,
  val parentID: String?,
  val rect: SwiftTUIRect,
  val role: String,
  val label: String?,
  val hint: String?,
  val hidden: Boolean,
  val liveRegion: String?,
  val cursorAnchor: SwiftTUIPoint?,
  val isFocused: Boolean
)

data class SwiftTUIAccessibilityAnnouncement(
  val message: String,
  val politeness: String
)

data class SwiftTUIRange(
  val lowerBound: Int,
  val upperBound: Int
)

data class SwiftTUITextDamageRow(
  val row: Int,
  val columnRanges: List<SwiftTUIRange>
)

data class SwiftTUIFrame(
  val schemaVersion: Int,
  val sequence: Long,
  val gridWidth: Int,
  val gridHeight: Int,
  val preferredGridWidth: Int?,
  val preferredGridHeight: Int?,
  val terminalStyle: SwiftTUITerminalStyle,
  val rows: List<String>,
  val cells: List<SwiftTUICell>,
  val imageAttachments: List<SwiftTUIImageAttachment>,
  val focusedIdentity: String?,
  val focusPresentation: SwiftTUIFocusPresentation,
  val accessibilityNodes: List<SwiftTUIAccessibilityNode>,
  val accessibilityAnnouncements: List<SwiftTUIAccessibilityAnnouncement>,
  val dirtyRows: List<Int>,
  val textDamageRows: List<SwiftTUITextDamageRow>,
  val requiresFullTextRepaint: Boolean,
  val requiresFullGraphicsReplay: Boolean
) {
  /**
   * The rendered cell covering a 1-based terminal [column]/[row], or `null` if
   * none. Spans are resolved to their lead cell so a tap anywhere inside a
   * wide glyph (or a hyperlink run) resolves to the owning cell. Pure, so it is
   * unit-testable without Android.
   */
  fun cellAt(column: Int, row: Int): SwiftTUICell? {
    val x = column - 1
    val y = row - 1
    if (x < 0 || y < 0) {
      return null
    }
    return cells.firstOrNull { cell ->
      !cell.isContinuation &&
        cell.y == y &&
        x >= cell.x &&
        x < cell.x + cell.spanWidth.coerceAtLeast(1)
    }
  }

  companion object {
    fun parse(json: String): SwiftTUIFrame {
      val objectValue = JSONObject(json)
      val rows = objectValue.optJSONArray("rows").strings()
      val cells = objectValue.optJSONArray("cells").objects().map { it.toCell() }
      val dirtyRows = objectValue.optJSONArray("dirtyRows").ints()
      val terminalStyle = objectValue.optJSONObject("terminalStyle")?.toTerminalStyle()
        ?: SwiftTUITerminalStyle.Default

      return SwiftTUIFrame(
        schemaVersion = objectValue.optInt("schemaVersion", 1),
        sequence = objectValue.optLong("sequence", 0L),
        gridWidth = objectValue.optInt("gridWidth", rows.maxOfOrNull { it.length } ?: 0),
        gridHeight = objectValue.optInt("gridHeight", rows.size),
        preferredGridWidth = objectValue.optionalInt("preferredGridWidth"),
        preferredGridHeight = objectValue.optionalInt("preferredGridHeight"),
        terminalStyle = terminalStyle,
        rows = rows,
        cells = cells,
        imageAttachments = objectValue.optJSONArray("imageAttachments").objects().map {
          it.toImageAttachment()
        },
        focusedIdentity = objectValue.optionalString("focusedIdentity"),
        focusPresentation = objectValue.optJSONObject("focusPresentation")?.toFocusPresentation()
          ?: SwiftTUIFocusPresentation.None,
        accessibilityNodes = objectValue.optJSONArray("accessibilityNodes").objects().map {
          it.toAccessibilityNode()
        },
        accessibilityAnnouncements = objectValue.optJSONArray("accessibilityAnnouncements")
          .objects()
          .map { it.toAccessibilityAnnouncement() },
        dirtyRows = dirtyRows,
        textDamageRows = objectValue.optJSONArray("textDamageRows").objects().map {
          it.toTextDamageRow()
        },
        requiresFullTextRepaint = objectValue.optBoolean("requiresFullTextRepaint", true),
        requiresFullGraphicsReplay = objectValue.optBoolean("requiresFullGraphicsReplay", true)
      )
    }
  }
}

private fun JSONObject.toTerminalStyle(): SwiftTUITerminalStyle =
  SwiftTUITerminalStyle(
    foregroundColor = color("foregroundColor") ?: SwiftTUITerminalStyle.Default.foregroundColor,
    backgroundColor = color("backgroundColor") ?: SwiftTUITerminalStyle.Default.backgroundColor,
    tintColor = color("tintColor") ?: SwiftTUITerminalStyle.Default.tintColor
  )

private fun JSONObject.toCell(): SwiftTUICell =
  SwiftTUICell(
    x = optInt("x"),
    y = optInt("y"),
    character = optString("character", " "),
    spanWidth = optInt("spanWidth", 1),
    continuationLeadX = optionalInt("continuationLeadX"),
    style = optJSONObject("style")?.toTextStyle(),
    hyperlink = optionalString("hyperlink")
  )

private fun JSONObject.toTextStyle(): SwiftTUITextStyle =
  SwiftTUITextStyle(
    foregroundColor = color("foregroundColor"),
    backgroundColor = color("backgroundColor"),
    emphasis = optJSONArray("emphasis").strings().toSet(),
    underlineStyle = optJSONObject("underlineStyle")?.toTextLineStyle(),
    strikethroughStyle = optJSONObject("strikethroughStyle")?.toTextLineStyle(),
    opacity = optDouble("opacity", 1.0)
  )

private fun JSONObject.toTextLineStyle(): SwiftTUITextLineStyle =
  SwiftTUITextLineStyle(
    pattern = optString("pattern", "solid"),
    color = color("color")
  )

private fun JSONObject.toImageAttachment(): SwiftTUIImageAttachment =
  SwiftTUIImageAttachment(
    id = optString("id"),
    bounds = optJSONObject("bounds").toRectOrZero(),
    visibleBounds = optJSONObject("visibleBounds").toRectOrZero(),
    sourceKind = optString("sourceKind", "unknown"),
    sourceIdentifier = optionalString("sourceIdentifier"),
    payloadBase64 = optionalString("payloadBase64"),
    payloadByteCount = optionalInt("payloadByteCount"),
    pixelSize = optJSONObject("pixelSize")?.toPixelSize(),
    cellPixelSize = optJSONObject("cellPixelSize")?.toPixelSize(),
    isResizable = optBoolean("isResizable"),
    scalingMode = optString("scalingMode", "stretch")
  )

private fun JSONObject.toFocusPresentation(): SwiftTUIFocusPresentation =
  SwiftTUIFocusPresentation(
    focusedIdentity = optionalString("focusedIdentity"),
    semantics = optString("semantics", "none"),
    prefersTextInput = optBoolean("prefersTextInput"),
    hasFocusedRegion = optBoolean("hasFocusedRegion")
  )

private fun JSONObject.toAccessibilityNode(): SwiftTUIAccessibilityNode =
  SwiftTUIAccessibilityNode(
    id = optString("id"),
    parentID = optionalString("parentID"),
    rect = optJSONObject("rect").toRectOrZero(),
    role = optString("role", "group"),
    label = optionalString("label"),
    hint = optionalString("hint"),
    hidden = optBoolean("hidden"),
    liveRegion = optionalString("liveRegion"),
    cursorAnchor = optJSONObject("cursorAnchor")?.toPoint(),
    isFocused = optBoolean("isFocused")
  )

private fun JSONObject.toAccessibilityAnnouncement(): SwiftTUIAccessibilityAnnouncement =
  SwiftTUIAccessibilityAnnouncement(
    message = optString("message"),
    politeness = optString("politeness", "polite")
  )

private fun JSONObject.toTextDamageRow(): SwiftTUITextDamageRow =
  SwiftTUITextDamageRow(
    row = optInt("row"),
    columnRanges = optJSONArray("columnRanges").objects().map {
      SwiftTUIRange(
        lowerBound = it.optInt("lowerBound"),
        upperBound = it.optInt("upperBound")
      )
    }
  )

private fun JSONObject?.toRectOrZero(): SwiftTUIRect =
  this?.let {
    SwiftTUIRect(
      x = optInt("x"),
      y = optInt("y"),
      width = optInt("width"),
      height = optInt("height")
    )
  } ?: SwiftTUIRect(x = 0, y = 0, width = 0, height = 0)

private fun JSONObject.toPoint(): SwiftTUIPoint =
  SwiftTUIPoint(
    x = optInt("x"),
    y = optInt("y")
  )

private fun JSONObject.toPixelSize(): SwiftTUIPixelSize =
  SwiftTUIPixelSize(
    width = optInt("width"),
    height = optInt("height")
  )

private fun JSONObject.color(name: String): SwiftTUIColor? =
  optJSONObject(name)?.optionalString("hex")?.let { SwiftTUIColor(it) }

private fun JSONObject.optionalInt(name: String): Int? =
  if (has(name) && !isNull(name)) optInt(name) else null

private fun JSONObject.optionalString(name: String): String? =
  if (has(name) && !isNull(name)) optString(name) else null

private fun JSONArray?.objects(): List<JSONObject> = buildList {
  val array = this@objects ?: return@buildList
  for (index in 0 until array.length()) {
    array.optJSONObject(index)?.let(::add)
  }
}

private fun JSONArray?.strings(): List<String> = buildList {
  val array = this@strings ?: return@buildList
  for (index in 0 until array.length()) {
    add(array.optString(index))
  }
}

private fun JSONArray?.ints(): List<Int> = buildList {
  val array = this@ints ?: return@buildList
  for (index in 0 until array.length()) {
    add(array.optInt(index))
  }
}

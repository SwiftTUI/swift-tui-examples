package org.swifttui.gallery.android

import org.json.JSONObject

data class SwiftTUIFrame(
  val schemaVersion: Int,
  val sequence: Long,
  val gridWidth: Int,
  val gridHeight: Int,
  val preferredGridWidth: Int?,
  val preferredGridHeight: Int?,
  val rows: List<String>,
  val focusedIdentity: String?,
  val dirtyRows: List<Int>,
  val requiresFullTextRepaint: Boolean,
  val requiresFullGraphicsReplay: Boolean
) {
  companion object {
    fun parse(json: String): SwiftTUIFrame {
      val objectValue = JSONObject(json)
      val rowArray = objectValue.optJSONArray("rows")
      val rows = buildList {
        if (rowArray != null) {
          for (index in 0 until rowArray.length()) {
            add(rowArray.optString(index))
          }
        }
      }
      val dirtyRowArray = objectValue.optJSONArray("dirtyRows")
      val dirtyRows = buildList {
        if (dirtyRowArray != null) {
          for (index in 0 until dirtyRowArray.length()) {
            add(dirtyRowArray.optInt(index))
          }
        }
      }

      return SwiftTUIFrame(
        schemaVersion = objectValue.optInt("schemaVersion", 1),
        sequence = objectValue.optLong("sequence", 0L),
        gridWidth = objectValue.optInt("gridWidth", rows.maxOfOrNull { it.length } ?: 0),
        gridHeight = objectValue.optInt("gridHeight", rows.size),
        preferredGridWidth = objectValue.optionalInt("preferredGridWidth"),
        preferredGridHeight = objectValue.optionalInt("preferredGridHeight"),
        rows = rows,
        focusedIdentity = objectValue.optionalString("focusedIdentity"),
        dirtyRows = dirtyRows,
        requiresFullTextRepaint = objectValue.optBoolean("requiresFullTextRepaint", true),
        requiresFullGraphicsReplay = objectValue.optBoolean("requiresFullGraphicsReplay", true)
      )
    }
  }
}

private fun JSONObject.optionalInt(name: String): Int? =
  if (has(name) && !isNull(name)) optInt(name) else null

private fun JSONObject.optionalString(name: String): String? =
  if (has(name) && !isNull(name)) optString(name) else null


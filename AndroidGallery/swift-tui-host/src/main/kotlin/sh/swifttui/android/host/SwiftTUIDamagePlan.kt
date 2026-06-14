package sh.swifttui.android.host

/**
 * Pure damage planner: decides whether a frame needs a full grid repaint or can
 * be patched row-by-row against the retained bitmap. Kept Android-free so the
 * branching rules are unit-tested directly.
 *
 * Incremental repaint is only safe when this frame's damage is relative to the
 * frame we actually rendered last. Because the client polls the *latest* frame
 * (and may skip intermediate sequences whose damage would be lost), a partial
 * repaint is allowed only when `frame.sequence == previousSequence + 1`.
 */
object SwiftTUIDamagePlan {
  data class RowDamage(
    val row: Int,
    val columnRanges: List<IntRange>
  ) {
    /** Whether any damaged column range overlaps the half-open cell span
     *  `[startColumn, endColumnExclusive)`. */
    fun intersects(startColumn: Int, endColumnExclusive: Int): Boolean =
      columnRanges.any { startColumn <= it.last && it.first < endColumnExclusive }
  }

  data class Plan(
    val fullRepaint: Boolean,
    val rows: List<RowDamage>
  )

  private val FULL = Plan(fullRepaint = true, rows = emptyList())

  fun plan(
    frame: SwiftTUIFrame,
    previousSequence: Long,
    sizeChanged: Boolean
  ): Plan {
    val requiresFull =
      sizeChanged ||
        previousSequence < 0L ||
        frame.sequence != previousSequence + 1 ||
        frame.requiresFullTextRepaint ||
        frame.requiresFullGraphicsReplay ||
        frame.cells.isEmpty() ||
        // Images are composited over cells; repaint everything when present so a
        // patched cell never paints over an image.
        frame.imageAttachments.isNotEmpty()
    if (requiresFull) {
      return FULL
    }

    val fullWidthRange = 0..(frame.gridWidth - 1).coerceAtLeast(0)
    val byRow = LinkedHashMap<Int, MutableList<IntRange>>()
    for (row in frame.dirtyRows) {
      byRow.getOrPut(row) { mutableListOf() }.add(fullWidthRange)
    }
    for (textRow in frame.textDamageRows) {
      val ranges = byRow.getOrPut(textRow.row) { mutableListOf() }
      for (range in textRow.columnRanges) {
        // SwiftTUIRange mirrors a Swift Range<Int> (upperBound exclusive).
        if (range.upperBound > range.lowerBound) {
          ranges.add(range.lowerBound..(range.upperBound - 1))
        }
      }
    }

    val rows = byRow.map { (row, ranges) -> RowDamage(row, ranges.toList()) }
    return Plan(fullRepaint = false, rows = rows)
  }
}

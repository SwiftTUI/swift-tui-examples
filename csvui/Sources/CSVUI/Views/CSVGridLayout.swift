import Foundation

public struct CSVGridSlice: Equatable, Sendable {
  public var rows: [RowID]
  public var frozenColumns: [ColumnID]
  public var scrollingColumns: [ColumnID]
  public var widths: [ColumnID: Int]
  public var gutterWidth: Int
  public var counters: CSVStructuralCounters

  public init(
    rows: [RowID],
    frozenColumns: [ColumnID],
    scrollingColumns: [ColumnID],
    widths: [ColumnID: Int],
    gutterWidth: Int,
    counters: CSVStructuralCounters
  ) {
    self.rows = rows
    self.frozenColumns = frozenColumns
    self.scrollingColumns = scrollingColumns
    self.widths = widths
    self.gutterWidth = gutterWidth
    self.counters = counters
  }

  public var allColumns: [ColumnID] { frozenColumns + scrollingColumns }
}

public enum CSVGridLayout {
  public static func slice(state: CSVState) -> CSVGridSlice {
    let rowStart = min(max(0, state.cursor.rowOrigin), state.projection.visibleRows.count)
    let rowEnd = min(
      state.projection.visibleRows.count,
      rowStart + state.viewport.dataRowCapacity
    )
    let rows = Array(state.projection.visibleRows[rowStart..<rowEnd])
    let gutterDigits = max(3, String(max(1, state.document.dataRecordCount)).count)
    let gutterWidth = min(10, gutterDigits + 2)
    let columns = state.projection.visibleColumns
    let frozenCount: Int
    if let frozen = state.projection.frozenThrough,
      let index = columns.firstIndex(of: frozen)
    {
      frozenCount = index + 1
    } else {
      frozenCount = 0
    }

    var available = max(1, state.viewport.width - gutterWidth - 1)
    var widths: [ColumnID: Int] = [:]
    var frozenColumns: [ColumnID] = []
    // Preserve a minimum scrolling-cell foothold. A large frozen set is still
    // frozen semantically, but only its leading columns that physically fit
    // can be painted in a finite terminal row.
    for column in columns.prefix(frozenCount) {
      let desired = state.projection.widths[column, default: 12]
      guard available > 4 else { break }
      let width = min(desired, max(4, available - 1))
      frozenColumns.append(column)
      widths[column] = width
      available -= width + 1
    }

    let scrolling = Array(columns.dropFirst(frozenCount))
    var start = min(max(0, state.cursor.scrollingColumnOrigin), scrolling.count)
    if let cursor = state.cursor.column,
      let cursorIndex = scrolling.firstIndex(of: cursor),
      cursorIndex < start
    {
      start = cursorIndex
    }
    var scrollingColumns: [ColumnID] = []
    func fill(from origin: Int) -> [ColumnID] {
      var result: [ColumnID] = []
      var remaining = available
      for column in scrolling.dropFirst(origin) {
        guard remaining > 0 else { break }
        let desired = state.projection.widths[column, default: 12]
        let width = result.isEmpty ? min(desired, max(1, remaining)) : desired
        if !result.isEmpty, width > remaining { break }
        result.append(column)
        widths[column] = width
        remaining -= min(width, remaining) + 1
      }
      return result
    }
    scrollingColumns = fill(from: start)
    if let cursor = state.cursor.column,
      let cursorIndex = scrolling.firstIndex(of: cursor),
      !scrollingColumns.contains(cursor)
    {
      scrollingColumns = fill(from: cursorIndex)
    }

    let columnCount = frozenColumns.count + scrollingColumns.count
    let counters = CSVStructuralCounters(
      realizedRows: rows.count,
      realizedScrollingColumns: scrollingColumns.count,
      realizedFrozenColumns: frozenColumns.count,
      realizedCells: rows.count * columnCount,
      decodedRows: rows.count,
      widthSamples: state.counters.widthSamples
    )
    return CSVGridSlice(
      rows: rows,
      frozenColumns: frozenColumns,
      scrollingColumns: scrollingColumns,
      widths: widths,
      gutterWidth: gutterWidth,
      counters: counters
    )
  }
}

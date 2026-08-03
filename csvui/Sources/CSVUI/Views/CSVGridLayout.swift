import Foundation

struct CSVGridLayoutInput: Equatable, Sendable {
  let visibleRows: [RowID]
  let visibleColumns: [ColumnID]
  let frozenThroughOrdinal: Int?
  let widths: [ColumnID: Int]
  let rowOrigin: Int
  let scrollingColumnOrigin: Int
  let selectedColumnOrdinal: Int?
  let viewport: CSVViewport
  let dataRecordCount: Int
  let widthSamples: Int

  init(
    visibleRows: [RowID],
    visibleColumns: [ColumnID],
    frozenThroughOrdinal: Int?,
    widths: [ColumnID: Int],
    rowOrigin: Int,
    scrollingColumnOrigin: Int,
    selectedColumnOrdinal: Int?,
    viewport: CSVViewport,
    dataRecordCount: Int,
    widthSamples: Int
  ) {
    self.visibleRows = visibleRows
    self.visibleColumns = visibleColumns
    self.frozenThroughOrdinal = frozenThroughOrdinal
    self.widths = widths
    self.rowOrigin = max(0, rowOrigin)
    self.scrollingColumnOrigin = max(0, scrollingColumnOrigin)
    self.selectedColumnOrdinal = selectedColumnOrdinal
    self.viewport = viewport
    self.dataRecordCount = max(0, dataRecordCount)
    self.widthSamples = max(0, widthSamples)
  }
}

struct CSVGridSlice: Equatable, Sendable {
  let rows: [RowID]
  let frozenColumns: [ColumnID]
  let scrollingColumns: [ColumnID]
  let widths: [ColumnID: Int]
  let gutterWidth: Int
  let counters: CSVStructuralCounters

  init(
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

  var allColumns: [ColumnID] { frozenColumns + scrollingColumns }
}

enum CSVGridLayout {
  static func slice(input: CSVGridLayoutInput) -> CSVGridSlice {
    let rowStart = min(max(0, input.rowOrigin), input.visibleRows.count)
    let rowEnd = min(
      input.visibleRows.count,
      rowStart + input.viewport.dataRowCapacity
    )
    let rows = Array(input.visibleRows[rowStart..<rowEnd])
    let gutterDigits = max(3, String(max(1, input.dataRecordCount)).count)
    let gutterWidth = min(10, gutterDigits + 2)
    let columns = input.visibleColumns
    let frozenCount = min(
      columns.count,
      max(0, input.frozenThroughOrdinal.map { $0 + 1 } ?? 0)
    )

    var available = max(1, input.viewport.width - gutterWidth - 1)
    var widths: [ColumnID: Int] = [:]
    var frozenColumns: [ColumnID] = []
    var inspectedColumns = 0
    // Preserve a minimum scrolling-cell foothold. A large frozen set is still
    // frozen semantically, but only its leading columns that physically fit
    // can be painted in a finite terminal row.
    for column in columns.prefix(frozenCount) {
      inspectedColumns += 1
      let desired = input.widths[column, default: 12]
      guard available > 4 else { break }
      let width = min(desired, max(4, available - 1))
      frozenColumns.append(column)
      widths[column] = width
      available -= width + 1
    }

    let scrollingCount = columns.count - frozenCount
    let selectedScrollingOrdinal = input.selectedColumnOrdinal.map { $0 - frozenCount }
    var start = min(max(0, input.scrollingColumnOrigin), scrollingCount)
    if let selectedScrollingOrdinal,
      selectedScrollingOrdinal >= 0,
      selectedScrollingOrdinal < start
    {
      start = selectedScrollingOrdinal
    }
    var scrollingColumns: [ColumnID] = []
    func fill(from origin: Int) -> [ColumnID] {
      var result: [ColumnID] = []
      var remaining = available
      guard origin < scrollingCount else { return result }
      for scrollingOrdinal in origin..<scrollingCount {
        guard remaining > 0 else { break }
        inspectedColumns += 1
        let column = columns[frozenCount + scrollingOrdinal]
        let desired = input.widths[column, default: 12]
        let width = result.isEmpty ? min(desired, max(1, remaining)) : desired
        if !result.isEmpty, width > remaining { break }
        result.append(column)
        widths[column] = width
        remaining -= min(width, remaining) + 1
      }
      return result
    }
    scrollingColumns = fill(from: start)
    if let selectedScrollingOrdinal,
      selectedScrollingOrdinal >= 0,
      selectedScrollingOrdinal < scrollingCount,
      !scrollingColumns.contains(columns[frozenCount + selectedScrollingOrdinal])
    {
      scrollingColumns = fill(from: selectedScrollingOrdinal)
    }

    let columnCount = frozenColumns.count + scrollingColumns.count
    let counters = CSVStructuralCounters(
      realizedRows: rows.count,
      realizedScrollingColumns: scrollingColumns.count,
      realizedFrozenColumns: frozenColumns.count,
      realizedCells: rows.count * columnCount,
      decodedRows: rows.count,
      widthSamples: input.widthSamples,
      inspectedColumns: inspectedColumns
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

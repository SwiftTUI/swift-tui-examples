import Foundation

public struct CSVInsertedRow: Equatable, Sendable {
  public var id: RowID
  public var values: [ColumnID: String]

  public init(id: RowID, values: [ColumnID: String] = [:]) {
    self.id = id
    self.values = values
  }
}

public struct CSVEditJournal: Equatable, Sendable {
  public var cellReplacements: [CSVCellAddress: String]
  public var headerReplacements: [ColumnID: String]
  public var insertedRows: [RowID: CSVInsertedRow]
  public var rowOrder: [RowID]
  public var originalRowOrder: [RowID]
  public var columnOrder: [ColumnID]
  public var originalColumnOrder: [ColumnID]

  public init(document: CSVDocument) {
    cellReplacements = [:]
    headerReplacements = [:]
    insertedRows = [:]
    rowOrder = document.sourceRows
    originalRowOrder = rowOrder
    columnOrder = document.columnIDs
    originalColumnOrder = document.columnIDs
  }

  public var isEmpty: Bool {
    cellReplacements.isEmpty
      && headerReplacements.isEmpty
      && insertedRows.isEmpty
      && rowOrder == originalRowOrder
      && columnOrder == originalColumnOrder
  }

  public var hasStructuralColumnEdits: Bool { columnOrder != originalColumnOrder }

  public func replacement(row: RowID, column: ColumnID) -> String? {
    cellReplacements[CSVCellAddress(row: row, column: column)]
      ?? insertedRows[row]?.values[column]
  }

  public mutating func replace(row: RowID, column: ColumnID, with value: String) {
    if insertedRows[row] != nil {
      insertedRows[row]?.values[column] = value
    } else {
      cellReplacements[CSVCellAddress(row: row, column: column)] = value
    }
  }

  public mutating func renameHeader(_ column: ColumnID, to value: String) {
    headerReplacements[column] = value
  }

  public mutating func insertRow(_ id: RowID, at index: Int) {
    let insertion = min(max(0, index), rowOrder.count)
    insertedRows[id] = CSVInsertedRow(id: id)
    rowOrder.insert(id, at: insertion)
  }

  @discardableResult
  public mutating func deleteRow(_ id: RowID) -> Bool {
    guard let index = rowOrder.firstIndex(of: id) else { return false }
    rowOrder.remove(at: index)
    insertedRows.removeValue(forKey: id)
    cellReplacements = cellReplacements.filter { $0.key.row != id }
    return true
  }

  public mutating func insertColumn(_ id: ColumnID, at index: Int) {
    let insertion = min(max(0, index), columnOrder.count)
    columnOrder.insert(id, at: insertion)
  }

  @discardableResult
  public mutating func deleteColumn(_ id: ColumnID) -> Bool {
    guard let index = columnOrder.firstIndex(of: id) else { return false }
    columnOrder.remove(at: index)
    headerReplacements.removeValue(forKey: id)
    cellReplacements = cellReplacements.filter { $0.key.column != id }
    for rowID in insertedRows.keys {
      insertedRows[rowID]?.values.removeValue(forKey: id)
    }
    return true
  }

  public func estimatedByteCost() -> Int {
    let rowBytes = rowOrder.count.multipliedReportingOverflow(by: MemoryLayout<RowID>.stride)
    let columnBytes = columnOrder.count.multipliedReportingOverflow(
      by: MemoryLayout<ColumnID>.stride
    )
    guard !rowBytes.overflow, !columnBytes.overflow else { return .max }
    var total = rowBytes.partialValue + columnBytes.partialValue
    for (address, value) in cellReplacements {
      _ = address
      let (next, overflow) = total.addingReportingOverflow(value.utf8.count + 32)
      if overflow { return .max }
      total = next
    }
    for value in headerReplacements.values {
      let (next, overflow) = total.addingReportingOverflow(value.utf8.count + 16)
      if overflow { return .max }
      total = next
    }
    return total
  }
}

public struct CSVHistory: Sendable {
  public struct Entry: Sendable {
    public var before: CSVEditJournal
    public var after: CSVEditJournal
    public var revisionBefore: UInt64
    public var revisionAfter: UInt64
    public var byteCost: Int
  }

  public static let maximumEntries = 256
  public static let maximumBytes = 16 * 1_024 * 1_024

  private(set) public var undoEntries: [Entry] = []
  private(set) public var redoEntries: [Entry] = []
  private(set) public var byteCost = 0

  public init() {}

  public mutating func record(_ entry: Entry) -> Bool {
    guard entry.byteCost <= Self.maximumBytes else { return false }
    byteCost -= redoEntries.reduce(into: 0) { $0 += $1.byteCost }
    redoEntries.removeAll(keepingCapacity: true)
    undoEntries.append(entry)
    byteCost += entry.byteCost
    while undoEntries.count > Self.maximumEntries || byteCost > Self.maximumBytes {
      byteCost -= undoEntries.removeFirst().byteCost
    }
    return true
  }

  public mutating func undo() -> Entry? {
    guard let entry = undoEntries.popLast() else { return nil }
    redoEntries.append(entry)
    return entry
  }

  public mutating func redo() -> Entry? {
    guard let entry = redoEntries.popLast() else { return nil }
    undoEntries.append(entry)
    return entry
  }
}

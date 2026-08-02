public import Foundation

public struct CSVSerializer: Sendable {
  public init() {}

  public func serialize(
    document: CSVDocument,
    journal: CSVEditJournal
  ) throws -> Data {
    if journal.isEmpty { return document.source.bytes }

    var output = Data()
    output.reserveCapacity(document.source.bytes.count)
    if document.dialect.hasUTF8BOM { output.append(contentsOf: [0xEF, 0xBB, 0xBF]) }

    let recordCount = journal.rowOrder.count + (document.dialect.hasHeaders ? 1 : 0)
    let originalColumnOffsets = Dictionary(
      uniqueKeysWithValues: journal.originalColumnOrder.enumerated().map { ($1, $0) }
    )
    var editedBeyondByRow: [RowID: Int] = [:]
    editedBeyondByRow.reserveCapacity(journal.cellReplacements.count)
    for address in journal.cellReplacements.keys {
      guard let offset = originalColumnOffsets[address.column] else { continue }
      editedBeyondByRow[address.row] = max(editedBeyondByRow[address.row, default: -1], offset)
    }
    var recordOffset = 0

    func appendRecord(
      fields: [SerializedField],
      originalEnding: CSVLineEnding?
    ) throws {
      if recordOffset.isMultiple(of: 256) { try Task.checkCancellation() }
      for (fieldIndex, field) in fields.enumerated() {
        if fieldIndex > 0 { output.append(document.dialect.delimiter.byte) }
        output.append(contentsOf: field.bytes)
      }
      let isLast = recordOffset == recordCount - 1
      if !isLast || document.dialect.hasFinalNewline {
        let ending = originalEnding ?? document.dialect.dominantLineEnding
        output.append(contentsOf: ending.bytes)
      }
      recordOffset += 1
    }

    if document.dialect.hasHeaders {
      try appendRecord(
        fields: try headerFields(
          document: document,
          journal: journal,
          originalColumnOffsets: originalColumnOffsets
        ),
        originalEnding: document.recordIndex.records.first?.lineEnding
      )
    }
    for rowID in journal.rowOrder {
      try appendRecord(
        fields: try rowFields(
          rowID,
          document: document,
          journal: journal,
          originalColumnOffsets: originalColumnOffsets,
          editedBeyond: editedBeyondByRow[rowID]
        ),
        originalEnding: originalLineEnding(for: rowID, document: document)
      )
    }
    return output
  }

  public func serializeRow(
    _ rowID: RowID,
    document: CSVDocument,
    journal: CSVEditJournal
  ) throws -> String {
    let originalColumnOffsets = Dictionary(
      uniqueKeysWithValues: journal.originalColumnOrder.enumerated().map { ($1, $0) }
    )
    let editedBeyond = journal.cellReplacements.keys.compactMap { address -> Int? in
      guard address.row == rowID else { return nil }
      return originalColumnOffsets[address.column]
    }.max()
    let fields = try rowFields(
      rowID,
      document: document,
      journal: journal,
      originalColumnOffsets: originalColumnOffsets,
      editedBeyond: editedBeyond
    )
    let bytes = fields.enumerated().flatMap { index, field -> [UInt8] in
      (index == 0 ? [] : [document.dialect.delimiter.byte]) + field.bytes
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  private struct SerializedField {
    var bytes: [UInt8]
  }

  private func headerFields(
    document: CSVDocument,
    journal: CSVEditJournal,
    originalColumnOffsets: [ColumnID: Int]
  ) throws -> [SerializedField] {
    let original = document.header?.fields ?? []
    return journal.columnOrder.map { column in
      if let replacement = journal.headerReplacements[column] {
        return SerializedField(bytes: encode(replacement, delimiter: document.dialect.delimiter))
      }
      guard let base = originalColumnOffsets[column],
        original.indices.contains(base)
      else {
        return SerializedField(bytes: [])
      }
      return SerializedField(bytes: Array(original[base].rawLexeme.utf8))
    }
  }

  private func rowFields(
    _ rowID: RowID,
    document: CSVDocument,
    journal: CSVEditJournal,
    originalColumnOffsets: [ColumnID: Int],
    editedBeyond: Int?
  ) throws -> [SerializedField] {
    let original = try document.decodeSourceRow(rowID)?.fields ?? []
    let lastOriginalField = original.indices.last

    // With no structural column operation, preserve a short row's exact arity.
    let columns: ArraySlice<ColumnID>
    if !journal.hasStructuralColumnEdits, let lastOriginalField {
      let count = max(lastOriginalField + 1, (editedBeyond ?? -1) + 1)
      columns = journal.columnOrder.prefix(count)
    } else if !journal.hasStructuralColumnEdits,
      journal.insertedRows[rowID] == nil,
      original.isEmpty
    {
      columns = journal.columnOrder.prefix(1)
    } else {
      columns = journal.columnOrder[...]
    }

    return columns.map { column in
      if let replacement = journal.replacement(row: rowID, column: column) {
        return SerializedField(bytes: encode(replacement, delimiter: document.dialect.delimiter))
      }
      guard let base = originalColumnOffsets[column],
        original.indices.contains(base)
      else {
        return SerializedField(bytes: [])
      }
      return SerializedField(bytes: Array(original[base].rawLexeme.utf8))
    }
  }

  private func originalLineEnding(
    for rowID: RowID,
    document: CSVDocument
  ) -> CSVLineEnding? {
    guard let index = document.recordIndex(for: rowID) else { return nil }
    return document.recordIndex.records[index].lineEnding
  }

  private func encode(_ value: String, delimiter: CSVDelimiter) -> [UInt8] {
    let source = Array(value.utf8)
    let needsQuotes =
      source.contains(delimiter.byte)
      || source.contains(0x22)
      || source.contains(0x0A)
      || source.contains(0x0D)
    guard needsQuotes else { return source }
    var result: [UInt8] = [0x22]
    result.reserveCapacity(source.count + 2)
    for byte in source {
      if byte == 0x22 { result.append(0x22) }
      result.append(byte)
    }
    result.append(0x22)
    return result
  }
}

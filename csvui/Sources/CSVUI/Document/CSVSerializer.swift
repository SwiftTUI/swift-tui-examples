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
    if document.dialect.hasUTF8BOM { output.append(contentsOf: Self.utf8BOM) }

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
      let recordStart = output.count
      for (fieldIndex, field) in fields.enumerated() {
        // The indexer refuses NUL anywhere, quoted or not, so a save that
        // wrote one could never be reopened. Source fields cannot hold it
        // (they were indexed), so only an edited value is checked.
        if field.isEdited, field.bytes.contains(0) {
          let isHeader = document.dialect.hasHeaders && recordOffset == 0
          let row = document.dialect.hasHeaders ? recordOffset : recordOffset + 1
          throw CSVSerializationError.nulCharacter(
            row: isHeader ? nil : row, column: fieldIndex + 1)
        }
        if fieldIndex > 0 { output.append(document.dialect.delimiter.byte) }
        if output.isEmpty, field.bytes.starts(with: Self.utf8BOM) {
          // With no BOM written, a first field starting with U+FEFF would put
          // EF BB BF at byte 0, which the indexer reads as the file's BOM.
          output.append(contentsOf: Self.quoted(field.bytes))
        } else {
          output.append(contentsOf: field.bytes)
        }
      }
      let isLast = recordOffset == recordCount - 1
      if !isLast || document.dialect.hasFinalNewline {
        let ending = originalEnding ?? document.dialect.dominantLineEnding
        output.append(contentsOf: ending.bytes)
      } else if output.count == recordStart {
        // An unterminated last record of zero bytes is no record at all to a
        // reader; a quoted empty field (RFC 4180) keeps it.
        output.append(contentsOf: [0x22, 0x22])
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
    /// True for a value the journal supplied, false for a source lexeme.
    var isEdited = false
  }

  private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

  private func headerFields(
    document: CSVDocument,
    journal: CSVEditJournal,
    originalColumnOffsets: [ColumnID: Int]
  ) throws -> [SerializedField] {
    let original = document.header?.fields ?? []
    return journal.columnOrder.map { column in
      if let replacement = journal.headerReplacements[column] {
        return SerializedField(
          bytes: encode(replacement, delimiter: document.dialect.delimiter), isEdited: true)
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
        return SerializedField(
          bytes: encode(replacement, delimiter: document.dialect.delimiter), isEdited: true)
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
    return Self.quoted(source)
  }

  /// `bytes` as one quoted field: wrapped in quotes, each quote doubled.
  private static func quoted(_ bytes: [UInt8]) -> [UInt8] {
    var result: [UInt8] = [0x22]
    result.reserveCapacity(bytes.count + 2)
    for byte in bytes {
      if byte == 0x22 { result.append(0x22) }
      result.append(byte)
    }
    result.append(0x22)
    return result
  }
}

/// Why `serialize` refused to write a document.
///
/// Internal: callers see it as `any Error` and show its description.
enum CSVSerializationError: Error, Equatable, Sendable, LocalizedError {
  /// An edited value holds NUL, which csvui refuses on read
  /// (`CSVRecordIndexer`), quoted or not. `row` is the 1-based data row in
  /// the document's current order, or `nil` for the header; `column` is the
  /// 1-based column in the current order.
  case nulCharacter(row: Int?, column: Int)

  var errorDescription: String? {
    switch self {
    case .nulCharacter(let row, let column):
      let place = row.map { "row \($0), column \(column)" } ?? "the header of column \(column)"
      return "cannot save: \(place) contains a NUL character, which csvui cannot reopen"
    }
  }
}

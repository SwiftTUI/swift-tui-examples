import Foundation

public struct CSVDocument: Equatable, Sendable {
  public var source: CSVSourceSnapshot
  public var dialect: CSVDialect
  public var recordIndex: CSVRecordIndex
  public var header: CSVDecodedRow?
  public var columnIDs: [ColumnID]
  public var irregularDataRecordCount: Int
  public var revision: UInt64

  public init(
    source: CSVSourceSnapshot,
    dialect: CSVDialect,
    recordIndex: CSVRecordIndex,
    header: CSVDecodedRow?,
    columnIDs: [ColumnID],
    irregularDataRecordCount: Int,
    revision: UInt64 = 0
  ) {
    self.source = source
    self.dialect = dialect
    self.recordIndex = recordIndex
    self.header = header
    self.columnIDs = columnIDs
    self.irregularDataRecordCount = irregularDataRecordCount
    self.revision = revision
  }

  public static func parse(
    source: CSVSourceSnapshot,
    delimiter: CSVDelimiter,
    hasHeaders: Bool
  ) throws -> CSVDocument {
    let index = try CSVRecordIndexer().index(source.bytes, delimiter: delimiter)
    let decoder = CSVRowDecoder()
    let header: CSVDecodedRow?
    if hasHeaders, let record = index.records.first {
      header = try decoder.decode(record, from: source.bytes, delimiter: delimiter)
    } else {
      header = nil
    }
    let dataStart = hasHeaders && !index.records.isEmpty ? 1 : 0
    let irregular = index.records.dropFirst(dataStart).reduce(into: 0) { result, record in
      if record.fieldCount != index.maximumFieldCount { result += 1 }
    }
    let observed = Set(index.lineEndingCounts.compactMap { $0.value > 0 ? $0.key : nil })
    return CSVDocument(
      source: source,
      dialect: CSVDialect(
        delimiter: delimiter,
        hasHeaders: hasHeaders,
        hasUTF8BOM: index.startsAfterUTF8BOM,
        dominantLineEnding: index.dominantLineEnding,
        observedLineEndings: observed,
        hasFinalNewline: index.hasFinalNewline
      ),
      recordIndex: index,
      header: header,
      columnIDs: (0..<index.maximumFieldCount).map(ColumnID.init),
      irregularDataRecordCount: irregular
    )
  }

  public var dataRecordCount: Int {
    max(0, recordIndex.records.count - (dialect.hasHeaders && !recordIndex.records.isEmpty ? 1 : 0))
  }

  public var sourceRows: [RowID] {
    (0..<dataRecordCount).map(RowID.init(sourceIndex:))
  }

  public func recordIndex(for rowID: RowID) -> Int? {
    guard let sourceIndex = rowID.sourceIndex, sourceIndex >= 0, sourceIndex < dataRecordCount
    else {
      return nil
    }
    return sourceIndex + (dialect.hasHeaders && !recordIndex.records.isEmpty ? 1 : 0)
  }

  public func columnLabel(_ id: ColumnID) -> String {
    guard let ordinal = columnIDs.firstIndex(of: id) else { return "column_?" }
    if dialect.hasHeaders,
      let header,
      header.fields.indices.contains(ordinal),
      !header.fields[ordinal].value.isEmpty
    {
      let value = header.fields[ordinal].value
      let duplicates = header.fields.prefix(ordinal).filter { $0.value == value }.count
      return duplicates == 0 ? value : "\(value) [\(duplicates + 1)]"
    }
    return "column_\(ordinal + 1)"
  }

  public func decodeSourceRow(
    _ rowID: RowID,
    cache: CSVRowCache? = nil
  ) throws -> CSVDecodedRow? {
    guard let index = recordIndex(for: rowID) else { return nil }
    let decode = {
      try CSVRowDecoder().decode(
        recordIndex.records[index],
        from: source.bytes,
        delimiter: dialect.delimiter
      )
    }
    if let cache { return try cache.row(recordIndex: index, decode: decode) }
    return try decode()
  }
}

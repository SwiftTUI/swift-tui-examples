import Foundation

struct CSVInitialWidthSample: Equatable, Sendable {
  var widths: [ColumnID: Int]
  var sampleCount: Int

  init(widths: [ColumnID: Int], sampleCount: Int) {
    self.widths = widths
    self.sampleCount = max(0, sampleCount)
  }
}

struct CSVLoadPhaseMetrics: Equatable, Sendable {
  var sourceReadNanoseconds: UInt64
  var validationAndIndexingNanoseconds: UInt64
  var documentConstructionNanoseconds: UInt64
  var initialWidthSamplingNanoseconds: UInt64
  var modelCommitNanoseconds: UInt64
  var firstPopulatedPresentationNanoseconds: UInt64

  init(
    sourceReadNanoseconds: UInt64 = 0,
    validationAndIndexingNanoseconds: UInt64,
    documentConstructionNanoseconds: UInt64,
    initialWidthSamplingNanoseconds: UInt64,
    modelCommitNanoseconds: UInt64 = 0,
    firstPopulatedPresentationNanoseconds: UInt64 = 0
  ) {
    self.sourceReadNanoseconds = sourceReadNanoseconds
    self.validationAndIndexingNanoseconds = validationAndIndexingNanoseconds
    self.documentConstructionNanoseconds = documentConstructionNanoseconds
    self.initialWidthSamplingNanoseconds = initialWidthSamplingNanoseconds
    self.modelCommitNanoseconds = modelCommitNanoseconds
    self.firstPopulatedPresentationNanoseconds = firstPopulatedPresentationNanoseconds
  }
}

struct CSVDocumentLoadResult: Equatable, Sendable {
  var document: CSVDocument
  var initialWidths: CSVInitialWidthSample
  var metrics: CSVLoadPhaseMetrics?
}

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
    return try construct(
      source: source,
      delimiter: delimiter,
      hasHeaders: hasHeaders,
      index: index
    )
  }

  static func load(
    source: CSVSourceSnapshot,
    delimiter: CSVDelimiter,
    hasHeaders: Bool,
    metricsEnabled: Bool = CSVLoadMetrics.isEnabled
  ) throws -> CSVDocumentLoadResult {
    let clock = ContinuousClock()
    let indexingStart = metricsEnabled ? clock.now : nil
    let index = try CSVRecordIndexer().index(source.bytes, delimiter: delimiter)
    let indexingNanoseconds =
      indexingStart.map {
        CSVLoadMetrics.nanoseconds($0.duration(to: clock.now))
      } ?? 0
    try Task.checkCancellation()
    let constructionStart = metricsEnabled ? clock.now : nil
    let document = try construct(
      source: source,
      delimiter: delimiter,
      hasHeaders: hasHeaders,
      index: index
    )
    let constructionNanoseconds =
      constructionStart.map {
        CSVLoadMetrics.nanoseconds($0.duration(to: clock.now))
      } ?? 0
    try Task.checkCancellation()
    let widthStart = metricsEnabled ? clock.now : nil
    let initialWidths = try document.initialWidthSample()
    let widthNanoseconds =
      widthStart.map {
        CSVLoadMetrics.nanoseconds($0.duration(to: clock.now))
      } ?? 0
    return CSVDocumentLoadResult(
      document: document,
      initialWidths: initialWidths,
      metrics: metricsEnabled
        ? CSVLoadPhaseMetrics(
          sourceReadNanoseconds: source.sourceReadNanoseconds ?? 0,
          validationAndIndexingNanoseconds: indexingNanoseconds,
          documentConstructionNanoseconds: constructionNanoseconds,
          initialWidthSamplingNanoseconds: widthNanoseconds
        )
        : nil
    )
  }

  private static func construct(
    source: CSVSourceSnapshot,
    delimiter: CSVDelimiter,
    hasHeaders: Bool,
    index: CSVRecordIndex
  ) throws -> CSVDocument {
    let decoder = CSVRowDecoder()
    let header: CSVDecodedRow?
    if hasHeaders, let record = index.records.first {
      header = try decoder.decode(record, from: source.bytes, delimiter: delimiter)
    } else {
      header = nil
    }
    let dataStart = hasHeaders && !index.records.isEmpty ? 1 : 0
    let headerIsIrregular =
      dataStart == 1 && index.records[0].fieldCount != index.maximumFieldCount
    let irregular = index.irregularRecordCount - (headerIsIrregular ? 1 : 0)
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

  func initialWidthSample(limit: Int = 1_000) throws -> CSVInitialWidthSample {
    var widths: [ColumnID: Int] = [:]
    for column in columnIDs {
      widths[column] = min(40, max(4, columnLabel(column).count + 2))
    }
    let sampleCount = min(max(0, limit), dataRecordCount)
    for rowIndex in 0..<sampleCount {
      if rowIndex.isMultiple(of: 64) { try Task.checkCancellation() }
      guard let decoded = try decodeSourceRow(RowID(sourceIndex: rowIndex)) else { continue }
      for (base, field) in decoded.fields.enumerated() where columnIDs.indices.contains(base) {
        let column = columnIDs[base]
        let width = Self.visibleControlCharacters(field.value).count + 2
        widths[column] = min(40, max(widths[column, default: 4], width))
      }
    }
    return CSVInitialWidthSample(widths: widths, sampleCount: sampleCount)
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

  private static func visibleControlCharacters(_ source: String) -> String {
    var result = ""
    for scalar in source.unicodeScalars {
      switch scalar.value {
      case 0x09: result.append("⇥")
      case 0x0A: result.append("↵")
      case 0x0D: result.append("␍")
      case 0x00...0x1F, 0x7F: result.append("�")
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result
  }
}

enum CSVLoadMetrics {
  static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["CSVUI_LOAD_METRICS"] == "1"
  }

  static func nanoseconds(_ duration: Duration) -> UInt64 {
    let components = duration.components
    let seconds = max(0, components.seconds)
    let nanos = max(0, components.attoseconds / 1_000_000_000)
    let (wholeSeconds, overflow) = UInt64(seconds).multipliedReportingOverflow(by: 1_000_000_000)
    if overflow { return .max }
    return wholeSeconds &+ UInt64(nanos)
  }

  static func emit(_ metrics: CSVLoadPhaseMetrics) {
    guard isEnabled else { return }
    let fields = [
      "source_read=\(metrics.sourceReadNanoseconds)",
      "validation_indexing=\(metrics.validationAndIndexingNanoseconds)",
      "document_construction=\(metrics.documentConstructionNanoseconds)",
      "initial_widths=\(metrics.initialWidthSamplingNanoseconds)",
      "model_commit=\(metrics.modelCommitNanoseconds)",
      "first_populated_presentation=\(metrics.firstPopulatedPresentationNanoseconds)",
    ]
    FileHandle.standardError.write(
      Data(("csvui_load_phases\t" + fields.joined(separator: "\t") + "\n").utf8))
  }

}

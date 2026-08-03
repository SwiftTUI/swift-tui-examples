import Foundation
import Synchronization
import Testing

@testable import CSVUI

@Suite("CSV document core")
struct CSVDocumentCoreTests {
  @Test("plain header and records index without materializing cells")
  func plainRecords() throws {
    let bytes = Data("name,age\r\nAda,36\r\nGrace,44\r\n".utf8)
    let document = try parse(bytes)

    #expect(document.recordIndex.records.count == 3)
    #expect(document.dataRecordCount == 2)
    #expect(document.columnIDs.count == 2)
    #expect(document.header?.fields.map(\.value) == ["name", "age"])
    #expect(document.dialect.dominantLineEnding == .crlf)
    #expect(document.dialect.hasFinalNewline)
    #expect(
      try document.decodeSourceRow(RowID(sourceIndex: 1))?.fields.map(\.value) == ["Grace", "44"])
  }

  @Test("quoted delimiters, physical newlines, and doubled quotes decode")
  func quotedFields() throws {
    let bytes = Data("name,note\nAda,\"line 1\nline 2, \"\"quoted\"\"\"\n".utf8)
    let document = try parse(bytes)
    let decoded = try document.decodeSourceRow(RowID(sourceIndex: 0))
    let row = try #require(decoded)

    #expect(row.fields[1].value == "line 1\nline 2, \"quoted\"")
    #expect(row.fields[1].rawLexeme == "\"line 1\nline 2, \"\"quoted\"\"\"")
    #expect(row.fields[1].wasQuoted)
  }

  @Test("bare quotes remain literal but post-closing bytes fail")
  func quotePolicy() throws {
    let accepted = try parse(Data("a,b\nx\"y,z\n".utf8))
    #expect(try accepted.decodeSourceRow(RowID(sourceIndex: 0))?.fields[0].value == "x\"y")

    do {
      _ = try parse(Data("a,b\n\"x\"z,y\n".utf8))
      Issue.record("expected invalid bytes after closing quote")
    } catch let error as CSVFormatError {
      #expect(error.message == "unexpected byte after closing quote")
      #expect(error.line == 2)
      #expect(error.byteOffset == 7)
    }
  }

  @Test("unclosed quote, NUL, and invalid UTF-8 report byte locations")
  func fatalInputDiagnostics() {
    #expect(throws: CSVFormatError.self) {
      _ = try parse(Data("a\n\"open".utf8))
    }
    do {
      _ = try parse(Data([0x61, 0x00, 0x62]))
      Issue.record("expected NUL rejection")
    } catch let error as CSVFormatError {
      #expect(error.byteOffset == 1)
    } catch {
      Issue.record("unexpected error: \(error)")
    }
    do {
      _ = try parse(Data([0x61, 0xC0, 0xAF]))
      Issue.record("expected UTF-8 rejection")
    } catch let error as CSVFormatError {
      #expect(error.byteOffset == 1)
    } catch {
      Issue.record("unexpected error: \(error)")
    }
  }

  @Test("fused validation preserves UTF-8 and NUL byte diagnostics at chunk edges")
  func fusedValidationBoundaries() throws {
    let invalidCases: [(bytes: [UInt8], offset: Int)] = [
      ([0x61, 0xC2], 1),
      ([0x61, 0xE0, 0x80, 0x80], 1),
      ([0x61, 0xE1, 0x80, 0x41], 3),
      (Array("a\n\"x\"".utf8) + [0xC0], 5),
    ]
    for fixture in invalidCases {
      do {
        _ = try parse(Data(fixture.bytes))
        Issue.record("expected invalid UTF-8 at \(fixture.offset)")
      } catch let error as CSVFormatError {
        #expect(error.message == "invalid UTF-8")
        #expect(error.byteOffset == fixture.offset)
        #expect(error.column == fixture.offset + 1)
      }
    }

    var chunked = Data(repeating: 0x61, count: 64 * 1_024 - 1)
    chunked.append(contentsOf: [0xE2, 0x82, 0xAC, 0x00])
    do {
      _ = try CSVRecordIndexer().index(chunked, delimiter: .comma)
      Issue.record("expected NUL rejection")
    } catch let error as CSVFormatError {
      #expect(error.message == "NUL bytes are not supported")
      #expect(error.byteOffset == 64 * 1_024 + 2)
    }
  }

  @Test("validation still precedes an earlier quote syntax failure")
  func validationPrepassPrecedence() {
    let syntaxPrefix = Array("a,b\n\"x\"z,".utf8)
    let cases: [(suffix: [UInt8], message: String, offset: Int)] = [
      ([0x00], "NUL bytes are not supported", syntaxPrefix.count),
      ([0xC0, 0xAF], "invalid UTF-8", syntaxPrefix.count),
    ]

    for fixture in cases {
      do {
        _ = try CSVRecordIndexer().index(
          Data(syntaxPrefix + fixture.suffix),
          delimiter: .comma
        )
        Issue.record("expected validation failure before quote syntax failure")
      } catch let error as CSVFormatError {
        #expect(error.message == fixture.message)
        #expect(error.byteOffset == fixture.offset)
        #expect(error.column == fixture.offset + 1)
      } catch {
        Issue.record("unexpected error: \(error)")
      }
    }
  }

  @Test("BOM, mixed endings, duplicate headers, and irregular rows are retained")
  func dialectAndShape() throws {
    var bytes = Data([0xEF, 0xBB, 0xBF])
    bytes.append(Data("name,name,\r\nAda\rGrace,44,ok\n".utf8))
    let document = try parse(bytes)

    #expect(document.dialect.hasUTF8BOM)
    #expect(document.dialect.observedLineEndings == Set([.crlf, .cr, .lf]))
    #expect(document.columnLabel(ColumnID(0)) == "name")
    #expect(document.columnLabel(ColumnID(1)) == "name [2]")
    #expect(document.columnLabel(ColumnID(2)) == "column_3")
    #expect(document.irregularDataRecordCount == 1)
  }

  @Test("no-header mode keeps record zero as data")
  func noHeaders() throws {
    let document = try parse(Data("Ada,36\nGrace,44".utf8), hasHeaders: false)
    #expect(document.header == nil)
    #expect(document.dataRecordCount == 2)
    #expect(document.columnLabel(ColumnID(0)) == "column_1")
  }

  @Test("delimiter detection returns inspectable evidence")
  func delimiterDetection() {
    let tsv = CSVDelimiterDetector().detect(Data("a\tb\n1\t2\n3\t4\n".utf8))
    #expect(tsv.delimiter == .tab)
    #expect(!tsv.usedDefault)
    #expect(tsv.evidence.first(where: { $0.delimiter == .tab })?.modalFieldCount == 2)

    let ambiguous = CSVDelimiterDetector().detect(Data("only one field\nnext\n".utf8))
    #expect(ambiguous.delimiter == .comma)
    #expect(ambiguous.usedDefault)
  }

  @Test("no-edit serialization is byte-identical across mixed records")
  func byteIdenticalRoundTrip() throws {
    var bytes = Data([0xEF, 0xBB, 0xBF])
    bytes.append(Data("h1,h2\r\n\"a\",b\rc,\"d\nq\"".utf8))
    let document = try parse(bytes)
    let serialized = try CSVSerializer().serialize(
      document: document,
      journal: CSVEditJournal(document: document)
    )
    #expect(serialized == bytes)
  }

  @Test("cell edits quote only the edited field and keep source order")
  func editedSerialization() throws {
    let document = try parse(Data("h1,h2\r\n\"a\",b\r\nc,d".utf8))
    var journal = CSVEditJournal(document: document)
    journal.replace(row: RowID(sourceIndex: 0), column: ColumnID(1), with: "x,y")
    let output = try CSVSerializer().serialize(document: document, journal: journal)

    #expect(String(decoding: output, as: UTF8.self) == "h1,h2\r\n\"a\",\"x,y\"\r\nc,d")
  }

  @Test("row and column structural edits are deterministic")
  func structuralSerialization() throws {
    let document = try parse(Data("a,b\n1,2\n3,4\n".utf8))
    var journal = CSVEditJournal(document: document)
    let insertedColumn = ColumnID(2)
    journal.insertColumn(insertedColumn, at: 1)
    journal.renameHeader(insertedColumn, to: "middle")
    let insertedRow = RowID(insertedID: 1)
    journal.insertRow(insertedRow, at: 1)
    journal.replace(row: insertedRow, column: insertedColumn, with: "new")
    _ = journal.deleteRow(RowID(sourceIndex: 1))

    let output = try CSVSerializer().serialize(document: document, journal: journal)
    #expect(String(decoding: output, as: UTF8.self) == "a,middle,b\n1,,2\n,new,\n")
  }

  @Test("row cache obeys both entry and byte caps")
  func cacheBounds() throws {
    let lines = (0..<600).map { "\($0),value-\($0)" }.joined(separator: "\n")
    let document = try parse(Data(lines.utf8), hasHeaders: false)
    let cache = CSVRowCache()
    for index in 0..<600 {
      _ = try document.decodeSourceRow(RowID(sourceIndex: index), cache: cache)
    }
    #expect(cache.statistics.entries <= CSVRowCache.maximumEntries)
    #expect(cache.statistics.bytes <= CSVRowCache.maximumBytes)
    #expect(cache.statistics.evictions > 0)
  }

  private func parse(_ data: Data, hasHeaders: Bool = true) throws -> CSVDocument {
    try CSVDocument.parse(
      source: CSVSourceSnapshot(origin: .standardInput, displayName: "fixture", bytes: data),
      delimiter: .comma,
      hasHeaders: hasHeaders
    )
  }

  @Test("indexing observes cancellation before scanning source bytes")
  func indexingCancellation() async {
    let task = Task {
      try? await Task.sleep(for: .seconds(60))
      return try CSVRecordIndexer().index(Data("a,b\n1,2\n".utf8), delimiter: .comma)
    }
    task.cancel()
    do {
      _ = try await task.value
      Issue.record("cancelled indexing unexpectedly completed")
    } catch is CancellationError {
      // Expected: cancellation is part of the source-loading contract.
    } catch {
      Issue.record("expected CancellationError, got \(error)")
    }
  }

  @Test("fused indexing checks cancellation at 64 KiB scan boundaries")
  func indexingCancellationDuringScan() async {
    let bytes = Data(repeating: 0x61, count: 64 * 1_024 * 1_024)
    let task = Task.detached {
      try CSVRecordIndexer().index(bytes, delimiter: .comma)
    }
    await Task.yield()
    task.cancel()
    do {
      _ = try await task.value
      Issue.record("cancelled in-flight indexing unexpectedly completed")
    } catch is CancellationError {
      // Expected at a periodic fused-scan cancellation check.
    } catch {
      Issue.record("expected CancellationError, got \(error)")
    }
  }

  @Test("CRLF jumps cannot skip a periodic cancellation threshold")
  func cancellationThresholdAcrossCRLF() throws {
    var bytes = Data([0x61])
    for _ in 0..<40_000 { bytes.append(contentsOf: [0x0D, 0x0A]) }
    let observedOffsets = Mutex<[Int]>([])
    _ = try CSVRecordIndexer { offset in
      observedOffsets.withLock { $0.append(offset) }
    }.index(bytes, delimiter: .comma)

    #expect(observedOffsets.withLock { $0.first } == 64 * 1_024 + 1)
  }

  @Test("load result carries phase attribution and initial widths")
  func attributedLoadResult() throws {
    let source = CSVSourceSnapshot(
      origin: .standardInput,
      displayName: "widths.csv",
      bytes: Data("short,long\na,1234567890\nwide-value,x\n".utf8)
    )
    let result = try CSVDocument.load(
      source: source,
      delimiter: .comma,
      hasHeaders: true,
      metricsEnabled: true
    )

    #expect(result.document.dataRecordCount == 2)
    #expect(result.initialWidths.widths[ColumnID(0)] == 12)
    #expect(result.initialWidths.widths[ColumnID(1)] == 12)
    #expect(result.initialWidths.sampleCount == 2)
    #expect(result.metrics != nil)
  }

  @Test("branching after undo releases the abandoned redo budget")
  func historyBranchBudget() throws {
    let document = try CSVDocument.parse(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: "history.csv",
        bytes: Data("a\n1\n".utf8)
      ),
      delimiter: .comma,
      hasHeaders: true
    )
    let journal = CSVEditJournal(document: document)
    var history = CSVHistory()
    let recordedFirst = history.record(
      .init(
        before: journal,
        after: journal,
        revisionBefore: 0,
        revisionAfter: 1,
        byteCost: 10
      )
    )
    #expect(recordedFirst)
    let recordedSecond = history.record(
      .init(
        before: journal,
        after: journal,
        revisionBefore: 1,
        revisionAfter: 2,
        byteCost: 20
      )
    )
    #expect(recordedSecond)
    _ = history.undo()
    #expect(history.byteCost == 30)
    let recordedBranch = history.record(
      .init(
        before: journal,
        after: journal,
        revisionBefore: 1,
        revisionAfter: 3,
        byteCost: 5
      )
    )
    #expect(recordedBranch)
    #expect(history.byteCost == 15)
    #expect(history.redoEntries.isEmpty)
  }
}

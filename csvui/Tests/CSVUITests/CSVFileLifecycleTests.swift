import Foundation
import Testing

@testable import CSVUI

@Suite("CSV file lifecycle", .serialized)
struct CSVFileLifecycleTests {
  @Test(
    "generated load phase probe reports the range-projection decision trigger",
    .enabled(
      if: ProcessInfo.processInfo.environment["CSVUI_LOAD_BENCHMARKS"] == "1",
      "Local performance probe; set CSVUI_LOAD_BENCHMARKS=1 to run."
    ),
    .timeLimit(.minutes(2))
  )
  func generatedLoadPhaseProbe() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    for requestedBytes in [8 * 1_024 * 1_024, 40 * 1_024 * 1_024] {
      let file = directory.appendingPathComponent("generated-\(requestedBytes).tsv")
      var bytes = Data("id\tname\tcity\tutf8\tnote\n".utf8)
      bytes.reserveCapacity(requestedBytes + 256)
      let row = Data(
        "123456\tgenerated-name\tgenerated-city\t東京-🙂\tstable-padding-0123456789abcdef\n".utf8
      )
      while bytes.count < requestedBytes { bytes.append(row) }
      try bytes.write(to: file)

      let totalStarted = ContinuousClock.now
      let source = try CSVSourceReader().read(fileURL: file, metricsEnabled: true)
      let result = try CSVDocument.load(
        source: source,
        delimiter: .tab,
        hasHeaders: true,
        metricsEnabled: true
      )
      let journalStarted = ContinuousClock.now
      let journal = CSVEditJournal(document: result.document)
      let journalNanoseconds = CSVLoadMetrics.nanoseconds(journalStarted.duration(to: .now))
      let totalNanoseconds = CSVLoadMetrics.nanoseconds(totalStarted.duration(to: .now))
      let triggerPercent =
        totalNanoseconds == 0
        ? 0
        : Double(journalNanoseconds) / Double(totalNanoseconds) * 100
      let metrics = try #require(result.metrics)
      print(
        "csvui_load_probe bytes=\(bytes.count) rows=\(journal.rowOrder.count) "
          + "source_read_ns=\(metrics.sourceReadNanoseconds) "
          + "validation_indexing_ns=\(metrics.validationAndIndexingNanoseconds) "
          + "document_ns=\(metrics.documentConstructionNanoseconds) "
          + "widths_ns=\(metrics.initialWidthSamplingNanoseconds) "
          + "journal_ns=\(journalNanoseconds) journal_percent=\(triggerPercent) "
          + "total_ns=\(totalNanoseconds)"
      )
      #expect(result.initialWidths.sampleCount == 1_000)
    }
  }

  @Test("Save As is atomic, preserves permissions, and grants authority")
  func saveAsAndOverwrite() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("saved.csv")
    let bytes = Data("name,age\nAda,44\n".utf8)

    let first = try CSVFileWriter().write(
      CSVFileWriteRequest(
        destination: destination,
        bytes: bytes,
        expectedBytes: nil,
        expectedIdentity: nil,
        overwrite: false
      )
    )
    #expect(first.source.bytes == bytes)
    #expect(first.source.writeBackAuthority != nil)
    #expect(try permissions(of: destination) == 0o644)
    #expect(try directoryContents(directory).allSatisfy { !$0.contains(".csvui-") })

    #expect(throws: CSVFileWriteError.destinationExists(destination)) {
      try CSVFileWriter().write(
        CSVFileWriteRequest(
          destination: destination,
          bytes: Data("replacement".utf8),
          expectedBytes: nil,
          expectedIdentity: nil,
          overwrite: false
        )
      )
    }
    #expect(try Data(contentsOf: destination) == bytes)
  }

  @Test("in-place save compares identity and bytes before replacement")
  func conflictDetection() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("source.csv")
    try Data("a,b\n1,2\n".utf8).write(to: destination)
    let opened = try CSVSourceReader().read(fileURL: destination)
    let authority = try #require(opened.writeBackAuthority)
    try Data("a,b\nexternal,3\n".utf8).write(to: destination)

    #expect(throws: CSVFileWriteError.sourceChanged) {
      try CSVFileWriter().write(
        CSVFileWriteRequest(
          destination: destination,
          bytes: Data("a,b\nlocal,4\n".utf8),
          expectedBytes: opened.bytes,
          expectedIdentity: authority.identity,
          overwrite: true
        )
      )
    }
    #expect(try String(contentsOf: destination, encoding: .utf8).contains("external"))
  }

  @Test("symlink destinations never acquire write-back authority")
  func symlinkSafety() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("target.csv")
    let link = directory.appendingPathComponent("link.csv")
    try Data("a\n1\n".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let source = try CSVSourceReader().read(fileURL: link)
    #expect(source.writeBackAuthority == nil)
  }

  @Test("file-backed load attribution includes the measured source read")
  func sourceReadAttribution() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("measured.csv")
    try Data(("value\n" + String(repeating: "x\n", count: 100_000)).utf8).write(to: file)

    let source = try CSVSourceReader().read(fileURL: file, metricsEnabled: true)
    let result = try CSVDocument.load(
      source: source,
      delimiter: .comma,
      hasHeaders: true,
      metricsEnabled: true
    )

    #expect(result.metrics?.sourceReadNanoseconds ?? 0 > 0)
    #expect(result.metrics?.validationAndIndexingNanoseconds ?? 0 > 0)
  }

  @Test("disabled metrics stay out of source identity and load results")
  func disabledMetricsAreOutOfBand() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("unmeasured.csv")
    try Data("value\nx\n".utf8).write(to: file)

    var first = try CSVSourceReader().read(
      fileURL: file,
      metricsEnabled: false
    )
    var second = first
    first.sourceReadNanoseconds = 1
    second.sourceReadNanoseconds = 9_999
    #expect(first == second)

    let unmeasured = try CSVSourceReader().read(
      fileURL: file,
      metricsEnabled: false
    )
    #expect(unmeasured.sourceReadNanoseconds == nil)
    let result = try CSVDocument.load(
      source: unmeasured,
      delimiter: .comma,
      hasHeaders: true,
      metricsEnabled: false
    )
    #expect(result.metrics == nil)
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("csvui-lifecycle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
  }

  private func directoryContents(_ url: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: url.path)
  }
}

@MainActor
@Suite("CSV model lifecycle", .serialized)
struct CSVModelLifecycleTests {
  @Test("plain Save acknowledges exactly the captured revision")
  func saveSnapshotWithNewerEdit() async throws {
    let fixture = try makeFile(rowBytes: 2_000_000)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let model = try makeModel(file: fixture.file)
    model.send(.beginEditCell)
    model.send(.updateEditor("saved-snapshot"))
    model.send(.commitEditor)
    let savedRevision = model.state.currentRevision
    model.send(.save)
    model.send(.moveColumns(1))
    model.send(.beginEditCell)
    model.send(.updateEditor("newer-edit"))
    model.send(.commitEditor)
    await model.waitForIdle()

    #expect(model.state.cleanRevision == savedRevision)
    #expect(model.state.isDirty)
    let disk = try String(contentsOf: fixture.file, encoding: .utf8)
    #expect(disk.contains("saved-snapshot"))
    #expect(!disk.contains("newer-edit"))
    await model.shutdown()
  }

  @Test("no-op Save does not touch the source")
  func noOpSave() async throws {
    let fixture = try makeFile()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let model = try makeModel(file: fixture.file)
    let before = try CSVSourceReader().read(fileURL: fixture.file)
    model.send(.save)
    await model.waitForIdle()
    let after = try CSVSourceReader().read(fileURL: fixture.file)
    #expect(after.identity == before.identity)
    #expect(model.state.diagnostic == nil)
    await model.shutdown()
  }

  @Test("clean reload commits valid bytes and retains last-good data on failure")
  func reloadLifecycle() async throws {
    let fixture = try makeFile()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let model = try makeModel(file: fixture.file)
    try Data("name,value\nexternal,9\n".utf8).write(to: fixture.file)
    model.send(.reload)
    await model.waitForIdle()
    #expect(model.value(row: RowID(sourceIndex: 0), column: ColumnID(0)) == "external")

    try Data("name,value\n\"unclosed".utf8).write(to: fixture.file)
    model.send(.reload)
    await model.waitForIdle()
    #expect(model.value(row: RowID(sourceIndex: 0), column: ColumnID(0)) == "external")
    #expect(model.state.diagnostic?.severity == .error)
    await model.shutdown()
  }

  @Test("dirty reload requires explicit discard")
  func dirtyReloadGuard() async throws {
    let fixture = try makeFile()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let model = try makeModel(file: fixture.file)
    model.send(.beginEditCell)
    model.send(.updateEditor("local"))
    model.send(.commitEditor)
    try Data("name,value\nexternal,9\n".utf8).write(to: fixture.file)
    model.send(.reload)
    #expect(model.state.mode == .confirmation(.dirtyReload))
    #expect(model.value(row: RowID(sourceIndex: 0), column: ColumnID(0)) == "local")
    model.send(.confirmDiscard)
    await model.waitForIdle()
    #expect(model.value(row: RowID(sourceIndex: 0), column: ColumnID(0)) == "external")
    #expect(!model.state.isDirty)
    await model.shutdown()
  }

  private func makeModel(file: URL) throws -> CSVModel {
    let source = try CSVSourceReader().read(fileURL: file)
    return CSVModel(
      document: try CSVDocument.parse(source: source, delimiter: .comma, hasHeaders: true),
      configuration: CSVModelConfiguration(
        watchesDocument: false,
        workingDirectory: file.deletingLastPathComponent()
      )
    )
  }

  private func makeFile(rowBytes: Int = 0) throws -> (directory: URL, file: URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("csvui-model-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("source.csv")
    let padding = String(repeating: "x", count: rowBytes)
    try Data("name,value\noriginal,1\(padding)\n".utf8).write(to: file)
    return (directory, file)
  }
}

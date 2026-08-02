import Foundation
import Testing

@testable import CSVUI

@Suite("CSV file lifecycle", .serialized)
struct CSVFileLifecycleTests {
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

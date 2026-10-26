import Foundation
import Testing

@testable import CSVUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Campaign two E1 pass 2: csvui round-trip, Save As and source contracts
/// (e1s184–e1s194). Round-trip cases reparse the serializer's bytes with the
/// app's own indexer; file cases use throwaway directories.
@Suite("Campaign E1 pass 2 CSV save contracts", .serialized)
struct AdversarialSetACSVSaveTests {
  @Test(arguments: Array(184...194))
  func save(id: Int) throws {
    switch id {
    case 184...188, 194: try e1RoundTrip(id)
    case 189...191: try e1SaveAs(id)
    default: try e1NonRegularSource(id)
    }
  }
}

// MARK: - round trips (e1s184–e1s188, e1s194)

private func e1RoundTrip(_ id: Int) throws {
  let source =
    switch id {
    case 184, 185: "a\nb"
    case 186: "a\nb\nc"
    default: "a,b\n1,2"
    }
  let document = try e1Parse(Data(source.utf8))
  var journal = CSVEditJournal(document: document)
  switch id {
  case 184, 186: journal.replace(row: RowID(sourceIndex: 0), column: ColumnID(0), with: "")
  case 185: journal.insertRow(RowID(insertedID: 1), at: journal.rowOrder.count)
  case 187: journal.replace(row: RowID(sourceIndex: 0), column: ColumnID(0), with: "a\u{0}b")
  case 188: journal.renameHeader(ColumnID(0), to: "\u{FEFF}x")
  default: journal.replace(row: RowID(sourceIndex: 0), column: ColumnID(1), with: "x\ry")
  }
  let expectedRows = journal.rowOrder.count
  if id == 187 {
    // Refusing to serialize satisfies the contract as well as a reparse does.
    guard let output = try? CSVSerializer().serialize(document: document, journal: journal) else {
      return
    }
    // NUL is refused on read (CSVRecordIndex.swift:293-302), so a save must not write it
    // (STUI-1347, promoted by repair wave 4).
    let reopened = try e1Parse(output)
    #expect(try reopened.decodeSourceRow(RowID(sourceIndex: 0))?.fields.first?.value == "a\u{0}b")
    return
  }
  let output = try CSVSerializer().serialize(document: document, journal: journal)
  let reopened = try e1Parse(output)
  switch id {
  case 184, 185:
    // RFC 4180 (a quoted empty field) and the round-trip arity contract
    // (AdversarialSetACSVTests.swift:131-132); STUI-1347, promoted by repair wave 4.
    #expect(reopened.dataRecordCount == expectedRows)
  case 188:
    // Edited values round-trip (CSVSerializer.swift:14); STUI-1347, promoted by repair wave 4.
    #expect(reopened.header?.fields.first?.value == "\u{FEFF}x")
  case 194:
    #expect(output == Data("a,b\n1,\"x\ry\"".utf8))
    #expect(
      try reopened.decodeSourceRow(RowID(sourceIndex: 0))?.fields.map(\.value) == ["1", "x\ry"])
  default:
    #expect(reopened.dataRecordCount == expectedRows)
    #expect(try reopened.decodeSourceRow(RowID(sourceIndex: 0))?.fields.map(\.value) == [""])
  }
}

// MARK: - Save As destinations (e1s189–e1s191)

private func e1SaveAs(_ id: Int) throws {
  try e1WithDirectory { directory in
    let manager = FileManager.default
    let destination = directory.appendingPathComponent("out.csv")
    switch id {
    case 189:
      try manager.createSymbolicLink(atPath: destination.path, withDestinationPath: "missing.csv")
    case 190:
      try Data("old\n".utf8).write(to: directory.appendingPathComponent("real.csv"))
      try manager.createSymbolicLink(atPath: destination.path, withDestinationPath: "real.csv")
    default:
      try Data("old\n".utf8).write(to: destination)
      try manager.linkItem(
        atPath: destination.path, toPath: directory.appendingPathComponent("twin.csv").path)
    }
    let request = CSVFileWriteRequest(
      destination: destination, bytes: Data("new\n".utf8), expectedBytes: nil,
      expectedIdentity: nil, overwrite: true)
    let refusal = CSVFileWriteError.unsafeDestination(request.destination)
    // Only a direct, singly linked regular file is replaced (CSVFileWriter.swift:23-24);
    // e1s189 is STUI-1347, promoted by repair wave 4.
    #expect(throws: refusal) { _ = try CSVFileWriter().write(request) }
    if id == 189 {
      #expect(!manager.fileExists(atPath: directory.appendingPathComponent("missing.csv").path))
      #expect(try manager.destinationOfSymbolicLink(atPath: destination.path) == "missing.csv")
    }
  }
}

// MARK: - non-regular sources (e1s192, e1s193)

private func e1NonRegularSource(_ id: Int) throws {
  try e1WithDirectory { directory in
    let source = directory.appendingPathComponent(id == 192 ? "pipe.csv" : "folder.csv")
    var writer: Int32 = -1
    if id == 192 {
      let made = source.path.withCString { unsafe mkfifo($0, mode_t(0o600)) }
      try #require(made == 0)
      // Hold a writer so the reader's blocking open returns immediately.
      writer = source.path.withCString { unsafe open($0, O_RDWR | O_NONBLOCK) }
      try #require(writer >= 0)
    } else {
      try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
    }
    defer { if writer >= 0 { _ = close(writer) } }
    do {
      _ = try CSVSourceReader().read(fileURL: source)
      Issue.record("a non-regular source was read")
    } catch CSVSourceReadError.notRegularFile {
    } catch {
      Issue.record("expected notRegularFile, got \(error)")
    }
  }
}

// MARK: - fixtures

private func e1Parse(_ bytes: Data) throws -> CSVDocument {
  try CSVDocument.parse(
    source: CSVSourceSnapshot(origin: .standardInput, displayName: "E1 fixture", bytes: bytes),
    delimiter: .comma, hasHeaders: true)
}

private func e1WithDirectory(_ body: (URL) throws -> Void) throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("e1-csv-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: directory) }
  try body(directory)
}

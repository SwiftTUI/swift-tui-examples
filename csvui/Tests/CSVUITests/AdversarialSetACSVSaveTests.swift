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
    e1Known(
      "NEW-33: csvui saves a cell value containing NUL into a file it then refuses to reopen; CSVSerializer writes the NUL byte verbatim while CSVRecordIndexer rejects NUL; contract: CSVRecordIndex.swift:295-301 (NUL unsupported), pass 1 round-trip arity"
    ) {
      let reopened = try e1Parse(output)
      #expect(try reopened.decodeSourceRow(RowID(sourceIndex: 0))?.fields.first?.value == "a\u{0}b")
    }
    return
  }
  let output = try CSVSerializer().serialize(document: document, journal: journal)
  let reopened = try e1Parse(output)
  switch id {
  case 184, 185:
    e1Known(
      "NEW-32: an empty last row of a single-column CSV without a final newline vanishes on reopen; the serializer writes the empty field as zero bytes after the last line ending, which the indexer reads as end of input; contract: RFC 4180 rule 7 (quoted empty field), pass 1 round-trip arity (AdversarialSetACSVTests.swift:131-132)"
    ) {
      #expect(reopened.dataRecordCount == expectedRows)
    }
  case 188:
    e1Known(
      "NEW-34: a header renamed to start with U+FEFF loses that character on reopen when the file had no BOM; the unquoted field's leading EF BB BF is reread as a byte order mark; contract: edited values round-trip (CSVSerializer.swift:14, RFC 4180)"
    ) {
      #expect(reopened.header?.fields.first?.value == "\u{FEFF}x")
    }
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
    if id == 189 {
      e1Known(
        "NEW-35: an overwriting Save As replaces a dangling symlink with a regular file; the destination safety check runs only when FileManager.fileExists, which follows the link, is true; contract: CSVFileWriter.swift:23-24 and :88-97 (direct, singly linked regular files only)"
      ) {
        #expect(throws: refusal) { _ = try CSVFileWriter().write(request) }
      }
      #expect(!manager.fileExists(atPath: directory.appendingPathComponent("missing.csv").path))
    } else {
      #expect(throws: refusal) { _ = try CSVFileWriter().write(request) }
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

private func e1Known(_ comment: Comment, _ body: () throws -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_E1_UNMARKED"] == "1" {
    do { try body() } catch { Issue.record(error, comment) }
  } else {
    withKnownIssue(comment) { try body() }
  }
}

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

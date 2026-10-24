import Foundation
import Testing

@testable import CSVUI

@Suite("Campaign E1 CSV contracts", .serialized)
struct AdversarialSetACSVTests {
  @Test(arguments: Array(1...30))
  func csv(id: Int) throws {
    if id <= 16 || id == 21 {
      let source: String
      let expected: [[String]]
      switch id {
      case 1:
        source = ""
        expected = []
      case 2:
        source = "\u{FEFF}"
        expected = []
      case 3:
        source = "a,b"
        expected = [["a", "b"]]
      case 4:
        source = "a,b\r\n"
        expected = [["a", "b"]]
      case 5:
        source = "\"a,b\",c"
        expected = [["a,b", "c"]]
      case 6:
        source = "\"a\r\nb\",c"
        expected = [["a\r\nb", "c"]]
      case 7:
        source = "\"a\"\"b\",c"
        expected = [["a\"b", "c"]]
      case 8:
        source = "\"\",x"
        expected = [["", "x"]]
      case 9:
        source = "a,"
        expected = [["a", ""]]
      case 10:
        source = ",a"
        expected = [["", "a"]]
      case 11:
        source = " a , b "
        expected = [[" a ", " b "]]
      case 12:
        source = "\u{FEFF}a,b"
        expected = [["a", "b"]]
      case 13:
        source = "界,😀,e\u{301}"
        expected = [["界", "😀", "e\u{301}"]]
      case 14:
        source = "a\r\nb\nc\r"
        expected = [["a"], ["b"], ["c"]]
      case 15:
        source = "a,b\nc\nd,e,f"
        expected = [["a", "b"], ["c"], ["d", "e", "f"]]
      case 16:
        source = "x\"y,z"
        expected = [["x\"y", "z"]]
      default:
        source = "\"a\nb\",c\nd,e"
        expected = [["a\nb", "c"], ["d", "e"]]
      }
      let data = Data(source.utf8)
      let index = try CSVRecordIndexer().index(data, delimiter: .comma)
      let rows = try index.records.map {
        try CSVRowDecoder().decode($0, from: data, delimiter: .comma)
      }
      #expect(rows.map { $0.fields.map(\.value) } == expected)
      #expect(index.records.map(\.fieldCount) == expected.map(\.count))
      if id == 2 || id == 12 { #expect(index.startsAfterUTF8BOM) }
      if id == 3 { #expect(!index.hasFinalNewline) }
      if id == 4 { #expect(index.hasFinalNewline && index.dominantLineEnding == .crlf) }
      if id == 8 { #expect(rows[0].fields[0].wasQuoted && rows[0].fields[0].rawLexeme == "\"\"") }
      if id == 14 { #expect(index.lineEndingCounts == [.crlf: 1, .lf: 1, .cr: 1]) }
      if id == 21 { #expect(index.records[1].physicalStartLine == 3) }
      return
    }
    if id <= 20 {
      let data: Data
      switch id {
      case 17: data = Data("\"open".utf8)
      case 18: data = Data("\"x\"z,y".utf8)
      case 19: data = Data([0x61, 0, 0x62])
      default: data = Data([0x61, 0xE2, 0x82])
      }
      #expect(throws: CSVFormatError.self) {
        _ = try CSVRecordIndexer().index(data, delimiter: .comma)
      }
      return
    }
    let source =
      id == 22
      ? "\u{FEFF}a,b\r\n\"x,y\",z\nlast,row\r"
      : id == 26 || id == 27
        ? "a,b\nshort\nlong,row\n" : id == 29 ? "a,b\nfirst,row\r\nlast,row\n" : "a,b\nx,\"y,z\"\n"
    let document = try e1CSVDocument(Data(source.utf8), headers: true)
    var journal = CSVEditJournal(document: document)
    if id == 22 {
      #expect(
        try CSVSerializer().serialize(document: document, journal: journal) == Data(source.utf8))
      return
    }
    let row = RowID(sourceIndex: id == 26 ? 1 : 0)
    switch id {
    case 23: journal.replace(row: row, column: ColumnID(0), with: "a,b")
    case 24: journal.replace(row: row, column: ColumnID(0), with: "a\"b")
    case 25: journal.replace(row: row, column: ColumnID(0), with: "a\nb")
    case 26: journal.replace(row: row, column: ColumnID(0), with: "changed")
    case 27: journal.replace(row: row, column: ColumnID(1), with: "filled")
    case 28: journal.renameHeader(ColumnID(0), to: "new,name")
    case 29: journal.rowOrder.reverse()
    case 30: journal.columnOrder.reverse()
    default: Issue.record("unknown E1 CSV scenario")
    }
    let output = try CSVSerializer().serialize(document: document, journal: journal)
    let expected: String
    switch id {
    case 23: expected = "a,b\n\"a,b\",\"y,z\"\n"
    case 24: expected = "a,b\n\"a\"\"b\",\"y,z\"\n"
    case 25: expected = "a,b\n\"a\nb\",\"y,z\"\n"
    case 26: expected = "a,b\nshort\nchanged,row\n"
    case 27: expected = "a,b\nshort,filled\nlong,row\n"
    case 28: expected = "\"new,name\",b\nx,\"y,z\"\n"
    case 29: expected = "a,b\nlast,row\nfirst,row\r\n"
    default: expected = "b,a\n\"y,z\",x\n"
    }
    #expect(output == Data(expected.utf8))
    let parsed = try e1CSVDocument(output, headers: true)
    #expect(parsed.dataRecordCount == document.dataRecordCount)
  }
}

private func e1CSVDocument(_ bytes: Data, headers: Bool) throws -> CSVDocument {
  try CSVDocument.parse(
    source: CSVSourceSnapshot(origin: .standardInput, displayName: "E1 fixture", bytes: bytes),
    delimiter: .comma, hasHeaders: headers)
}

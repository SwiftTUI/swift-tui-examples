import Foundation
import Testing

@testable import CSVUI

struct CSVSortKeyTests {
  @Test("numeric prefixes stay text and natural suffixes determine ordering")
  func numericPrefixes() {
    for (earlier, later) in [
      ("2026-09-01", "2026-09-02"), ("2a", "2z"), ("1.2.txt", "1.10.txt"),
      ("file2", "file02"), ("file9", "file10"),
    ] {
      #expect(CSVSortKey(earlier).number == nil)
      #expect(CSVSortKey(earlier).compare(to: CSVSortKey(later)) == .orderedAscending)
    }
    #expect(CSVSortKey("-1.25e2").number == -125)
    #expect(CSVSortKey(".5").number == Decimal(string: "0.5"))
    #expect(CSVSortKey("1e").number == nil)
  }

  @Test("mixed signed numbers and text define a transitive ordering")
  func transitive() {
    let keys = ["-2", "-1", "-1x", "2", "10", "2a", "2z", "1.10.txt", "", "é2"].map(CSVSortKey.init)
    for a in keys {
      #expect(a.compare(to: a) == .orderedSame)
      for b in keys where a.compare(to: b) == .orderedAscending {
        #expect(b.compare(to: a) == .orderedDescending)
        for c in keys where b.compare(to: c) == .orderedAscending {
          #expect(a.compare(to: c) == .orderedAscending)
        }
      }
    }
  }

  @Test("keys borrow UTF-8 text and keep scalar order for non-ASCII values")
  func utf8Keys() {
    let key = CSVSortKey("naïve 10")
    #expect(key.storageBytes == "naïve 10".utf8.count)
    #expect(key.number == nil)
    #expect(CSVSortKey("z").compare(to: CSVSortKey("é")) == .orderedAscending)
    #expect(CSVSortKey("é").compare(to: CSVSortKey("é1")) == .orderedAscending)
    #expect(CSVSortKey("é2").compare(to: CSVSortKey("é10")) == .orderedAscending)
    #expect(CSVSortKey("1e400").compare(to: CSVSortKey("1e400")) == .orderedSame)
  }

  @Test("the sort budget admits every column the 0.11.1 string workspace admitted")
  func sortBudgetParity() {
    let previousBudget = 64 * 1_024 * 1_024
    let previousRowOverhead = 32
    for textBytes in [0, 1, 8, 16, 64, 1_024, 16 * 1_024] {
      let previousRows = previousBudget / (textBytes + previousRowOverhead)
      let rows =
        CSVProjectionEngine.maximumSortWorkspaceBytes
        / (textBytes + CSVProjectionEngine.sortRowOverheadBytes)
      #expect(rows >= previousRows, "\(textBytes)-byte keys")
    }
  }

  @Test("sort keeps numeric ties stable and empty cells last in both directions")
  func stableRows() async throws {
    let document = try CSVDocument.parse(
      source: CSVSourceSnapshot(
        origin: .standardInput, displayName: "sort.csv",
        bytes: Data("value\n2\n02\n10\n\"\"\n2z\n2a\n".utf8)
      ), delimiter: .comma, hasHeaders: true
    )
    let journal = CSVEditJournal(document: document)
    let snapshot = CSVScanSnapshot(document: document, journal: journal)
    let ascending = try await CSVProjectionEngine().sort(
      snapshot: snapshot, rows: journal.rowOrder,
      spec: .init(column: ColumnID(0), direction: .ascending)
    )
    #expect(ascending.map(\.sourceIndex) == [0, 1, 2, 5, 4, 3])
    let descending = try await CSVProjectionEngine().sort(
      snapshot: snapshot, rows: journal.rowOrder,
      spec: .init(column: ColumnID(0), direction: .descending)
    )
    #expect(descending.map(\.sourceIndex) == [4, 5, 2, 0, 1, 3])
  }
}

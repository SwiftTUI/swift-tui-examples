import Foundation
import Testing

@testable import GIFEditorCore

@Suite("Recent documents")
struct RecentDocumentsTests {

  // MARK: - Ordering, de-duplication, cap

  @Test("Re-opening a document moves it to the front instead of adding a second entry")
  func insertMovesAnExistingEntryToTheFront() {
    var recents = RecentDocuments()
    recents.insert(URL(fileURLWithPath: "/art/first.halfcell"))
    recents.insert(URL(fileURLWithPath: "/art/second.halfcell"))
    recents.insert(URL(fileURLWithPath: "/art/third.halfcell"))
    #expect(
      recents.urls.map(\.lastPathComponent) == [
        "third.halfcell", "second.halfcell", "first.halfcell",
      ]
    )

    recents.insert(URL(fileURLWithPath: "/art/first.halfcell"))

    #expect(recents.count == 3, "re-opening must not grow the list")
    #expect(
      recents.urls.map(\.lastPathComponent) == [
        "first.halfcell", "third.halfcell", "second.halfcell",
      ]
    )
  }

  @Test("Equivalent spellings of the same path are one entry")
  func equivalentPathsDeduplicate() {
    var recents = RecentDocuments()
    recents.insert(URL(fileURLWithPath: "/art/sprites/nyan.halfcell"))
    recents.insert(URL(fileURLWithPath: "/art/sprites/../sprites/./nyan.halfcell"))

    #expect(recents.count == 1)
    #expect(recents.urls.first?.path == "/art/sprites/nyan.halfcell")
  }

  @Test("The list is capped and drops the oldest entry")
  func insertCapsTheList() {
    var recents = RecentDocuments(limit: 3)
    for index in 1...5 {
      recents.insert(URL(fileURLWithPath: "/art/\(index).halfcell"))
    }

    #expect(recents.count == 3)
    #expect(recents.urls.map(\.lastPathComponent) == ["5.halfcell", "4.halfcell", "3.halfcell"])
  }

  @Test("The initializer applies the cap to a list handed to it whole")
  func initializerCapsAndDeduplicates() {
    let recents = RecentDocuments(
      urls: [
        URL(fileURLWithPath: "/art/a.halfcell"),
        URL(fileURLWithPath: "/art/b.halfcell"),
        URL(fileURLWithPath: "/art/a.halfcell"),
        URL(fileURLWithPath: "/art/c.halfcell"),
        URL(fileURLWithPath: "/art/d.halfcell"),
      ],
      limit: 3
    )

    #expect(recents.urls.map(\.lastPathComponent) == ["a.halfcell", "b.halfcell", "c.halfcell"])
  }

  @Test("A zero limit keeps nothing rather than trapping")
  func zeroLimitKeepsNothing() {
    var recents = RecentDocuments(limit: 0)
    recents.insert(URL(fileURLWithPath: "/art/a.halfcell"))
    #expect(recents.isEmpty)
  }

  @Test("Removing forgets one document and leaves the rest in order")
  func removingDropsOneEntry() {
    var recents = RecentDocuments(
      urls: [
        URL(fileURLWithPath: "/art/a.halfcell"),
        URL(fileURLWithPath: "/art/b.halfcell"),
        URL(fileURLWithPath: "/art/c.halfcell"),
      ]
    )
    recents.remove(URL(fileURLWithPath: "/art/b.halfcell"))

    #expect(recents.urls.map(\.lastPathComponent) == ["a.halfcell", "c.halfcell"])
  }

  // MARK: - State file

  @Test("The list round-trips through its state file")
  func roundTripsThroughTheStateFile() throws {
    try withTemporaryDirectory { directory in
      let documents = try (1...3).map { index -> URL in
        let url = directory.appendingPathComponent("\(index).halfcell")
        try Data("not really a project".utf8).write(to: url)
        return url
      }
      let stateURL = directory.appendingPathComponent(RecentDocuments.defaultFileName)

      var written = RecentDocuments()
      for url in documents { written.insert(url) }
      try written.write(to: stateURL)

      let read = RecentDocuments.load(from: stateURL)
      #expect(read.urls == written.urls)
      #expect(read.urls.map(\.lastPathComponent) == ["3.halfcell", "2.halfcell", "1.halfcell"])
    }
  }

  @Test("Writing creates the state directory it was pointed at")
  func writeCreatesTheStateDirectory() throws {
    try withTemporaryDirectory { directory in
      let stateURL =
        directory
        .appendingPathComponent(".config")
        .appendingPathComponent("halfcell")
        .appendingPathComponent(RecentDocuments.defaultFileName)

      try RecentDocuments(urls: [URL(fileURLWithPath: "/art/a.halfcell")]).write(to: stateURL)

      #expect(FileManager.default.fileExists(atPath: stateURL.path))
      let read = RecentDocuments.load(from: stateURL, pruningMissingFiles: false)
      #expect(read.urls.map(\.path) == ["/art/a.halfcell"])
    }
  }

  @Test("The state file is inspectable: a version and a list of plain paths")
  func stateFileShapeIsPlainPaths() throws {
    try withTemporaryDirectory { directory in
      let stateURL = directory.appendingPathComponent(RecentDocuments.defaultFileName)
      try RecentDocuments(urls: [URL(fileURLWithPath: "/art/a.halfcell")]).write(to: stateURL)

      let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: stateURL))
      let envelope = try #require(object as? [String: Any])
      #expect(envelope["version"] as? Int == RecentDocuments.currentStateVersion)
      #expect(envelope["paths"] as? [String] == ["/art/a.halfcell"])
    }
  }

  @Test("A missing state file degrades to an empty list")
  func missingStateFileDegradesToEmpty() throws {
    try withTemporaryDirectory { directory in
      let stateURL = directory.appendingPathComponent("never-written.json")
      #expect(!FileManager.default.fileExists(atPath: stateURL.path))
      #expect(RecentDocuments.load(from: stateURL).isEmpty)
    }
  }

  @Test(
    "A corrupt state file degrades to an empty list",
    arguments: [
      "",
      "{",
      "{\"version\": 1, \"paths\": \"not-an-array\"}",
      "{\"paths\": [\"/art/a.halfcell\"]}",
      "\u{0}\u{1}\u{2}not json at all",
    ]
  )
  func corruptStateFileDegradesToEmpty(contents: String) throws {
    try withTemporaryDirectory { directory in
      let stateURL = directory.appendingPathComponent(RecentDocuments.defaultFileName)
      try Data(contents.utf8).write(to: stateURL)

      // The gate is "does not throw and does not trap"; an empty list is
      // the whole recovery story for a cosmetic file.
      #expect(RecentDocuments.load(from: stateURL).isEmpty)
    }
  }

  @Test("A state file from a future build degrades to an empty list")
  func futureStateVersionDegradesToEmpty() throws {
    try withTemporaryDirectory { directory in
      let stateURL = directory.appendingPathComponent(RecentDocuments.defaultFileName)
      let future = RecentDocuments.currentStateVersion + 1
      try Data("{\"version\": \(future), \"paths\": [\"/art/a.halfcell\"]}".utf8)
        .write(to: stateURL)

      #expect(RecentDocuments.load(from: stateURL).isEmpty)
    }
  }

  // MARK: - Pruning

  @Test("Loading prunes entries whose file is gone")
  func loadPrunesMissingFiles() throws {
    try withTemporaryDirectory { directory in
      let present = directory.appendingPathComponent("present.halfcell")
      let removed = directory.appendingPathComponent("removed.halfcell")
      try Data("x".utf8).write(to: present)
      try Data("x".utf8).write(to: removed)

      let stateURL = directory.appendingPathComponent(RecentDocuments.defaultFileName)
      try RecentDocuments(urls: [removed, present]).write(to: stateURL)
      try FileManager.default.removeItem(at: removed)

      let read = RecentDocuments.load(from: stateURL)
      #expect(read.urls.map(\.lastPathComponent) == ["present.halfcell"])

      // The prune is in-memory: nothing rewrote the file, so a caller
      // that only reads has not destroyed anything.
      let unpruned = RecentDocuments.load(from: stateURL, pruningMissingFiles: false)
      #expect(unpruned.count == 2)
    }
  }

  @Test("Loading applies the caller's limit, not the one the file was written with")
  func loadAppliesTheCallersLimit() throws {
    try withTemporaryDirectory { directory in
      let stateURL = directory.appendingPathComponent(RecentDocuments.defaultFileName)
      let urls = (1...6).map { URL(fileURLWithPath: "/art/\($0).halfcell") }
      try RecentDocuments(urls: urls, limit: 6).write(to: stateURL)

      let read = RecentDocuments.load(from: stateURL, limit: 2, pruningMissingFiles: false)
      #expect(read.limit == 2)
      #expect(read.urls.map(\.lastPathComponent) == ["1.halfcell", "2.halfcell"])
    }
  }
}

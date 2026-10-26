import Foundation
import Synchronization
import Testing

@testable import Sextant

@Suite("Persistent state")
struct StateStoreTests {
  @Test("help, recents, and bookmarks persist with bounds and deduplication")
  func mutations() async throws {
    let box = Mutex(SextantPersistentState())
    let repository = SextantStateRepository(
      client: PersistentStateClient(
        load: { box.withLock { $0 } },
        save: { value in box.withLock { $0 = value } }
      )
    )
    let one = URL(fileURLWithPath: "/one")
    let two = URL(fileURLWithPath: "/two")

    try await repository.markHelpSeen()
    try await repository.recordRecent(one)
    try await repository.recordRecent(two)
    try await repository.recordRecent(one)
    #expect(try await repository.toggleBookmark(one))
    #expect(!(try await repository.toggleBookmark(one)))

    let state = try await repository.load()
    #expect(state.hasSeenHelp)
    #expect(state.recents == ["/one", "/two"])
    #expect(state.bookmarks.isEmpty)
  }

  /// POSIX filenames are byte strings, so bookmarks and recents are keyed by
  /// the bytes of the path a URL reports, not by `String` equality, which is
  /// canonical equivalence. Darwin's file URLs decompose a path (so both
  /// spellings below are one path there); Linux keeps the bytes.
  @Test("bookmarks and recents keep byte-distinct paths apart")
  func pathIdentityIsByteExact() async throws {
    let box = Mutex(SextantPersistentState())
    let repository = SextantStateRepository(
      client: PersistentStateClient(
        load: { box.withLock { $0 } },
        save: { value in box.withLock { $0 = value } }
      )
    )
    let composed = URL(fileURLWithPath: "/b/\u{E9}")
    let decomposed = URL(fileURLWithPath: "/b/e\u{301}")
    let composedPath = Array(composed.standardizedFileURL.path.utf8)
    let decomposedPath = Array(decomposed.standardizedFileURL.path.utf8)
    let distinct = composedPath != decomposedPath

    #expect(try await repository.toggleBookmark(composed))
    #expect(try await repository.toggleBookmark(decomposed) == distinct)
    try await repository.recordRecent(composed)
    try await repository.recordRecent(decomposed)
    var state = try await repository.load()
    #expect(
      state.bookmarks.map { Array($0.utf8) }
        == (distinct ? [composedPath, decomposedPath] : []))
    #expect(
      state.recents.map { Array($0.utf8) }
        == (distinct ? [decomposedPath, composedPath] : [decomposedPath]))

    // Toggling one spelling again removes only that spelling.
    _ = try await repository.toggleBookmark(decomposed)
    state = try await repository.load()
    #expect(
      state.bookmarks.map { Array($0.utf8) } == (distinct ? [composedPath] : [decomposedPath]))
  }

  @Test("JSON client uses an atomic round-trip")
  func jsonRoundTrip() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("sextant-state-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.json")
    let repository = SextantStateRepository(
      client: .jsonFile(at: url)
    )

    try await repository.recordRecent(URL(fileURLWithPath: "/fixture"))
    #expect(FileManager.default.fileExists(atPath: url.path))
    let decoded = try JSONDecoder().decode(
      SextantPersistentState.self,
      from: Data(contentsOf: url)
    )
    #expect(decoded.recents == ["/fixture"])
  }
}

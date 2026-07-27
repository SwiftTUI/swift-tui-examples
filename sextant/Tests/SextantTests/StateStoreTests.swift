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

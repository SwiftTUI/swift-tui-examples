import Foundation
import Synchronization
import Testing

@testable import CSVUI

@Suite("CSV file watcher")
struct CSVFileWatcherTests {
  @Test("producer bursts keep only one pending change")
  func burstCoalescing() async throws {
    let box = Mutex<AsyncStream<Void>.Continuation?>(nil)
    let changes = csvFileChangeStream { continuation in box.withLock { $0 = continuation } }
    let continuation = try #require(box.withLock { $0 })
    var dropped = 0
    for _ in 0..<1_000 {
      if case .dropped = continuation.yield(()) { dropped += 1 }
    }
    continuation.finish()
    var iterator = changes.makeAsyncIterator()
    #expect(await iterator.next() != nil)
    #expect(await iterator.next() == nil)
    #expect(dropped == 999)
  }

  @Test("atomic replacements remain observable through one stream", .timeLimit(.minutes(1)))
  func atomicReplacement() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("csvui-watcher-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("source.csv")
    try Data("first".utf8).write(to: file)
    let changes = CSVFileWatcher().changes(to: file)
    let collector = Task {
      var iterator = changes.makeAsyncIterator()
      guard await iterator.next() != nil else { return false }
      return await iterator.next() != nil
    }
    try await Task.sleep(for: .milliseconds(50))
    try Data("second".utf8).write(to: file, options: .atomic)
    try await Task.sleep(for: .milliseconds(100))
    try Data("third".utf8).write(to: file, options: .atomic)

    let observed = await withTaskGroup(of: Bool.self) { group in
      group.addTask { await collector.value }
      group.addTask {
        try? await Task.sleep(for: .seconds(2))
        return false
      }
      let value = await group.next() ?? false
      group.cancelAll()
      return value
    }
    if !observed { collector.cancel() }
    #expect(observed)
  }
}

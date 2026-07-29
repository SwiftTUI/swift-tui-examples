import Foundation
import Synchronization
import Testing

@testable import Mrkdwn

#if canImport(Darwin)
  import Darwin
#endif

@Suite("platform file watcher")
struct FileWatcherTests {
  #if canImport(Darwin)
    @Test("Darwin watcher descriptors are close-on-exec")
    func watcherDescriptorIsCloseOnExec() throws {
      let descriptor = openDarwinWatchDirectory(
        FileManager.default.temporaryDirectory
      )
      #expect(descriptor >= 0)
      guard descriptor >= 0 else { return }
      defer { close(descriptor) }
      let flags = fcntl(descriptor, F_GETFD)
      #expect(flags >= 0)
      #expect(flags & FD_CLOEXEC != 0)
    }
  #endif

  @Test("a producer burst retains only the newest pending change")
  func burstCoalescing() async throws {
    let continuationBox = Mutex<AsyncStream<Void>.Continuation?>(nil)
    let changes = fileChangeStream { continuation in
      continuationBox.withLock { $0 = continuation }
    }
    let continuation = try #require(
      continuationBox.withLock { $0 }
    )

    var droppedEvents = 0
    for _ in 0..<10_000 {
      if case .dropped = continuation.yield(()) {
        droppedEvents += 1
      }
    }
    continuation.finish()

    var iterator = changes.makeAsyncIterator()
    #expect(await iterator.next() != nil)
    #expect(await iterator.next() == nil)
    #expect(droppedEvents == 9_999)
  }

  @Test(
    "atomic file replacement emits repeated events through one armed stream",
    .timeLimit(.minutes(1))
  )
  func atomicReplacement() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mrkdwn-watcher-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("document.md")
    try Data("# first".utf8).write(to: file)

    let changes = FileWatcher().changes(to: file)
    let collector = Task {
      var iterator = changes.makeAsyncIterator()
      guard await iterator.next() != nil else { return false }
      return await iterator.next() != nil
    }
    try await Task.sleep(for: .milliseconds(50))
    try Data("# second".utf8).write(to: file, options: .atomic)

    try await Task.sleep(for: .milliseconds(100))
    try Data("# third".utf8).write(to: file, options: .atomic)
    #expect(await receivesTwoEvents(from: collector))
  }

  private func receivesTwoEvents(from collector: Task<Bool, Never>) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        await collector.value
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(2))
        return false
      }
      let result = await group.next() ?? false
      group.cancelAll()
      if !result { collector.cancel() }
      return result
    }
  }
}

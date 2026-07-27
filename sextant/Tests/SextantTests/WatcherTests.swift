import Foundation
import Testing

@testable import Sextant

@Suite("Directory watcher")
struct WatcherTests {
  @Test("scripted watcher replaces subscriptions and closes its stream")
  func scriptedLifecycle() async throws {
    let watcher = ScriptedDirectoryWatcher()
    let first = URL(fileURLWithPath: "/one", isDirectory: true)
    let second = URL(fileURLWithPath: "/two", isDirectory: true)
    let stream = await watcher.events(for: [first, second])
    let consumer = Task<DirectoryWatchEvent?, Never> {
      for await event in stream {
        return event
      }
      return nil
    }

    await watcher.send([second])
    #expect(
      await consumer.value
        == DirectoryWatchEvent(changedDirectories: [second])
    )
    await watcher.shutdown()
    #expect(await watcher.isShutdown)
    #expect(await watcher.subscriptions == [[first, second]])
  }

  @Test("live watcher coalesces writes and closes descriptors")
  func liveCoalescingAndTeardown() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("sextant-watcher-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let watcher = LiveDirectoryWatcher()
    let stream = await watcher.events(for: [directory])
    #expect(await watcher.activeDescriptorCount() == 1)
    let eventTask = Task<DirectoryWatchEvent?, Never> {
      for await event in stream {
        return event
      }
      return nil
    }
    for index in 0..<3 {
      try Data("\(index)".utf8).write(
        to: directory.appendingPathComponent("\(index).txt")
      )
    }
    let event = try await withThrowingTaskGroup(
      of: DirectoryWatchEvent?.self
    ) { group in
      group.addTask { await eventTask.value }
      group.addTask {
        try await ContinuousClock().sleep(for: .seconds(3))
        throw Timeout()
      }
      let first = try await group.next()!
      group.cancelAll()
      return first
    }
    #expect(event?.changedDirectories == [directory])
    await watcher.shutdown()
    #expect(await watcher.activeDescriptorCount() == 0)
  }

  @Test("terminating a replaced stream cannot clear the new subscriber")
  func replacementKeepsNewSubscriber() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "sextant-watcher-replacement-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let watcher = LiveDirectoryWatcher()
    let oldStream = await watcher.events(for: [directory])
    let oldConsumer = Task {
      for await _ in oldStream {}
    }
    let currentStream = await watcher.events(for: [directory])
    for _ in 0..<10 {
      await Task.yield()
    }
    let currentConsumer = Task<DirectoryWatchEvent?, Never> {
      for await event in currentStream {
        return event
      }
      return nil
    }

    try Data("change".utf8).write(
      to: directory.appendingPathComponent("change.txt")
    )
    let event = try await withThrowingTaskGroup(
      of: DirectoryWatchEvent?.self
    ) { group in
      group.addTask { await currentConsumer.value }
      group.addTask {
        try await ContinuousClock().sleep(for: .seconds(3))
        throw Timeout()
      }
      let first = try await group.next()!
      group.cancelAll()
      return first
    }

    #expect(event?.changedDirectories == [directory])
    await watcher.shutdown()
    oldConsumer.cancel()
    _ = await oldConsumer.result
  }
}

private struct Timeout: Error {}

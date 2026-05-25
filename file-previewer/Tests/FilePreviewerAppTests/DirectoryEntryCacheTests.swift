@testable import FilePreviewerApp
import Foundation
import Testing

@MainActor
struct DirectoryEntryCacheTests {
  @Test("cache loads a directory once and returns the cached entries")
  func cacheLoadsDirectoryOnce() {
    let directory = URL(fileURLWithPath: "/tmp/project")
    var loadCount = 0
    let cache = DirectoryEntryCache(capacity: 8) { requested in
      loadCount += 1
      return [
        FileEntry(
          url: requested.appendingPathComponent("README.md"),
          isDirectory: false
        )
      ]
    }

    let first = cache.entries(in: directory)
    let second = cache.entries(in: directory)

    #expect(first == second)
    #expect(loadCount == 1)
  }

  @Test("retainOnly evicts directories that are no longer visible")
  func retainOnlyEvictsHiddenDirectories() {
    let root = URL(fileURLWithPath: "/tmp/root")
    let child = root.appendingPathComponent("child")
    let sibling = root.appendingPathComponent("sibling")
    var loaded: [URL] = []
    let cache = DirectoryEntryCache(capacity: 8) { requested in
      loaded.append(requested)
      return [
        FileEntry(
          url: requested.appendingPathComponent("file.swift"),
          isDirectory: false
        )
      ]
    }

    _ = cache.entries(in: root)
    _ = cache.entries(in: child)
    _ = cache.entries(in: sibling)
    cache.retainOnly([root, child])
    _ = cache.entries(in: root)
    _ = cache.entries(in: child)
    _ = cache.entries(in: sibling)

    #expect(loaded == [root, child, sibling, sibling])
  }

  @Test("capacity evicts the least recently used directory")
  func capacityEvictsLeastRecentlyUsedDirectory() {
    let one = URL(fileURLWithPath: "/tmp/one")
    let two = URL(fileURLWithPath: "/tmp/two")
    let three = URL(fileURLWithPath: "/tmp/three")
    var loaded: [URL] = []
    let cache = DirectoryEntryCache(capacity: 2) { requested in
      loaded.append(requested)
      return [
        FileEntry(
          url: requested.appendingPathComponent("file.swift"),
          isDirectory: false
        )
      ]
    }

    _ = cache.entries(in: one)
    _ = cache.entries(in: two)
    _ = cache.entries(in: one)
    _ = cache.entries(in: three)
    _ = cache.entries(in: two)

    #expect(loaded == [one, two, three, two])
  }
}

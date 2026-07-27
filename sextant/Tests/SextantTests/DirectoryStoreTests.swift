import Foundation
import Testing

@testable import Sextant

struct DirectoryStoreTests {
  @Test("cache keys include hidden and sort policy")
  func policyKeysRemainSeparate() async throws {
    let url = URL(fileURLWithPath: "/fixtures/policy", isDirectory: true)
    let client = InMemoryFileSystemClient()
    await client.setDirectory(
      [
        entry("visible", index: 1),
        entry(".hidden", index: 2, hidden: true),
      ],
      at: url
    )
    let store = DirectoryStore(client: client)
    let ordinary = storeRequest(1, url: url)
    let hidden = storeRequest(
      2,
      url: url,
      policy: DirectoryPolicy(showsHiddenFiles: true)
    )

    let ordinarySnapshot = try #require((await store.load(ordinary)).successValue)
    let hiddenSnapshot = try #require((await store.load(hidden)).successValue)
    _ = await store.load(ordinary)
    _ = await store.load(hidden)
    let reads = await client.recordedDirectoryRequests()

    #expect(ordinarySnapshot.items.map(\.name) == ["visible"])
    #expect(Set(hiddenSnapshot.items.map(\.name)) == ["visible", ".hidden"])
    #expect(reads.count == 2)
  }

  @Test("failures are returned and are never cached as empty snapshots")
  func failuresAreNotCachedAsEmpty() async {
    let url = URL(fileURLWithPath: "/fixtures/denied", isDirectory: true)
    let client = InMemoryFileSystemClient()
    await client.setDirectoryFailure(.permissionDenied(path: url.path), at: url)
    let store = DirectoryStore(client: client)
    let requested = storeRequest(1, url: url)

    let first = await store.load(requested)
    let second = await store.load(
      storeRequest(2, url: url)
    )
    let stats = await store.statistics()

    #expect(first == .failure(.permissionDenied(path: url.path)))
    #expect(second == .failure(.permissionDenied(path: url.path)))
    #expect(stats.cachedSnapshotCount == 0)
    #expect((await client.recordedDirectoryRequests()).count == 2)
  }

  @Test("LRU budgets evict unpinned snapshots before pinned snapshots")
  func lruAndPinning() async {
    let client = InMemoryFileSystemClient()
    let urls = (0..<4).map {
      URL(fileURLWithPath: "/fixtures/cache/\($0)", isDirectory: true)
    }
    for (index, url) in urls.enumerated() {
      await client.setDirectory(
        [
          entry("a", index: index * 2),
          entry("b", index: index * 2 + 1),
        ],
        at: url
      )
    }
    let store = DirectoryStore(
      client: client,
      budget: .init(maximumSnapshots: 2, maximumItems: 5)
    )
    let requests = urls.enumerated().map {
      storeRequest(UInt64($0.offset + 1), url: $0.element)
    }

    _ = await store.load(requests[0])
    _ = await store.load(requests[1])
    _ = await store.cachedSnapshot(for: requests[0])
    _ = await store.load(requests[2])

    #expect(await store.cachedSnapshot(for: requests[0]) != nil)
    #expect(await store.cachedSnapshot(for: requests[1]) == nil)
    #expect(await store.cachedSnapshot(for: requests[2]) != nil)

    await store.setPinnedRequests([requests[0]])
    _ = await store.load(requests[3])

    #expect(await store.cachedSnapshot(for: requests[0]) != nil)
    #expect(await store.cachedSnapshot(for: requests[2]) == nil)
    #expect(await store.cachedSnapshot(for: requests[3]) != nil)
    #expect(await store.statistics().cachedItemCount == 4)
  }

  @Test("snapshots larger than the item budget are served but not cached")
  func oversizedSnapshotsAreNotCached() async throws {
    let url = URL(fileURLWithPath: "/fixtures/oversized", isDirectory: true)
    let client = InMemoryFileSystemClient()
    await client.setDirectory((0..<6).map { entry("item-\($0)", index: $0) }, at: url)
    let store = DirectoryStore(
      client: client,
      budget: .init(maximumSnapshots: 8, maximumItems: 5)
    )
    let requested = storeRequest(1, url: url)

    let snapshot = try #require((await store.load(requested)).successValue)

    #expect(snapshot.items.count == 6)
    #expect(await store.cachedSnapshot(for: requested) == nil)
    #expect(await store.statistics().cachedItemCount == 0)
  }

  @Test("the default store retains 1, 1,000, and 10,000-entry snapshots")
  func fixtureSizes() async throws {
    let counts = [1, 1_000, 10_000]
    let client = InMemoryFileSystemClient()
    let store = DirectoryStore(client: client)

    for (fixtureIndex, count) in counts.enumerated() {
      let url = URL(
        fileURLWithPath: "/fixtures/size-\(count)",
        isDirectory: true
      )
      await client.setDirectory(
        (0..<count).map {
          entry(
            "item-\($0)",
            index: fixtureIndex * 20_000 + $0
          )
        },
        at: url
      )
      let snapshot = try #require(
        (await store.load(storeRequest(UInt64(fixtureIndex + 1), url: url))).successValue
      )
      #expect(snapshot.items.count == count)
    }

    let stats = await store.statistics()
    #expect(stats.cachedSnapshotCount == 3)
    #expect(stats.cachedItemCount == 11_001)
  }

  @Test("no more than four directory reads run concurrently")
  func readConcurrencyIsBounded() async {
    let client = MeasuringFileSystemClient(delay: .milliseconds(40))
    let store = DirectoryStore(client: client)

    await withTaskGroup(of: Void.self) { group in
      for index in 0..<12 {
        group.addTask {
          let url = URL(
            fileURLWithPath: "/fixtures/concurrent-\(index)",
            isDirectory: true
          )
          _ = await store.load(storeRequest(UInt64(index + 1), url: url))
        }
      }
    }

    #expect(await client.maximumActiveReads == 4)
    #expect(await store.statistics().inFlightReadCount == 0)
  }

  @Test("a newer request supersedes and cancels the older policy-equivalent read")
  func requestSupersession() async {
    let url = URL(fileURLWithPath: "/fixtures/supersession", isDirectory: true)
    let client = MeasuringFileSystemClient(delay: .milliseconds(200))
    let store = DirectoryStore(client: client)
    let firstRequest = storeRequest(1, url: url)
    let secondRequest = storeRequest(2, url: url)

    let first = Task {
      await store.load(firstRequest)
    }
    await client.waitForStartedReads(1)
    let second = Task {
      await store.load(secondRequest)
    }

    #expect(await first.value == .failure(.superseded(firstRequest.id)))
    let secondSnapshot = await second.value.successValue
    #expect(secondSnapshot?.request.id == secondRequest.id)
    #expect(await client.cancelledReads >= 1)
  }

  @Test("explicit invalidation removes every policy variant and forces reload")
  func invalidation() async {
    let url = URL(fileURLWithPath: "/fixtures/invalidate", isDirectory: true)
    let client = InMemoryFileSystemClient()
    await client.setDirectory([entry("item", index: 1)], at: url)
    let store = DirectoryStore(client: client)
    let ordinary = storeRequest(1, url: url)
    let hidden = storeRequest(
      2,
      url: url,
      policy: DirectoryPolicy(showsHiddenFiles: true)
    )
    _ = await store.load(ordinary)
    _ = await store.load(hidden)

    await store.invalidate(ordinary.directoryID)
    _ = await store.load(storeRequest(3, url: url))
    _ = await store.load(
      storeRequest(
        4,
        url: url,
        policy: DirectoryPolicy(showsHiddenFiles: true)
      )
    )

    #expect((await client.recordedDirectoryRequests()).count == 4)
  }
}

private actor MeasuringFileSystemClient: FileSystemClient {
  let delay: Duration
  private(set) var activeReads = 0
  private(set) var maximumActiveReads = 0
  private(set) var startedReads = 0
  private(set) var cancelledReads = 0

  init(delay: Duration) {
    self.delay = delay
  }

  func readDirectory(
    _ request: DirectoryRequest
  ) async -> Result<DirectorySnapshot, FileSystemFailure> {
    activeReads += 1
    startedReads += 1
    maximumActiveReads = max(maximumActiveReads, activeReads)
    do {
      try await Task.sleep(for: delay)
    } catch {
      cancelledReads += 1
      activeReads -= 1
      return .failure(.cancelled)
    }
    activeReads -= 1
    return .success(DirectorySnapshot(request: request, items: []))
  }

  func metadata(
    at url: URL,
    followingSymbolicLinks: Bool
  ) async -> Result<ItemMetadata, FileSystemFailure> {
    .failure(.notFound(path: url.path))
  }

  func readPrefix(
    at url: URL,
    maximumBytes: Int
  ) async -> Result<FilePrefix, FileSystemFailure> {
    .failure(.notFound(path: url.path))
  }

  func waitForStartedReads(_ count: Int) async {
    while startedReads < count {
      await Task.yield()
    }
  }
}

private func entry(
  _ name: String,
  index: Int,
  hidden: Bool = false
) -> InMemoryFileSystemEntry {
  InMemoryFileSystemEntry(
    name: name,
    kind: .file,
    identity: .inode(device: 1, inode: UInt64(index + 1)),
    byteCount: UInt64(index),
    isHidden: hidden
  )
}

private func storeRequest(
  _ id: UInt64,
  url: URL,
  policy: DirectoryPolicy = DirectoryPolicy()
) -> DirectoryRequest {
  DirectoryRequest(
    id: DirectoryRequestID(rawValue: id),
    directoryID: DirectoryID(identity: .pathFallback(for: url)),
    url: url,
    policy: policy
  )
}

extension Result {
  fileprivate var successValue: Success? {
    guard case .success(let value) = self else {
      return nil
    }
    return value
  }
}

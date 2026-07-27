import Foundation
import Testing

@testable import Sextant

@Suite("Filename search")
struct SearchTests {
  @Test("recursive search streams bounded matches and avoids a symlink cycle")
  func recursiveBoundedSearch() async {
    let fileSystem = InMemoryFileSystemClient()
    let root = URL(fileURLWithPath: "/root", isDirectory: true)
    let child = root.appendingPathComponent("child", isDirectory: true)
    let rootID = DirectoryID(identity: .path(root.path))
    let childID = DirectoryID(identity: .path(child.path))
    await fileSystem.setDirectory(
      [
        InMemoryFileSystemEntry(
          name: "needle-one.txt",
          kind: .file,
          identity: .path("/root/needle-one.txt")
        ),
        InMemoryFileSystemEntry(
          name: "child",
          kind: .directory,
          identity: childID.identity,
          targetDirectoryID: childID
        ),
      ],
      at: root
    )
    await fileSystem.setDirectory(
      [
        InMemoryFileSystemEntry(
          name: "needle-two.txt",
          kind: .file,
          identity: .path("/root/child/needle-two.txt")
        ),
        InMemoryFileSystemEntry(
          name: "back",
          kind: .symbolicLinkToDirectory,
          identity: .path("/root/child/back"),
          targetDirectoryID: rootID
        ),
      ],
      at: child
    )
    let search = FilenameSearchCoordinator(
      fileSystem: fileSystem,
      budget: .init(batchSize: 1, maximumResults: 10)
    )

    var results: [FilenameSearchResult] = []
    for await event in await search.search(
      root: root,
      query: "needle",
      policy: DirectoryPolicy()
    ) {
      if case .batch(_, let batch) = event {
        results.append(contentsOf: batch)
      }
    }
    #expect(results.map(\.name) == ["needle-one.txt", "needle-two.txt"])
    #expect(await fileSystem.recordedDirectoryRequests().count == 2)
  }

  @Test("permission islands do not abort sibling results")
  func permissionIsland() async {
    let fileSystem = InMemoryFileSystemClient()
    let root = URL(fileURLWithPath: "/root", isDirectory: true)
    let denied = root.appendingPathComponent("denied", isDirectory: true)
    let deniedID = DirectoryID(identity: .path(denied.path))
    await fileSystem.setDirectory(
      [
        InMemoryFileSystemEntry(
          name: "match.txt",
          kind: .file,
          identity: .path("/root/match.txt")
        ),
        InMemoryFileSystemEntry(
          name: "denied",
          kind: .directory,
          identity: deniedID.identity,
          targetDirectoryID: deniedID
        ),
      ],
      at: root
    )
    await fileSystem.setDirectoryFailure(
      .permissionDenied(path: denied.path),
      at: denied
    )
    let search = FilenameSearchCoordinator(fileSystem: fileSystem)

    var names: [String] = []
    for await event in await search.search(
      root: root,
      query: "match",
      policy: DirectoryPolicy()
    ) {
      if case .batch(_, let batch) = event {
        names.append(contentsOf: batch.map(\.name))
      }
    }
    #expect(names == ["match.txt"])
  }

  @Test("recursive search applies ignore rules without overriding hidden policy")
  func ignoreAndHiddenPoliciesRemainIndependent() async {
    let fileSystem = InMemoryFileSystemClient()
    let root = URL(fileURLWithPath: "/root", isDirectory: true)
    let ignored = root.appendingPathComponent("ignored", isDirectory: true)
    let ignoredID = DirectoryID(identity: .path(ignored.path))
    await fileSystem.setDirectory(
      [
        InMemoryFileSystemEntry(
          name: ".hidden-needle.txt",
          kind: .file,
          identity: .path("/root/.hidden-needle.txt"),
          isHidden: true
        ),
        InMemoryFileSystemEntry(
          name: "visible-needle.txt",
          kind: .file,
          identity: .path("/root/visible-needle.txt")
        ),
        InMemoryFileSystemEntry(
          name: "ignored",
          kind: .directory,
          identity: ignoredID.identity,
          targetDirectoryID: ignoredID
        ),
      ],
      at: root
    )
    await fileSystem.setDirectory(
      [
        InMemoryFileSystemEntry(
          name: "nested-needle.txt",
          kind: .file,
          identity: .path("/root/ignored/nested-needle.txt")
        )
      ],
      at: ignored
    )
    let search = FilenameSearchCoordinator(fileSystem: fileSystem)
    let ignore = DirectoryIgnorePolicy(entryNames: ["ignored"])

    let visibleAndHidden = await resultNames(
      from: search,
      root: root,
      policy: DirectoryPolicy(
        showsHiddenFiles: true,
        recursiveSearchIgnore: ignore
      )
    )
    let visibleOnly = await resultNames(
      from: search,
      root: root,
      policy: DirectoryPolicy(
        showsHiddenFiles: false,
        recursiveSearchIgnore: ignore
      )
    )

    #expect(
      visibleAndHidden == [".hidden-needle.txt", "visible-needle.txt"]
    )
    #expect(visibleOnly == ["visible-needle.txt"])
    #expect(
      await fileSystem.recordedDirectoryRequests()
        .allSatisfy { $0.url.standardizedFileURL != ignored.standardizedFileURL }
    )
  }

  @Test("search roots use filesystem identity with adapter fallback")
  func rootIdentityLookup() async {
    let storage = InMemoryFileSystemClient()
    let root = URL(fileURLWithPath: "/root", isDirectory: true)
    let rootIdentity = FileSystemIdentity.inode(device: 4, inode: 8)
    await storage.setDirectory([], at: root)
    let fileSystem = IdentityProvidingFileSystemClient(
      storage: storage,
      root: root,
      rootIdentity: rootIdentity
    )
    let search = FilenameSearchCoordinator(fileSystem: fileSystem)

    for await _ in await search.search(
      root: root,
      query: "needle",
      policy: DirectoryPolicy()
    ) {}

    #expect(
      await storage.recordedDirectoryRequests().first?.directoryID
        == DirectoryID(identity: rootIdentity)
    )
  }

  @Test("a huge wide tree stops at the directory budget")
  func hugeWideTreeIsBounded() async {
    let fileSystem = WideTreeFileSystem(childCount: 5_000)
    let search = FilenameSearchCoordinator(
      fileSystem: fileSystem,
      budget: .init(
        batchSize: 10,
        maximumResults: 10,
        maximumDirectories: 257
      )
    )
    var finished: FilenameSearchEvent?

    for await event in await search.search(
      root: fileSystem.root,
      query: "not-present",
      policy: DirectoryPolicy()
    ) {
      if case .finished = event {
        finished = event
      }
    }

    #expect(await fileSystem.readCount == 257)
    #expect(
      finished
        == .finished(
          generation: FilenameSearchGeneration(rawValue: 1),
          retainedResultCount: 0,
          wasTruncated: true
        )
    )
  }

  private func resultNames(
    from search: FilenameSearchCoordinator,
    root: URL,
    policy: DirectoryPolicy
  ) async -> [String] {
    var names: [String] = []
    for await event in await search.search(
      root: root,
      query: "needle",
      policy: policy
    ) {
      if case .batch(_, let batch) = event {
        names.append(contentsOf: batch.map(\.name))
      }
    }
    return names
  }
}

private actor WideTreeFileSystem: FileSystemClient {
  nonisolated let root = URL(fileURLWithPath: "/wide", isDirectory: true)
  nonisolated let childCount: Int
  private(set) var readCount = 0

  init(childCount: Int) {
    self.childCount = childCount
  }

  nonisolated func identity(
    at url: URL,
    followingSymbolicLinks _: Bool
  ) -> Result<FileSystemIdentity, FileSystemFailure> {
    .success(.pathFallback(for: url))
  }

  func readDirectory(
    _ request: DirectoryRequest
  ) async -> Result<DirectorySnapshot, FileSystemFailure> {
    readCount += 1
    guard request.url.standardizedFileURL == root.standardizedFileURL else {
      return .success(DirectorySnapshot(request: request, items: []))
    }
    let items = (0..<childCount).map { index in
      let url = root.appendingPathComponent(
        "directory-\(index)",
        isDirectory: true
      )
      let identity = FileSystemIdentity.path(url.path)
      return BrowserItem(
        id: BrowserItemID(identity: identity),
        directoryID: request.directoryID,
        targetDirectoryID: DirectoryID(identity: identity),
        name: url.lastPathComponent,
        url: url,
        kind: .directory,
        listingMetadata: ItemMetadata(
          identity: identity,
          isReadable: true,
          isExecutable: true
        )
      )
    }
    return .success(DirectorySnapshot(request: request, items: items))
  }

  func metadata(
    at url: URL,
    followingSymbolicLinks _: Bool
  ) async -> Result<ItemMetadata, FileSystemFailure> {
    .failure(.notFound(path: url.path))
  }

  func readPrefix(
    at url: URL,
    maximumBytes _: Int
  ) async -> Result<FilePrefix, FileSystemFailure> {
    .failure(.notFound(path: url.path))
  }
}

private struct IdentityProvidingFileSystemClient: FileSystemClient {
  var storage: InMemoryFileSystemClient
  var root: URL
  var rootIdentity: FileSystemIdentity

  func identity(
    at url: URL,
    followingSymbolicLinks _: Bool
  ) -> Result<FileSystemIdentity, FileSystemFailure> {
    url.standardizedFileURL == root.standardizedFileURL
      ? .success(rootIdentity)
      : .success(.pathFallback(for: url))
  }

  func readDirectory(
    _ request: DirectoryRequest
  ) async -> Result<DirectorySnapshot, FileSystemFailure> {
    await storage.readDirectory(request)
  }

  func metadata(
    at url: URL,
    followingSymbolicLinks: Bool
  ) async -> Result<ItemMetadata, FileSystemFailure> {
    await storage.metadata(
      at: url,
      followingSymbolicLinks: followingSymbolicLinks
    )
  }

  func readPrefix(
    at url: URL,
    maximumBytes: Int
  ) async -> Result<FilePrefix, FileSystemFailure> {
    await storage.readPrefix(at: url, maximumBytes: maximumBytes)
  }
}

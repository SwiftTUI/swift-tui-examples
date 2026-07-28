import Foundation
import Testing

@testable import Sextant

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct FileSystemClientTests {
  @Test("in-memory directory failures stay typed instead of becoming empty snapshots")
  func inMemoryFailuresStayTyped() async {
    let client = InMemoryFileSystemClient()
    let deniedURL = URL(fileURLWithPath: "/fixtures/denied", isDirectory: true)
    let missingURL = URL(fileURLWithPath: "/fixtures/missing", isDirectory: true)
    await client.setDirectoryFailure(
      .permissionDenied(path: deniedURL.path),
      at: deniedURL
    )
    await client.setDirectoryFailure(
      .notFound(path: missingURL.path),
      at: missingURL
    )

    let denied = await client.readDirectory(request(1, url: deniedURL))
    let missing = await client.readDirectory(request(2, url: missingURL))

    #expect(denied == .failure(.permissionDenied(path: deniedURL.path)))
    #expect(missing == .failure(.notFound(path: missingURL.path)))
  }

  @Test("in-memory prefix reads are bounded and record the requested byte count")
  func inMemoryPrefixIsBounded() async throws {
    let client = InMemoryFileSystemClient()
    let url = URL(fileURLWithPath: "/fixtures/large.txt")
    let data = Data((0..<32).map(UInt8.init))
    await client.setFile(
      data,
      metadata: ItemMetadata(
        identity: .pathFallback(for: url),
        byteCount: UInt64(data.count),
        isReadable: true
      ),
      at: url
    )

    let result = await client.readPrefix(at: url, maximumBytes: 9)
    let prefix = try #require(result.successValue)
    let reads = await client.recordedPrefixReads()

    #expect(prefix.data == Data(data.prefix(9)))
    #expect(prefix.totalByteCount == 32)
    #expect(prefix.isTruncated)
    #expect(reads == [.init(url: url.standardizedFileURL, maximumBytes: 9)])
  }

  @Test("in-memory listings preserve every filesystem item kind")
  func inMemoryKindsRemainDistinct() async throws {
    let client = InMemoryFileSystemClient()
    let url = URL(fileURLWithPath: "/fixtures/kinds", isDirectory: true)
    let kinds: [BrowserItemKind] = [
      .file,
      .directory,
      .symbolicLinkToFile,
      .symbolicLinkToDirectory,
      .symbolicLinkToSpecial(.socket),
      .brokenSymbolicLink,
      .package,
      .special(.fifo),
      .special(.characterDevice),
      .special(.blockDevice),
    ]
    await client.setDirectory(
      kinds.enumerated().map { index, kind in
        InMemoryFileSystemEntry(
          name: "kind-\(index)",
          kind: kind,
          identity: .inode(device: 3, inode: UInt64(index + 1)),
          targetDirectoryID: kind.isDirectoryLike
            ? DirectoryID(identity: .inode(device: 3, inode: UInt64(index + 1)))
            : nil
        )
      },
      at: url
    )

    let snapshot = try #require(
      (await client.readDirectory(request(1, url: url))).successValue
    )

    #expect(Set(snapshot.items.map(\.kind)) == Set(kinds))
  }

  @Test("live adapter reports file, directory, links, package, and hidden entries")
  func liveAdapterClassifiesTemporaryDirectory() async throws {
    try await withTemporaryDirectory { root in
      let file = root.appendingPathComponent("-plain.txt")
      let unicode = root.appendingPathComponent("éclair\n界.txt")
      let directory = root.appendingPathComponent("child", isDirectory: true)
      let package = root.appendingPathComponent("Fixture.app", isDirectory: true)
      let hidden = root.appendingPathComponent(".hidden")
      let fileLink = root.appendingPathComponent("file-link")
      let directoryLink = root.appendingPathComponent("directory-link")
      let brokenLink = root.appendingPathComponent("broken-link")
      try Data("hello".utf8).write(to: file)
      try Data("unicode".utf8).write(to: unicode)
      try Data("hidden".utf8).write(to: hidden)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
      try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: file)
      try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: directory)
      try FileManager.default.createSymbolicLink(
        at: brokenLink,
        withDestinationURL: root.appendingPathComponent("absent")
      )

      let client = LocalFileSystemClient()
      let visibleResult = await client.readDirectory(request(1, url: root))
      let visible = try #require(visibleResult.successValue)
      let allResult = await client.readDirectory(
        request(
          2,
          url: root,
          policy: DirectoryPolicy(showsHiddenFiles: true)
        )
      )
      let all = try #require(allResult.successValue)

      #expect(visible.items.first { $0.name == "-plain.txt" }?.kind == .file)
      #expect(visible.items.first { $0.name == "child" }?.kind == .directory)
      #expect(visible.items.first { $0.name == "Fixture.app" }?.kind == .package)
      #expect(visible.items.first { $0.name == "file-link" }?.kind == .symbolicLinkToFile)
      #expect(
        visible.items.first { $0.name == "directory-link" }?.kind
          == .symbolicLinkToDirectory
      )
      #expect(
        visible.items.first { $0.name == "directory-link" }?.targetDirectoryID != nil
      )
      #expect(visible.items.first { $0.name == "broken-link" }?.kind == .brokenSymbolicLink)
      #expect(visible.items.contains { $0.name == "éclair\n界.txt" })
      #expect(!visible.items.contains { $0.name == ".hidden" })
      #expect(all.items.contains { $0.name == ".hidden" })
    }
  }

  /// The filesystem root is the one directory a user always reaches by holding
  /// the parent key, and on Darwin it is also the only one that lists a devfs
  /// mount — whose `dev_t` is negative. Reading it is the end-to-end guard on
  /// that widening; before the fix this trapped rather than failing.
  @Test("the live adapter lists the filesystem root, devfs mounts and all")
  func liveAdapterListsFilesystemRoot() async throws {
    let client = LocalFileSystemClient()
    let rootURL = URL(fileURLWithPath: "/", isDirectory: true)

    let result = await client.readDirectory(
      request(1, url: rootURL, policy: DirectoryPolicy(showsHiddenFiles: true))
    )
    let snapshot = try #require(result.successValue)
    #expect(!snapshot.items.isEmpty)

    // Every entry's identity has to be readable on its own too — that is the
    // path `climbAboveTrail` takes when it resolves the node it is inserting.
    for item in snapshot.items {
      guard case .inode = item.listingMetadata.identity else {
        continue
      }
      #expect(item.id.identity == item.listingMetadata.identity)
    }
    #expect(
      client.identity(at: rootURL, followingSymbolicLinks: true).successValue != nil
    )
  }

  @Test("live metadata and prefix reads preserve filesystem truth")
  func liveMetadataAndPrefix() async throws {
    try await withTemporaryDirectory { root in
      let file = root.appendingPathComponent("sample.bin")
      let bytes = Data((0..<64).map(UInt8.init))
      try bytes.write(to: file)
      let client = LocalFileSystemClient()

      let metadataResult = await client.metadata(at: file, followingSymbolicLinks: true)
      let metadata = try #require(metadataResult.successValue)
      let identity = try #require(
        client.identity(
          at: file,
          followingSymbolicLinks: true
        ).successValue
      )
      let prefixResult = await client.readPrefix(at: file, maximumBytes: 17)
      let prefix = try #require(prefixResult.successValue)

      #expect(metadata.byteCount == 64)
      #expect(identity == metadata.identity)
      guard case .inode = identity else {
        Issue.record("the live adapter should expose inode identity")
        return
      }
      #expect(metadata.isReadable)
      #expect(prefix.data == Data(bytes.prefix(17)))
      #expect(prefix.totalByteCount == 64)
      #expect(prefix.isTruncated)
    }
  }

  @Test("live adapter distinguishes missing and non-directory reads")
  func liveAdapterTypedFailures() async throws {
    try await withTemporaryDirectory { root in
      let file = root.appendingPathComponent("file.txt")
      try Data().write(to: file)
      let missing = root.appendingPathComponent("missing", isDirectory: true)
      let client = LocalFileSystemClient()

      let missingResult = await client.readDirectory(request(1, url: missing))
      let fileResult = await client.readDirectory(request(2, url: file))

      #expect(missingResult == .failure(.notFound(path: missing.path)))
      #expect(fileResult == .failure(.notDirectory(path: file.path)))
    }
  }

  @Test(
    "live prefix reads never return bytes from a special file swapped after inspection",
    .timeLimit(.minutes(1))
  )
  func livePrefixRejectsSwappedFIFO() async throws {
    try await withTemporaryDirectory { root in
      let regular = root.appendingPathComponent("regular.txt")
      let fifo = root.appendingPathComponent("special.fifo")
      let live = root.appendingPathComponent("live")
      let replacement = root.appendingPathComponent("replacement")
      let regularBytes = Data("regular!".utf8)
      try regularBytes.write(to: regular)
      let fifoResult = unsafe fifo.path.withCString {
        unsafe mkfifo($0, mode_t(0o600))
      }
      try #require(fifoResult == 0)
      let fifoDescriptor = unsafe fifo.path.withCString {
        unsafe open($0, O_RDWR | O_NONBLOCK)
      }
      try #require(fifoDescriptor >= 0)
      defer { _ = close(fifoDescriptor) }
      let fill = [UInt8](repeating: 0x58, count: 4_096)
      while unsafe fill.withUnsafeBytes({
        unsafe write(fifoDescriptor, $0.baseAddress, $0.count)
      }) > 0 {}

      try FileManager.default.createSymbolicLink(
        at: live,
        withDestinationURL: regular
      )
      let swapTask = Task.detached {
        var nextTarget = fifo
        while !Task.isCancelled {
          try? FileManager.default.removeItem(at: replacement)
          try FileManager.default.createSymbolicLink(
            at: replacement,
            withDestinationURL: nextTarget
          )
          let swapped = unsafe replacement.path.withCString { source in
            unsafe live.path.withCString { destination in
              unsafe rename(source, destination)
            }
          }
          if swapped == 0 {
            nextTarget = nextTarget == fifo ? regular : fifo
          }
        }
      }
      defer {
        swapTask.cancel()
      }

      let client = LocalFileSystemClient()
      for _ in 0..<10_000 {
        let result = await client.readPrefix(at: live, maximumBytes: regularBytes.count)
        if case .success(let prefix) = result {
          #expect(prefix.data == regularBytes)
          if prefix.data != regularBytes {
            break
          }
        }
      }
      swapTask.cancel()
      _ = await swapTask.result
    }
  }
}

private func request(
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

private func withTemporaryDirectory(
  _ operation: (URL) async throws -> Void
) async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("sextant-filesystem-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  defer {
    try? FileManager.default.removeItem(at: root)
  }
  try await operation(root)
}

extension Result {
  fileprivate var successValue: Success? {
    guard case .success(let value) = self else {
      return nil
    }
    return value
  }
}

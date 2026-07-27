import Foundation

protocol FileSystemClient: Sendable {
  func identity(
    at url: URL,
    followingSymbolicLinks: Bool
  ) -> Result<FileSystemIdentity, FileSystemFailure>

  func readDirectory(
    _ request: DirectoryRequest
  ) async -> Result<DirectorySnapshot, FileSystemFailure>

  func metadata(
    at url: URL,
    followingSymbolicLinks: Bool
  ) async -> Result<ItemMetadata, FileSystemFailure>

  func readPrefix(
    at url: URL,
    maximumBytes: Int
  ) async -> Result<FilePrefix, FileSystemFailure>
}

extension FileSystemClient {
  func identity(
    at url: URL,
    followingSymbolicLinks _: Bool
  ) -> Result<FileSystemIdentity, FileSystemFailure> {
    .success(.pathFallback(for: url))
  }
}

struct InMemoryFileSystemEntry: Equatable, Sendable {
  var name: String
  var kind: BrowserItemKind
  var metadata: ItemMetadata
  var targetDirectoryID: DirectoryID?
  var isHidden: Bool

  init(
    name: String,
    kind: BrowserItemKind,
    identity: FileSystemIdentity,
    byteCount: UInt64? = nil,
    modificationDate: Date? = nil,
    targetDirectoryID: DirectoryID? = nil,
    isHidden: Bool = false
  ) {
    self.name = name
    self.kind = kind
    self.metadata = ItemMetadata(
      identity: identity,
      byteCount: byteCount,
      modificationDate: modificationDate,
      isReadable: true,
      isWritable: true,
      isExecutable: kind.isDirectoryLike
    )
    self.targetDirectoryID = targetDirectoryID
    self.isHidden = isHidden
  }

  init(
    name: String,
    kind: BrowserItemKind,
    metadata: ItemMetadata,
    targetDirectoryID: DirectoryID? = nil,
    isHidden: Bool = false
  ) {
    self.name = name
    self.kind = kind
    self.metadata = metadata
    self.targetDirectoryID = targetDirectoryID
    self.isHidden = isHidden
  }
}

actor InMemoryFileSystemClient: FileSystemClient {
  struct PrefixRead: Equatable, Sendable {
    var url: URL
    var maximumBytes: Int
  }

  private enum DirectoryResponse: Sendable {
    case entries([InMemoryFileSystemEntry])
    case failure(FileSystemFailure)
  }

  private var directories: [String: DirectoryResponse] = [:]
  private var metadataByPath: [String: Result<ItemMetadata, FileSystemFailure>] = [:]
  private var dataByPath: [String: Data] = [:]
  private var directoryRequests: [DirectoryRequest] = []
  private var prefixReadLog: [PrefixRead] = []

  func setDirectory(
    _ entries: [InMemoryFileSystemEntry],
    at url: URL
  ) {
    directories[key(for: url)] = .entries(entries)
  }

  func setDirectoryFailure(
    _ failure: FileSystemFailure,
    at url: URL
  ) {
    directories[key(for: url)] = .failure(failure)
  }

  func setMetadata(
    _ result: Result<ItemMetadata, FileSystemFailure>,
    at url: URL
  ) {
    metadataByPath[key(for: url)] = result
  }

  func setFile(
    _ data: Data,
    metadata: ItemMetadata,
    at url: URL
  ) {
    let path = key(for: url)
    dataByPath[path] = data
    metadataByPath[path] = .success(metadata)
  }

  func recordedDirectoryRequests() -> [DirectoryRequest] {
    directoryRequests
  }

  func recordedPrefixReads() -> [PrefixRead] {
    prefixReadLog
  }

  func readDirectory(
    _ request: DirectoryRequest
  ) async -> Result<DirectorySnapshot, FileSystemFailure> {
    directoryRequests.append(request)
    if Task.isCancelled {
      return .failure(.cancelled)
    }

    guard let response = directories[key(for: request.url)] else {
      return .failure(.notFound(path: request.url.path))
    }
    switch response {
    case .failure(let failure):
      return .failure(failure)
    case .entries(let entries):
      let listingEntries = entries.map { entry in
        let entryURL = request.url.appendingPathComponent(
          entry.name,
          isDirectory: entry.kind.isDirectoryLike
        )
        return DirectoryListingEntry(
          name: entry.name,
          url: entryURL,
          kind: entry.kind,
          metadata: entry.metadata,
          targetDirectoryID: entry.targetDirectoryID,
          isHidden: entry.isHidden
        )
      }
      return .success(
        DirectorySnapshot(
          request: request,
          items: makeBrowserItems(
            entries: listingEntries,
            directoryID: request.directoryID,
            policy: request.policy
          )
        )
      )
    }
  }

  func metadata(
    at url: URL,
    followingSymbolicLinks: Bool
  ) async -> Result<ItemMetadata, FileSystemFailure> {
    if Task.isCancelled {
      return .failure(.cancelled)
    }
    return metadataByPath[key(for: url)] ?? .failure(.notFound(path: url.path))
  }

  func readPrefix(
    at url: URL,
    maximumBytes: Int
  ) async -> Result<FilePrefix, FileSystemFailure> {
    prefixReadLog.append(PrefixRead(url: url.standardizedFileURL, maximumBytes: maximumBytes))
    if Task.isCancelled {
      return .failure(.cancelled)
    }
    guard maximumBytes >= 0 else {
      return .failure(
        .unsupported(path: url.path, reason: "The byte limit must not be negative.")
      )
    }
    guard let data = dataByPath[key(for: url)] else {
      return .failure(.notFound(path: url.path))
    }
    let prefix = Data(data.prefix(maximumBytes))
    return .success(
      FilePrefix(
        data: prefix,
        totalByteCount: UInt64(data.count),
        isTruncated: prefix.count < data.count
      )
    )
  }

  private func key(for url: URL) -> String {
    url.standardizedFileURL.path
  }
}

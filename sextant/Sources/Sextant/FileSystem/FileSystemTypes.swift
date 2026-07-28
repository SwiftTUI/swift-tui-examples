import Foundation

enum FileSystemIdentity: Hashable, Sendable {
  case inode(device: UInt64, inode: UInt64)
  case path(String)

  static func pathFallback(for url: URL) -> Self {
    .path(url.standardizedFileURL.path)
  }

  /// Builds an inode identity out of raw POSIX `stat` fields, whose concrete
  /// integer types differ by platform.
  static func posixInode(
    device: some BinaryInteger,
    inode: some BinaryInteger
  ) -> Self {
    .inode(device: identityToken(device), inode: identityToken(inode))
  }

  /// Widens one raw `stat` identity field to `UInt64` without trapping.
  ///
  /// `dev_t` is a *signed* `Int32` on Darwin, and devfs and autofs mounts are
  /// handed negative device numbers — `/dev` is one of them, so a plain
  /// `UInt64(st_dev)` trapped on every listing of `/`. These numbers are
  /// opaque identity tokens here, never arithmetic operands, so a
  /// two's-complement widening is the conversion this wants: total for any
  /// fixed-width integer, and injective within a single field's platform type,
  /// which is all a `Hashable` identity asks for. Nonnegative values keep
  /// their arithmetic value.
  static func identityToken(_ value: some BinaryInteger) -> UInt64 {
    UInt64(bitPattern: Int64(truncatingIfNeeded: value))
  }
}

struct DirectoryID: Hashable, Sendable {
  var identity: FileSystemIdentity
}

struct BrowserItemID: Hashable, Sendable {
  var identity: FileSystemIdentity
  var collisionDiscriminator: String?

  init(
    identity: FileSystemIdentity,
    collisionDiscriminator: String? = nil
  ) {
    self.identity = identity
    self.collisionDiscriminator = collisionDiscriminator
  }
}

enum SpecialFileKind: String, Hashable, Sendable {
  case fifo
  case socket
  case characterDevice
  case blockDevice
  case other
}

enum BrowserItemKind: Hashable, Sendable {
  case file
  case directory
  case symbolicLinkToFile
  case symbolicLinkToDirectory
  case symbolicLinkToSpecial(SpecialFileKind)
  case brokenSymbolicLink
  case package
  case special(SpecialFileKind)

  var isDirectoryLike: Bool {
    switch self {
    case .directory, .symbolicLinkToDirectory, .package:
      true
    case .file, .symbolicLinkToFile, .symbolicLinkToSpecial,
      .brokenSymbolicLink, .special:
      false
    }
  }

  var isSymbolicLink: Bool {
    switch self {
    case .symbolicLinkToFile, .symbolicLinkToDirectory,
      .symbolicLinkToSpecial, .brokenSymbolicLink:
      true
    case .file, .directory, .package, .special:
      false
    }
  }

  fileprivate var sortRank: Int {
    switch self {
    case .directory:
      0
    case .package:
      1
    case .symbolicLinkToDirectory:
      2
    case .file:
      3
    case .symbolicLinkToFile:
      4
    case .brokenSymbolicLink:
      5
    case .symbolicLinkToSpecial:
      6
    case .special:
      7
    }
  }
}

struct ItemMetadata: Equatable, Sendable {
  var identity: FileSystemIdentity
  var byteCount: UInt64?
  var creationDate: Date?
  var modificationDate: Date?
  var permissions: UInt16?
  var isReadable: Bool
  var isWritable: Bool
  var isExecutable: Bool

  init(
    identity: FileSystemIdentity,
    byteCount: UInt64? = nil,
    creationDate: Date? = nil,
    modificationDate: Date? = nil,
    permissions: UInt16? = nil,
    isReadable: Bool = false,
    isWritable: Bool = false,
    isExecutable: Bool = false
  ) {
    self.identity = identity
    self.byteCount = byteCount
    self.creationDate = creationDate
    self.modificationDate = modificationDate
    self.permissions = permissions
    self.isReadable = isReadable
    self.isWritable = isWritable
    self.isExecutable = isExecutable
  }
}

struct BrowserItem: Identifiable, Equatable, Sendable {
  var id: BrowserItemID
  var directoryID: DirectoryID
  var targetDirectoryID: DirectoryID?
  var name: String
  var url: URL
  var kind: BrowserItemKind
  var listingMetadata: ItemMetadata

  init(
    id: BrowserItemID,
    directoryID: DirectoryID,
    targetDirectoryID: DirectoryID? = nil,
    name: String,
    url: URL,
    kind: BrowserItemKind,
    listingMetadata: ItemMetadata
  ) {
    self.id = id
    self.directoryID = directoryID
    self.targetDirectoryID = targetDirectoryID
    self.name = name
    self.url = url
    self.kind = kind
    self.listingMetadata = listingMetadata
  }
}

enum SortDirection: Hashable, Sendable {
  case ascending
  case descending
}

struct DirectorySort: Hashable, Sendable {
  enum Key: Hashable, Sendable {
    case name
    case modificationDate
    case size
    case kind
  }

  var key: Key
  var direction: SortDirection

  init(
    key: Key = .name,
    direction: SortDirection = .ascending
  ) {
    self.key = key
    self.direction = direction
  }

  static let nameAscending = Self()
  static let nameDescending = Self(key: .name, direction: .descending)
}

struct DirectoryIgnorePolicy: Hashable, Sendable {
  var entryNames: Set<String>

  init(entryNames: Set<String> = []) {
    self.entryNames = entryNames
  }

  func ignores(entryNamed name: String) -> Bool {
    entryNames.contains(name)
  }

  static let recursiveSearchDefault = Self(
    entryNames: [".build", ".git", "node_modules"]
  )
}

struct DirectoryPolicy: Hashable, Sendable {
  var showsHiddenFiles: Bool
  var sort: DirectorySort
  var directoriesFirst: Bool
  var recursiveSearchIgnore: DirectoryIgnorePolicy

  init(
    showsHiddenFiles: Bool = false,
    sort: DirectorySort = .nameAscending,
    directoriesFirst: Bool = true,
    recursiveSearchIgnore: DirectoryIgnorePolicy = .recursiveSearchDefault
  ) {
    self.showsHiddenFiles = showsHiddenFiles
    self.sort = sort
    self.directoriesFirst = directoriesFirst
    self.recursiveSearchIgnore = recursiveSearchIgnore
  }
}

struct DirectoryRequest: Hashable, Sendable {
  var id: DirectoryRequestID
  var directoryID: DirectoryID
  var url: URL
  var policy: DirectoryPolicy

  init(
    id: DirectoryRequestID,
    directoryID: DirectoryID,
    url: URL,
    policy: DirectoryPolicy = DirectoryPolicy()
  ) {
    self.id = id
    self.directoryID = directoryID
    self.url = url.standardizedFileURL
    self.policy = policy
  }
}

struct DirectorySnapshot: Equatable, Sendable {
  var request: DirectoryRequest
  var items: [BrowserItem]
  var loadedAt: Date

  init(
    request: DirectoryRequest,
    items: [BrowserItem],
    loadedAt: Date = Date()
  ) {
    self.request = request
    self.items = items
    self.loadedAt = loadedAt
  }
}

struct FilePrefix: Equatable, Sendable {
  var data: Data
  var totalByteCount: UInt64?
  var isTruncated: Bool
}

enum FileSystemFailure: Error, Equatable, Sendable {
  case cancelled
  case superseded(DirectoryRequestID)
  case permissionDenied(path: String)
  case notFound(path: String)
  case notDirectory(path: String)
  case stale(path: String)
  case unsupported(path: String, reason: String)
  case io(path: String, code: Int32, message: String)
}

extension FileSystemFailure: CustomStringConvertible {
  var description: String {
    switch self {
    case .cancelled:
      "Filesystem request was cancelled."
    case .superseded(let requestID):
      "Filesystem request \(requestID.rawValue) was superseded."
    case .permissionDenied(let path):
      "Permission denied: \(path)"
    case .notFound(let path):
      "No such file or directory: \(path)"
    case .notDirectory(let path):
      "Not a directory: \(path)"
    case .stale(let path):
      "Filesystem entry became stale: \(path)"
    case .unsupported(let path, let reason):
      "Unsupported filesystem entry at \(path): \(reason)"
    case .io(let path, _, let message):
      "Filesystem error at \(path): \(message)"
    }
  }
}

struct DirectoryListingEntry: Equatable, Sendable {
  var name: String
  var url: URL
  var kind: BrowserItemKind
  var metadata: ItemMetadata
  var targetDirectoryID: DirectoryID?
  var isHidden: Bool

  init(
    name: String,
    url: URL,
    kind: BrowserItemKind,
    metadata: ItemMetadata,
    targetDirectoryID: DirectoryID? = nil,
    isHidden: Bool = false
  ) {
    self.name = name
    self.url = url
    self.kind = kind
    self.metadata = metadata
    self.targetDirectoryID = targetDirectoryID
    self.isHidden = isHidden
  }
}

func makeBrowserItems(
  entries: [DirectoryListingEntry],
  directoryID: DirectoryID,
  policy: DirectoryPolicy
) -> [BrowserItem] {
  let visibleEntries =
    policy.showsHiddenFiles
    ? entries
    : entries.filter { !$0.isHidden && !$0.name.hasPrefix(".") }
  let identityCounts = Dictionary(
    grouping: visibleEntries,
    by: \.metadata.identity
  ).mapValues(\.count)

  let items = visibleEntries.map { entry in
    let needsDiscriminator = identityCounts[entry.metadata.identity, default: 0] > 1
    return BrowserItem(
      id: BrowserItemID(
        identity: entry.metadata.identity,
        collisionDiscriminator: needsDiscriminator ? entry.url.standardizedFileURL.path : nil
      ),
      directoryID: directoryID,
      targetDirectoryID: entry.targetDirectoryID,
      name: entry.name,
      url: entry.url.standardizedFileURL,
      kind: entry.kind,
      listingMetadata: entry.metadata
    )
  }

  return items.sorted { lhs, rhs in
    if policy.directoriesFirst, lhs.kind.isDirectoryLike != rhs.kind.isDirectoryLike {
      return lhs.kind.isDirectoryLike
    }

    let comparison: ComparisonResult
    switch policy.sort.key {
    case .name:
      comparison = stableNameComparison(lhs.name, rhs.name)
    case .modificationDate:
      comparison = compareOptional(
        lhs.listingMetadata.modificationDate,
        rhs.listingMetadata.modificationDate
      )
    case .size:
      comparison = compareOptional(
        lhs.listingMetadata.byteCount,
        rhs.listingMetadata.byteCount
      )
    case .kind:
      comparison = compare(lhs.kind.sortRank, rhs.kind.sortRank)
    }

    if comparison == .orderedSame {
      let nameComparison = stableNameComparison(lhs.name, rhs.name)
      if nameComparison == .orderedSame {
        return lhs.url.path < rhs.url.path
      }
      return nameComparison == .orderedAscending
    }
    return comparison
      == (policy.sort.direction == .ascending ? .orderedAscending : .orderedDescending)
  }
}

private func stableNameComparison(_ lhs: String, _ rhs: String) -> ComparisonResult {
  let folded = lhs.compare(
    rhs,
    options: [.caseInsensitive, .numeric, .widthInsensitive],
    range: nil,
    locale: Locale(identifier: "en_US_POSIX")
  )
  if folded != .orderedSame {
    return folded
  }
  return lhs.compare(rhs, options: .literal)
}

private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
  if lhs < rhs {
    return .orderedAscending
  }
  if lhs > rhs {
    return .orderedDescending
  }
  return .orderedSame
}

private func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
  switch (lhs, rhs) {
  case (.none, .none):
    .orderedSame
  case (.none, .some):
    .orderedDescending
  case (.some, .none):
    .orderedAscending
  case (.some(let lhs), .some(let rhs)):
    compare(lhs, rhs)
  }
}

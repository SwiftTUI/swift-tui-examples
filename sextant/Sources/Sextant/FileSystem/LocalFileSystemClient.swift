import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct LocalFileSystemClient: FileSystemClient {
  func identity(
    at url: URL,
    followingSymbolicLinks: Bool
  ) -> Result<FileSystemIdentity, FileSystemFailure> {
    readStat(
      at: url,
      followingSymbolicLinks: followingSymbolicLinks
    ).map { fileSystemIdentity(from: $0) }
  }

  func readDirectory(
    _ request: DirectoryRequest
  ) async -> Result<DirectorySnapshot, FileSystemFailure> {
    if Task.isCancelled {
      return .failure(.cancelled)
    }

    let directoryInfo: stat
    switch readStat(at: request.url, followingSymbolicLinks: true) {
    case .success(let info):
      directoryInfo = info
    case .failure(let failure):
      return .failure(failure)
    }
    guard fileType(of: directoryInfo) == fileTypeDirectory else {
      return .failure(.notDirectory(path: request.url.path))
    }

    let actualDirectoryIdentity = fileSystemIdentity(from: directoryInfo)
    if case .inode = request.directoryID.identity,
      request.directoryID.identity != actualDirectoryIdentity
    {
      return .failure(.stale(path: request.url.path))
    }

    let urls: [URL]
    do {
      urls = try FileManager.default.contentsOfDirectory(
        at: request.url,
        includingPropertiesForKeys: [.isHiddenKey, .isPackageKey],
        options: []
      )
    } catch {
      return .failure(map(error, path: request.url.path))
    }

    var entries: [DirectoryListingEntry] = []
    entries.reserveCapacity(urls.count)
    for url in urls {
      if Task.isCancelled {
        return .failure(.cancelled)
      }
      switch listingEntry(at: url) {
      case .success(let entry):
        entries.append(entry)
      case .failure(.notFound):
        return .failure(.stale(path: url.path))
      case .failure(let failure):
        return .failure(failure)
      }
    }

    return .success(
      DirectorySnapshot(
        request: request,
        items: makeBrowserItems(
          entries: entries,
          directoryID: request.directoryID,
          policy: request.policy
        )
      )
    )
  }

  func metadata(
    at url: URL,
    followingSymbolicLinks: Bool
  ) async -> Result<ItemMetadata, FileSystemFailure> {
    if Task.isCancelled {
      return .failure(.cancelled)
    }
    return readStat(at: url, followingSymbolicLinks: followingSymbolicLinks)
      .map { itemMetadata(from: $0, at: url) }
  }

  func readPrefix(
    at url: URL,
    maximumBytes: Int
  ) async -> Result<FilePrefix, FileSystemFailure> {
    if Task.isCancelled {
      return .failure(.cancelled)
    }
    guard maximumBytes >= 0 else {
      return .failure(
        .unsupported(path: url.path, reason: "The byte limit must not be negative.")
      )
    }

    let descriptor = unsafe url.path.withCString {
      unsafe open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOCTTY)
    }
    guard descriptor >= 0 else {
      return .failure(mapPOSIX(errno, path: url.path))
    }
    defer {
      _ = close(descriptor)
    }

    var info = stat()
    guard unsafe fstat(descriptor, &info) == 0 else {
      return .failure(mapPOSIX(errno, path: url.path))
    }
    guard fileType(of: info) == fileTypeRegular else {
      return .failure(
        .unsupported(path: url.path, reason: "Only regular files have readable prefixes.")
      )
    }

    var data = Data()
    data.reserveCapacity(min(maximumBytes, prefixReadChunkSize))
    while data.count < maximumBytes {
      if Task.isCancelled {
        return .failure(.cancelled)
      }
      let requestedCount = min(prefixReadChunkSize, maximumBytes - data.count)
      var buffer = [UInt8](repeating: 0, count: requestedCount)
      let bytesRead = unsafe buffer.withUnsafeMutableBytes {
        unsafe read(descriptor, $0.baseAddress, requestedCount)
      }
      if bytesRead > 0 {
        data.append(contentsOf: buffer.prefix(Int(bytesRead)))
      } else if bytesRead == 0 {
        break
      } else if errno != EINTR {
        return .failure(mapPOSIX(errno, path: url.path))
      }
    }

    let totalByteCount = nonnegativeByteCount(info.st_size)
    return .success(
      FilePrefix(
        data: data,
        totalByteCount: totalByteCount,
        isTruncated: totalByteCount.map { $0 > UInt64(data.count) } ?? false
      )
    )
  }

  private func listingEntry(
    at url: URL
  ) -> Result<DirectoryListingEntry, FileSystemFailure> {
    let linkInfo: stat
    switch readStat(at: url, followingSymbolicLinks: false) {
    case .success(let info):
      linkInfo = info
    case .failure(let failure):
      return .failure(failure)
    }

    let linkType = fileType(of: linkInfo)
    var entryMetadata = itemMetadata(from: linkInfo, at: url)
    let kind: BrowserItemKind
    let targetDirectoryID: DirectoryID?

    if linkType == fileTypeSymbolicLink {
      switch readStat(at: url, followingSymbolicLinks: true) {
      case .failure(.notFound):
        kind = .brokenSymbolicLink
        targetDirectoryID = nil
      case .failure(let failure):
        return .failure(failure)
      case .success(let targetInfo):
        let targetType = fileType(of: targetInfo)
        if targetType == fileTypeDirectory {
          kind = .symbolicLinkToDirectory
          targetDirectoryID = DirectoryID(
            identity: fileSystemIdentity(from: targetInfo)
          )
        } else if targetType == fileTypeRegular {
          kind = .symbolicLinkToFile
          targetDirectoryID = nil
          entryMetadata.byteCount = nonnegativeByteCount(targetInfo.st_size)
        } else {
          kind = .symbolicLinkToSpecial(specialKind(for: targetType))
          targetDirectoryID = nil
        }
      }
    } else if linkType == fileTypeDirectory {
      let values = try? url.resourceValues(forKeys: [.isPackageKey])
      kind = values?.isPackage == true ? .package : .directory
      targetDirectoryID = DirectoryID(
        identity: fileSystemIdentity(from: linkInfo)
      )
    } else if linkType == fileTypeRegular {
      kind = .file
      targetDirectoryID = nil
    } else {
      kind = .special(specialKind(for: linkType))
      targetDirectoryID = nil
    }

    let hiddenValues = try? url.resourceValues(forKeys: [.isHiddenKey])
    return .success(
      DirectoryListingEntry(
        name: url.lastPathComponent,
        url: url,
        kind: kind,
        metadata: entryMetadata,
        targetDirectoryID: targetDirectoryID,
        isHidden: hiddenValues?.isHidden == true || url.lastPathComponent.hasPrefix(".")
      )
    )
  }
}

private let fileTypeMask = UInt32(S_IFMT)
private let fileTypeRegular = UInt32(S_IFREG)
private let fileTypeDirectory = UInt32(S_IFDIR)
private let fileTypeSymbolicLink = UInt32(S_IFLNK)
private let fileTypeFIFO = UInt32(S_IFIFO)
private let fileTypeSocket = UInt32(S_IFSOCK)
private let fileTypeCharacterDevice = UInt32(S_IFCHR)
private let fileTypeBlockDevice = UInt32(S_IFBLK)
private let prefixReadChunkSize = 64 * 1_024

private func fileType(of info: stat) -> UInt32 {
  UInt32(info.st_mode) & fileTypeMask
}

private func specialKind(for fileType: UInt32) -> SpecialFileKind {
  switch fileType {
  case fileTypeFIFO:
    .fifo
  case fileTypeSocket:
    .socket
  case fileTypeCharacterDevice:
    .characterDevice
  case fileTypeBlockDevice:
    .blockDevice
  default:
    .other
  }
}

private func fileSystemIdentity(from info: stat) -> FileSystemIdentity {
  .posixInode(device: info.st_dev, inode: info.st_ino)
}

private func itemMetadata(
  from info: stat,
  at url: URL
) -> ItemMetadata {
  ItemMetadata(
    identity: fileSystemIdentity(from: info),
    byteCount: fileType(of: info) == fileTypeRegular
      ? nonnegativeByteCount(info.st_size)
      : nil,
    creationDate: creationDate(from: info),
    modificationDate: modificationDate(from: info),
    permissions: UInt16(UInt32(info.st_mode) & 0o7777),
    isReadable: pathIsAccessible(url.path, mode: R_OK),
    isWritable: pathIsAccessible(url.path, mode: W_OK),
    isExecutable: pathIsAccessible(url.path, mode: X_OK)
  )
}

private func readStat(
  at url: URL,
  followingSymbolicLinks: Bool
) -> Result<stat, FileSystemFailure> {
  var info = stat()
  let result = unsafe url.path.withCString { path in
    if followingSymbolicLinks {
      unsafe stat(path, &info)
    } else {
      unsafe lstat(path, &info)
    }
  }
  guard result == 0 else {
    let code = errno
    return .failure(mapPOSIX(code, path: url.path))
  }
  return .success(info)
}

private func pathIsAccessible(
  _ path: String,
  mode: Int32
) -> Bool {
  unsafe path.withCString { unsafe access($0, mode) == 0 }
}

private func nonnegativeByteCount<T: BinaryInteger>(_ value: T) -> UInt64? {
  guard value >= 0 else {
    return nil
  }
  return UInt64(value)
}

private func modificationDate(from info: stat) -> Date {
  #if canImport(Darwin)
    let seconds = TimeInterval(info.st_mtimespec.tv_sec)
    let nanoseconds = TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
  #else
    let seconds = TimeInterval(info.st_mtim.tv_sec)
    let nanoseconds = TimeInterval(info.st_mtim.tv_nsec) / 1_000_000_000
  #endif
  return Date(timeIntervalSince1970: seconds + nanoseconds)
}

private func creationDate(from info: stat) -> Date? {
  #if canImport(Darwin)
    let seconds = TimeInterval(info.st_birthtimespec.tv_sec)
    let nanoseconds = TimeInterval(info.st_birthtimespec.tv_nsec) / 1_000_000_000
    return Date(timeIntervalSince1970: seconds + nanoseconds)
  #else
    return nil
  #endif
}

private func map(
  _ error: any Error,
  path: String
) -> FileSystemFailure {
  let nsError = error as NSError
  if nsError.domain == NSPOSIXErrorDomain {
    return mapPOSIX(Int32(nsError.code), path: path)
  }
  if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
    underlying.domain == NSPOSIXErrorDomain
  {
    return mapPOSIX(Int32(underlying.code), path: path)
  }
  switch CocoaError.Code(rawValue: nsError.code) {
  case .fileNoSuchFile, .fileReadNoSuchFile:
    return .notFound(path: path)
  case .fileReadNoPermission, .fileWriteNoPermission:
    return .permissionDenied(path: path)
  default:
    return .io(path: path, code: Int32(nsError.code), message: nsError.localizedDescription)
  }
}

private func mapPOSIX(
  _ code: Int32,
  path: String
) -> FileSystemFailure {
  switch code {
  case EACCES, EPERM:
    .permissionDenied(path: path)
  case ENOENT:
    .notFound(path: path)
  case ENOTDIR:
    .notDirectory(path: path)
  #if canImport(Darwin) || canImport(Glibc)
    case ESTALE:
      .stale(path: path)
  #endif
  default:
    .io(
      path: path,
      code: code,
      message: unsafe String(cString: strerror(code))
    )
  }
}

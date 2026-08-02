public import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public enum CSVSourceReadError: Error, Sendable, LocalizedError {
  case notRegularFile
  case tooLarge(Int)
  case cancelled
  case changedDuringRead
  case unreadable(String)

  public var errorDescription: String? {
    switch self {
    case .notRegularFile: "source is not a regular file"
    case .tooLarge(let count): "source exceeds the 256 MiB limit (\(count) bytes)"
    case .cancelled: "source read was cancelled"
    case .changedDuringRead: "source changed while it was being read"
    case .unreadable(let reason): "source is unreadable: \(reason)"
    }
  }
}

public struct CSVSourceReader: Sendable {
  public static let maximumBytes = 256 * 1_024 * 1_024

  public init() {}

  public func read(fileURL: URL, generation: UInt64 = 0) throws -> CSVSourceSnapshot {
    let standardized = fileURL.standardizedFileURL
    let descriptor = try openReadOnly(standardized)
    defer { _ = close(descriptor) }

    var initialStatus = stat()
    guard unsafe fstat(descriptor, &initialStatus) == 0 else { throw systemError() }
    guard (initialStatus.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
      throw CSVSourceReadError.notRegularFile
    }
    let initialIdentity = identity(initialStatus)
    guard initialIdentity.size <= UInt64(Self.maximumBytes) else {
      throw CSVSourceReadError.tooLarge(
        initialIdentity.size > UInt64(Int.max) ? Int.max : Int(initialIdentity.size)
      )
    }

    var data = Data()
    data.reserveCapacity(Int(initialIdentity.size))
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while true {
      guard !Task.isCancelled else { throw CSVSourceReadError.cancelled }
      let count = unsafe buffer.withUnsafeMutableBytes { raw in
        unsafe csvuiSystemRead(descriptor, raw.baseAddress, raw.count)
      }
      if count > 0 {
        guard count <= Self.maximumBytes - data.count else {
          throw CSVSourceReadError.tooLarge(data.count + count)
        }
        data.append(contentsOf: buffer.prefix(count))
        continue
      }
      if count == 0 { break }
      if errno == EINTR { continue }
      throw systemError()
    }

    var finalStatus = stat()
    guard unsafe fstat(descriptor, &finalStatus) == 0 else { throw systemError() }
    let finalIdentity = identity(finalStatus)
    guard finalIdentity == initialIdentity else { throw CSVSourceReadError.changedDuringRead }

    var pathStatus = stat()
    let pathStatResult = unsafe standardized.withUnsafeFileSystemRepresentation { path in
      guard let path = unsafe path else { return Int32(-1) }
      return unsafe lstat(path, &pathStatus)
    }
    let isDirectRegularPath =
      pathStatResult == 0
      && (pathStatus.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
    let isWritable = unsafe standardized.withUnsafeFileSystemRepresentation { path in
      guard let path = unsafe path else { return false }
      return unsafe access(path, W_OK) == 0
    }
    let authority =
      isDirectRegularPath && finalIdentity.linkCount == 1 && isWritable
      ? CSVWriteBackAuthority(destination: standardized, identity: finalIdentity)
      : nil
    return CSVSourceSnapshot(
      origin: .regularFile(standardized),
      displayName: standardized.lastPathComponent,
      bytes: data,
      identity: finalIdentity,
      writeBackAuthority: authority,
      loadGeneration: generation
    )
  }

  public func readStandardInput(generation: UInt64 = 0) throws -> CSVSourceSnapshot {
    var data = Data()
    while true {
      guard !Task.isCancelled else { throw CSVSourceReadError.cancelled }
      let chunk: Data
      do { chunk = try FileHandle.standardInput.read(upToCount: 64 * 1_024) ?? Data() } catch {
        throw CSVSourceReadError.unreadable(error.localizedDescription)
      }
      if chunk.isEmpty { break }
      guard chunk.count <= Self.maximumBytes - data.count else {
        throw CSVSourceReadError.tooLarge(data.count + chunk.count)
      }
      data.append(chunk)
    }
    return CSVSourceSnapshot(
      origin: .standardInput,
      displayName: "stdin",
      bytes: data,
      loadGeneration: generation
    )
  }

  public func currentIdentity(of url: URL) throws -> CSVSourceIdentity {
    let descriptor = try openReadOnly(url)
    defer { _ = close(descriptor) }
    var status = stat()
    guard unsafe fstat(descriptor, &status) == 0 else { throw systemError() }
    guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
      throw CSVSourceReadError.notRegularFile
    }
    return identity(status)
  }

  private func openReadOnly(_ url: URL) throws -> Int32 {
    let descriptor = unsafe url.withUnsafeFileSystemRepresentation { path in
      guard let path = unsafe path else { return Int32(-1) }
      return unsafe open(path, O_RDONLY | O_CLOEXEC)
    }
    guard descriptor >= 0 else { throw systemError() }
    return descriptor
  }

  private func identity(_ status: stat) -> CSVSourceIdentity {
    #if canImport(Darwin)
      let modificationSeconds = Int64(status.st_mtimespec.tv_sec)
      let modificationNanoseconds = Int64(status.st_mtimespec.tv_nsec)
      let changeSeconds = Int64(status.st_ctimespec.tv_sec)
      let changeNanoseconds = Int64(status.st_ctimespec.tv_nsec)
    #else
      let modificationSeconds = Int64(status.st_mtim.tv_sec)
      let modificationNanoseconds = Int64(status.st_mtim.tv_nsec)
      let changeSeconds = Int64(status.st_ctim.tv_sec)
      let changeNanoseconds = Int64(status.st_ctim.tv_nsec)
    #endif
    return CSVSourceIdentity(
      device: UInt64(status.st_dev),
      inode: UInt64(status.st_ino),
      size: UInt64(max(0, status.st_size)),
      modificationSeconds: modificationSeconds,
      modificationNanoseconds: modificationNanoseconds,
      changeSeconds: changeSeconds,
      changeNanoseconds: changeNanoseconds,
      mode: UInt32(status.st_mode),
      linkCount: UInt64(status.st_nlink)
    )
  }

  private func systemError() -> CSVSourceReadError {
    unsafe CSVSourceReadError.unreadable(String(cString: strerror(errno)))
  }
}

#if canImport(Darwin) || canImport(Glibc)
  private func csvuiSystemRead(
    _ descriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe read(descriptor, buffer, count)
  }
#endif

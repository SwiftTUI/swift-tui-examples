import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

enum BoundedRegularFileReadError: Error, LocalizedError {
  case notRegularFile
  case tooLarge(Int)
  case timedOut
  case cancelled
  case changedDuringRead
  case unreadable(String)

  var errorDescription: String? {
    switch self {
    case .notRegularFile:
      "source is not a regular file"
    case .tooLarge(let byteCount):
      "source exceeds the byte limit (\(byteCount) bytes)"
    case .timedOut:
      "source read timed out"
    case .cancelled:
      "source read was cancelled"
    case .changedDuringRead:
      "source changed while it was being read"
    case .unreadable(let reason):
      "source is unreadable: \(reason)"
    }
  }
}

struct RegularFileIdentity: Equatable, Hashable, Sendable, CustomStringConvertible {
  var device: UInt64
  var inode: UInt64
  var byteCount: UInt64
  var modificationSeconds: Int64
  var modificationNanoseconds: Int64
  var changeSeconds: Int64
  var changeNanoseconds: Int64

  var description: String {
    [
      device,
      inode,
      byteCount,
      UInt64(bitPattern: modificationSeconds),
      UInt64(bitPattern: modificationNanoseconds),
      UInt64(bitPattern: changeSeconds),
      UInt64(bitPattern: changeNanoseconds),
    ]
    .map(String.init)
    .joined(separator: ":")
  }

  fileprivate init(_ status: stat) {
    device = UInt64(status.st_dev)
    inode = UInt64(status.st_ino)
    byteCount = UInt64(max(0, status.st_size))
    #if canImport(Darwin)
      modificationSeconds = Int64(status.st_mtimespec.tv_sec)
      modificationNanoseconds = Int64(status.st_mtimespec.tv_nsec)
      changeSeconds = Int64(status.st_ctimespec.tv_sec)
      changeNanoseconds = Int64(status.st_ctimespec.tv_nsec)
    #elseif canImport(Glibc)
      modificationSeconds = Int64(status.st_mtim.tv_sec)
      modificationNanoseconds = Int64(status.st_mtim.tv_nsec)
      changeSeconds = Int64(status.st_ctim.tv_sec)
      changeNanoseconds = Int64(status.st_ctim.tv_nsec)
    #endif
  }
}

struct BoundedRegularFileReadResult: Equatable, Sendable {
  var data: Data
  var identity: RegularFileIdentity
}

enum BoundedRegularFileReader {
  static func read(
    _ url: URL,
    maximumBytes: Int,
    timeout: Duration = .seconds(10)
  ) throws -> Data {
    try readWithIdentity(
      url,
      maximumBytes: maximumBytes,
      timeout: timeout
    ).data
  }

  static func readWithIdentity(
    _ url: URL,
    maximumBytes: Int,
    timeout: Duration = .seconds(10)
  ) throws -> BoundedRegularFileReadResult {
    let descriptor = unsafe url.withUnsafeFileSystemRepresentation { path in
      guard let path = unsafe path else { return Int32(-1) }
      return unsafe systemOpen(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
      throw BoundedRegularFileReadError.unreadable(systemErrorDescription())
    }
    defer { _ = systemClose(descriptor) }

    var status = stat()
    guard unsafe systemFstat(descriptor, &status) == 0 else {
      throw BoundedRegularFileReadError.unreadable(systemErrorDescription())
    }
    guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
      throw BoundedRegularFileReadError.notRegularFile
    }
    let initialIdentity = RegularFileIdentity(status)
    if status.st_size > off_t(maximumBytes) {
      let reported =
        status.st_size > off_t(Int.max)
        ? Int.max
        : Int(status.st_size)
      throw BoundedRegularFileReadError.tooLarge(reported)
    }

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while true {
      guard !Task.isCancelled else {
        throw BoundedRegularFileReadError.cancelled
      }
      guard clock.now < deadline else {
        throw BoundedRegularFileReadError.timedOut
      }

      let byteCount = unsafe buffer.withUnsafeMutableBytes {
        unsafe systemRead(descriptor, $0.baseAddress, $0.count)
      }
      if byteCount > 0 {
        guard byteCount <= maximumBytes - data.count else {
          throw BoundedRegularFileReadError.tooLarge(data.count + byteCount)
        }
        data.append(contentsOf: buffer.prefix(byteCount))
        continue
      }
      if byteCount == 0 {
        var finalStatus = stat()
        guard unsafe systemFstat(descriptor, &finalStatus) == 0 else {
          throw BoundedRegularFileReadError.unreadable(systemErrorDescription())
        }
        let finalIdentity = RegularFileIdentity(finalStatus)
        guard finalIdentity == initialIdentity else {
          throw BoundedRegularFileReadError.changedDuringRead
        }
        return BoundedRegularFileReadResult(
          data: data,
          identity: finalIdentity
        )
      }
      if errno == EINTR { continue }
      if errno == EAGAIN || errno == EWOULDBLOCK {
        var pollDescriptor = pollfd(
          fd: descriptor,
          events: Int16(POLLIN),
          revents: 0
        )
        let result = unsafe systemPoll(&pollDescriptor, 1, 50)
        if result >= 0 { continue }
      }
      throw BoundedRegularFileReadError.unreadable(systemErrorDescription())
    }
  }

  static func identity(of url: URL) throws -> RegularFileIdentity {
    let descriptor = unsafe url.withUnsafeFileSystemRepresentation { path in
      guard let path = unsafe path else { return Int32(-1) }
      return unsafe systemOpen(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
      throw BoundedRegularFileReadError.unreadable(systemErrorDescription())
    }
    defer { _ = systemClose(descriptor) }

    var status = stat()
    guard unsafe systemFstat(descriptor, &status) == 0 else {
      throw BoundedRegularFileReadError.unreadable(systemErrorDescription())
    }
    guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
      throw BoundedRegularFileReadError.notRegularFile
    }
    return RegularFileIdentity(status)
  }

  private static func systemErrorDescription() -> String {
    unsafe String(cString: strerror(errno))
  }
}

#if canImport(Darwin)
  private func systemOpen(_ path: UnsafePointer<CChar>, _ flags: Int32) -> Int32 {
    unsafe open(path, flags)
  }

  private func systemFstat(_ descriptor: Int32, _ status: UnsafeMutablePointer<stat>) -> Int32 {
    unsafe fstat(descriptor, status)
  }

  private func systemRead(
    _ descriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe read(descriptor, buffer, count)
  }

  private func systemPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>,
    _ count: nfds_t,
    _ timeout: Int32
  ) -> Int32 {
    unsafe poll(descriptors, count, timeout)
  }

  private func systemClose(_ descriptor: Int32) -> Int32 {
    close(descriptor)
  }
#elseif canImport(Glibc)
  private func systemOpen(_ path: UnsafePointer<CChar>, _ flags: Int32) -> Int32 {
    unsafe open(path, flags)
  }

  private func systemFstat(_ descriptor: Int32, _ status: UnsafeMutablePointer<stat>) -> Int32 {
    unsafe fstat(descriptor, status)
  }

  private func systemRead(
    _ descriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe read(descriptor, buffer, count)
  }

  private func systemPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>,
    _ count: nfds_t,
    _ timeout: Int32
  ) -> Int32 {
    unsafe poll(descriptors, count, timeout)
  }

  private func systemClose(_ descriptor: Int32) -> Int32 {
    close(descriptor)
  }
#endif

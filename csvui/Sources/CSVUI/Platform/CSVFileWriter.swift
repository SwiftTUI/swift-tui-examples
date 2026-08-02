import Dispatch
public import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public enum CSVFileWriteError: Error, Equatable, Sendable, LocalizedError {
  case sourceChanged
  case destinationExists(URL)
  case unsafeDestination(URL)
  case cannotCreateTemporaryFile(String)
  case writeFailed(String)

  public var errorDescription: String? {
    switch self {
    case .sourceChanged:
      "the source changed outside csvui"
    case .destinationExists(let url):
      "destination already exists: \(url.path)"
    case .unsafeDestination(let url):
      "destination is not a direct, singly linked regular file: \(url.path)"
    case .cannotCreateTemporaryFile(let reason):
      "cannot create save temporary file: \(reason)"
    case .writeFailed(let reason):
      "cannot save: \(reason)"
    }
  }
}

public struct CSVFileWriteRequest: Sendable {
  public var destination: URL
  public var bytes: Data
  public var expectedBytes: Data?
  public var expectedIdentity: CSVSourceIdentity?
  public var overwrite: Bool

  public init(
    destination: URL,
    bytes: Data,
    expectedBytes: Data?,
    expectedIdentity: CSVSourceIdentity?,
    overwrite: Bool
  ) {
    self.destination = destination.standardizedFileURL
    self.bytes = bytes
    self.expectedBytes = expectedBytes
    self.expectedIdentity = expectedIdentity
    self.overwrite = overwrite
  }
}

public struct CSVFileWriteResult: Sendable {
  public var source: CSVSourceSnapshot

  public init(source: CSVSourceSnapshot) { self.source = source }
}

/// Performs conflict checks and atomic replacement away from the main actor.
///
/// The metadata and byte comparison closes the common external-edit races. No
/// portable filesystem primitive can make that comparison and the later rename
/// one cross-process compare-and-swap, so callers must still surface that limit.
public struct CSVFileWriter: Sendable {
  public init() {}

  public func write(_ request: CSVFileWriteRequest) throws -> CSVFileWriteResult {
    try Task.checkCancellation()
    let destination = request.destination
    let reader = CSVSourceReader()
    let existing = FileManager.default.fileExists(atPath: destination.path)
    var permissionBits = mode_t(0o644)

    if let expectedIdentity = request.expectedIdentity,
      let expectedBytes = request.expectedBytes
    {
      guard existing else { throw CSVFileWriteError.sourceChanged }
      let current = try reader.read(fileURL: destination)
      guard current.identity == expectedIdentity,
        current.bytes == expectedBytes,
        current.writeBackAuthority != nil
      else {
        throw CSVFileWriteError.sourceChanged
      }
      permissionBits = mode_t(expectedIdentity.mode) & mode_t(0o7777)
    } else if existing {
      guard request.overwrite else {
        throw CSVFileWriteError.destinationExists(destination)
      }
      let current = try reader.read(fileURL: destination)
      guard let identity = current.identity, current.writeBackAuthority != nil else {
        throw CSVFileWriteError.unsafeDestination(destination)
      }
      permissionBits = mode_t(identity.mode) & mode_t(0o7777)
    }

    try Task.checkCancellation()
    let directory = destination.deletingLastPathComponent()
    let temporary = directory.appendingPathComponent(
      ".\(destination.lastPathComponent).csvui-\(UUID().uuidString).tmp"
    )
    var temporaryExists = false
    defer {
      if temporaryExists { try? FileManager.default.removeItem(at: temporary) }
    }

    let descriptor = try openExclusive(temporary)
    temporaryExists = true
    var shouldClose = true
    defer { if shouldClose { _ = close(descriptor) } }

    do {
      try writeAll(request.bytes, to: descriptor)
      guard fchmod(descriptor, permissionBits) == 0 else { throw systemWriteError() }
      guard fsync(descriptor) == 0 else { throw systemWriteError() }
      guard close(descriptor) == 0 else { throw systemWriteError() }
      shouldClose = false
      try Task.checkCancellation()
      if request.expectedIdentity == nil, !request.overwrite {
        try installWithoutOverwrite(temporary, at: destination)
      } else {
        let renamed = unsafe temporary.path.withCString { sourcePath in
          unsafe destination.path.withCString { destinationPath in
            unsafe rename(sourcePath, destinationPath)
          }
        }
        guard renamed == 0 else { throw systemWriteError() }
      }
      temporaryExists = false
      flushDirectory(directory)
    } catch let error as CSVFileWriteError {
      throw error
    } catch {
      throw CSVFileWriteError.writeFailed(error.localizedDescription)
    }

    let source = try reader.read(fileURL: destination)
    guard source.bytes == request.bytes, source.writeBackAuthority != nil else {
      throw CSVFileWriteError.writeFailed("saved file could not be verified")
    }
    return CSVFileWriteResult(source: source)
  }

  private func openExclusive(_ url: URL) throws -> Int32 {
    let descriptor = unsafe url.path.withCString {
      unsafe open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600))
    }
    guard descriptor >= 0 else {
      throw CSVFileWriteError.cannotCreateTemporaryFile(systemMessage())
    }
    return descriptor
  }

  /// Publishes a new Save As destination without a check-then-rename race.
  /// Both paths share a directory, so an atomic hard-link create either wins
  /// exactly once or fails with EEXIST; removing the temporary name leaves the
  /// destination as the sole link to the flushed inode.
  private func installWithoutOverwrite(_ temporary: URL, at destination: URL) throws {
    let linked = unsafe temporary.path.withCString { sourcePath in
      unsafe destination.path.withCString { destinationPath in
        unsafe link(sourcePath, destinationPath)
      }
    }
    guard linked == 0 else {
      if errno == EEXIST { throw CSVFileWriteError.destinationExists(destination) }
      throw systemWriteError()
    }
    let removed = unsafe temporary.path.withCString { unsafe unlink($0) }
    guard removed == 0 else { throw systemWriteError() }
  }

  private func writeAll(_ data: Data, to descriptor: Int32) throws {
    try unsafe data.withUnsafeBytes { raw in
      var offset = 0
      while offset < raw.count {
        try Task.checkCancellation()
        let count = unsafe csvuiSystemWrite(
          descriptor,
          raw.baseAddress?.advanced(by: offset),
          raw.count - offset
        )
        if count > 0 {
          offset += count
        } else if count < 0, errno == EINTR {
          continue
        } else {
          throw systemWriteError()
        }
      }
    }
  }

  private func flushDirectory(_ url: URL) {
    let descriptor = unsafe url.path.withCString {
      unsafe open($0, O_RDONLY | O_CLOEXEC)
    }
    guard descriptor >= 0 else { return }
    defer { _ = close(descriptor) }
    _ = fsync(descriptor)
  }

  private func systemWriteError() -> CSVFileWriteError {
    .writeFailed(systemMessage())
  }

  private func systemMessage() -> String {
    unsafe String(cString: strerror(errno))
  }
}

#if canImport(Darwin) || canImport(Glibc)
  private func csvuiSystemWrite(
    _ descriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe write(descriptor, buffer, count)
  }
#endif

import Dispatch
public import Foundation
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public struct FileWatcher: Sendable {
  public init() {}

  public func changes(to url: URL) -> AsyncStream<Void> {
    #if canImport(Darwin)
      return darwinChanges(to: url)
    #elseif canImport(Glibc)
      return linuxChanges(to: url)
    #else
      return fileChangeStream { continuation in
        continuation.finish()
      }
    #endif
  }
}

func fileChangeStream(
  _ build: @escaping @Sendable (AsyncStream<Void>.Continuation) -> Void
) -> AsyncStream<Void> {
  AsyncStream(bufferingPolicy: .bufferingNewest(1), build)
}

private struct FileSignature: Equatable, Sendable {
  var modificationDate: Date?
  var size: Int?
  var resourceIdentifier: String?
  var fileSystemIdentity: UInt64?
}

private func signature(of url: URL) -> FileSignature {
  let values = try? url.resourceValues(forKeys: [
    .contentModificationDateKey,
    .fileSizeKey,
    .fileResourceIdentifierKey,
  ])
  return FileSignature(
    modificationDate: values?.contentModificationDate,
    size: values?.fileSize,
    resourceIdentifier: values?.fileResourceIdentifier.map(String.init(describing:)),
    fileSystemIdentity: fileSystemIdentity(at: url)
  )
}

private func fileSystemIdentity(at url: URL) -> UInt64? {
  #if canImport(Darwin) || canImport(Glibc)
    var metadata = stat()
    guard
      unsafe url.path.withCString({
        unsafe lstat($0, &metadata)
      }) == 0
    else {
      return nil
    }
    let device = UInt64(metadata.st_dev)
    let inode = UInt64(metadata.st_ino)
    return (device &* 1_099_511_628_211) ^ inode
  #else
    return nil
  #endif
}

#if canImport(Darwin)
  func openDarwinWatchDirectory(_ directory: URL) -> Int32 {
    unsafe directory.path.withCString {
      unsafe open($0, O_EVTONLY | O_CLOEXEC)
    }
  }

  private func darwinChanges(to url: URL) -> AsyncStream<Void> {
    fileChangeStream { continuation in
      let watcher = DarwinDirectoryWatcher(url: url, continuation: continuation)
      watcher.start()
      continuation.onTermination = { _ in
        watcher.cancel()
      }
    }
  }

  private final class DarwinDirectoryWatcher: Sendable {
    private struct State {
      var source: DispatchSourceFileSystemObject?
      var previous: FileSignature
      var isCancelled = false
    }

    private let url: URL
    private let continuation: AsyncStream<Void>.Continuation
    private let queue = DispatchQueue(label: "mrkdwn.file-watcher")
    private let state: Mutex<State>

    init(url: URL, continuation: AsyncStream<Void>.Continuation) {
      self.url = url
      self.continuation = continuation
      state = Mutex(State(previous: signature(of: url)))
    }

    func start() {
      queue.async { [weak self] in
        self?.installOrRetry()
      }
    }

    private func installOrRetry() {
      let shouldInstall = state.withLock {
        !$0.isCancelled && $0.source == nil
      }
      guard shouldInstall else { return }
      let directory = url.deletingLastPathComponent()
      let descriptor = openDarwinWatchDirectory(directory)
      guard descriptor >= 0 else {
        queue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
          self?.installOrRetry()
        }
        return
      }
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor,
        eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
        queue: queue
      )
      source.setEventHandler { [weak self] in
        self?.handle(source.data)
      }
      source.setCancelHandler {
        close(descriptor)
      }
      let installed = state.withLock {
        guard !$0.isCancelled, $0.source == nil else { return false }
        $0.source = source
        return true
      }
      guard installed else {
        source.resume()
        source.cancel()
        return
      }
      source.resume()
    }

    func cancel() {
      let source = state.withLock {
        $0.isCancelled = true
        let source = $0.source
        $0.source = nil
        return source
      }
      source?.cancel()
      continuation.finish()
    }

    private func handle(_ events: DispatchSource.FileSystemEvent) {
      publishIfChanged()
      guard !events.intersection([.delete, .rename, .revoke]).isEmpty else {
        return
      }
      let source = state.withLock {
        let source = $0.source
        $0.source = nil
        return source
      }
      source?.cancel()
      queue.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
        self?.installOrRetry()
      }
    }

    private func publishIfChanged() {
      let current = signature(of: url)
      let changed = state.withLock {
        guard current != $0.previous else { return false }
        $0.previous = current
        return true
      }
      guard changed else { return }
      continuation.yield(())
    }
  }
#endif

#if canImport(Glibc)
  private func linuxChanges(to url: URL) -> AsyncStream<Void> {
    fileChangeStream { continuation in
      let task = Task.detached {
        await runLinuxWatcher(url: url, continuation: continuation)
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func runLinuxWatcher(
    url: URL,
    continuation: AsyncStream<Void>.Continuation
  ) async {
    var previous = signature(of: url)
    let directoryPath = url.deletingLastPathComponent().path
    let mask = UInt32(
      IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE | IN_ATTRIB
        | IN_MOVE_SELF | IN_DELETE_SELF
    )

    while !Task.isCancelled {
      let descriptor = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
      guard descriptor >= 0 else {
        try? await Task.sleep(for: .milliseconds(100))
        continue
      }
      let watch = unsafe directoryPath.withCString {
        unsafe inotify_add_watch(descriptor, $0, mask)
      }
      guard watch >= 0 else {
        close(descriptor)
        try? await Task.sleep(for: .milliseconds(100))
        continue
      }

      var shouldRearm = false
      var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
      var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
      while !Task.isCancelled, !shouldRearm {
        let result = unsafe poll(&pollDescriptor, 1, 250)
        if result < 0 {
          if errno == EINTR { continue }
          shouldRearm = true
          continue
        }
        guard result > 0, pollDescriptor.revents & Int16(POLLIN) != 0 else {
          continue
        }
        let byteCount = unsafe buffer.withUnsafeMutableBytes { rawBuffer in
          unsafe read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
        }
        guard byteCount > 0 else {
          if errno != EAGAIN && errno != EINTR {
            shouldRearm = true
          }
          continue
        }

        var offset = 0
        while offset + MemoryLayout<inotify_event>.size <= byteCount {
          let event = unsafe buffer.withUnsafeBytes { rawBuffer -> inotify_event in
            unsafe rawBuffer.loadUnaligned(
              fromByteOffset: offset,
              as: inotify_event.self
            )
          }
          if event.mask & UInt32(IN_IGNORED | IN_MOVE_SELF | IN_DELETE_SELF) != 0 {
            shouldRearm = true
          }
          offset += MemoryLayout<inotify_event>.size + Int(event.len)
        }

        let current = signature(of: url)
        if current != previous {
          previous = current
          continuation.yield(())
        }
      }
      inotify_rm_watch(descriptor, watch)
      close(descriptor)
    }
    continuation.finish()
  }
#endif

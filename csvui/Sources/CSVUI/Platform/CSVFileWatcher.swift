import Dispatch
public import Foundation
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public struct CSVFileWatcher: Sendable {
  public init() {}

  public func changes(to url: URL) -> AsyncStream<Void> {
    #if canImport(Darwin)
      return darwinChanges(to: url)
    #elseif canImport(Glibc)
      return linuxChanges(to: url)
    #else
      return csvFileChangeStream { $0.finish() }
    #endif
  }
}

func csvFileChangeStream(
  _ build: @escaping @Sendable (AsyncStream<Void>.Continuation) -> Void
) -> AsyncStream<Void> {
  AsyncStream(bufferingPolicy: .bufferingNewest(1), build)
}

private struct CSVFileSignature: Equatable, Sendable {
  var modificationDate: Date?
  var size: Int?
  var resourceIdentifier: String?
  var fileSystemIdentity: UInt64?
}

private func csvFileSignature(of url: URL) -> CSVFileSignature {
  let values = try? url.resourceValues(forKeys: [
    .contentModificationDateKey, .fileSizeKey, .fileResourceIdentifierKey,
  ])
  return CSVFileSignature(
    modificationDate: values?.contentModificationDate,
    size: values?.fileSize,
    resourceIdentifier: values?.fileResourceIdentifier.map(String.init(describing:)),
    fileSystemIdentity: csvFileSystemIdentity(at: url)
  )
}

private func csvFileSystemIdentity(at url: URL) -> UInt64? {
  #if canImport(Darwin) || canImport(Glibc)
    var metadata = stat()
    guard unsafe url.path.withCString({ unsafe lstat($0, &metadata) }) == 0 else { return nil }
    return (UInt64(metadata.st_dev) &* 1_099_511_628_211) ^ UInt64(metadata.st_ino)
  #else
    return nil
  #endif
}

#if canImport(Darwin)
  func openCSVWatchDirectory(_ directory: URL) -> Int32 {
    unsafe directory.path.withCString { unsafe open($0, O_EVTONLY | O_CLOEXEC) }
  }

  private func darwinChanges(to url: URL) -> AsyncStream<Void> {
    csvFileChangeStream { continuation in
      let watcher = CSVDarwinDirectoryWatcher(url: url, continuation: continuation)
      watcher.start()
      continuation.onTermination = { _ in watcher.cancel() }
    }
  }

  private final class CSVDarwinDirectoryWatcher: Sendable {
    private struct State {
      var source: (any DispatchSourceFileSystemObject)?
      var previous: CSVFileSignature
      var isCancelled = false
    }

    private let url: URL
    private let continuation: AsyncStream<Void>.Continuation
    private let queue = DispatchQueue(label: "csvui.file-watcher")
    private let state: Mutex<State>

    init(url: URL, continuation: AsyncStream<Void>.Continuation) {
      self.url = url
      self.continuation = continuation
      state = Mutex(State(previous: csvFileSignature(of: url)))
    }

    func start() { queue.async { [weak self] in self?.installOrRetry() } }

    private func installOrRetry() {
      guard state.withLock({ !$0.isCancelled && $0.source == nil }) else { return }
      let descriptor = openCSVWatchDirectory(url.deletingLastPathComponent())
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
      source.setEventHandler { [weak self] in self?.handle(source.data) }
      source.setCancelHandler { close(descriptor) }
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
      guard !events.intersection([.delete, .rename, .revoke]).isEmpty else { return }
      let source = state.withLock { value in
        let source = value.source
        value.source = nil
        return source
      }
      source?.cancel()
      queue.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
        self?.installOrRetry()
      }
    }

    private func publishIfChanged() {
      let current = csvFileSignature(of: url)
      guard
        state.withLock({ value in
          guard current != value.previous else { return false }
          value.previous = current
          return true
        })
      else { return }
      continuation.yield(())
    }
  }
#endif

#if canImport(Glibc)
  private final class CSVLinuxWatcherStopFlag: Sendable {
    let isStopped = Atomic(false)
  }

  /// The permanent blocking inotify loop must not occupy a Swift cooperative
  /// executor worker. Document and theme watchers each get a dedicated thread.
  private func linuxChanges(to url: URL) -> AsyncStream<Void> {
    csvFileChangeStream { continuation in
      let stopFlag = CSVLinuxWatcherStopFlag()
      let thread = Thread {
        runCSVLinuxWatcher(url: url, continuation: continuation, stopFlag: stopFlag)
      }
      thread.name = "csvui.file-watcher"
      thread.start()
      continuation.onTermination = { _ in stopFlag.isStopped.store(true, ordering: .relaxed) }
    }
  }

  private func runCSVLinuxWatcher(
    url: URL,
    continuation: AsyncStream<Void>.Continuation,
    stopFlag: CSVLinuxWatcherStopFlag
  ) {
    var previous = csvFileSignature(of: url)
    let directoryPath = url.deletingLastPathComponent().path
    let mask = UInt32(
      IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE | IN_ATTRIB
        | IN_MOVE_SELF | IN_DELETE_SELF
    )
    let stopped = { stopFlag.isStopped.load(ordering: .relaxed) }

    while !stopped() {
      let descriptor = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
      guard descriptor >= 0 else {
        Thread.sleep(forTimeInterval: 0.1)
        continue
      }
      let watch = unsafe directoryPath.withCString {
        unsafe inotify_add_watch(descriptor, $0, mask)
      }
      guard watch >= 0 else {
        close(descriptor)
        Thread.sleep(forTimeInterval: 0.1)
        continue
      }

      var shouldRearm = false
      var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
      var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
      while !stopped(), !shouldRearm {
        let result = unsafe poll(&pollDescriptor, 1, 250)
        if result < 0 {
          if errno == EINTR { continue }
          shouldRearm = true
          continue
        }
        guard result > 0, pollDescriptor.revents & Int16(POLLIN) != 0 else { continue }
        let byteCount = unsafe buffer.withUnsafeMutableBytes {
          unsafe read(descriptor, $0.baseAddress, $0.count)
        }
        guard byteCount > 0 else {
          if errno != EAGAIN && errno != EINTR { shouldRearm = true }
          continue
        }
        var offset = 0
        while offset + MemoryLayout<inotify_event>.size <= byteCount {
          let event = unsafe buffer.withUnsafeBytes {
            unsafe $0.loadUnaligned(fromByteOffset: offset, as: inotify_event.self)
          }
          if event.mask & UInt32(IN_IGNORED | IN_MOVE_SELF | IN_DELETE_SELF) != 0 {
            shouldRearm = true
          }
          offset += MemoryLayout<inotify_event>.size + Int(event.len)
        }
        let current = csvFileSignature(of: url)
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

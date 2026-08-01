import Dispatch
import Foundation
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

#if canImport(Glibc)
  /// Stop flag shared between a watcher thread and the actor that armed it.
  /// A class wrapper because `Atomic` is noncopyable and both sides need the
  /// same instance.
  final class LinuxWatcherStopFlag: Sendable {
    let isStopped = Atomic(false)
  }
#endif

struct DirectoryWatchEvent: Equatable, Sendable {
  var changedDirectories: Set<URL>

  init(changedDirectories: Set<URL>) {
    self.changedDirectories = Set(
      changedDirectories.map(\.standardizedFileURL)
    )
  }
}

protocol DirectoryWatching: Sendable {
  func events(for directories: [URL]) async -> AsyncStream<DirectoryWatchEvent>
  func shutdown() async
}

actor ScriptedDirectoryWatcher: DirectoryWatching {
  private var continuation: AsyncStream<DirectoryWatchEvent>.Continuation?
  private(set) var subscriptions: [[URL]] = []
  private(set) var isShutdown = false

  func events(for directories: [URL]) -> AsyncStream<DirectoryWatchEvent> {
    subscriptions.append(directories.map(\.standardizedFileURL))
    return AsyncStream { continuation in
      self.continuation?.finish()
      self.continuation = continuation
    }
  }

  func send(_ directories: Set<URL>) {
    continuation?.yield(
      DirectoryWatchEvent(changedDirectories: directories)
    )
  }

  func shutdown() {
    isShutdown = true
    continuation?.finish()
    continuation = nil
  }
}

actor LiveDirectoryWatcher: DirectoryWatching {
  private struct ContinuationSlot {
    var id: UUID
    var continuation: AsyncStream<DirectoryWatchEvent>.Continuation
  }

  // Dispatch's file-system-object source is Apple-only: swift-corelibs-libdispatch
  // has no equivalent, so Linux watches the same directories through inotify.
  // Both shapes keep one descriptor per watched directory so the debounce,
  // flush, and `activeDescriptorCount()` behavior below stays identical.
  #if canImport(Darwin)
    private struct WatchedSource {
      var url: URL
      var fileDescriptor: Int32
      var source: DispatchSourceFileSystemObject
    }

    private let queue = DispatchQueue(
      label: "sh.swifttui.sextant.directory-watcher"
    )
  #elseif canImport(Glibc)
    private struct WatchedSource {
      var url: URL
      var fileDescriptor: Int32
      var watch: Int32
      var stopFlag: LinuxWatcherStopFlag
    }
  #endif

  private var sources: [String: WatchedSource] = [:]
  private var continuationSlot: ContinuationSlot?
  private var pendingURLs: Set<URL> = []
  private var flushTask: Task<Void, Never>?
  private var isShutdown = false

  func events(for directories: [URL]) async -> AsyncStream<DirectoryWatchEvent> {
    guard !isShutdown else {
      return AsyncStream { $0.finish() }
    }
    await replaceSources(with: directories)
    return AsyncStream { continuation in
      let id = UUID()
      self.continuationSlot?.continuation.finish()
      self.continuationSlot = ContinuationSlot(
        id: id,
        continuation: continuation
      )
      continuation.onTermination = { [weak self] _ in
        Task {
          await self?.clearContinuation(ifOwnedBy: id)
        }
      }
    }
  }

  func shutdown() async {
    guard !isShutdown else {
      return
    }
    isShutdown = true
    flushTask?.cancel()
    flushTask = nil
    pendingURLs.removeAll()
    continuationSlot?.continuation.finish()
    continuationSlot = nil
    let current = Array(sources.values)
    sources.removeAll()
    for watched in current {
      await close(watched)
    }
  }

  func activeDescriptorCount() -> Int {
    sources.count
  }

  private func replaceSources(with directories: [URL]) async {
    let desired = Dictionary(
      uniqueKeysWithValues: directories.map {
        let url = $0.standardizedFileURL
        return (url.path, url)
      }
    )
    let removed = sources.keys.filter { desired[$0] == nil }
    for path in removed {
      if let watched = sources.removeValue(forKey: path) {
        await close(watched)
      }
    }
    for (path, url) in desired where sources[path] == nil {
      if let source = makeSource(for: url) {
        sources[path] = source
      }
    }
  }

  #if canImport(Darwin)
    private func makeSource(for url: URL) -> WatchedSource? {
      let descriptor = unsafe Darwin.open(url.path, O_EVTONLY)
      guard descriptor >= 0 else {
        return nil
      }
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor,
        eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
        queue: queue
      )
      source.setEventHandler { [weak self] in
        Task {
          await self?.record(url)
        }
      }
      source.resume()
      return WatchedSource(
        url: url,
        fileDescriptor: descriptor,
        source: source
      )
    }
  #elseif canImport(Glibc)
    private static let inotifyMask = UInt32(
      IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO | IN_ATTRIB
        | IN_CLOSE_WRITE | IN_MOVE_SELF | IN_DELETE_SELF
    )

    private func makeSource(for url: URL) -> WatchedSource? {
      let descriptor = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
      guard descriptor >= 0 else {
        return nil
      }
      let watch = unsafe url.path.withCString {
        unsafe inotify_add_watch(descriptor, $0, Self.inotifyMask)
      }
      guard watch >= 0 else {
        _ = Glibc.close(descriptor)
        return nil
      }
      // The blocking poll/read loop runs on its own dedicated thread, never
      // on a Swift concurrency executor: its idle path never suspends, so a
      // cooperative-pool worker it occupied would be pinned for the watcher's
      // whole lifetime — and the pool is sized to the host's CPU count, so a
      // browse across as few directories as the host has CPUs would starve
      // the entire concurrency runtime (the mechanism behind mrkdwn's
      // 2-vCPU-CI first-paint deadlock; see mrkdwn FileWatcher.swift). The
      // thread owns the descriptor and closes it on exit; `close(_:)` only
      // raises the stop flag. The weak reference is re-read per event rather
      // than bound once so an orphan thread cannot keep this actor alive.
      let stopFlag = LinuxWatcherStopFlag()
      let thread = Thread { [weak self] in
        var reader = INotifyReader(descriptor: descriptor)
        loop: while !stopFlag.isStopped.load(ordering: .relaxed) {
          switch reader.next() {
          case .idle:
            continue
          case .changed(let watchEnded):
            Task { [weak self] in
              await self?.record(url)
            }
            if watchEnded { break loop }
          case .failed:
            break loop
          }
        }
        _ = inotify_rm_watch(descriptor, watch)
        _ = Glibc.close(descriptor)
      }
      thread.name = "sextant.directory-watcher"
      thread.start()
      return WatchedSource(
        url: url,
        fileDescriptor: descriptor,
        watch: watch,
        stopFlag: stopFlag
      )
    }

    /// Reads one directory's inotify stream. Every event on the watch means the
    /// same thing to the caller — "this directory changed" — so a whole read is
    /// coalesced into a single `.changed`, and the actor's existing debounce
    /// does the rest.
    private struct INotifyReader {
      /// Bounded so cancellation is observed promptly: `close(_:)` awaits the
      /// polling task before closing the descriptor.
      private static let pollTimeoutMilliseconds: Int32 = 100

      private let descriptor: Int32
      private var pollDescriptor: pollfd
      private var buffer = [UInt8](repeating: 0, count: 16 * 1_024)

      init(descriptor: Int32) {
        self.descriptor = descriptor
        self.pollDescriptor = pollfd(
          fd: descriptor,
          events: Int16(POLLIN),
          revents: 0
        )
      }

      enum Outcome {
        /// Nothing to report yet; poll again.
        case idle
        /// The directory changed. `watchEnded` means the watch is gone (the
        /// directory itself was moved or deleted), so stop polling.
        case changed(watchEnded: Bool)
        /// The descriptor is unusable; stop polling.
        case failed
      }

      mutating func next() -> Outcome {
        let ready = unsafe poll(&pollDescriptor, 1, Self.pollTimeoutMilliseconds)
        if ready < 0 {
          return errno == EINTR ? .idle : .failed
        }
        guard ready > 0, pollDescriptor.revents & Int16(POLLIN) != 0 else {
          return .idle
        }
        let byteCount = unsafe buffer.withUnsafeMutableBytes { rawBuffer in
          unsafe read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
        }
        guard byteCount > 0 else {
          return errno == EAGAIN || errno == EINTR ? .idle : .failed
        }

        var offset = 0
        var watchEnded = false
        while offset + MemoryLayout<inotify_event>.size <= byteCount {
          let event = unsafe buffer.withUnsafeBytes { rawBuffer -> inotify_event in
            unsafe rawBuffer.loadUnaligned(
              fromByteOffset: offset,
              as: inotify_event.self
            )
          }
          if event.mask & UInt32(IN_IGNORED | IN_MOVE_SELF | IN_DELETE_SELF) != 0 {
            watchEnded = true
          }
          // Each record is a fixed-size header followed by `len` name bytes.
          offset += MemoryLayout<inotify_event>.size + Int(event.len)
        }
        return .changed(watchEnded: watchEnded)
      }
    }
  #endif

  private func record(_ url: URL) {
    guard !isShutdown else {
      return
    }
    pendingURLs.insert(url.standardizedFileURL)
    guard flushTask == nil else {
      return
    }
    flushTask = Task { [weak self] in
      do {
        try await ContinuousClock().sleep(for: .milliseconds(100))
      } catch {
        return
      }
      await self?.flush()
    }
  }

  private func flush() {
    flushTask = nil
    guard !pendingURLs.isEmpty else {
      return
    }
    let changed = pendingURLs
    pendingURLs.removeAll()
    continuationSlot?.continuation.yield(
      DirectoryWatchEvent(changedDirectories: changed)
    )
  }

  #if canImport(Darwin)
    private func close(_ watched: WatchedSource) async {
      await withCheckedContinuation { continuation in
        watched.source.setCancelHandler {
          _ = Darwin.close(watched.fileDescriptor)
          continuation.resume()
        }
        watched.source.cancel()
      }
    }
  #elseif canImport(Glibc)
    private func close(_ watched: WatchedSource) async {
      // The watcher thread owns the descriptor: it observes the flag within
      // one poll timeout and closes the descriptor itself, so it can never
      // poll/read a descriptor another context already closed.
      watched.stopFlag.isStopped.store(true, ordering: .relaxed)
    }
  #endif

  private func clearContinuation(ifOwnedBy id: UUID) {
    guard continuationSlot?.id == id else {
      return
    }
    continuationSlot = nil
  }
}

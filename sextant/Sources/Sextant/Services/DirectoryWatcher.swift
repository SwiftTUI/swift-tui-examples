import Dispatch
import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
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

  private struct WatchedSource {
    var url: URL
    var fileDescriptor: Int32
    var source: DispatchSourceFileSystemObject
  }

  private let queue = DispatchQueue(
    label: "sh.swifttui.sextant.directory-watcher"
  )
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

  private func makeSource(for url: URL) -> WatchedSource? {
    #if canImport(Darwin)
      let descriptor = unsafe Darwin.open(url.path, O_EVTONLY)
    #elseif canImport(Glibc)
      let descriptor = unsafe Glibc.open(url.path, O_RDONLY | O_CLOEXEC)
    #else
      return nil
    #endif
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

  private func close(_ watched: WatchedSource) async {
    await withCheckedContinuation { continuation in
      watched.source.setCancelHandler {
        #if canImport(Darwin)
          _ = Darwin.close(watched.fileDescriptor)
        #elseif canImport(Glibc)
          _ = Glibc.close(watched.fileDescriptor)
        #endif
        continuation.resume()
      }
      watched.source.cancel()
    }
  }

  private func clearContinuation(ifOwnedBy id: UUID) {
    guard continuationSlot?.id == id else {
      return
    }
    continuationSlot = nil
  }
}

import Foundation

enum ImageLoadCoordinatorError: Error, LocalizedError {
  case queueFull(Int)

  var errorDescription: String? {
    switch self {
    case .queueFull(let maximum):
      "image request queue is full (maximum \(maximum))"
    }
  }
}

actor ImageLoadCoordinator {
  private struct CachedReference: Sendable {
    var key: ResourceCacheKey
    var image: InspectedImage
    var localVersion: RegularFileIdentity?
  }

  private let loader: ResourceLoader
  private let cache: ResourceCache
  private let maximumConcurrentRequests: Int
  private let maximumQueuedRequests: Int
  private var activeRequests = 0
  private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
  private var waiterOrder: [UUID] = []
  private var references: [URL: CachedReference] = [:]
  private var referenceRecency: [URL] = []

  init(
    loader: ResourceLoader,
    cache: ResourceCache = ResourceCache(),
    maximumConcurrentRequests: Int = 4,
    maximumQueuedRequests: Int = 64
  ) {
    self.loader = loader
    self.cache = cache
    self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
    self.maximumQueuedRequests = max(0, maximumQueuedRequests)
  }

  func load(source: String, relativeTo documentURL: URL?) async throws -> LoadedImage {
    let url = try loader.resolvedURL(source, relativeTo: documentURL)
    let currentLocalVersion = localVersion(for: url)
    if let reference = references[url],
      reference.localVersion == currentLocalVersion,
      let data = await cache.value(for: reference.key)
    {
      touch(url)
      return LoadedImage(
        data: data,
        url: url,
        image: reference.image,
        localVersion: reference.localVersion
      )
    }

    try await acquire()
    defer { release() }
    try Task.checkCancellation()

    let loaded = try await loader.load(source: source, relativeTo: documentURL)
    try Task.checkCancellation()
    let key = ResourceCacheKey(
      url: loaded.url,
      fingerprint: ResourceLoader.fingerprint(loaded.data)
    )
    await cache.insert(loaded.data, for: key)
    references[loaded.url] = CachedReference(
      key: key,
      image: loaded.image,
      localVersion: loaded.localVersion
    )
    touch(loaded.url)
    trimReferences()
    return loaded
  }

  var activeRequestCount: Int {
    activeRequests
  }

  var queuedRequestCount: Int {
    waiters.count
  }

  private func acquire() async throws {
    try Task.checkCancellation()
    if activeRequests < maximumConcurrentRequests {
      activeRequests += 1
      return
    }
    guard waiters.count < maximumQueuedRequests else {
      throw ImageLoadCoordinatorError.queueFull(maximumQueuedRequests)
    }
    let waiterID = UUID()
    let acquired = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(returning: false)
        } else {
          waiters[waiterID] = continuation
          waiterOrder.append(waiterID)
        }
      }
    } onCancel: {
      Task { await self.cancelWaiter(waiterID) }
    }
    guard acquired else { throw CancellationError() }
    do {
      try Task.checkCancellation()
    } catch {
      release()
      throw error
    }
  }

  private func release() {
    while let waiterID = waiterOrder.first {
      waiterOrder.removeFirst()
      guard let continuation = waiters.removeValue(forKey: waiterID) else {
        continue
      }
      continuation.resume(returning: true)
      return
    }
    activeRequests = max(0, activeRequests - 1)
  }

  private func cancelWaiter(_ waiterID: UUID) {
    guard let continuation = waiters.removeValue(forKey: waiterID) else { return }
    waiterOrder.removeAll { $0 == waiterID }
    continuation.resume(returning: false)
  }

  private func touch(_ url: URL) {
    referenceRecency.removeAll { $0 == url }
    referenceRecency.append(url)
  }

  private func trimReferences() {
    while references.count > ResourceCache.maximumEntries {
      guard let oldest = referenceRecency.first else { return }
      referenceRecency.removeFirst()
      references.removeValue(forKey: oldest)
    }
  }

  private func localVersion(for url: URL) -> RegularFileIdentity? {
    guard url.isFileURL else { return nil }
    return try? BoundedRegularFileReader.identity(of: url)
  }
}

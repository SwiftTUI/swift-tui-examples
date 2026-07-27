import Foundation

actor DirectoryStore {
  struct Budget: Equatable, Sendable {
    var maximumSnapshots: Int
    var maximumItems: Int

    init(
      maximumSnapshots: Int = 64,
      maximumItems: Int = 50_000
    ) {
      precondition(maximumSnapshots >= 0)
      precondition(maximumItems >= 0)
      self.maximumSnapshots = maximumSnapshots
      self.maximumItems = maximumItems
    }

    static let `default` = Self()
  }

  struct Statistics: Equatable, Sendable {
    var cachedSnapshotCount: Int
    var cachedItemCount: Int
    var inFlightReadCount: Int
    var pinnedSnapshotCount: Int
  }

  private struct CacheKey: Hashable, Sendable {
    var directoryID: DirectoryID
    var policy: DirectoryPolicy
  }

  private struct CacheEntry: Sendable {
    var snapshot: DirectorySnapshot
    var lastAccess: UInt64
  }

  private struct InFlightRead {
    var request: DirectoryRequest
    var task: Task<Result<DirectorySnapshot, FileSystemFailure>, Never>
  }

  private let client: any FileSystemClient
  private let budget: Budget
  private let readGate: DirectoryReadGate
  private var cache: [CacheKey: CacheEntry] = [:]
  private var inFlight: [CacheKey: InFlightRead] = [:]
  private var pinnedKeys: Set<CacheKey> = []
  private var accessSequence: UInt64 = 0

  init(
    client: any FileSystemClient,
    budget: Budget = .default,
    maximumConcurrentReads: Int = 4
  ) {
    precondition(maximumConcurrentReads > 0)
    self.client = client
    self.budget = budget
    self.readGate = DirectoryReadGate(limit: maximumConcurrentReads)
  }

  func load(
    _ request: DirectoryRequest
  ) async -> Result<DirectorySnapshot, FileSystemFailure> {
    if Task.isCancelled {
      return .failure(.cancelled)
    }

    let key = CacheKey(directoryID: request.directoryID, policy: request.policy)
    if var cached = cachedSnapshot(for: request, key: key) {
      cached.request = request
      return .success(cached)
    }

    if let current = inFlight[key] {
      if current.request.id == request.id {
        return await awaitShared(current, as: request)
      }
      current.task.cancel()
    }

    let client = self.client
    let readGate = self.readGate
    let task = Task<Result<DirectorySnapshot, FileSystemFailure>, Never> {
      await readGate.run {
        if Task.isCancelled {
          return Result<DirectorySnapshot, FileSystemFailure>.failure(.cancelled)
        }
        return await client.readDirectory(request)
      }
    }
    let read = InFlightRead(request: request, task: task)
    inFlight[key] = read
    return await finish(read, for: key)
  }

  func cachedSnapshot(
    for request: DirectoryRequest
  ) -> DirectorySnapshot? {
    let key = CacheKey(directoryID: request.directoryID, policy: request.policy)
    guard var snapshot = cachedSnapshot(for: request, key: key) else {
      return nil
    }
    snapshot.request = request
    return snapshot
  }

  func setPinnedRequests(
    _ requests: [DirectoryRequest]
  ) {
    pinnedKeys = Set(
      requests.map {
        CacheKey(directoryID: $0.directoryID, policy: $0.policy)
      }
    )
    enforceBudget()
  }

  func invalidate(
    _ directoryID: DirectoryID
  ) {
    let cacheKeys = cache.keys.filter { $0.directoryID == directoryID }
    for key in cacheKeys {
      cache.removeValue(forKey: key)
    }

    for (key, read) in inFlight where key.directoryID == directoryID {
      read.task.cancel()
    }
  }

  func invalidateAll() {
    cache.removeAll(keepingCapacity: true)
    pinnedKeys.removeAll(keepingCapacity: true)
    cancelAll()
  }

  func cancel(
    _ requestID: DirectoryRequestID
  ) {
    for read in inFlight.values where read.request.id == requestID {
      read.task.cancel()
    }
  }

  func cancelAll() {
    for read in inFlight.values {
      read.task.cancel()
    }
  }

  func statistics() -> Statistics {
    Statistics(
      cachedSnapshotCount: cache.count,
      cachedItemCount: cachedItemCount,
      inFlightReadCount: inFlight.count,
      pinnedSnapshotCount: pinnedKeys.filter { cache[$0] != nil }.count
    )
  }

  private func finish(
    _ read: InFlightRead,
    for key: CacheKey
  ) async -> Result<DirectorySnapshot, FileSystemFailure> {
    let result = await withTaskCancellationHandler {
      await read.task.value
    } onCancel: {
      read.task.cancel()
    }

    guard inFlight[key]?.request.id == read.request.id else {
      return .failure(.superseded(read.request.id))
    }
    inFlight.removeValue(forKey: key)

    if read.task.isCancelled || Task.isCancelled {
      return .failure(.cancelled)
    }

    switch result {
    case .failure:
      return result
    case .success(var snapshot):
      snapshot.request = read.request
      insert(snapshot, for: key)
      return .success(snapshot)
    }
  }

  private func awaitShared(
    _ read: InFlightRead,
    as request: DirectoryRequest
  ) async -> Result<DirectorySnapshot, FileSystemFailure> {
    let result = await read.task.value
    if read.task.isCancelled || Task.isCancelled {
      return .failure(.cancelled)
    }
    return result.map { snapshot in
      var snapshot = snapshot
      snapshot.request = request
      return snapshot
    }
  }

  private func cachedSnapshot(
    for request: DirectoryRequest,
    key: CacheKey
  ) -> DirectorySnapshot? {
    guard var entry = cache[key],
      entry.snapshot.request.url == request.url
    else {
      return nil
    }
    entry.lastAccess = nextAccessSequence()
    cache[key] = entry
    return entry.snapshot
  }

  private func insert(
    _ snapshot: DirectorySnapshot,
    for key: CacheKey
  ) {
    guard budget.maximumSnapshots > 0,
      snapshot.items.count <= budget.maximumItems
    else {
      cache.removeValue(forKey: key)
      return
    }
    cache[key] = CacheEntry(
      snapshot: snapshot,
      lastAccess: nextAccessSequence()
    )
    enforceBudget()
  }

  private func enforceBudget() {
    while cache.count > budget.maximumSnapshots
      || cachedItemCount > budget.maximumItems
    {
      let unpinned = cache.filter { !pinnedKeys.contains($0.key) }
      let candidates = unpinned.isEmpty ? cache : unpinned
      guard let victim = candidates.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else {
        break
      }
      cache.removeValue(forKey: victim.key)
    }
  }

  private var cachedItemCount: Int {
    cache.values.reduce(into: 0) { count, entry in
      count += entry.snapshot.items.count
    }
  }

  private func nextAccessSequence() -> UInt64 {
    accessSequence &+= 1
    return accessSequence
  }
}

private actor DirectoryReadGate {
  private let limit: Int
  private var activeCount = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(limit: Int) {
    self.limit = limit
  }

  func run<Value: Sendable>(
    _ operation: @Sendable () async -> Value
  ) async -> Value {
    await acquire()
    let value = await operation()
    release()
    return value
  }

  private func acquire() async {
    if activeCount < limit {
      activeCount += 1
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  private func release() {
    if waiters.isEmpty {
      activeCount -= 1
    } else {
      let continuation = waiters.removeFirst()
      continuation.resume()
    }
  }
}

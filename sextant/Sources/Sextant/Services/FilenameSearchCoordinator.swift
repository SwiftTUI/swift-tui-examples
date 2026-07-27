import Foundation

struct FilenameSearchGeneration: Hashable, Sendable {
  var rawValue: UInt64
}

struct FilenameSearchResult: Equatable, Identifiable, Sendable {
  var id: BrowserItemID
  var url: URL
  var name: String
  var kind: BrowserItemKind
}

enum FilenameSearchEvent: Equatable, Sendable {
  case batch(
    generation: FilenameSearchGeneration,
    results: [FilenameSearchResult]
  )
  case finished(
    generation: FilenameSearchGeneration,
    retainedResultCount: Int,
    wasTruncated: Bool
  )
}

actor FilenameSearchCoordinator {
  struct Budget: Equatable, Sendable {
    var batchSize: Int
    var maximumResults: Int
    var maximumDirectories: Int

    init(
      batchSize: Int = 50,
      maximumResults: Int = 2_000,
      maximumDirectories: Int = 20_000
    ) {
      precondition(batchSize > 0)
      precondition(maximumResults > 0)
      precondition(maximumDirectories > 0)
      self.batchSize = batchSize
      self.maximumResults = maximumResults
      self.maximumDirectories = maximumDirectories
    }
  }

  private struct PendingDirectory: Sendable {
    var id: DirectoryID
    var url: URL
  }

  private let fileSystem: any FileSystemClient
  private let budget: Budget
  private var nextGenerationValue: UInt64 = 0
  private var task: Task<Void, Never>?

  init(
    fileSystem: any FileSystemClient,
    budget: Budget = Budget()
  ) {
    self.fileSystem = fileSystem
    self.budget = budget
  }

  func search(
    root: URL,
    query: String,
    policy: DirectoryPolicy
  ) -> AsyncStream<FilenameSearchEvent> {
    task?.cancel()
    nextGenerationValue &+= 1
    let generation = FilenameSearchGeneration(
      rawValue: nextGenerationValue
    )
    let normalizedQuery =
      query
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !normalizedQuery.isEmpty else {
      return AsyncStream { continuation in
        continuation.yield(
          .finished(
            generation: generation,
            retainedResultCount: 0,
            wasTruncated: false
          )
        )
        continuation.finish()
      }
    }

    return AsyncStream { continuation in
      continuation.onTermination = { [weak self] _ in
        Task {
          await self?.cancel(generation)
        }
      }
      task = Task { [weak self] in
        guard let self else {
          continuation.finish()
          return
        }
        await self.run(
          root: root.standardizedFileURL,
          query: normalizedQuery,
          policy: policy,
          generation: generation,
          continuation: continuation
        )
      }
    }
  }

  func cancel() async {
    let task = task
    self.task = nil
    task?.cancel()
    await task?.value
  }

  private func run(
    root: URL,
    query: String,
    policy: DirectoryPolicy,
    generation: FilenameSearchGeneration,
    continuation: AsyncStream<FilenameSearchEvent>.Continuation
  ) async {
    let rootIdentity: FileSystemIdentity =
      switch fileSystem.identity(at: root, followingSymbolicLinks: true) {
      case .success(let identity):
        identity
      case .failure:
        .pathFallback(for: root)
      }
    var queue = [
      PendingDirectory(
        id: DirectoryID(identity: rootIdentity),
        url: root
      )
    ]
    var queueHead = 0
    var visited: Set<DirectoryID> = []
    var discovered: Set<DirectoryID> = [DirectoryID(identity: rootIdentity)]
    var batch: [FilenameSearchResult] = []
    var retainedCount = 0
    var requestValue: UInt64 = 0
    var wasTruncated = false

    while queueHead < queue.count,
      visited.count < budget.maximumDirectories,
      retainedCount < budget.maximumResults,
      !Task.isCancelled
    {
      let directory = queue[queueHead]
      queueHead += 1
      guard visited.insert(directory.id).inserted else {
        continue
      }
      requestValue &+= 1
      let request = DirectoryRequest(
        id: DirectoryRequestID(rawValue: requestValue),
        directoryID: directory.id,
        url: directory.url,
        policy: policy
      )
      guard case .success(let snapshot) = await fileSystem.readDirectory(request) else {
        continue
      }
      for item in snapshot.items {
        guard !Task.isCancelled else {
          break
        }
        guard !policy.recursiveSearchIgnore.ignores(entryNamed: item.name) else {
          continue
        }
        if item.name.lowercased().contains(query) {
          batch.append(
            FilenameSearchResult(
              id: item.id,
              url: item.url,
              name: item.name,
              kind: item.kind
            )
          )
          retainedCount += 1
          if batch.count == budget.batchSize {
            continuation.yield(
              .batch(generation: generation, results: batch)
            )
            batch.removeAll(keepingCapacity: true)
          }
          if retainedCount == budget.maximumResults {
            wasTruncated = true
            break
          }
        }
        if item.kind.isDirectoryLike,
          let targetDirectoryID = item.targetDirectoryID,
          !discovered.contains(targetDirectoryID)
        {
          guard discovered.count < budget.maximumDirectories else {
            wasTruncated = true
            continue
          }
          discovered.insert(targetDirectoryID)
          queue.append(
            PendingDirectory(id: targetDirectoryID, url: item.url)
          )
        }
      }
    }

    if visited.count == budget.maximumDirectories, queueHead < queue.count {
      wasTruncated = true
    }
    if !batch.isEmpty, !Task.isCancelled {
      continuation.yield(.batch(generation: generation, results: batch))
    }
    if !Task.isCancelled {
      continuation.yield(
        .finished(
          generation: generation,
          retainedResultCount: retainedCount,
          wasTruncated: wasTruncated
        )
      )
    }
    continuation.finish()
  }

  private func cancel(_ generation: FilenameSearchGeneration) async {
    guard generation.rawValue == nextGenerationValue else {
      return
    }
    await cancel()
  }
}

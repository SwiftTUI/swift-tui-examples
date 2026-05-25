public import Foundation

@MainActor
public final class DirectoryEntryCache {
  public typealias Loader = @MainActor (URL) -> [FileEntry]

  private let capacity: Int
  private let loadEntries: Loader
  private var cachedEntries: [URL: [FileEntry]] = [:]
  private var recency: [URL] = []

  public init(
    capacity: Int = 32,
    loadEntries: @escaping Loader = { FileEntry.entries(in: $0) }
  ) {
    self.capacity = max(1, capacity)
    self.loadEntries = loadEntries
  }

  public func entries(in directory: URL) -> [FileEntry] {
    if let entries = cachedEntries[directory] {
      markRecentlyUsed(directory)
      return entries
    }

    let entries = loadEntries(directory)
    cachedEntries[directory] = entries
    markRecentlyUsed(directory)
    trimToCapacity()
    return entries
  }

  public func invalidate(_ directory: URL) {
    cachedEntries[directory] = nil
    recency.removeAll { $0 == directory }
  }

  public func retainOnly(_ directories: Set<URL>) {
    cachedEntries = cachedEntries.filter { directories.contains($0.key) }
    recency.removeAll { !directories.contains($0) }
  }

  private func markRecentlyUsed(_ directory: URL) {
    recency.removeAll { $0 == directory }
    recency.append(directory)
  }

  private func trimToCapacity() {
    while cachedEntries.count > capacity, let evicted = recency.first {
      recency.removeFirst()
      cachedEntries[evicted] = nil
    }
  }
}

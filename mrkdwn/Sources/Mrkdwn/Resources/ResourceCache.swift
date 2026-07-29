import Foundation

public struct ResourceCacheKey: Equatable, Hashable, Sendable {
  public var url: URL
  public var fingerprint: UInt64

  public init(url: URL, fingerprint: UInt64) {
    self.url = url
    self.fingerprint = fingerprint
  }
}

public actor ResourceCache {
  public static let maximumEntries = 64
  public static let maximumBytes = 64 * 1_024 * 1_024

  private var values: [ResourceCacheKey: Data] = [:]
  private var recency: [ResourceCacheKey] = []
  private var byteCount = 0

  public init() {}

  public func value(for key: ResourceCacheKey) -> Data? {
    guard let value = values[key] else { return nil }
    touch(key)
    return value
  }

  public func insert(_ value: Data, for key: ResourceCacheKey) {
    guard value.count <= Self.maximumBytes else { return }
    if let previous = values[key] {
      byteCount -= previous.count
    }
    values[key] = value
    byteCount += value.count
    touch(key)
    while values.count > Self.maximumEntries || byteCount > Self.maximumBytes {
      guard let oldest = recency.first else { break }
      recency.removeFirst()
      if let removed = values.removeValue(forKey: oldest) {
        byteCount -= removed.count
      }
    }
  }

  public var occupancy: (entries: Int, bytes: Int) {
    (values.count, byteCount)
  }

  private func touch(_ key: ResourceCacheKey) {
    recency.removeAll { $0 == key }
    recency.append(key)
  }
}

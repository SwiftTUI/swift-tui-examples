public import Foundation
import Synchronization

public struct CSVDecodedField: Equatable, Sendable {
  public var value: String
  public var rawLexeme: String
  public var wasQuoted: Bool

  public init(value: String, rawLexeme: String, wasQuoted: Bool) {
    self.value = value
    self.rawLexeme = rawLexeme
    self.wasQuoted = wasQuoted
  }
}

public struct CSVDecodedRow: Equatable, Sendable {
  public var fields: [CSVDecodedField]
  public var decodedByteCost: Int

  public init(fields: [CSVDecodedField]) {
    self.fields = fields
    decodedByteCost = fields.reduce(into: 0) {
      $0 += $1.value.utf8.count + $1.rawLexeme.utf8.count
    }
  }
}

public struct CSVRowDecoder: Sendable {
  public static let maximumDecodedFieldBytes = 16 * 1_024 * 1_024

  public init() {}

  public func decode(
    _ record: CSVRecordDescriptor,
    from data: Data,
    delimiter: CSVDelimiter
  ) throws -> CSVDecodedRow {
    try Task.checkCancellation()
    var fields: [CSVDecodedField] = []
    fields.reserveCapacity(record.fieldCount)
    var fieldStart = record.byteRange.lowerBound
    let end = record.byteRange.upperBound

    while fieldStart <= end {
      if fieldStart < end, data[fieldStart] == 0x22 {
        var cursor = fieldStart + 1
        var decoded = [UInt8]()
        decoded.reserveCapacity(min(256, end - fieldStart))
        var rawEnd = fieldStart + 1
        while cursor < end {
          if (cursor - fieldStart).isMultiple(of: 64 * 1_024) {
            try Task.checkCancellation()
          }
          if data[cursor] == 0x22 {
            if cursor + 1 < end, data[cursor + 1] == 0x22 {
              decoded.append(0x22)
              cursor += 2
              continue
            }
            rawEnd = cursor + 1
            cursor += 1
            break
          }
          decoded.append(data[cursor])
          cursor += 1
          guard decoded.count <= Self.maximumDecodedFieldBytes else {
            throw oversizedField(record: record, offset: fieldStart)
          }
        }
        let rawData = data.subdata(in: fieldStart..<rawEnd)
        guard let raw = String(data: rawData, encoding: .utf8),
          let value = String(data: Data(decoded), encoding: .utf8)
        else {
          throw invalidUTF8(record: record, offset: fieldStart)
        }
        fields.append(CSVDecodedField(value: value, rawLexeme: raw, wasQuoted: true))
        if cursor >= end { break }
        fieldStart = cursor + 1
      } else {
        var cursor = fieldStart
        while cursor < end, data[cursor] != delimiter.byte {
          if (cursor - fieldStart).isMultiple(of: 64 * 1_024) {
            try Task.checkCancellation()
          }
          cursor += 1
        }
        guard cursor - fieldStart <= Self.maximumDecodedFieldBytes else {
          throw oversizedField(record: record, offset: fieldStart)
        }
        let rawData = data.subdata(in: fieldStart..<cursor)
        guard let raw = String(data: rawData, encoding: .utf8) else {
          throw invalidUTF8(record: record, offset: fieldStart)
        }
        fields.append(CSVDecodedField(value: raw, rawLexeme: raw, wasQuoted: false))
        if cursor >= end { break }
        fieldStart = cursor + 1
      }
    }
    return CSVDecodedRow(fields: fields)
  }

  private func oversizedField(record: CSVRecordDescriptor, offset: Int) -> CSVFormatError {
    CSVFormatError(
      message: "decoded field exceeds 16 MiB",
      line: record.physicalStartLine,
      column: max(1, offset - record.byteRange.lowerBound + 1),
      byteOffset: offset
    )
  }

  private func invalidUTF8(record: CSVRecordDescriptor, offset: Int) -> CSVFormatError {
    CSVFormatError(
      message: "invalid UTF-8",
      line: record.physicalStartLine,
      column: max(1, offset - record.byteRange.lowerBound + 1),
      byteOffset: offset
    )
  }
}

public final class CSVRowCache: Sendable {
  public struct Statistics: Equatable, Sendable {
    public var entries: Int
    public var bytes: Int
    public var hits: Int
    public var misses: Int
    public var evictions: Int
  }

  private struct Entry: Sendable {
    var row: CSVDecodedRow
    var cost: Int
    var lastUse: UInt64
  }

  private struct State: Sendable {
    var entries: [Int: Entry] = [:]
    var bytes = 0
    var use: UInt64 = 0
    var hits = 0
    var misses = 0
    var evictions = 0
  }

  public static let maximumEntries = 512
  public static let maximumBytes = 16 * 1_024 * 1_024
  private let state = Mutex(State())

  public init() {}

  public var statistics: Statistics {
    state.withLock {
      Statistics(
        entries: $0.entries.count,
        bytes: $0.bytes,
        hits: $0.hits,
        misses: $0.misses,
        evictions: $0.evictions
      )
    }
  }

  public func removeAll() {
    state.withLock {
      $0.entries.removeAll(keepingCapacity: true)
      $0.bytes = 0
    }
  }

  public func row(
    recordIndex: Int,
    decode: () throws -> CSVDecodedRow
  ) throws -> CSVDecodedRow {
    if let cached = state.withLock({ state -> CSVDecodedRow? in
      state.use &+= 1
      guard var entry = state.entries[recordIndex] else {
        state.misses += 1
        return nil
      }
      state.hits += 1
      entry.lastUse = state.use
      state.entries[recordIndex] = entry
      return entry.row
    }) {
      return cached
    }

    let decoded = try decode()
    let cost = decoded.decodedByteCost
    guard cost <= Self.maximumBytes else { return decoded }
    state.withLock { state in
      state.use &+= 1
      while state.entries.count >= Self.maximumEntries
        || state.bytes + cost > Self.maximumBytes
      {
        guard let oldest = state.entries.min(by: { $0.value.lastUse < $1.value.lastUse }) else {
          break
        }
        state.bytes -= oldest.value.cost
        state.entries.removeValue(forKey: oldest.key)
        state.evictions += 1
      }
      state.entries[recordIndex] = Entry(row: decoded, cost: cost, lastUse: state.use)
      state.bytes += cost
    }
    return decoded
  }
}

public import Foundation

public struct CSVRecordDescriptor: Equatable, Sendable {
  public var byteRange: Range<Int>
  public var separatorRange: Range<Int>
  public var lineEnding: CSVLineEnding?
  public var fieldCount: Int
  public var physicalStartLine: Int

  public init(
    byteRange: Range<Int>,
    separatorRange: Range<Int>,
    lineEnding: CSVLineEnding?,
    fieldCount: Int,
    physicalStartLine: Int
  ) {
    self.byteRange = byteRange
    self.separatorRange = separatorRange
    self.lineEnding = lineEnding
    self.fieldCount = fieldCount
    self.physicalStartLine = physicalStartLine
  }
}

public struct CSVRecordIndex: Equatable, Sendable {
  public static let maximumRecords = 2_000_000
  public static let maximumColumns = 16_384

  public var records: [CSVRecordDescriptor]
  public var maximumFieldCount: Int
  public var irregularRecordCount: Int
  public var lineEndingCounts: [CSVLineEnding: Int]
  public var startsAfterUTF8BOM: Bool

  public init(
    records: [CSVRecordDescriptor],
    maximumFieldCount: Int,
    irregularRecordCount: Int,
    lineEndingCounts: [CSVLineEnding: Int],
    startsAfterUTF8BOM: Bool
  ) {
    self.records = records
    self.maximumFieldCount = maximumFieldCount
    self.irregularRecordCount = irregularRecordCount
    self.lineEndingCounts = lineEndingCounts
    self.startsAfterUTF8BOM = startsAfterUTF8BOM
  }

  public var dominantLineEnding: CSVLineEnding {
    CSVLineEnding.allCases.max { left, right in
      let leftCount = lineEndingCounts[left, default: 0]
      let rightCount = lineEndingCounts[right, default: 0]
      if leftCount == rightCount {
        return Self.lineEndingPriority(left) < Self.lineEndingPriority(right)
      }
      return leftCount < rightCount
    } ?? .lf
  }

  public var hasFinalNewline: Bool {
    guard let last = records.last else { return false }
    return last.lineEnding != nil
  }

  private static func lineEndingPriority(_ ending: CSVLineEnding) -> Int {
    switch ending {
    case .lf: 3
    case .crlf: 2
    case .cr: 1
    }
  }
}

public struct CSVRecordIndexer: Sendable {
  private enum State { case fieldStart, unquoted, quoted, afterQuote }

  public init() {}

  public func index(_ data: Data, delimiter: CSVDelimiter) throws -> CSVRecordIndex {
    try Task.checkCancellation()
    try validateUTF8AndNUL(data)
    let hasBOM = data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF
    let contentStart = hasBOM ? 3 : 0
    guard contentStart < data.count else {
      return CSVRecordIndex(
        records: [],
        maximumFieldCount: 0,
        irregularRecordCount: 0,
        lineEndingCounts: [:],
        startsAfterUTF8BOM: hasBOM
      )
    }

    var records: [CSVRecordDescriptor] = []
    records.reserveCapacity(min(16_384, max(1, data.count / 32)))
    var lineEndingCounts: [CSVLineEnding: Int] = [:]
    var state: State = .fieldStart
    var recordStart = contentStart
    var recordStartLine = 1
    var fieldCount = 1
    var line = 1
    var column = 1
    var index = contentStart

    func appendRecord(end: Int, separatorEnd: Int, ending: CSVLineEnding?) throws {
      guard fieldCount <= CSVRecordIndex.maximumColumns else {
        throw CSVFormatError(
          message: "record has more than \(CSVRecordIndex.maximumColumns) columns",
          line: recordStartLine,
          column: 1,
          byteOffset: recordStart
        )
      }
      guard records.count < CSVRecordIndex.maximumRecords else {
        throw CSVFormatError(
          message: "document has more than \(CSVRecordIndex.maximumRecords) records",
          line: recordStartLine,
          column: 1,
          byteOffset: recordStart
        )
      }
      records.append(
        CSVRecordDescriptor(
          byteRange: recordStart..<end,
          separatorRange: end..<separatorEnd,
          lineEnding: ending,
          fieldCount: fieldCount,
          physicalStartLine: recordStartLine
        )
      )
      if let ending { lineEndingCounts[ending, default: 0] += 1 }
    }

    while index < data.count {
      if index.isMultiple(of: 64 * 1_024) { try Task.checkCancellation() }
      let byte = data[index]
      switch state {
      case .fieldStart:
        if byte == 0x22 {
          state = .quoted
          index += 1
          column += 1
        } else if byte == delimiter.byte {
          fieldCount += 1
          index += 1
          column += 1
        } else if let separator = separator(in: data, at: index) {
          try appendRecord(
            end: index, separatorEnd: index + separator.length, ending: separator.ending)
          index += separator.length
          line += 1
          column = 1
          recordStart = index
          recordStartLine = line
          fieldCount = 1
        } else {
          state = .unquoted
          index += 1
          column += 1
        }

      case .unquoted:
        if byte == delimiter.byte {
          fieldCount += 1
          state = .fieldStart
          index += 1
          column += 1
        } else if let separator = separator(in: data, at: index) {
          try appendRecord(
            end: index, separatorEnd: index + separator.length, ending: separator.ending)
          index += separator.length
          line += 1
          column = 1
          recordStart = index
          recordStartLine = line
          fieldCount = 1
          state = .fieldStart
        } else {
          index += 1
          column += 1
        }

      case .quoted:
        if byte == 0x22 {
          if index + 1 < data.count, data[index + 1] == 0x22 {
            index += 2
            column += 2
          } else {
            state = .afterQuote
            index += 1
            column += 1
          }
        } else if let separator = separator(in: data, at: index) {
          index += separator.length
          line += 1
          column = 1
        } else {
          index += 1
          column += 1
        }

      case .afterQuote:
        if byte == delimiter.byte {
          fieldCount += 1
          state = .fieldStart
          index += 1
          column += 1
        } else if let separator = separator(in: data, at: index) {
          try appendRecord(
            end: index, separatorEnd: index + separator.length, ending: separator.ending)
          index += separator.length
          line += 1
          column = 1
          recordStart = index
          recordStartLine = line
          fieldCount = 1
          state = .fieldStart
        } else {
          throw CSVFormatError(
            message: "unexpected byte after closing quote",
            line: line,
            column: column,
            byteOffset: index
          )
        }
      }
    }

    if state == .quoted {
      throw CSVFormatError(
        message: "unclosed quoted field",
        line: line,
        column: column,
        byteOffset: data.count
      )
    }
    if recordStart < data.count {
      try appendRecord(end: data.count, separatorEnd: data.count, ending: nil)
    }

    let maximumFieldCount = records.map(\.fieldCount).max() ?? 0
    let irregular = records.reduce(into: 0) { count, record in
      if record.fieldCount != maximumFieldCount { count += 1 }
    }
    return CSVRecordIndex(
      records: records,
      maximumFieldCount: maximumFieldCount,
      irregularRecordCount: irregular,
      lineEndingCounts: lineEndingCounts,
      startsAfterUTF8BOM: hasBOM
    )
  }

  private func separator(
    in data: Data,
    at index: Int
  ) -> (ending: CSVLineEnding, length: Int)? {
    switch data[index] {
    case 0x0A: return (.lf, 1)
    case 0x0D:
      if index + 1 < data.count, data[index + 1] == 0x0A {
        return (.crlf, 2)
      }
      return (.cr, 1)
    default: return nil
    }
  }

  private func validateUTF8AndNUL(_ data: Data) throws {
    var index = 0
    while index < data.count {
      if index.isMultiple(of: 64 * 1_024) { try Task.checkCancellation() }
      let first = data[index]
      if first == 0 {
        throw CSVFormatError(
          message: "NUL bytes are not supported",
          line: 1,
          column: index + 1,
          byteOffset: index
        )
      }
      if first <= 0x7F {
        index += 1
        continue
      }

      let length: Int
      let secondRange: ClosedRange<UInt8>
      switch first {
      case 0xC2...0xDF:
        length = 2
        secondRange = 0x80...0xBF
      case 0xE0:
        length = 3
        secondRange = 0xA0...0xBF
      case 0xE1...0xEC, 0xEE...0xEF:
        length = 3
        secondRange = 0x80...0xBF
      case 0xED:
        length = 3
        secondRange = 0x80...0x9F
      case 0xF0:
        length = 4
        secondRange = 0x90...0xBF
      case 0xF1...0xF3:
        length = 4
        secondRange = 0x80...0xBF
      case 0xF4:
        length = 4
        secondRange = 0x80...0x8F
      default:
        throw invalidUTF8(at: index)
      }
      guard index + length <= data.count, secondRange.contains(data[index + 1]) else {
        throw invalidUTF8(at: index)
      }
      if length > 2 {
        for continuation in (index + 2)..<(index + length) {
          guard (0x80...0xBF).contains(data[continuation]) else {
            throw invalidUTF8(at: continuation)
          }
        }
      }
      index += length
    }
  }

  private func invalidUTF8(at offset: Int) -> CSVFormatError {
    CSVFormatError(
      message: "invalid UTF-8",
      line: 1,
      column: offset + 1,
      byteOffset: offset
    )
  }
}

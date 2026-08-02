public import Foundation

public enum CSVProjectionError: Error, Equatable, Sendable, LocalizedError {
  case invalidRegex(String)
  case workspaceLimit

  public var errorDescription: String? {
    switch self {
    case .invalidRegex(let reason): "invalid regular expression: \(reason)"
    case .workspaceLimit: "operation exceeded the 64 MiB projection workspace limit"
    }
  }
}

public struct CSVSearchResultSet: Equatable, Sendable {
  public var matches: [CSVSearchMatch]
  public var isTruncated: Bool

  public init(matches: [CSVSearchMatch], isTruncated: Bool) {
    self.matches = matches
    self.isTruncated = isTruncated
  }
}

public struct CSVScanSnapshot: Sendable {
  public var document: CSVDocument
  public var journal: CSVEditJournal
  private var originalColumnOffsets: [ColumnID: Int]

  public init(document: CSVDocument, journal: CSVEditJournal) {
    self.document = document
    self.journal = journal
    originalColumnOffsets = Dictionary(
      uniqueKeysWithValues: journal.originalColumnOrder.enumerated().map { ($1, $0) }
    )
  }

  public func rowValues(_ row: RowID, columns: [ColumnID]) throws -> [String] {
    let decoded = try document.decodeSourceRow(row)?.fields ?? []
    return columns.map { column in
      if let replacement = journal.replacement(row: row, column: column) {
        return replacement
      }
      guard let base = originalColumnOffsets[column],
        decoded.indices.contains(base)
      else {
        return ""
      }
      return decoded[base].value
    }
  }

  public func value(row: RowID, column: ColumnID) throws -> String {
    try rowValues(row, columns: [column]).first ?? ""
  }
}

public struct CSVProjectionEngine: Sendable {
  public static let maximumSearchMatches = 10_000
  public static let maximumWorkspaceBytes = 64 * 1_024 * 1_024

  public init() {}

  public func validate(query: String) -> String? {
    guard query.hasPrefix("re:") else { return nil }
    do {
      _ = try NSRegularExpression(pattern: String(query.dropFirst(3)))
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  public func search(
    snapshot: CSVScanSnapshot,
    rows: [RowID],
    columns: [ColumnID],
    query: String
  ) async throws -> CSVSearchResultSet {
    let matcher = try Matcher(query: query)
    var matches: [CSVSearchMatch] = []
    matches.reserveCapacity(min(Self.maximumSearchMatches, rows.count))
    var isTruncated = false

    for (rowOffset, row) in rows.enumerated() {
      if rowOffset.isMultiple(of: 512) {
        try Task.checkCancellation()
        await Task.yield()
      }
      let values = try snapshot.rowValues(row, columns: columns)
      for (columnOffset, value) in values.enumerated() where matcher.matches(value) {
        if matches.count == Self.maximumSearchMatches {
          isTruncated = true
          return CSVSearchResultSet(matches: matches, isTruncated: isTruncated)
        }
        matches.append(
          CSVSearchMatch(address: CSVCellAddress(row: row, column: columns[columnOffset]))
        )
      }
    }
    return CSVSearchResultSet(matches: matches, isTruncated: isTruncated)
  }

  public func filter(
    snapshot: CSVScanSnapshot,
    rows: [RowID],
    visibleColumns: [ColumnID],
    spec: CSVFilterSpec
  ) async throws -> [RowID] {
    let matcher = try Matcher(query: spec.query)
    let columns: [ColumnID]
    switch spec.scope {
    case .column(let column): columns = [column]
    case .allVisibleColumns: columns = visibleColumns
    }
    var result: [RowID] = []
    result.reserveCapacity(min(rows.count, 16_384))
    for (offset, row) in rows.enumerated() {
      if offset.isMultiple(of: 512) {
        try Task.checkCancellation()
        await Task.yield()
      }
      let values = try snapshot.rowValues(row, columns: columns)
      if values.contains(where: matcher.matches) { result.append(row) }
    }
    return result
  }

  public func sort(
    snapshot: CSVScanSnapshot,
    rows: [RowID],
    spec: CSVSortSpec
  ) async throws -> [RowID] {
    struct KeyedRow {
      var row: RowID
      var value: String
      var ordinal: Int
    }
    var keyed: [KeyedRow] = []
    keyed.reserveCapacity(rows.count)
    var workspaceBytes = 0
    for (offset, row) in rows.enumerated() {
      if offset.isMultiple(of: 512) {
        try Task.checkCancellation()
        await Task.yield()
      }
      let value = try snapshot.value(row: row, column: spec.column)
      let (next, overflow) = workspaceBytes.addingReportingOverflow(value.utf8.count + 32)
      guard !overflow, next <= Self.maximumWorkspaceBytes else {
        throw CSVProjectionError.workspaceLimit
      }
      workspaceBytes = next
      keyed.append(KeyedRow(row: row, value: value, ordinal: offset))
    }
    keyed.sort { lhs, rhs in
      let leftEmpty = lhs.value.isEmpty
      let rightEmpty = rhs.value.isEmpty
      if leftEmpty != rightEmpty { return !leftEmpty }
      let comparison = naturalCompare(lhs.value, rhs.value)
      if comparison == .orderedSame { return lhs.ordinal < rhs.ordinal }
      switch spec.direction {
      case .ascending: return comparison == .orderedAscending
      case .descending: return comparison == .orderedDescending
      }
    }
    return keyed.map(\.row)
  }

  private func naturalCompare(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let locale = Locale(identifier: "en_US_POSIX")
    if let leftNumber = Decimal(string: lhs, locale: locale),
      let rightNumber = Decimal(string: rhs, locale: locale)
    {
      return NSDecimalNumber(decimal: leftNumber).compare(NSDecimalNumber(decimal: rightNumber))
    }

    let left = Array(lhs.unicodeScalars)
    let right = Array(rhs.unicodeScalars)
    var leftIndex = 0
    var rightIndex = 0
    while leftIndex < left.count, rightIndex < right.count {
      if left[leftIndex].properties.numericType != nil,
        right[rightIndex].properties.numericType != nil
      {
        var leftEnd = leftIndex
        var rightEnd = rightIndex
        while leftEnd < left.count, left[leftEnd].properties.numericType != nil { leftEnd += 1 }
        while rightEnd < right.count, right[rightEnd].properties.numericType != nil {
          rightEnd += 1
        }
        let leftDigits = String(String.UnicodeScalarView(left[leftIndex..<leftEnd]))
        let rightDigits = String(String.UnicodeScalarView(right[rightIndex..<rightEnd]))
        let trimmedLeft = leftDigits.drop(while: { $0 == "0" })
        let trimmedRight = rightDigits.drop(while: { $0 == "0" })
        if trimmedLeft.count != trimmedRight.count {
          return trimmedLeft.count < trimmedRight.count ? .orderedAscending : .orderedDescending
        }
        if trimmedLeft != trimmedRight {
          return trimmedLeft.lexicographicallyPrecedes(trimmedRight)
            ? .orderedAscending : .orderedDescending
        }
        if leftDigits.count != rightDigits.count {
          return leftDigits.count < rightDigits.count ? .orderedAscending : .orderedDescending
        }
        leftIndex = leftEnd
        rightIndex = rightEnd
        continue
      }
      if left[leftIndex].value != right[rightIndex].value {
        return left[leftIndex].value < right[rightIndex].value
          ? .orderedAscending : .orderedDescending
      }
      leftIndex += 1
      rightIndex += 1
    }
    if left.count == right.count { return .orderedSame }
    return left.count < right.count ? .orderedAscending : .orderedDescending
  }

  private struct Matcher {
    var source: String
    var caseSensitive: Bool
    var expression: NSRegularExpression?

    init(query: String) throws {
      source = query
      if query.hasPrefix("re:") {
        do { expression = try NSRegularExpression(pattern: String(query.dropFirst(3))) } catch {
          throw CSVProjectionError.invalidRegex(error.localizedDescription)
        }
        caseSensitive = true
      } else {
        expression = nil
        caseSensitive = query.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
      }
    }

    func matches(_ value: String) -> Bool {
      if let expression {
        return expression.firstMatch(
          in: value,
          range: NSRange(value.startIndex..<value.endIndex, in: value)
        ) != nil
      }
      if source.isEmpty { return true }
      return value.range(
        of: source,
        options: caseSensitive ? [] : [.caseInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      ) != nil
    }
  }
}

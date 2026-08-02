public import Foundation

public struct CSVDelimiterCandidateEvidence: Equatable, Sendable {
  public var delimiter: CSVDelimiter
  public var sampledRecords: Int
  public var consistentRecords: Int
  public var modalFieldCount: Int

  public init(
    delimiter: CSVDelimiter,
    sampledRecords: Int,
    consistentRecords: Int,
    modalFieldCount: Int
  ) {
    self.delimiter = delimiter
    self.sampledRecords = sampledRecords
    self.consistentRecords = consistentRecords
    self.modalFieldCount = modalFieldCount
  }
}

public struct CSVDelimiterDetection: Equatable, Sendable {
  public var delimiter: CSVDelimiter
  public var evidence: [CSVDelimiterCandidateEvidence]
  public var usedDefault: Bool
  public var wasAmbiguous: Bool

  public init(
    delimiter: CSVDelimiter,
    evidence: [CSVDelimiterCandidateEvidence],
    usedDefault: Bool,
    wasAmbiguous: Bool
  ) {
    self.delimiter = delimiter
    self.evidence = evidence
    self.usedDefault = usedDefault
    self.wasAmbiguous = wasAmbiguous
  }
}

public struct CSVDelimiterDetector: Sendable {
  public static let maximumBytes = 64 * 1_024
  public static let maximumRecords = 100
  private static let candidates: [CSVDelimiter] = [.comma, .tab, .semicolon, .pipe]

  public init() {}

  public func detect(_ data: Data) -> CSVDelimiterDetection {
    let evidence = Self.candidates.map { score($0, in: data) }
    let viable = evidence.filter { $0.consistentRecords > 0 && $0.modalFieldCount > 1 }
    guard let best = viable.max(by: isWorse) else {
      return CSVDelimiterDetection(
        delimiter: .comma,
        evidence: evidence,
        usedDefault: true,
        wasAmbiguous: true
      )
    }
    let equalBest = viable.filter {
      $0.consistentRecords == best.consistentRecords
        && $0.modalFieldCount == best.modalFieldCount
    }
    return CSVDelimiterDetection(
      delimiter: best.delimiter,
      evidence: evidence,
      usedDefault: false,
      wasAmbiguous: equalBest.count > 1
    )
  }

  private func isWorse(
    _ lhs: CSVDelimiterCandidateEvidence,
    _ rhs: CSVDelimiterCandidateEvidence
  ) -> Bool {
    if lhs.consistentRecords != rhs.consistentRecords {
      return lhs.consistentRecords < rhs.consistentRecords
    }
    if lhs.modalFieldCount != rhs.modalFieldCount {
      return lhs.modalFieldCount < rhs.modalFieldCount
    }
    return priority(lhs.delimiter) < priority(rhs.delimiter)
  }

  private func priority(_ delimiter: CSVDelimiter) -> Int {
    switch delimiter.byte {
    case CSVDelimiter.comma.byte: 4
    case CSVDelimiter.tab.byte: 3
    case CSVDelimiter.semicolon.byte: 2
    case CSVDelimiter.pipe.byte: 1
    default: 0
    }
  }

  private func score(
    _ delimiter: CSVDelimiter,
    in data: Data
  ) -> CSVDelimiterCandidateEvidence {
    let limit = min(data.count, Self.maximumBytes)
    var arities: [Int] = []
    arities.reserveCapacity(Self.maximumRecords)
    var fields = 1
    var fieldStart = true
    var quoted = false
    var afterQuote = false
    var index = data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF ? 3 : 0

    while index < limit, arities.count < Self.maximumRecords {
      let byte = data[index]
      if quoted {
        if byte == 0x22 {
          if index + 1 < limit, data[index + 1] == 0x22 {
            index += 2
            continue
          }
          quoted = false
          afterQuote = true
        }
        index += 1
        continue
      }
      if fieldStart, byte == 0x22 {
        quoted = true
        fieldStart = false
        index += 1
        continue
      }
      if byte == delimiter.byte {
        fields += 1
        fieldStart = true
        afterQuote = false
        index += 1
        continue
      }
      if byte == 0x0A || byte == 0x0D {
        arities.append(fields)
        fields = 1
        fieldStart = true
        afterQuote = false
        if byte == 0x0D, index + 1 < limit, data[index + 1] == 0x0A {
          index += 2
        } else {
          index += 1
        }
        continue
      }
      if afterQuote {
        // The real parser will issue the useful diagnostic. A malformed
        // candidate cannot accumulate a misleadingly strong score.
        break
      }
      fieldStart = false
      index += 1
    }
    if index == data.count, !quoted, arities.count < Self.maximumRecords,
      data.isEmpty || fields > 1 || !fieldStart
    {
      arities.append(fields)
    }

    var counts: [Int: Int] = [:]
    for arity in arities where arity > 1 { counts[arity, default: 0] += 1 }
    let modal = counts.max {
      if $0.value == $1.value { return $0.key < $1.key }
      return $0.value < $1.value
    }
    return CSVDelimiterCandidateEvidence(
      delimiter: delimiter,
      sampledRecords: arities.count,
      consistentRecords: modal?.value ?? 0,
      modalFieldCount: modal?.key ?? 0
    )
  }
}

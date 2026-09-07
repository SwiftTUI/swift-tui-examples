import Foundation

/// Prepared once per row, rather than allocating and parsing during every comparison.
///
/// The key keeps its text as a contiguous `String` and borrows those UTF-8
/// bytes during comparison, so a prepared row costs its text plus one fixed
/// record and never allocates a per-row scalar array. UTF-8 byte order equals
/// Unicode scalar order, so text keeps the documented scalar ordering with
/// natural ASCII digit runs.
struct CSVSortKey {
  let text: String
  let number: Decimal?

  init(_ value: String) {
    var text = value
    // Makes the storage contiguous once, so later borrowed comparisons never
    // copy, and classifies the complete string as a numeric literal.
    let isNumber = text.withUTF8(Self.isNumber)
    self.text = text
    number = isNumber ? Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) : nil
  }

  var isEmpty: Bool { text.isEmpty }
  /// UTF-8 bytes the key retains. Inline small strings are still counted.
  var storageBytes: Int { text.utf8.count }

  func compare(to other: Self) -> ComparisonResult {
    // A distinct numeric category keeps mixed signed numbers/text transitive.
    switch (number, other.number) {
    case (.some(let left), .some(let right)):
      return left == right ? .orderedSame : left < right ? .orderedAscending : .orderedDescending
    case (.some, .none): return .orderedAscending
    case (.none, .some): return .orderedDescending
    case (.none, .none): break
    }
    var lhs = text
    var rhs = other.text
    return lhs.withUTF8 { left in
      rhs.withUTF8 { right in
        Self.compareText(left, right)
      }
    }
  }

  private static let zero = UInt8(ascii: "0")

  private static func compareText(
    _ lhs: UnsafeBufferPointer<UInt8>,
    _ rhs: UnsafeBufferPointer<UInt8>
  ) -> ComparisonResult {
    var left = 0
    var right = 0
    while left < lhs.count, right < rhs.count {
      if isDigit(lhs[left]), isDigit(rhs[right]) {
        var leftEnd = left
        var rightEnd = right
        while leftEnd < lhs.count, isDigit(lhs[leftEnd]) { leftEnd += 1 }
        while rightEnd < rhs.count, isDigit(rhs[rightEnd]) { rightEnd += 1 }
        var leftStart = left
        var rightStart = right
        while leftStart < leftEnd, lhs[leftStart] == zero { leftStart += 1 }
        while rightStart < rightEnd, rhs[rightStart] == zero { rightStart += 1 }
        let leftCount = leftEnd - leftStart
        let rightCount = rightEnd - rightStart
        if leftCount != rightCount {
          return leftCount < rightCount ? .orderedAscending : .orderedDescending
        }
        for offset in 0..<leftCount {
          let leftByte = lhs[leftStart + offset]
          let rightByte = rhs[rightStart + offset]
          if leftByte != rightByte {
            return leftByte < rightByte ? .orderedAscending : .orderedDescending
          }
        }
        if leftEnd - left != rightEnd - right {
          return leftEnd - left < rightEnd - right ? .orderedAscending : .orderedDescending
        }
        left = leftEnd
        right = rightEnd
      } else {
        if lhs[left] != rhs[right] {
          return lhs[left] < rhs[right] ? .orderedAscending : .orderedDescending
        }
        left += 1
        right += 1
      }
    }
    if left == lhs.count, right == rhs.count { return .orderedSame }
    return left == lhs.count ? .orderedAscending : .orderedDescending
  }

  private static func isDigit(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
  }

  private static func isNumber(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
    let plus = UInt8(ascii: "+")
    let minus = UInt8(ascii: "-")
    let dot = UInt8(ascii: ".")
    let lowerE = UInt8(ascii: "e")
    let upperE = UInt8(ascii: "E")
    var index = 0
    if index < bytes.count, bytes[index] == plus || bytes[index] == minus { index += 1 }
    let integerStart = index
    while index < bytes.count, isDigit(bytes[index]) { index += 1 }
    var digits = index - integerStart
    if index < bytes.count, bytes[index] == dot {
      index += 1
      let fractionStart = index
      while index < bytes.count, isDigit(bytes[index]) { index += 1 }
      digits += index - fractionStart
    }
    guard digits > 0 else { return false }
    if index < bytes.count, bytes[index] == lowerE || bytes[index] == upperE {
      index += 1
      if index < bytes.count, bytes[index] == plus || bytes[index] == minus { index += 1 }
      let exponentStart = index
      while index < bytes.count, isDigit(bytes[index]) { index += 1 }
      guard index > exponentStart else { return false }
    }
    return index == bytes.count
  }
}

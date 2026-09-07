import Foundation

/// Prepared once per row, rather than allocating and parsing during every comparison.
struct CSVSortKey {
  let scalars: [Unicode.Scalar]
  let number: Decimal?

  init(_ value: String) {
    scalars = Array(value.unicodeScalars)
    number =
      Self.isNumber(scalars)
      ? Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) : nil
  }

  var isEmpty: Bool { scalars.isEmpty }
  var storageBytes: Int { scalars.count * MemoryLayout<Unicode.Scalar>.stride }

  func compare(to other: Self) -> ComparisonResult {
    // A distinct numeric category keeps mixed signed numbers/text transitive.
    switch (number, other.number) {
    case (.some(let left), .some(let right)):
      return left == right ? .orderedSame : left < right ? .orderedAscending : .orderedDescending
    case (.some, .none): return .orderedAscending
    case (.none, .some): return .orderedDescending
    case (.none, .none): break
    }
    var left = 0
    var right = 0
    while left < scalars.count, right < other.scalars.count {
      if Self.isDigit(scalars[left]), Self.isDigit(other.scalars[right]) {
        var leftEnd = left
        var rightEnd = right
        while leftEnd < scalars.count, Self.isDigit(scalars[leftEnd]) { leftEnd += 1 }
        while rightEnd < other.scalars.count, Self.isDigit(other.scalars[rightEnd]) {
          rightEnd += 1
        }
        var leftStart = left
        var rightStart = right
        while leftStart < leftEnd, scalars[leftStart] == "0" { leftStart += 1 }
        while rightStart < rightEnd, other.scalars[rightStart] == "0" { rightStart += 1 }
        let leftCount = leftEnd - leftStart
        let rightCount = rightEnd - rightStart
        if leftCount != rightCount {
          return leftCount < rightCount ? .orderedAscending : .orderedDescending
        }
        for offset in 0..<leftCount {
          let lhs = scalars[leftStart + offset].value
          let rhs = other.scalars[rightStart + offset].value
          if lhs != rhs { return lhs < rhs ? .orderedAscending : .orderedDescending }
        }
        if leftEnd - left != rightEnd - right {
          return leftEnd - left < rightEnd - right ? .orderedAscending : .orderedDescending
        }
        left = leftEnd
        right = rightEnd
      } else {
        if scalars[left] != other.scalars[right] {
          return scalars[left].value < other.scalars[right].value
            ? .orderedAscending : .orderedDescending
        }
        left += 1
        right += 1
      }
    }
    if left == scalars.count, right == other.scalars.count { return .orderedSame }
    return left == scalars.count ? .orderedAscending : .orderedDescending
  }

  private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
    (48...57).contains(scalar.value)
  }

  private static func isNumber(_ scalars: [Unicode.Scalar]) -> Bool {
    var index = 0
    if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" { index += 1 }
    let integerStart = index
    while index < scalars.count, isDigit(scalars[index]) { index += 1 }
    var digits = index - integerStart
    if index < scalars.count, scalars[index] == "." {
      index += 1
      let fractionStart = index
      while index < scalars.count, isDigit(scalars[index]) { index += 1 }
      digits += index - fractionStart
    }
    guard digits > 0 else { return false }
    if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
      index += 1
      if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" { index += 1 }
      let exponentStart = index
      while index < scalars.count, isDigit(scalars[index]) { index += 1 }
      guard index > exponentStart else { return false }
    }
    return index == scalars.count
  }
}

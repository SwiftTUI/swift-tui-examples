public import Foundation

public struct BuiltInPreviewFormatter: Sendable {
  public static let maximumReadBytes = 256 * 1_024
  public static let requestedReadBytes = maximumReadBytes + 1
  public static let classificationByteLimit = 8 * 1_024
  public static let hexadecimalByteLimit = 4 * 1_024

  public init() {}

  /// Classifies the first `classificationByteLimit` bytes of `data`.
  ///
  /// When `data` continues past that sample, a scalar the sample boundary
  /// splits is trimmed before validation: it is cut, not ill-formed.
  public func classify(_ data: Data) -> PreviewContentClassification {
    let sample = data.prefix(Self.classificationByteLimit)
    return decide(sample, continues: data.count > sample.count).classification
  }

  func format(prefix: FilePrefix) -> BuiltInPreviewBody {
    let bounded = Data(prefix.data.prefix(Self.maximumReadBytes))
    let readWasTruncated =
      prefix.isTruncated || prefix.data.count > Self.maximumReadBytes

    // Text versus binary is decided on the whole capped read, and the text
    // shown is exactly the payload that passed strict validation.
    switch decide(bounded[...], continues: readWasTruncated) {
    case .text(let encoding, let payload):
      return .text(
        TextPreview(
          text: decodeText(payload, encoding: encoding),
          encoding: encoding,
          isTruncated: readWasTruncated
        )
      )
    case .binary:
      let bytes = Array(bounded.prefix(Self.hexadecimalByteLimit))
      return .hexadecimal(
        HexPreview(
          formatted: formatHex(bytes),
          renderedByteCount: bytes.count,
          isTruncated: readWasTruncated || bounded.count > bytes.count
        )
      )
    }
  }

  private enum Decision {
    /// Strictly valid text; `payload` excludes the byte order mark and any
    /// scalar the end of the bytes cut.
    case text(PreviewTextEncoding, payload: Data.SubSequence)
    case binary

    var classification: PreviewContentClassification {
      switch self {
      case .text(let encoding, _): .text(encoding)
      case .binary: .binary
      }
    }
  }

  /// Decides text versus binary for `bytes`. `continues` says the content
  /// goes on past `bytes`, so an incomplete scalar at the end was cut there.
  private func decide(_ bytes: Data.SubSequence, continues: Bool) -> Decision {
    // UTF-32 marks first: `FF FE 00 00` also starts with the UTF-16LE mark.
    // UTF-32 is not a preview text encoding (Unicode 23.8, Table 23-4).
    if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00])
      || bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF])
    {
      return .binary
    }
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
      let payload = trimmingCutUTF8(bytes.dropFirst(3), continues: continues)
      return isStrictUTF8(payload) ? .text(.utf8, payload: payload) : .binary
    }
    if bytes.starts(with: [0xFF, 0xFE]) {
      return decideUTF16(bytes.dropFirst(2), byteOrder: .little, continues: continues)
    }
    if bytes.starts(with: [0xFE, 0xFF]) {
      return decideUTF16(bytes.dropFirst(2), byteOrder: .big, continues: continues)
    }
    let payload = trimmingCutUTF8(bytes, continues: continues)
    guard !payload.contains(0), isStrictUTF8(payload) else {
      return .binary
    }
    return .text(.utf8, payload: payload)
  }

  private func decideUTF16(
    _ bytes: Data.SubSequence,
    byteOrder: ByteOrder,
    continues: Bool
  ) -> Decision {
    var payload = bytes
    if continues {
      // A cut can leave half a code unit, then a high surrogate whose low
      // surrogate is past the cut.
      if !payload.count.isMultiple(of: 2) {
        payload = payload.dropLast()
      }
      if payload.count >= 2 {
        let last = payload.suffix(2)
        let unit = codeUnit(
          last[last.startIndex], last[last.index(after: last.startIndex)], byteOrder)
        if (0xD800...0xDBFF).contains(unit) {
          payload = payload.dropLast(2)
        }
      }
    }
    let (validation, encoding): (String.Encoding, PreviewTextEncoding) =
      switch byteOrder {
      case .little: (.utf16LittleEndian, .utf16LittleEndian)
      case .big: (.utf16BigEndian, .utf16BigEndian)
      }
    guard payload.count.isMultiple(of: 2),
      String(data: Data(payload), encoding: validation) != nil
    else {
      return .binary
    }
    return .text(encoding, payload: payload)
  }

  private func isStrictUTF8(_ bytes: Data.SubSequence) -> Bool {
    String(data: Data(bytes), encoding: .utf8) != nil
  }

  /// Drops a trailing proper prefix of a well-formed UTF-8 sequence (Unicode
  /// 3.9, Table 3-7) when the content continues past `bytes`. Bytes that
  /// cannot begin a well-formed sequence are kept, so they still fail
  /// validation.
  private func trimmingCutUTF8(
    _ bytes: Data.SubSequence,
    continues: Bool
  ) -> Data.SubSequence {
    guard continues else {
      return bytes
    }
    var leadIndex = bytes.endIndex
    var continuationCount = 0
    while leadIndex > bytes.startIndex, continuationCount <= 3 {
      leadIndex = bytes.index(before: leadIndex)
      guard bytes[leadIndex] & 0xC0 == 0x80 else {
        break
      }
      continuationCount += 1
    }
    guard leadIndex < bytes.endIndex, bytes[leadIndex] & 0xC0 != 0x80 else {
      return bytes
    }
    let lead = bytes[leadIndex]
    let length: Int
    var secondByteRange: ClosedRange<UInt8> = 0x80...0xBF
    switch lead {
    case 0xC2...0xDF: length = 2
    case 0xE0: (length, secondByteRange) = (3, 0xA0...0xBF)
    case 0xE1...0xEC, 0xEE...0xEF: length = 3
    case 0xED: (length, secondByteRange) = (3, 0x80...0x9F)
    case 0xF0: (length, secondByteRange) = (4, 0x90...0xBF)
    case 0xF1...0xF3: length = 4
    case 0xF4: (length, secondByteRange) = (4, 0x80...0x8F)
    default: return bytes
    }
    guard continuationCount + 1 < length else {
      return bytes
    }
    if continuationCount > 0,
      !secondByteRange.contains(bytes[bytes.index(after: leadIndex)])
    {
      return bytes
    }
    return bytes[bytes.startIndex..<leadIndex]
  }

  private func decodeText(
    _ payload: Data.SubSequence,
    encoding: PreviewTextEncoding
  ) -> String {
    switch encoding {
    case .utf8:
      String(decoding: payload, as: UTF8.self)
    case .utf16LittleEndian:
      decodeUTF16(payload, byteOrder: .little)
    case .utf16BigEndian:
      decodeUTF16(payload, byteOrder: .big)
    }
  }

  private enum ByteOrder {
    case little
    case big
  }

  private func codeUnit(_ first: UInt8, _ second: UInt8, _ byteOrder: ByteOrder) -> UInt16 {
    switch byteOrder {
    case .little:
      UInt16(first) | (UInt16(second) << 8)
    case .big:
      (UInt16(first) << 8) | UInt16(second)
    }
  }

  private func decodeUTF16(
    _ bytes: Data.SubSequence,
    byteOrder: ByteOrder
  ) -> String {
    var codeUnits: [UInt16] = []
    codeUnits.reserveCapacity(bytes.count / 2)
    var index = bytes.startIndex
    while index < bytes.endIndex {
      let next = bytes.index(after: index)
      guard next < bytes.endIndex else {
        break
      }
      codeUnits.append(codeUnit(bytes[index], bytes[next], byteOrder))
      index = bytes.index(after: next)
    }
    return String(decoding: codeUnits, as: UTF16.self)
  }

  private func formatHex(_ bytes: [UInt8]) -> String {
    guard !bytes.isEmpty else {
      return ""
    }

    var lines: [String] = []
    lines.reserveCapacity((bytes.count + 15) / 16)
    for offset in stride(from: 0, to: bytes.count, by: 16) {
      let line = Array(bytes[offset..<min(offset + 16, bytes.count)])
      var groups: [String] = []
      groups.reserveCapacity(16)
      for index in 0..<16 {
        if index < line.count {
          groups.append(paddedHex(UInt64(line[index]), width: 2))
        } else {
          groups.append("  ")
        }
      }
      let left = groups[0..<8].joined(separator: " ")
      let right = groups[8..<16].joined(separator: " ")
      let ascii = line.map { byte -> Character in
        guard byte >= 0x20, byte <= 0x7E else {
          return "."
        }
        return Character(UnicodeScalar(byte))
      }
      lines.append(
        "\(paddedHex(UInt64(offset), width: 8))  \(left)  \(right)  |\(String(ascii))|"
      )
    }
    return lines.joined(separator: "\n")
  }

  private func paddedHex(_ value: UInt64, width: Int) -> String {
    let digits = String(value, radix: 16)
    guard digits.count < width else {
      return digits
    }
    return String(repeating: "0", count: width - digits.count) + digits
  }
}

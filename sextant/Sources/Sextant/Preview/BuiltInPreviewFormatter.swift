public import Foundation

public struct BuiltInPreviewFormatter: Sendable {
  public static let maximumReadBytes = 256 * 1_024
  public static let requestedReadBytes = maximumReadBytes + 1
  public static let classificationByteLimit = 8 * 1_024
  public static let hexadecimalByteLimit = 4 * 1_024

  public init() {}

  public func classify(_ data: Data) -> PreviewContentClassification {
    let sample = Data(data.prefix(Self.classificationByteLimit))
    if sample.starts(with: [0xEF, 0xBB, 0xBF]) {
      let payload = sample.dropFirst(3)
      if String(data: payload, encoding: .utf8) != nil {
        return .text(.utf8)
      }
      return .binary
    }
    if sample.starts(with: [0xFF, 0xFE]) {
      let payload = sample.dropFirst(2)
      if payload.count.isMultiple(of: 2),
        String(data: payload, encoding: .utf16LittleEndian) != nil
      {
        return .text(.utf16LittleEndian)
      }
      return .binary
    }
    if sample.starts(with: [0xFE, 0xFF]) {
      let payload = sample.dropFirst(2)
      if payload.count.isMultiple(of: 2),
        String(data: payload, encoding: .utf16BigEndian) != nil
      {
        return .text(.utf16BigEndian)
      }
      return .binary
    }
    if sample.contains(0) {
      return .binary
    }
    guard String(data: sample, encoding: .utf8) != nil else {
      return .binary
    }
    return .text(.utf8)
  }

  func format(prefix: FilePrefix) -> BuiltInPreviewBody {
    let bounded = Data(prefix.data.prefix(Self.maximumReadBytes))
    let readWasTruncated =
      prefix.isTruncated || prefix.data.count > Self.maximumReadBytes

    switch classify(bounded) {
    case .text(let encoding):
      return .text(
        TextPreview(
          text: decodeText(bounded, encoding: encoding),
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

  private func decodeText(
    _ data: Data,
    encoding: PreviewTextEncoding
  ) -> String {
    switch encoding {
    case .utf8:
      let payload =
        data.starts(with: [0xEF, 0xBB, 0xBF])
        ? data.dropFirst(3)
        : data[...]
      return String(decoding: payload, as: UTF8.self)
    case .utf16LittleEndian:
      return decodeUTF16(data.dropFirst(2), byteOrder: .little)
    case .utf16BigEndian:
      return decodeUTF16(data.dropFirst(2), byteOrder: .big)
    }
  }

  private enum ByteOrder {
    case little
    case big
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
      let first = UInt16(bytes[index])
      let second = UInt16(bytes[next])
      switch byteOrder {
      case .little:
        codeUnits.append(first | (second << 8))
      case .big:
        codeUnits.append((first << 8) | second)
      }
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

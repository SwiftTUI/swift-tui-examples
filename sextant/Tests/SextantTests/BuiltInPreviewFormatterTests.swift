import Foundation
import Testing

@testable import Sextant

@Suite("Built-in preview formatting")
struct BuiltInPreviewFormatterTests {
  private let formatter = BuiltInPreviewFormatter()

  @Test("strict UTF-8 is text")
  func strictUTF8() {
    let data = Data("hello, Sextant\n".utf8)
    #expect(formatter.classify(data) == .text(.utf8))
    #expect(
      formatter.format(
        prefix: FilePrefix(
          data: data,
          totalByteCount: UInt64(data.count),
          isTruncated: false
        )
      )
        == .text(
          TextPreview(
            text: "hello, Sextant\n",
            encoding: .utf8,
            isTruncated: false
          )
        )
    )
  }

  @Test(
    "BOM text is classified before the NUL heuristic",
    arguments: [
      (
        Data([0xEF, 0xBB, 0xBF] + Array("hello".utf8)),
        PreviewTextEncoding.utf8,
        "hello"
      ),
      (
        Data([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]),
        PreviewTextEncoding.utf16LittleEndian,
        "hi"
      ),
      (
        Data([0xFE, 0xFF, 0x00, 0x68, 0x00, 0x69]),
        PreviewTextEncoding.utf16BigEndian,
        "hi"
      ),
    ])
  func byteOrderMarks(
    data: Data,
    encoding: PreviewTextEncoding,
    expected: String
  ) {
    #expect(formatter.classify(data) == .text(encoding))
    guard
      case .text(let text) =
        formatter.format(
          prefix: FilePrefix(
            data: data,
            totalByteCount: UInt64(data.count),
            isTruncated: false
          )
        )
    else {
      Issue.record("expected text preview")
      return
    }
    #expect(text.encoding == encoding)
    #expect(text.text == expected)
  }

  @Test("invalid UTF-8 and NUL select hexadecimal preview")
  func binaryClassification() {
    let invalid = Data([0xC3, 0x28])
    let nul = Data([0x61, 0x00, 0x62])
    #expect(formatter.classify(invalid) == .binary)
    #expect(formatter.classify(nul) == .binary)
  }

  @Test("empty files remain useful text previews")
  func emptyFile() {
    #expect(formatter.classify(Data()) == .text(.utf8))
    #expect(
      formatter.format(
        prefix: FilePrefix(
          data: Data(),
          totalByteCount: 0,
          isTruncated: false
        )
      )
        == .text(
          TextPreview(text: "", encoding: .utf8, isTruncated: false)
        )
    )
  }

  @Test("read and hexadecimal output are bounded")
  func byteLimits() {
    let data = Data(repeating: 0, count: BuiltInPreviewFormatter.requestedReadBytes)
    guard
      case .hexadecimal(let preview) =
        formatter.format(
          prefix: FilePrefix(
            data: data,
            totalByteCount: UInt64(data.count),
            isTruncated: true
          )
        )
    else {
      Issue.record("expected hexadecimal preview")
      return
    }
    #expect(
      BuiltInPreviewFormatter.requestedReadBytes
        == BuiltInPreviewFormatter.maximumReadBytes + 1
    )
    #expect(
      preview.renderedByteCount
        == BuiltInPreviewFormatter.hexadecimalByteLimit
    )
    #expect(preview.isTruncated)
    #expect(preview.formatted.hasPrefix("00000000"))
    #expect(preview.formatted.contains("00000ff0"))
    #expect(!preview.formatted.contains("00001000"))
  }

  @Test("text truncation is explicit")
  func textTruncation() {
    let data = Data(
      repeating: Character("a").asciiValue!,
      count: BuiltInPreviewFormatter.requestedReadBytes
    )
    guard
      case .text(let preview) =
        formatter.format(
          prefix: FilePrefix(
            data: data,
            totalByteCount: UInt64(data.count),
            isTruncated: true
          )
        )
    else {
      Issue.record("expected text preview")
      return
    }
    #expect(preview.text.utf8.count == BuiltInPreviewFormatter.maximumReadBytes)
    #expect(preview.isTruncated)
  }
}

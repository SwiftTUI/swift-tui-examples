import Foundation

public struct HeadingSlugger: Sendable {
  private var counts: [String: Int] = [:]

  public init() {}

  public mutating func slug(for text: String) -> String {
    let folded = text.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    let scalars = folded.unicodeScalars.map { scalar -> Character in
      if CharacterSet.alphanumerics.contains(scalar) || scalar.properties.isEmojiPresentation {
        return Character(String(scalar))
      }
      if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "-" || scalar == "_" {
        return "-"
      }
      return "\0"
    }
    let base =
      String(scalars.filter { $0 != "\0" })
      .split(separator: "-", omittingEmptySubsequences: true)
      .joined(separator: "-")
      .lowercased()
    let normalized = base.isEmpty ? "section" : base
    let occurrence = counts[normalized, default: 0]
    counts[normalized] = occurrence + 1
    return occurrence == 0 ? normalized : "\(normalized)-\(occurrence)"
  }
}

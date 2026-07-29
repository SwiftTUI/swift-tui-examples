// Cluster-width behavior adapted from grok-mermaid width.ts at commit 6be6507;
// substantially modified to use Swift Character and explicit ambiguous-width policy.

enum MermaidUnicodeWidth {
  static func width(
    of character: Character,
    ambiguousWidth: MermaidAmbiguousWidth
  ) -> Int {
    let scalars = character.unicodeScalars
    if scalars.isEmpty { return 0 }

    var result = 0
    var regionalIndicators = 0
    var emojiPresentation = false
    var keycap = false

    for scalar in scalars {
      let value = scalar.value
      let scalarWidth = MermaidUnicodeWidthData.width(
        of: value,
        policy: ambiguousWidth
      )
      if scalarWidth == 0 {
        if value == 0xFE0F { emojiPresentation = true }
        if value == 0x20E3 { keycap = true }
        continue
      }
      if (0x1F1E6...0x1F1FF).contains(value) {
        regionalIndicators += 1
      }
      if scalar.properties.isEmojiPresentation {
        emojiPresentation = true
      }
      result = max(result, scalarWidth)
    }

    if regionalIndicators >= 2 || emojiPresentation || keycap {
      return 2
    }
    return result
  }

  static func displayWidth(
    of text: String,
    ambiguousWidth: MermaidAmbiguousWidth
  ) -> Int {
    text.reduce(into: 0) { result, character in
      result += width(of: character, ambiguousWidth: ambiguousWidth)
    }
  }

  static func containsBidiControl(_ source: String) -> Bool {
    source.unicodeScalars.contains { scalar in
      switch scalar.value {
      case 0x061C, 0x200E...0x200F, 0x202A...0x202E, 0x2066...0x2069:
        true
      default:
        false
      }
    }
  }

  static func containsStrongRTL(_ source: String) -> Bool {
    source.unicodeScalars.contains { scalar in
      MermaidUnicodeBidiData.isStrongRightToLeft(scalar.value)
    }
  }

  static func containsRejectedControl(_ source: String) -> Bool {
    source.unicodeScalars.contains { scalar in
      let value = scalar.value
      if value == 0x0A || value == 0x0D || value == 0x09 {
        return false
      }
      return value < 0x20
        || (0x7F...0x9F).contains(value)
        || (0x2028...0x2029).contains(value)
    }
  }

  static func containsStandaloneZeroWidthCharacter(_ source: String) -> Bool {
    source.contains { character in
      if character == "\n" || character == "\r" || character == "\t" {
        return false
      }
      return width(of: character, ambiguousWidth: .narrow) == 0
    }
  }
}

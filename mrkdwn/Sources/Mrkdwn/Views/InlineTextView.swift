import Foundation

public import SwiftTUI

struct InlineTextView: View {
  struct HighlightedSegment {
    var runIndex: Int
    var text: String
    var highlighted: Bool
  }

  var runs: [InlineRun]
  var theme: ViewerTheme
  var baseColor: Color?
  var bold = false
  var searchQuery: String?

  var body: some View {
    Text(content)
  }

  private var content: Text.RichContent {
    var interpolation = Text.StringInterpolation(
      literalCapacity: runs.reduce(0) { $0 + $1.text.count },
      interpolationCount: runs.count
    )
    for segment in Self.highlightedSegments(
      runs: runs,
      searchQuery: searchQuery
    ) {
      let run = runs[segment.runIndex]
      let text = styledText(
        run,
        source: segment.text,
        highlighted: segment.highlighted
      )
      if let destination = run.destination, !destination.isEmpty {
        interpolation.appendInterpolation(
          Link(text, destination: LinkDestination(destination))
        )
      } else {
        interpolation.appendInterpolation(text)
      }
    }
    return Text.RichContent(stringInterpolation: interpolation)
  }

  private func styledText(
    _ run: InlineRun,
    source: String,
    highlighted: Bool
  ) -> Text {
    var text = Text(source)
      .foregroundStyle(
        highlighted
          ? theme.searchMatch.swiftTUIColor
          : run.destination == nil
            ? (baseColor ?? theme.foreground.swiftTUIColor)
            : theme.link.swiftTUIColor
      )
      .bold(bold || run.traits.contains(.strong))
      .italic(run.traits.contains(.emphasis))
      .strikethrough(run.traits.contains(.strikethrough))
    if run.traits.contains(.code) {
      text =
        text
        .foregroundStyle(theme.codeForeground.swiftTUIColor)
        .cellBackground(theme.codeBackground.swiftTUIColor)
    }
    if run.traits.contains(.html) {
      text = text.foregroundStyle(theme.muted.swiftTUIColor)
    }
    if highlighted {
      text =
        text
        .foregroundStyle(theme.searchMatch.swiftTUIColor)
        .reverse()
    }
    return text
  }

  static func highlightedSegments(
    runs: [InlineRun],
    searchQuery: String?
  ) -> [HighlightedSegment] {
    guard let searchQuery, !searchQuery.isEmpty else {
      return runs.enumerated().map {
        HighlightedSegment(runIndex: $0.offset, text: $0.element.text, highlighted: false)
      }
    }

    var result: [HighlightedSegment] = []
    result.reserveCapacity(
      min(
        runs.count + (SearchIndex.maximumRetainedMatches * 2),
        2_048
      )
    )
    var remainingMatchBudget = SearchIndex.maximumRetainedMatches
    for (runIndex, run) in runs.enumerated() {
      let resultStart = result.count
      var remainder = run.text.startIndex..<run.text.endIndex
      while remainingMatchBudget > 0,
        let match = run.text.range(
          of: searchQuery,
          options: [.caseInsensitive, .diacriticInsensitive],
          range: remainder
        )
      {
        if remainder.lowerBound < match.lowerBound {
          result.append(
            HighlightedSegment(
              runIndex: runIndex,
              text: String(run.text[remainder.lowerBound..<match.lowerBound]),
              highlighted: false
            )
          )
        }
        result.append(
          HighlightedSegment(
            runIndex: runIndex,
            text: String(run.text[match]),
            highlighted: true
          )
        )
        remainingMatchBudget -= 1
        guard match.upperBound < run.text.endIndex else {
          remainder = run.text.endIndex..<run.text.endIndex
          break
        }
        remainder = match.upperBound..<run.text.endIndex
      }
      if remainder.lowerBound < remainder.upperBound {
        result.append(
          HighlightedSegment(
            runIndex: runIndex,
            text: String(run.text[remainder]),
            highlighted: false
          )
        )
      }
      if result.count == resultStart {
        result.append(
          HighlightedSegment(
            runIndex: runIndex,
            text: run.text,
            highlighted: false
          )
        )
      }
    }
    return result
  }
}

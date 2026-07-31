import Foundation
import Synchronization

public import SwiftTUI

/// Memoizes search-highlight segmentation per (runs, query).
///
/// The segmentation runs a case- and diacritic-insensitive `range(of:)` (an
/// ICU scan) per run per body evaluation whenever a query is active — per
/// notch for re-resolving table cells, and once per block per keystroke while
/// typing (S6, org plan 2026-07-31-001). Content addressing keeps the cache
/// sound by construction across models and documents (table cells have no
/// per-cell identity to key by), and hashing a run array is nanoseconds
/// against the ICU scan it replaces.
final class InlineHighlightCache: Sendable {
  struct Statistics: Equatable, Sendable {
    var entryCount: Int
    var computationCount: Int
    var hitCount: Int
    var evictionCount: Int
  }

  private struct Key: Hashable, Sendable {
    var runs: [InlineRun]
    var query: String
  }

  private struct Entry: Sendable {
    var segments: [InlineTextView.HighlightedSegment]
    var lastUse: UInt64
  }

  private struct State: Sendable {
    var entries: [Key: Entry] = [:]
    var useCounter: UInt64 = 0
    var computationCount = 0
    var hitCount = 0
    var evictionCount = 0
  }

  static let shared = InlineHighlightCache(capacity: 4_096)

  private let capacity: Int
  private let state = Mutex(State())

  init(capacity: Int) {
    self.capacity = max(1, capacity)
  }

  var statistics: Statistics {
    state.withLock { state in
      Statistics(
        entryCount: state.entries.count,
        computationCount: state.computationCount,
        hitCount: state.hitCount,
        evictionCount: state.evictionCount
      )
    }
  }

  func segments(
    runs: [InlineRun],
    searchQuery: String?
  ) -> [InlineTextView.HighlightedSegment] {
    guard let searchQuery, !searchQuery.isEmpty else {
      // No query means no ICU work — identity segmentation is cheaper than
      // the lookup, and caching it would just flush the highlighted entries.
      return InlineTextView.highlightedSegments(runs: runs, searchQuery: nil)
    }
    let key = Key(runs: runs, query: searchQuery)
    return state.withLock { state in
      state.useCounter &+= 1
      if var cached = state.entries[key] {
        state.hitCount += 1
        cached.lastUse = state.useCounter
        state.entries[key] = cached
        return cached.segments
      }
      let segments = InlineTextView.highlightedSegments(
        runs: runs,
        searchQuery: searchQuery
      )
      state.computationCount += 1
      if state.entries.count == capacity,
        let evicted = state.entries.min(by: { $0.value.lastUse < $1.value.lastUse })?.key
      {
        state.entries.removeValue(forKey: evicted)
        state.evictionCount += 1
      }
      state.entries[key] = Entry(segments: segments, lastUse: state.useCounter)
      return segments
    }
  }
}

struct InlineTextView: View {
  struct HighlightedSegment: Equatable, Sendable {
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
    for segment in InlineHighlightCache.shared.segments(
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
        .backgroundStyle(theme.codeBackground.swiftTUIColor)
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

  nonisolated static func highlightedSegments(
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

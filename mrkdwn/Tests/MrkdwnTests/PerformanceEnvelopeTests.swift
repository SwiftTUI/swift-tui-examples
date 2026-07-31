import Foundation
import SwiftTUI
import Synchronization
import Testing

@testable import Mrkdwn

/// The wall-clock budgets in this suite are calibrated for a quiet developer
/// machine. Shared CI runners are slower and contended, so enforcing them there
/// reports hardware noise as a product regression. Budget *enforcement* is
/// therefore opt-in via `MRKDWN_PERFORMANCE_BUDGETS=1`; every structural
/// assertion still runs everywhere, and the measured durations are always
/// printed so CI logs remain a usable performance record.
let mrkdwnPerformanceBudgetsEnforced =
  ProcessInfo.processInfo.environment["MRKDWN_PERFORMANCE_BUDGETS"] != nil

/// Asserts `elapsed` against two tiers.
///
///   - `ceiling` is always enforced. Breaching it means an order-of-magnitude
///     regression — a lost cache, an accidental O(n²) — which no machine class
///     explains. Ceilings sit at ~5× their budget: observed CI runners land
///     2–3× slower than the calibration machine and the regressions worth
///     catching are 10×+, so 5× separates the two with margin on both sides. A
///     measurement whose absolute scale lets scheduler jitter dominate gets a
///     wider ceiling, justified at its call site.
///   - `budget` is the calibrated number, enforced only under
///     ``mrkdwnPerformanceBudgetsEnforced``.
func expectWithinPerformanceBudget(
  _ elapsed: Duration,
  _ budget: Duration,
  ceiling: Duration,
  _ label: String,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(
    elapsed < ceiling,
    "\(label) took \(elapsed), past the \(ceiling) machine-independent ceiling",
    sourceLocation: sourceLocation
  )
  guard mrkdwnPerformanceBudgetsEnforced else { return }
  #expect(
    elapsed < budget,
    "\(label) took \(elapsed), over the \(budget) budget",
    sourceLocation: sourceLocation
  )
}

@Suite("performance envelope", .serialized)
struct PerformanceEnvelopeTests {
  @Test("one MiB ten-thousand-block document compiles within the checked budget")
  func largeDocument() {
    let padding = String(repeating: "reader content ", count: 7)
    let source = (0..<10_000)
      .map { "paragraph \($0) \(padding)" }
      .joined(separator: "\n\n")
    #expect(source.utf8.count >= 1_048_576)

    let clock = ContinuousClock()
    let start = clock.now
    let document = MarkdownCompiler().compile(source: source, sourceURL: nil)
    let elapsed = start.duration(to: clock.now)

    print("1 MiB compile baseline: \(elapsed)")
    #expect(document.blocks.count == 10_000)
    expectWithinPerformanceBudget(
      elapsed,
      .milliseconds(200),
      ceiling: .milliseconds(1_000),
      "1 MiB compile"
    )
  }

  @MainActor
  @Test("five-hundred-by-twenty table compiles, measures, and renders within checked budgets")
  func largeTable() {
    let header = "| " + (0..<20).map { "Column \($0)" }.joined(separator: " | ") + " |"
    let separator = "|" + (0..<20).map { _ in " --- " }.joined(separator: "|") + "|"
    let rows = (0..<500).map { row in
      "| " + (0..<20).map { "r\(row)c\($0)" }.joined(separator: " | ") + " |"
    }
    let source = ([header, separator] + rows).joined(separator: "\n")

    let clock = ContinuousClock()
    let start = clock.now
    let document = MarkdownCompiler().compile(source: source, sourceURL: nil)
    let compileElapsed = start.duration(to: clock.now)

    guard case .table(_, let table, _)? = document.blocks.first else {
      Issue.record("Expected one compiled table")
      return
    }
    #expect(table.header.count == 20)
    #expect(table.rows.count == 500)

    let measurementStart = clock.now
    let metrics = MarkdownTableLayout.metrics(for: table)
    let measurementElapsed = measurementStart.duration(to: clock.now)

    let documentScrollPosition = Mutex(ScrollPosition.zero)
    let documentScrollBinding = Binding(
      get: { documentScrollPosition.withLock { $0 } },
      set: { next in documentScrollPosition.withLock { $0 = next } }
    )
    let tableScrollPosition = Mutex(ScrollPosition.zero)
    let tableScrollBinding = Binding(
      get: { tableScrollPosition.withLock { $0 } },
      set: { next in tableScrollPosition.withLock { $0 = next } }
    )
    let renderer = DefaultRenderer()
    let renderStart = clock.now
    let artifacts = renderer.render(
      VStack(alignment: .leading, spacing: 0) {
        Text("mrkdwn")
        Divider()
        ScrollView(
          .vertical,
          showsIndicators: true,
          position: documentScrollBinding
        ) {
          MarkdownTableView(
            table: table,
            theme: .default,
            searchQuery: nil,
            offeredWidth: 80,
            tableTop: 0,
            documentScrollOffset: documentScrollPosition.withLock { $0.y },
            viewportHeight: 20,
            horizontalScrollPosition: tableScrollBinding
          )
        }
        .frame(width: 80, height: 20, alignment: .topLeading)
        Divider()
        Text("status")
      }
      .frame(width: 80, height: 24, alignment: .topLeading),
      context: .init(identity: Identity(components: [.named("LargeMarkdownTable")])),
      proposal: ProposedSize(width: 80, height: 24)
    )
    let renderElapsed = renderStart.duration(to: clock.now)
    let renderedText = artifacts.rasterSurface.lines.joined(separator: "\n")

    documentScrollPosition.withLock { $0.scrollBy(y: 100) }
    tableScrollPosition.withLock { $0.scrollBy(x: 40) }
    let scrollStart = clock.now
    let scrolledArtifacts = renderer.render(
      VStack(alignment: .leading, spacing: 0) {
        Text("mrkdwn")
        Divider()
        ScrollView(
          .vertical,
          showsIndicators: true,
          position: documentScrollBinding
        ) {
          MarkdownTableView(
            table: table,
            theme: .default,
            searchQuery: nil,
            offeredWidth: 80,
            tableTop: 0,
            documentScrollOffset: documentScrollPosition.withLock { $0.y },
            viewportHeight: 20,
            horizontalScrollPosition: tableScrollBinding
          )
        }
        .frame(width: 80, height: 20, alignment: .topLeading)
        Divider()
        Text("status")
      }
      .frame(width: 80, height: 24, alignment: .topLeading),
      context: .init(identity: Identity(components: [.named("LargeMarkdownTable")])),
      proposal: ProposedSize(width: 80, height: 24)
    )
    let scrollElapsed = scrollStart.duration(to: clock.now)
    let scrolledText = scrolledArtifacts.rasterSurface.lines.joined(separator: "\n")
    let initiallyVisibleRows = Set(
      renderedText.matches(of: /r(\d+)c\d+/).compactMap { Int($0.1) }
    )
    let scrolledVisibleRows = Set(
      scrolledText.matches(of: /r(\d+)c\d+/).compactMap { Int($0.1) }
    )
    let initialRoutes = artifacts.semanticSnapshot.scrollRoutes
    let initialVerticalRoutes = initialRoutes.filter {
      $0.contentBounds.size.height > $0.viewportRect.size.height
    }
    let initialHorizontalOnlyRoutes = initialRoutes.filter {
      $0.contentBounds.size.width > $0.viewportRect.size.width
        && $0.contentBounds.size.height <= $0.viewportRect.size.height
    }

    print(
      "500x20 table baseline: compile=\(compileElapsed), "
        + "measure=\(measurementElapsed), render=\(renderElapsed), "
        + "scroll=\(scrollElapsed), "
        + "resolved=\(artifacts.diagnostics.counts.resolvedNodes), "
        + "measured=\(artifacts.diagnostics.counts.measuredNodes), "
        + "placed=\(artifacts.diagnostics.counts.placedNodes), "
        + "draw=\(artifacts.diagnostics.counts.drawNodes), "
        + "scrolledResolved=\(scrolledArtifacts.diagnostics.counts.resolvedNodes), "
        + "scrolledMeasured=\(scrolledArtifacts.diagnostics.counts.measuredNodes), "
        + "scrolledPlaced=\(scrolledArtifacts.diagnostics.counts.placedNodes), "
        + "scrolledDraw=\(scrolledArtifacts.diagnostics.counts.drawNodes), "
        + "visibleRows=\(initiallyVisibleRows.count), "
        + "scrolledVisibleRows=\(scrolledVisibleRows.count)"
    )
    #expect(metrics.columnWidths.count == 20)
    #expect(metrics.totalHeight == 502)
    #expect(renderedText.contains("Column 0"))
    #expect(renderedText.contains("r0c0"))
    #expect(!scrolledText.contains("r0c0"))
    #expect(scrolledText.contains("r98c"))
    #expect(initiallyVisibleRows.contains(0))
    #expect(initiallyVisibleRows.count <= 20)
    #expect(scrolledVisibleRows.contains(98))
    #expect(scrolledVisibleRows.count <= 20)
    #expect(documentScrollPosition.withLock { $0.y } == 100)
    #expect(tableScrollPosition.withLock { $0.x } == 40)
    #expect(tableScrollPosition.withLock { $0.y } == 0)
    #expect(initialVerticalRoutes.count == 1)
    #expect(initialHorizontalOnlyRoutes.count == 1)
    #expect(artifacts.diagnostics.counts.resolvedNodes < 1_250)
    #expect(artifacts.diagnostics.counts.measuredNodes < 1_250)
    #expect(artifacts.diagnostics.counts.placedNodes < 1_250)
    #expect(artifacts.diagnostics.counts.drawNodes < 1_250)
    #expect(scrolledArtifacts.diagnostics.counts.resolvedNodes < 1_250)
    #expect(scrolledArtifacts.diagnostics.counts.measuredNodes < 1_250)
    #expect(scrolledArtifacts.diagnostics.counts.placedNodes < 1_250)
    #expect(scrolledArtifacts.diagnostics.counts.drawNodes < 1_250)
    expectWithinPerformanceBudget(
      compileElapsed,
      .milliseconds(130),
      ceiling: .milliseconds(650),
      "table compile"
    )
    expectWithinPerformanceBudget(
      measurementElapsed,
      .milliseconds(300),
      ceiling: .milliseconds(1_500),
      "table measurement"
    )
    expectWithinPerformanceBudget(
      renderElapsed,
      .milliseconds(1_230),
      ceiling: .milliseconds(6_150),
      "table render"
    )
    expectWithinPerformanceBudget(
      scrollElapsed,
      .milliseconds(1_700),
      ceiling: .milliseconds(8_500),
      "table scroll"
    )
  }
}

import Foundation
import Testing

@testable import Mrkdwn

extension PerformanceEnvelopeTests {
  @MainActor
  @Test("ten-thousand-block geometry and repeated scroll updates stay within checked budgets")
  func largeDocumentScrollingGeometry() async {
    let source = (0..<10_000)
      .map { index in
        index.isMultiple(of: 100)
          ? "## Heading \(index)"
          : "paragraph \(index) with enough content to exercise terminal layout"
      }
      .joined(separator: "\n\n")
    let model = ViewerModel(
      snapshot: DocumentSnapshot(
        source: source,
        url: nil,
        displayName: "geometry.md"
      ),
      theme: .default,
      watchesDocument: false,
      allowsRemoteImages: false
    )
    await model.start()

    let clock = ContinuousClock()
    let firstGeometryStart = clock.now
    model.updateDocumentScrollOffset(1)
    let firstGeometryElapsed = firstGeometryStart.duration(to: clock.now)

    let repeatedScrollStart = clock.now
    for offset in 2...1_001 {
      model.updateDocumentScrollOffset(offset)
    }
    let repeatedScrollElapsed = repeatedScrollStart.duration(to: clock.now)

    print(
      "10000-block geometry baseline: first=\(firstGeometryElapsed), "
        + "1000-scroll-updates=\(repeatedScrollElapsed)"
    )
    #expect(model.renderedGeometryComputationCount == 1)
    expectWithinPerformanceBudget(
      firstGeometryElapsed,
      .milliseconds(1_200),
      "first geometry pass"
    )
    expectWithinPerformanceBudget(
      repeatedScrollElapsed,
      .microseconds(1_500),
      "1000 scroll updates"
    )
    await model.shutdown()
  }
}

import Testing

@testable import Sextant

@Suite("Browser layout policy")
struct BrowserLayoutPolicyTests {
  private let policy = BrowserLayoutPolicy()

  @Test(
    "visible work is independent of trail depth",
    arguments: [1, 3, 20, 200])
  func boundedVisibleColumns(depth: Int) {
    let decision = policy.decision(
      width: 200,
      trailCount: depth,
      activeIndex: max(0, depth - 1),
      hasPreview: true,
      previewFocused: false
    )
    #expect(decision.visibleDirectoryIndices.count <= 2)
    #expect(decision.showsPreview)
  }

  @Test("wide layout pairs the active column with the one it was entered from")
  func wideLayoutLooksBackwards() {
    // The model keeps a prefetched node past the active column for the
    // selected directory. It must not be composed: advancing into a directory
    // is the user's call, so the second column is the parent, never the child.
    #expect(
      policy.decision(
        width: 86,
        trailCount: 3,
        activeIndex: 1,
        hasPreview: false,
        previewFocused: false
      ).visibleDirectoryIndices == [0, 1]
    )
    #expect(
      policy.decision(
        width: 86,
        trailCount: 2,
        activeIndex: 0,
        hasPreview: false,
        previewFocused: false
      ).visibleDirectoryIndices == [0]
    )
  }

  @Test("middle layout uses one browser column and preview")
  func middleLayout() {
    let decision = policy.decision(
      width: 63,
      trailCount: 200,
      activeIndex: 119,
      hasPreview: true,
      previewFocused: false
    )
    #expect(decision.visibleDirectoryIndices == [119])
    #expect(decision.mode == .browserAndPreview)
    #expect(decision.showsPreview)
  }

  @Test("narrow layout switches between browser and preview")
  func narrowLayout() {
    let browser = policy.decision(
      width: 60,
      trailCount: 20,
      activeIndex: 19,
      hasPreview: true,
      previewFocused: false
    )
    #expect(browser.visibleDirectoryIndices == [19])
    #expect(!browser.showsPreview)

    let preview = policy.decision(
      width: 60,
      trailCount: 20,
      activeIndex: 19,
      hasPreview: true,
      previewFocused: true
    )
    #expect(preview.visibleDirectoryIndices.isEmpty)
    #expect(preview.showsPreview)
  }

  @Test("acceptance widths select the documented modes")
  func acceptanceWidths() {
    #expect(
      policy.decision(
        width: 60,
        trailCount: 1,
        activeIndex: 0,
        hasPreview: true,
        previewFocused: false
      ).mode == .singleSurface
    )
    #expect(
      policy.decision(
        width: 100,
        trailCount: 1,
        activeIndex: 0,
        hasPreview: true,
        previewFocused: false
      ).mode == .twoBrowsersAndPreview
    )
    #expect(
      policy.decision(
        width: 140,
        trailCount: 1,
        activeIndex: 0,
        hasPreview: true,
        previewFocused: false
      ).mode == .twoBrowsersAndPreview
    )
    #expect(
      policy.decision(
        width: 200,
        trailCount: 1,
        activeIndex: 0,
        hasPreview: true,
        previewFocused: false
      ).mode == .twoBrowsersAndPreview
    )
  }

  @Test(
    "layout breakpoints keep surface counts bounded",
    arguments: [
      (62, BrowserLayoutDecision.Mode.singleSurface, 1, false),
      (63, BrowserLayoutDecision.Mode.browserAndPreview, 1, true),
      (85, BrowserLayoutDecision.Mode.browserAndPreview, 1, true),
      (86, BrowserLayoutDecision.Mode.twoBrowsersAndPreview, 2, true),
    ])
  func breakpointBoundaries(
    width: Int,
    mode: BrowserLayoutDecision.Mode,
    browserCount: Int,
    showsPreview: Bool
  ) {
    let decision = policy.decision(
      width: width,
      trailCount: 5,
      activeIndex: 3,
      hasPreview: true,
      previewFocused: false
    )

    #expect(decision.mode == mode)
    #expect(decision.visibleDirectoryIndices.count == browserCount)
    #expect(decision.showsPreview == showsPreview)
  }
}

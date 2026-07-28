public struct BrowserLayoutPolicy: Equatable, Sendable {
  public static let browserMinimumWidth = 22
  public static let previewMinimumWidth = 40
  public static let separatorWidth = 1
  public static let twoColumnBreakpoint = 86
  public static let splitBreakpoint = 63

  public init() {}

  public func decision(
    width: Int,
    trailCount: Int,
    activeIndex: Int,
    hasPreview: Bool,
    previewFocused: Bool
  ) -> BrowserLayoutDecision {
    let count = max(0, trailCount)
    let active =
      count == 0
      ? 0
      : min(max(activeIndex, 0), count - 1)

    if width < Self.splitBreakpoint {
      return BrowserLayoutDecision(
        visibleDirectoryIndices: previewFocused && hasPreview ? [] : [active],
        showsPreview: previewFocused && hasPreview,
        mode: .singleSurface
      )
    }

    if width < Self.twoColumnBreakpoint {
      return BrowserLayoutDecision(
        visibleDirectoryIndices: count == 0 ? [] : [active],
        showsPreview: true,
        mode: .browserAndPreview
      )
    }

    // Only columns that have actually been entered are shown. The model still
    // appends and prefetches the selected directory's node so `→` is instant
    // and the preview's counts are real, but showing that node here would put
    // a directory on screen before the user asked to go there — so the wide
    // layout looks backwards, at the column we came from, never forwards.
    var visible: [Int] = []
    if count > 0 {
      visible = active > 0 ? [active - 1, active] : [active]
    }
    return BrowserLayoutDecision(
      visibleDirectoryIndices: visible,
      showsPreview: true,
      mode: .twoBrowsersAndPreview
    )
  }
}

public struct BrowserLayoutDecision: Equatable, Sendable {
  public enum Mode: Equatable, Sendable {
    case singleSurface
    case browserAndPreview
    case twoBrowsersAndPreview
  }

  public var visibleDirectoryIndices: [Int]
  public var showsPreview: Bool
  public var mode: Mode

  public init(
    visibleDirectoryIndices: [Int],
    showsPreview: Bool,
    mode: Mode
  ) {
    self.visibleDirectoryIndices = visibleDirectoryIndices
    self.showsPreview = showsPreview
    self.mode = mode
  }
}

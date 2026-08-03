public import Foundation

public struct ViewerSize: Equatable, Hashable, Sendable {
  private static let documentHorizontalPadding = 2
  private static let verticalScrollIndicatorWidth = 1
  private static let inlineOutlineWidth = 28
  private static let inlineOutlineDividerWidth = 1

  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = max(0, width)
    self.height = max(0, height)
  }

  public var documentWidth: Int {
    documentWidth(showsInlineOutline: width >= 120)
  }

  public var documentFrameWidth: Int {
    documentFrameWidth(showsInlineOutline: width >= 120)
  }

  public func documentWidth(showsInlineOutline: Bool) -> Int {
    max(
      1,
      documentFrameWidth(showsInlineOutline: showsInlineOutline)
        - Self.documentHorizontalPadding
        - Self.verticalScrollIndicatorWidth
    )
  }

  public func documentFrameWidth(showsInlineOutline: Bool) -> Int {
    let inlineOutlineChrome =
      showsInlineOutline
      ? Self.inlineOutlineWidth + Self.inlineOutlineDividerWidth
      : 0
    return max(1, width - inlineOutlineChrome)
  }

  public var documentHeight: Int {
    max(1, height - 4)
  }
}

public struct ViewerDiagnostic: Equatable, Sendable {
  public enum Severity: Equatable, Sendable {
    case information
    case warning
    case error
  }

  public var severity: Severity
  public var message: String

  public init(_ severity: Severity, _ message: String) {
    self.severity = severity
    self.message = message
  }
}

public enum ImagePresentation: Equatable, Sendable {
  case loading(resolvedURL: URL?)
  case ready(LoadedImage)
  case blocked(resolvedURL: URL?, hint: String)
  case failed(resolvedURL: URL?, diagnostic: String)
  case terminalFallback(resolvedURL: URL?, diagnostic: String)
}

public struct ViewerState: Equatable, Sendable {
  public var snapshot: DocumentSnapshot
  public var document: CompiledDocument?
  public var theme: ViewerTheme
  public var viewport: ViewerSize
  public var outlineVisible: Bool
  public var helpVisible: Bool
  public var searchVisible: Bool
  public var searchQuery: String
  public var searchMatches: [SearchMatch]
  public var searchResultsTruncated: Bool
  public var isSearching: Bool
  public var selectedSearchMatch: Int?
  public var canGoBack: Bool
  public var canGoForward: Bool
  public var diagnostic: ViewerDiagnostic?
  public var isReloading: Bool
  public var contentRevision: UInt64

  public var showsInlineOutline: Bool {
    viewport.width >= 120 && outlineVisible
  }

  public var documentWidth: Int {
    viewport.documentWidth(showsInlineOutline: showsInlineOutline)
  }

  public var documentFrameWidth: Int {
    viewport.documentFrameWidth(showsInlineOutline: showsInlineOutline)
  }

  public init(
    snapshot: DocumentSnapshot,
    theme: ViewerTheme,
    viewport: ViewerSize = ViewerSize(width: 80, height: 24)
  ) {
    self.snapshot = snapshot
    document = nil
    self.theme = theme
    self.viewport = viewport
    outlineVisible = viewport.width >= 120
    helpVisible = false
    searchVisible = false
    searchQuery = ""
    searchMatches = []
    searchResultsTruncated = false
    isSearching = false
    selectedSearchMatch = nil
    canGoBack = false
    canGoForward = false
    diagnostic = nil
    isReloading = false
    contentRevision = 0
  }
}

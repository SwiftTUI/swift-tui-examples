public import Foundation

public struct ViewerSize: Equatable, Hashable, Sendable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = max(0, width)
    self.height = max(0, height)
  }

  public var documentWidth: Int {
    // Resource proposals describe the cells inside the document's horizontal
    // padding, not the padded scroll-view frame. Use every cell left after
    // the shell and, on wide terminals, the inline outline.
    max(1, (width >= 120 ? width - 32 : width - 4) - 2)
  }

  public var documentFrameWidth: Int {
    documentWidth + 2
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

public enum MermaidPaintRole: Equatable, Hashable, Sendable {
  case background
  case border
  case text
  case edge
  case edgeLabel
  case title
  case unknown
}

public struct MermaidPaintCell: Equatable, Sendable {
  public var character: Character
  public var spanWidth: Int
  public var continuationLeadX: Int?
  public var role: MermaidPaintRole

  public init(
    character: Character = " ",
    spanWidth: Int = 1,
    continuationLeadX: Int? = nil,
    role: MermaidPaintRole = .background
  ) {
    self.character = character
    self.spanWidth = spanWidth
    self.continuationLeadX = continuationLeadX
    self.role = role
  }
}

public struct RenderedMermaid: Equatable, Sendable {
  public var width: Int
  public var height: Int
  public var cells: [[MermaidPaintCell]]
  public var diagnostics: [String]
  public var isPartial: Bool

  public init(
    width: Int,
    height: Int,
    cells: [[MermaidPaintCell]],
    diagnostics: [String] = [],
    isPartial: Bool = false
  ) {
    self.width = width
    self.height = height
    self.cells = cells
    self.diagnostics = diagnostics
    self.isPartial = isPartial
  }
}

public enum MermaidPresentation: Equatable, Sendable {
  case pending
  case ready(RenderedMermaid)
  case reflowing(RenderedMermaid)
  case unavailable(diagnostic: String)
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
  public var revealedMermaidSources: Set<BlockID>
  public var canGoBack: Bool
  public var canGoForward: Bool
  public var diagnostic: ViewerDiagnostic?
  public var isReloading: Bool
  public var contentRevision: UInt64

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
    revealedMermaidSources = []
    canGoBack = false
    canGoForward = false
    diagnostic = nil
    isReloading = false
    contentRevision = 0
  }
}

import Foundation
import SwiftTUITerminal

struct DirectoryRequestID: Hashable, Sendable {
  let rawValue: UInt64
}

struct PreviewGeneration: Hashable, Sendable {
  let rawValue: UInt64
}

struct DirectoryFilter: Equatable, Sendable {
  var query = ""
}

enum BrowserOverlay: Equatable, Sendable {
  case none
  case filter
  case help
  case palette
  case search
}

enum BrowserStatus: Equatable, Sendable {
  case none
  case message(String)
  case failure(String)
}

enum DirectoryRefreshState: Equatable, Sendable {
  case loading(DirectoryRequestID)
  case failed(FileSystemFailure)
}

struct BrowserSearchState: Equatable, Sendable {
  var query = ""
  var generation: FilenameSearchGeneration?
  var results: [FilenameSearchResult] = []
  var isSearching = false
  var wasTruncated = false
}

enum BrowserDirectoryState: Equatable, Sendable {
  case notRequested
  case loading(DirectoryRequestID)
  case loaded(DirectorySnapshot)
  case empty(DirectorySnapshot)
  case stale(snapshot: DirectorySnapshot, refresh: DirectoryRefreshState)
  case failed(FileSystemFailure)

  var snapshot: DirectorySnapshot? {
    switch self {
    case .loaded(let snapshot), .empty(let snapshot), .stale(let snapshot, _):
      snapshot
    case .notRequested, .loading, .failed:
      nil
    }
  }
}

struct BrowserTrailNode: Equatable, Sendable {
  var id: DirectoryID
  var url: URL
  var directory: BrowserDirectoryState
  var selectedItemID: BrowserItemID?
}

struct SelectionAnchor: Equatable, Sendable {
  var itemID: BrowserItemID
  var url: URL
  var sortedIndex: Int
}

enum PreviewState {
  case welcome
  case loading(item: BrowserItem, generation: PreviewGeneration)
  case builtIn(item: BrowserItem, generation: PreviewGeneration, preview: BuiltInPreview)
  case external(ExternalPreviewState)
  case unavailable(
    item: BrowserItem,
    generation: PreviewGeneration,
    reason: PreviewUnavailableReason
  )
  case failed(
    item: BrowserItem,
    generation: PreviewGeneration,
    adapter: String?,
    failure: PreviewFailure,
    fallback: BuiltInPreview?
  )

  var item: BrowserItem? {
    switch self {
    case .welcome:
      nil
    case .loading(let item, _),
      .builtIn(let item, _, _),
      .unavailable(let item, _, _),
      .failed(let item, _, _, _, _):
      item
    case .external(let preview):
      preview.item
    }
  }

  var generation: PreviewGeneration? {
    switch self {
    case .welcome:
      nil
    case .loading(_, let generation),
      .builtIn(_, let generation, _),
      .unavailable(_, let generation, _),
      .failed(_, let generation, _, _, _):
      generation
    case .external(let preview):
      preview.generation
    }
  }
}

struct ExternalPreviewState: Sendable {
  var item: BrowserItem
  var generation: PreviewGeneration
  var adapterName: String
  var status: ExternalPreviewStatus
  var handle: PreviewSessionHandle
  var fallback: BuiltInPreview?
}

enum ExternalPreviewStatus: Equatable, Sendable {
  case starting
  case ready
  case slow
  case exited(TerminalExitReason)
}

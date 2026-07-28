import Foundation

enum SelectionMovement: Equatable, Sendable {
  case offset(Int)
  case first
  case last
}

enum BrowserAction: Sendable {
  case start
  case moveSelection(SelectionMovement)
  case selectItem(directoryID: DirectoryID, itemID: BrowserItemID)
  case advanceIntoSelected
  case enterSelected
  case moveToParent
  case focusPreview
  case focusBrowser
  case activatePreviewFallback
  case runtimeFocusChanged(BrowserFocus?)
  case setVisibleDirectoryWindow([DirectoryID])
  case refresh
  case setHidden(Bool)
  case setSort(DirectorySort)
  case showFilter
  case setFilter(String)
  case showHelp
  case showPalette
  case showSearch
  case setSearchQuery(String)
  case searchResponse(FilenameSearchEvent)
  case activateSearchResult(Int)
  case jumpToPath(String)
  case toggleBookmark
  case bookmarkResponse(path: String, isBookmarked: Bool?)
  case performHandoff(BrowserHandoffCommand)
  case handoffResponse(
    command: BrowserHandoffCommand,
    itemName: String,
    result: Result<Void, HandoffFailure>
  )
  case reportStatus(BrowserStatus)
  case filesystemChanged(DirectoryWatchEvent)
  case reloadAfterInvalidation(DirectoryID)
  case directoryResponse(
    request: DirectoryRequest,
    result: Result<DirectorySnapshot, FileSystemFailure>
  )
  case previewResponse(PreviewModelEvent)
  case dismissOverlay
}

enum BrowserHandoffCommand: Equatable, Sendable {
  case open
  case edit
  case reveal
  case copyAbsolutePath
  case copyRelativePath
}

enum BrowserHandoffRequest: Equatable, Sendable {
  case open(URL)
  case edit(command: [String], url: URL)
  case reveal(URL)
  case copy(String)
}

enum PreviewModelEvent: Sendable {
  case builtIn(
    item: BrowserItem,
    generation: PreviewGeneration,
    preview: BuiltInPreview
  )
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
  case cleared(PreviewGeneration)
}

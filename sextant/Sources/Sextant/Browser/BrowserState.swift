import Foundation

struct BrowserState {
  var root: URL
  var trail: [BrowserTrailNode]
  var activeDirectoryID: DirectoryID
  var focus: BrowserFocus
  var filter: DirectoryFilter
  var policy: DirectoryPolicy
  var preview: PreviewState
  var overlay: BrowserOverlay
  var status: BrowserStatus
  var hasSeenHelp: Bool
  var search: BrowserSearchState
  var bookmarks: [String]
  var recents: [String]

  var activeDirectory: BrowserTrailNode? {
    trail.first { $0.id == activeDirectoryID }
  }

  var activeDirectoryIndex: Int? {
    trail.firstIndex { $0.id == activeDirectoryID }
  }

  var selectedItem: BrowserItem? {
    guard let directory = activeDirectory,
      let selectedItemID = directory.selectedItemID
    else {
      return nil
    }
    return directory.directory.snapshot?.items.first { $0.id == selectedItemID }
  }
}

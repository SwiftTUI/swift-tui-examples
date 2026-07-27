import Foundation

struct DirectoryID: Hashable, Sendable {
  var url: URL

  init(_ url: URL) {
    self.url = url.standardizedFileURL
  }
}

enum BrowserFocus: Hashable, Sendable {
  case browser(DirectoryID)
  case preview
  case filter
  case help
  case palette
}

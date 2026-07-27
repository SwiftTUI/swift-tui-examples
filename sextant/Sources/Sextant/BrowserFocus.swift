import Foundation

enum BrowserFocus: Hashable, Sendable {
  case browser(DirectoryID)
  case preview
  case filter
  case help
  case palette
}

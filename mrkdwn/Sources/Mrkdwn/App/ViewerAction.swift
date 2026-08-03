public enum ViewerAction: Equatable, Sendable {
  case openDestination(String)
  case scrollToHeading(BlockID)
  case nextHeading
  case previousHeading
  case beginSearch
  case endSearch
  case updateSearch(String)
  case nextMatch
  case previousMatch
  case reload
  case toggleOutline
  case toggleHelp
  case goBack
  case goForward
  case dismissError
  case clearScrollTarget
}

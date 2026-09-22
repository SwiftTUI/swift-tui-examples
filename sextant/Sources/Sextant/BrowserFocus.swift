import Foundation

enum BrowserFocus: Hashable, Sendable {
  case browser(DirectoryID)
  case preview
  case filter
  case help
  case palette
}

/// A model-authored focus request remains authoritative until the runtime
/// acknowledges it. Replacing a focus member can publish an intermediate
/// fallback to the browser; mirroring that fallback would cancel the request
/// and route the next child key to the browser (STUI-534).
struct BrowserFocusSynchronization: Equatable {
  enum Feedback: Equatable {
    case ignore
    case request(BrowserFocus)
    case publish(BrowserFocus?)
  }

  private(set) var pending: BrowserFocus?

  mutating func request(_ focus: BrowserFocus, current: BrowserFocus?) {
    pending = current == focus ? nil : focus
  }

  mutating func observe(_ observed: BrowserFocus?, current: BrowserFocus?) -> Feedback {
    // A newer authored write can supersede an onChange snapshot before its
    // callback runs. Only acknowledge the live value.
    guard observed == current else { return .ignore }
    if let pending {
      guard observed == pending else { return .request(pending) }
      self.pending = nil
    }
    return .publish(observed)
  }
}

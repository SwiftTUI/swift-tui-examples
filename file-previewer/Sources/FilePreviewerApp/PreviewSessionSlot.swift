@MainActor
public final class PreviewSessionSlot<Session: AnyObject & Sendable> {
  public typealias Termination = @Sendable (Session) -> Void

  private let terminate: Termination
  public private(set) var current: Session?

  public init(terminate: @escaping Termination) {
    self.terminate = terminate
  }

  deinit {
    if let current {
      terminate(current)
    }
  }

  public func replace(with next: Session?) {
    guard current !== next else {
      return
    }
    let previous = current
    current = next
    if let previous {
      terminate(previous)
    }
  }

  public func clear() {
    replace(with: nil)
  }
}

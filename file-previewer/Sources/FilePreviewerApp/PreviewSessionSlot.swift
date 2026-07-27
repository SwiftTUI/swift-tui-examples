@MainActor
public final class PreviewSessionSlot<Session: AnyObject & Sendable> {
  public typealias Termination = @Sendable (Session) async -> Void

  private enum Phase {
    case accepting
    case shuttingDown
    case shutDown
  }

  private let terminate: Termination
  private var operationTail: Task<Void, Never>?
  private var operationGeneration: UInt64 = 0
  private var phase: Phase = .accepting
  public private(set) var current: Session?

  public init(terminate: @escaping Termination) {
    self.terminate = terminate
  }

  deinit {
    guard let current else {
      return
    }
    let terminate = terminate
    let operationTail = operationTail
    Task {
      await operationTail?.value
      await terminate(current)
    }
  }

  /// Publishes `next` only after the previously published session has exited.
  ///
  /// Replacements are serialized so two child sessions can never overlap.
  /// Once shutdown begins, new sessions are rejected and terminated in that
  /// same serialized queue.
  @discardableResult
  public func replace(with next: Session?) async -> Bool {
    let precedingOperation = operationTail
    let operation = Task { @MainActor [weak self] () -> Bool in
      await precedingOperation?.value
      guard let self else {
        return false
      }
      guard self.phase == .accepting else {
        if let next {
          await self.terminate(next)
        }
        return false
      }
      guard self.current !== next else {
        return true
      }
      let previous = self.current
      self.current = nil
      if let previous {
        await self.terminate(previous)
      }
      guard self.phase == .accepting else {
        if let next {
          await self.terminate(next)
        }
        return false
      }
      self.current = next
      return true
    }
    appendToTail(operation)
    return await operation.value
  }

  public func clear() async {
    _ = await replace(with: nil)
  }

  public func shutdown() async {
    if phase == .accepting {
      phase = .shuttingDown
      let precedingOperation = operationTail
      let operation = Task { @MainActor [weak self] in
        await precedingOperation?.value
        guard let self else {
          return
        }
        let current = self.current
        self.current = nil
        if let current {
          await self.terminate(current)
        }
      }
      appendToTail(operation)
    }
    await waitForPendingTerminations()
    phase = .shutDown
  }

  func waitForPendingTerminations() async {
    while let operationTail {
      let generation = operationGeneration
      await operationTail.value
      guard generation == operationGeneration else {
        continue
      }
      self.operationTail = nil
    }
  }

  private func appendToTail<Value>(_ operation: Task<Value, Never>) {
    operationGeneration &+= 1
    operationTail = Task {
      _ = await operation.value
    }
  }
}

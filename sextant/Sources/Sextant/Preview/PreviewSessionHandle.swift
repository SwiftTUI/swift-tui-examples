public import Foundation
public import SwiftTUI
public import SwiftTUITerminalView

public final class PreviewSessionHandle: Sendable, Identifiable {
  public typealias Start = @Sendable () async throws -> Void
  public typealias Terminate = @Sendable (_ signal: Int32) async -> Void
  public typealias Lifecycle = @Sendable () async -> TerminalLifecycle

  public let id: UUID
  // Preserve the concrete conformance when TerminalSession gains capabilities.
  public let terminal: any TerminalSession

  private let startValue: Start
  private let terminateValue: Terminate
  private let lifecycleValue: Lifecycle

  public init<Session: TerminalSession>(
    id: UUID = UUID(),
    terminal: Session,
    start: @escaping Start,
    terminate: @escaping Terminate,
    lifecycle: @escaping Lifecycle
  ) {
    self.id = id
    self.terminal = terminal
    startValue = start
    terminateValue = terminate
    lifecycleValue = lifecycle
  }

  public func start() async throws {
    try await startValue()
  }

  public func terminate(signal: Int32 = 15) async {
    await terminateValue(signal)
  }

  public func lifecycle() async -> TerminalLifecycle {
    await lifecycleValue()
  }

  public func waitForExit(timeout: Duration?) async -> TerminalExitReason? {
    let clock = ContinuousClock()
    let deadline = timeout.map { clock.now + $0 }
    while deadline.map({ clock.now < $0 }) ?? true {
      if case .exited(let reason) = await lifecycleValue() {
        return reason
      }
      do {
        try await clock.sleep(for: .milliseconds(10))
      } catch {
        return nil
      }
    }
    if case .exited(let reason) = await lifecycleValue() {
      return reason
    }
    return nil
  }
}

extension PreviewSessionHandle {
  public static func process(
    launch: PreviewLaunch,
    initialSize: CellSize = CellSize(width: 80, height: 40)
  ) -> PreviewSessionHandle {
    let session = TerminalProcessSession(
      command: launch.executable,
      arguments: launch.arguments,
      initialSize: initialSize
    )
    return PreviewSessionHandle(
      terminal: session,
      start: { try await session.start() },
      terminate: { await session.terminate(signal: $0) },
      lifecycle: { await session.currentLifecycle() }
    )
  }
}

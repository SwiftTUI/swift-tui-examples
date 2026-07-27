public import Foundation
public import SwiftTUI
public import SwiftTUITerminal

public final class AnyTerminalSession: TerminalSession, @unchecked Sendable {
  private let snapshotValue: @Sendable () -> ForeignGrid
  private let startValue: @Sendable () async throws -> Void
  private let snapshotAsyncValue: @Sendable () async -> ForeignGrid
  private let titleValue: @Sendable () async -> String?
  private let workingDirectoryValue: @Sendable () async -> String?
  private let lifecycleValue: @Sendable () async -> TerminalLifecycle
  private let sendKeyValue: @Sendable (TerminalEmulatorKey) async -> Void
  private let sendPasteValue: @Sendable (String) async -> Void
  private let sendMouseValue: @Sendable (TerminalEmulatorMouse) async -> Void
  private let resizeValue: @Sendable (CellSize) async throws -> Void
  private let eventsValue: @Sendable () -> AsyncStream<TerminalEmulatorEvent>

  public init<Session: TerminalSession>(_ session: Session) {
    snapshotValue = { session.cachedSnapshot }
    startValue = { try await session.start() }
    snapshotAsyncValue = { await session.snapshot() }
    titleValue = { await session.currentTitle() }
    workingDirectoryValue = { await session.currentWorkingDirectory() }
    lifecycleValue = { await session.currentLifecycle() }
    sendKeyValue = { await session.send(key: $0) }
    sendPasteValue = { await session.send(paste: $0) }
    sendMouseValue = { await session.send(mouse: $0) }
    resizeValue = { try await session.resize($0) }
    eventsValue = { session.events() }
  }

  public var cachedSnapshot: ForeignGrid {
    snapshotValue()
  }

  public func start() async throws {
    try await startValue()
  }

  public func snapshot() async -> ForeignGrid {
    await snapshotAsyncValue()
  }

  public func currentTitle() async -> String? {
    await titleValue()
  }

  public func currentWorkingDirectory() async -> String? {
    await workingDirectoryValue()
  }

  public func currentLifecycle() async -> TerminalLifecycle {
    await lifecycleValue()
  }

  public func send(key: TerminalEmulatorKey) async {
    await sendKeyValue(key)
  }

  public func send(paste: String) async {
    await sendPasteValue(paste)
  }

  public func send(mouse: TerminalEmulatorMouse) async {
    await sendMouseValue(mouse)
  }

  public func resize(_ size: CellSize) async throws {
    try await resizeValue(size)
  }

  public func events() -> AsyncStream<TerminalEmulatorEvent> {
    eventsValue()
  }
}

public final class PreviewSessionHandle: @unchecked Sendable, Identifiable {
  public typealias Start = @Sendable () async throws -> Void
  public typealias Terminate = @Sendable (_ signal: Int32) async -> Void
  public typealias Lifecycle = @Sendable () async -> TerminalLifecycle

  public let id: UUID
  public let terminal: AnyTerminalSession

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
    self.terminal = AnyTerminalSession(terminal)
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

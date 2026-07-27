public import Foundation
public import SwiftTUITerminal

public struct PreviewClock: Sendable {
  public var sleep: @Sendable (Duration) async throws -> Void

  public init(
    sleep: @escaping @Sendable (Duration) async throws -> Void
  ) {
    self.sleep = sleep
  }

  public static let continuous = PreviewClock { duration in
    try await ContinuousClock().sleep(for: duration)
  }
}

public struct PreviewProcessClient: Sendable {
  public var makeSession: @Sendable (_ launch: PreviewLaunch) async throws -> PreviewSessionHandle

  public init(
    makeSession:
      @escaping @Sendable (_ launch: PreviewLaunch) async throws -> PreviewSessionHandle
  ) {
    self.makeSession = makeSession
  }

  public static let live = PreviewProcessClient { launch in
    PreviewSessionHandle.process(launch: launch)
  }
}

public enum PreviewLaunchFailure: Equatable, Sendable {
  case missingExecutable
  case startup(String)
}

public enum PreviewCoordinatorEvent: Sendable {
  case builtIn(generation: UInt64, preview: BuiltInPreview)
  case starting(
    generation: UInt64,
    launch: PreviewLaunch,
    handle: PreviewSessionHandle,
    fallback: BuiltInPreview
  )
  case ready(generation: UInt64, handleID: UUID)
  case slow(generation: UInt64, handleID: UUID)
  case exited(
    generation: UInt64,
    handleID: UUID,
    reason: TerminalExitReason
  )
  case failed(
    generation: UInt64,
    failure: PreviewLaunchFailure,
    fallback: BuiltInPreview
  )
}

private enum PreviewSessionObservation: Sendable {
  case output
  case slow
  case exited(TerminalExitReason?)
  case cancelled
}

public actor PreviewCoordinator {
  public typealias EventSink =
    @Sendable (PreviewCoordinatorEvent) async -> Void

  private let clock: PreviewClock
  private let processClient: PreviewProcessClient
  private let eventSink: EventSink

  private var highestGeneration: UInt64?
  private var activeGeneration: UInt64?
  private var operationToken: UInt64 = 0
  private var selectionTask: Task<Void, Never>?
  private var current: PreviewSessionHandle?
  private var isShuttingDown = false

  public init(
    clock: PreviewClock = .continuous,
    processClient: PreviewProcessClient = .live,
    eventSink: @escaping EventSink
  ) {
    self.clock = clock
    self.processClient = processClient
    self.eventSink = eventSink
  }

  public func select(
    generation: UInt64,
    launch: PreviewLaunch?,
    fallback: BuiltInPreview
  ) {
    guard !isShuttingDown else {
      return
    }
    guard highestGeneration.map({ generation > $0 }) ?? true else {
      return
    }

    highestGeneration = generation
    activeGeneration = generation
    operationToken &+= 1
    let token = operationToken
    let predecessor = selectionTask
    predecessor?.cancel()
    selectionTask = Task { [weak self] in
      _ = await predecessor?.value
      guard let self else {
        return
      }
      await self.runSelection(
        token: token,
        generation: generation,
        launch: launch,
        fallback: fallback
      )
    }
  }

  public func shutdown() async {
    isShuttingDown = true
    await cancelCurrent()
  }

  public func cancelCurrent() async {
    activeGeneration = nil
    operationToken &+= 1
    let token = operationToken
    let predecessor = selectionTask
    predecessor?.cancel()
    let cancellation = Task { [weak self] in
      _ = await predecessor?.value
      await self?.terminateCurrent()
    }
    selectionTask = cancellation
    _ = await cancellation.value
    if operationToken == token {
      selectionTask = nil
    }
  }

  private func runSelection(
    token: UInt64,
    generation: UInt64,
    launch: PreviewLaunch?,
    fallback: BuiltInPreview
  ) async {
    guard let launch else {
      await terminateCurrent()
      guard owns(token: token, generation: generation) else {
        return
      }
      await eventSink(.builtIn(generation: generation, preview: fallback))
      return
    }

    do {
      try await clock.sleep(.milliseconds(120))
    } catch {
      return
    }
    guard owns(token: token, generation: generation) else {
      return
    }

    await terminateCurrent()
    guard owns(token: token, generation: generation) else {
      return
    }

    let handle: PreviewSessionHandle
    do {
      handle = try await processClient.makeSession(launch)
    } catch {
      guard owns(token: token, generation: generation) else {
        return
      }
      await eventSink(
        .failed(
          generation: generation,
          failure: .startup(String(describing: error)),
          fallback: fallback
        )
      )
      return
    }

    guard owns(token: token, generation: generation) else {
      await terminate(handle)
      return
    }

    do {
      try await handle.start()
    } catch {
      await terminate(handle)
      guard owns(token: token, generation: generation) else {
        return
      }
      await eventSink(
        .failed(
          generation: generation,
          failure: .startup(String(describing: error)),
          fallback: fallback
        )
      )
      return
    }

    guard owns(token: token, generation: generation) else {
      await terminate(handle)
      return
    }

    current = handle
    await eventSink(
      .starting(
        generation: generation,
        launch: launch,
        handle: handle,
        fallback: fallback
      )
    )
    guard owns(token: token, generation: generation) else {
      await terminate(handle)
      return
    }

    let startedReady: Bool
    if case .running = await handle.lifecycle() {
      guard owns(token: token, generation: generation) else {
        await terminate(handle)
        return
      }
      await eventSink(.ready(generation: generation, handleID: handle.id))
      startedReady = true
    } else {
      startedReady = false
    }
    guard owns(token: token, generation: generation) else {
      await terminate(handle)
      return
    }

    let reason = await monitor(
      handle,
      token: token,
      generation: generation,
      startedReady: startedReady
    )
    if let reason, owns(token: token, generation: generation) {
      await eventSink(
        .exited(
          generation: generation,
          handleID: handle.id,
          reason: reason
        )
      )
    }
    if current?.id == handle.id {
      current = nil
    }
    if !owns(token: token, generation: generation) || Task.isCancelled {
      await terminate(handle)
    }
  }

  private func monitor(
    _ handle: PreviewSessionHandle,
    token: UInt64,
    generation: UInt64,
    startedReady: Bool
  ) async -> TerminalExitReason? {
    var observation = await Self.firstObservation(
      handle: handle,
      clock: clock,
      includesSlowTimer: true
    )

    switch observation {
    case .output:
      guard owns(token: token, generation: generation) else {
        return nil
      }
      if !startedReady {
        await eventSink(.ready(generation: generation, handleID: handle.id))
      }
      guard owns(token: token, generation: generation) else {
        return nil
      }
      return await handle.waitForExit(timeout: nil)

    case .slow:
      guard owns(token: token, generation: generation) else {
        return nil
      }
      if Self.hasVisibleOutput(handle.terminal.cachedSnapshot) {
        if !startedReady {
          await eventSink(.ready(generation: generation, handleID: handle.id))
        }
        guard owns(token: token, generation: generation) else {
          return nil
        }
        return await handle.waitForExit(timeout: nil)
      } else {
        await eventSink(.slow(generation: generation, handleID: handle.id))
      }
      guard owns(token: token, generation: generation) else {
        return nil
      }
      observation = await Self.firstObservation(
        handle: handle,
        clock: clock,
        includesSlowTimer: false
      )
      switch observation {
      case .output:
        guard owns(token: token, generation: generation) else {
          return nil
        }
        await eventSink(.ready(generation: generation, handleID: handle.id))
        guard owns(token: token, generation: generation) else {
          return nil
        }
        return await handle.waitForExit(timeout: nil)
      case .exited(let reason):
        if Self.hasVisibleOutput(handle.terminal.cachedSnapshot),
          owns(token: token, generation: generation)
        {
          await eventSink(.ready(generation: generation, handleID: handle.id))
        }
        return reason
      case .slow, .cancelled:
        return nil
      }

    case .exited(let reason):
      if Self.hasVisibleOutput(handle.terminal.cachedSnapshot),
        !startedReady,
        owns(token: token, generation: generation)
      {
        await eventSink(.ready(generation: generation, handleID: handle.id))
      }
      return reason

    case .cancelled:
      return nil
    }
  }

  private static func firstObservation(
    handle: PreviewSessionHandle,
    clock: PreviewClock,
    includesSlowTimer: Bool
  ) async -> PreviewSessionObservation {
    await withTaskGroup(of: PreviewSessionObservation.self) { group in
      group.addTask {
        if await waitForVisibleOutput(handle) {
          return .output
        }
        return .cancelled
      }
      if includesSlowTimer {
        group.addTask {
          do {
            try await clock.sleep(.seconds(2))
          } catch {
            return .cancelled
          }
          guard !Task.isCancelled else {
            return .cancelled
          }
          return .slow
        }
      }
      group.addTask {
        .exited(await handle.waitForExit(timeout: nil))
      }

      while let observation = await group.next() {
        if case .cancelled = observation {
          continue
        }
        group.cancelAll()
        return observation
      }
      return .cancelled
    }
  }

  private static func waitForVisibleOutput(
    _ handle: PreviewSessionHandle
  ) async -> Bool {
    let clock = ContinuousClock()
    while !Task.isCancelled {
      if hasVisibleOutput(handle.terminal.cachedSnapshot) {
        return true
      }
      if case .exited = await handle.lifecycle() {
        return false
      }
      do {
        try await clock.sleep(for: .milliseconds(10))
      } catch {
        return false
      }
    }
    return false
  }

  private static func hasVisibleOutput(_ grid: ForeignGrid) -> Bool {
    grid.cells.contains { row in
      row.contains { cell in
        cell.character != " "
          || cell.style != nil
          || cell.hyperlink != nil
      }
    }
  }

  private func owns(token: UInt64, generation: UInt64) -> Bool {
    !isShuttingDown
      && !Task.isCancelled
      && operationToken == token
      && activeGeneration == generation
  }

  private func terminateCurrent() async {
    guard let current else {
      return
    }
    self.current = nil
    await terminate(current)
  }

  private func terminate(_ handle: PreviewSessionHandle) async {
    let cleanup = Task {
      await handle.terminate(signal: 15)
      if await handle.waitForExit(timeout: .milliseconds(750)) != nil {
        return
      }
      await handle.terminate(signal: 9)
      _ = await handle.waitForExit(timeout: nil)
    }
    _ = await cleanup.value
  }
}

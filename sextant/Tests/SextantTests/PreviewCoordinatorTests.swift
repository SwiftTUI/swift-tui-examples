import Foundation
import SwiftTUI
import SwiftTUITerminal
import Synchronization
import Testing

@testable import Sextant

@Suite("Preview coordinator", .serialized)
struct PreviewCoordinatorTests {
  @Test("debounce launches only after the clock advances")
  func debounce() async throws {
    let clock = ManualPreviewClock()
    let sessions = SessionFactory()
    let events = PreviewEventRecorder()
    let coordinator = PreviewCoordinator(
      clock: PreviewClock { try await clock.sleep($0) },
      processClient: PreviewProcessClient { launch in
        await sessions.make(launch: launch)
      },
      eventSink: { await events.record($0) }
    )

    await coordinator.select(
      generation: 1,
      launch: launch("one"),
      fallback: fallback()
    )
    try await waitUntil { await clock.pendingDurations == [.milliseconds(120)] }
    #expect(await sessions.createdCount == 0)

    await clock.advanceAll()
    try await waitUntil { await sessions.createdCount == 1 }
    await sessions.produceOutputForLatest()
    try await waitUntil { await events.hasReady(generation: 1) }
    #expect(await sessions.createdCount == 1)

    await coordinator.shutdown()
    #expect(await sessions.liveCount == 0)
  }

  @Test("one hundred rapid selections launch only the current request")
  func rapidSelections() async throws {
    let clock = ManualPreviewClock()
    let sessions = SessionFactory()
    let events = PreviewEventRecorder()
    let coordinator = PreviewCoordinator(
      clock: PreviewClock { try await clock.sleep($0) },
      processClient: PreviewProcessClient { launch in
        await sessions.make(launch: launch)
      },
      eventSink: { await events.record($0) }
    )

    for generation in 1...100 {
      await coordinator.select(
        generation: UInt64(generation),
        launch: launch("\(generation)"),
        fallback: fallback()
      )
    }
    try await waitUntil { await clock.pendingDurations == [.milliseconds(120)] }
    await clock.advanceAll()
    try await waitUntil { await sessions.createdCount == 1 }
    await sessions.produceOutputForLatest()
    try await waitUntil { await events.hasReady(generation: 100) }

    #expect(await sessions.createdCount == 1)
    #expect(await sessions.startedLaunchNames == ["100"])
    await coordinator.shutdown()
    #expect(await sessions.liveCount == 0)
  }

  @Test("replacement terminates the old child before the new child starts")
  func serializedReplacement() async throws {
    let clock = ManualPreviewClock()
    let sessions = SessionFactory()
    let events = PreviewEventRecorder()
    let coordinator = PreviewCoordinator(
      clock: PreviewClock { try await clock.sleep($0) },
      processClient: PreviewProcessClient { launch in
        await sessions.make(launch: launch)
      },
      eventSink: { await events.record($0) }
    )

    await coordinator.select(
      generation: 1,
      launch: launch("first"),
      fallback: fallback()
    )
    try await waitUntil { await clock.pendingDurations == [.milliseconds(120)] }
    await clock.advanceAll()
    try await waitUntil { await sessions.createdCount == 1 }
    await sessions.produceOutputForLatest()
    try await waitUntil { await events.hasReady(generation: 1) }

    await coordinator.select(
      generation: 2,
      launch: launch("second"),
      fallback: fallback()
    )
    try await waitUntil { await clock.pendingDurations == [.milliseconds(120)] }
    await clock.advanceAll()
    try await waitUntil { await sessions.createdCount == 2 }
    await sessions.produceOutputForLatest()
    try await waitUntil { await events.hasReady(generation: 2) }

    #expect(await sessions.maximumLiveCount == 1)
    #expect(await sessions.startedLaunchNames == ["first", "second"])
    #expect(await sessions.terminationSignals.first == 15)
    await coordinator.shutdown()
  }

  @Test("running is ready and output cancels the slow timer")
  func runningReadinessAndOutput() async throws {
    let clock = ManualPreviewClock()
    let sessions = SessionFactory()
    let events = PreviewEventRecorder()
    let coordinator = PreviewCoordinator(
      clock: PreviewClock { try await clock.sleep($0) },
      processClient: PreviewProcessClient { launch in
        await sessions.make(launch: launch)
      },
      eventSink: { await events.record($0) }
    )

    await coordinator.select(
      generation: 1,
      launch: launch("output"),
      fallback: fallback()
    )
    try await waitUntil { await clock.pendingDurations == [.milliseconds(120)] }
    await clock.advanceAll()
    try await waitUntil { await sessions.createdCount == 1 }
    try await waitUntil { await events.hasReady(generation: 1) }
    try await waitUntil { await clock.pendingDurations == [.seconds(2)] }

    await sessions.produceOutputForLatest()
    try await waitUntil { await clock.pendingDurations.isEmpty }
    #expect(await events.hasSlow(generation: 1) == false)

    await coordinator.shutdown()
  }

  @Test("ready requires a running lifecycle or actual output")
  func readinessRequiresRunningOrOutput() async throws {
    let clock = ManualPreviewClock()
    let sessions = SessionFactory(marksRunningOnStart: false)
    let events = PreviewEventRecorder()
    let coordinator = PreviewCoordinator(
      clock: PreviewClock { try await clock.sleep($0) },
      processClient: PreviewProcessClient { launch in
        await sessions.make(launch: launch)
      },
      eventSink: { await events.record($0) }
    )

    await coordinator.select(
      generation: 1,
      launch: launch("not-running"),
      fallback: fallback()
    )
    try await waitUntil { await clock.pendingDurations == [.milliseconds(120)] }
    await clock.advanceAll()
    try await waitUntil { await sessions.createdCount == 1 }
    try await waitUntil { await clock.pendingDurations == [.seconds(2)] }
    #expect(await events.hasReady(generation: 1) == false)

    await sessions.produceOutputForLatest()
    try await waitUntil { await events.hasReady(generation: 1) }
    await coordinator.shutdown()
  }

  @Test("slow is reported only after two seconds without output")
  func slowWithoutOutput() async throws {
    let clock = ManualPreviewClock()
    let sessions = SessionFactory()
    let events = PreviewEventRecorder()
    let coordinator = PreviewCoordinator(
      clock: PreviewClock { try await clock.sleep($0) },
      processClient: PreviewProcessClient { launch in
        await sessions.make(launch: launch)
      },
      eventSink: { await events.record($0) }
    )

    await coordinator.select(
      generation: 1,
      launch: launch("slow"),
      fallback: fallback()
    )
    try await waitUntil { await clock.pendingDurations == [.milliseconds(120)] }
    await clock.advanceAll()
    try await waitUntil { await sessions.createdCount == 1 }
    try await waitUntil { await events.hasReady(generation: 1) }
    try await waitUntil { await clock.pendingDurations == [.seconds(2)] }
    await clock.advanceAll()
    try await waitUntil { await events.hasSlow(generation: 1) }

    await sessions.produceOutputForLatest()
    try await waitUntil { await events.readyCount(generation: 1) == 2 }
    await coordinator.shutdown()
  }

  @Test("selection generations are monotonic")
  func monotonicGenerations() async throws {
    let clock = ManualPreviewClock()
    let sessions = SessionFactory()
    let events = PreviewEventRecorder()
    let coordinator = PreviewCoordinator(
      clock: PreviewClock { try await clock.sleep($0) },
      processClient: PreviewProcessClient { launch in
        await sessions.make(launch: launch)
      },
      eventSink: { await events.record($0) }
    )

    await coordinator.select(
      generation: 2,
      launch: launch("new"),
      fallback: fallback()
    )
    await coordinator.select(
      generation: 1,
      launch: launch("stale"),
      fallback: fallback()
    )
    try await waitUntil { await clock.pendingDurations == [.milliseconds(120)] }
    await clock.advanceAll()
    try await waitUntil { await sessions.createdCount == 1 }
    await sessions.produceOutputForLatest()
    try await waitUntil { await events.hasReady(generation: 2) }

    #expect(await sessions.startedLaunchNames == ["new"])
    #expect(await events.contains(generation: 1) == false)
    await coordinator.shutdown()
  }

  @Test("new selection waits behind pending cancellation")
  func selectionWaitsForCancellation() async throws {
    let clock = ManualPreviewClock()
    let sessions = SessionFactory(blocksFirstTermination: true)
    let events = PreviewEventRecorder()
    let coordinator = PreviewCoordinator(
      clock: PreviewClock { try await clock.sleep($0) },
      processClient: PreviewProcessClient { launch in
        await sessions.make(launch: launch)
      },
      eventSink: { await events.record($0) }
    )

    await coordinator.select(
      generation: 1,
      launch: launch("first"),
      fallback: fallback()
    )
    try await waitUntil { await clock.pendingDurations == [.milliseconds(120)] }
    await clock.advanceAll()
    try await waitUntil { await sessions.createdCount == 1 }
    await sessions.produceOutputForLatest()
    try await waitUntil { await events.hasReady(generation: 1) }

    let cancellation = Task {
      await coordinator.cancelCurrent()
    }
    try await waitUntil { await sessions.terminationStartedCount == 1 }
    await coordinator.select(
      generation: 2,
      launch: launch("second"),
      fallback: fallback()
    )
    await Task.yield()
    #expect(await sessions.createdCount == 1)
    #expect(await clock.pendingDurations.isEmpty)

    await sessions.releaseFirstTermination()
    _ = await cancellation.value
    try await waitUntil { await clock.pendingDurations == [.milliseconds(120)] }
    await clock.advanceAll()
    try await waitUntil { await sessions.createdCount == 2 }
    await sessions.produceOutputForLatest()
    try await waitUntil { await events.hasReady(generation: 2) }

    #expect(await sessions.maximumLiveCount == 1)
    await coordinator.shutdown()
  }

  @Test("startup failure retains the built-in fallback")
  func startupFailure() async throws {
    let clock = ManualPreviewClock()
    let events = PreviewEventRecorder()
    let expectedFallback = fallback()
    let coordinator = PreviewCoordinator(
      clock: PreviewClock { try await clock.sleep($0) },
      processClient: PreviewProcessClient { _ in
        throw StubFailure.startup
      },
      eventSink: { await events.record($0) }
    )

    await coordinator.select(
      generation: 7,
      launch: launch("broken"),
      fallback: expectedFallback
    )
    try await waitUntil { await clock.pendingDurations == [.milliseconds(120)] }
    await clock.advanceAll()
    try await waitUntil { await events.hasFailure(generation: 7) }
    #expect(await events.failureFallback(generation: 7) == expectedFallback)
    await coordinator.shutdown()
  }

  private func launch(_ name: String) -> PreviewLaunch {
    PreviewLaunch(
      adapterID: PreviewAdapterID(name),
      adapterName: name,
      executable: "/bin/\(name)",
      arguments: [name],
      isInteractive: false
    )
  }

  private func fallback() -> BuiltInPreview {
    BuiltInPreview(
      metadata: PreviewMetadata(
        displayName: "fixture",
        path: "/fixture",
        kind: "file"
      ),
      body: .metadataOnly
    )
  }
}

private enum StubFailure: Error {
  case startup
}

private actor ManualPreviewClock {
  private struct Waiter {
    var duration: Duration
    var continuation: CheckedContinuation<Void, any Error>
  }

  private var waiters: [UUID: Waiter] = [:]

  var pendingDurations: [Duration] {
    waiters.values.map(\.duration).sorted { $0 < $1 }
  }

  func sleep(_ duration: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          waiters[id] = Waiter(
            duration: duration,
            continuation: continuation
          )
        }
      }
    } onCancel: {
      Task {
        await self.cancel(id)
      }
    }
  }

  func advanceAll() {
    let current = waiters.values
    waiters.removeAll()
    for waiter in current {
      waiter.continuation.resume()
    }
  }

  private func cancel(_ id: UUID) {
    waiters.removeValue(forKey: id)?.continuation.resume(
      throwing: CancellationError()
    )
  }
}

private actor PreviewEventRecorder {
  private var events: [PreviewCoordinatorEvent] = []

  func record(_ event: PreviewCoordinatorEvent) {
    events.append(event)
  }

  func hasReady(generation: UInt64) -> Bool {
    events.contains { event in
      if case .ready(let candidate, _) = event {
        return candidate == generation
      }
      return false
    }
  }

  func readyCount(generation: UInt64) -> Int {
    events.count { event in
      if case .ready(let candidate, _) = event {
        return candidate == generation
      }
      return false
    }
  }

  func hasFailure(generation: UInt64) -> Bool {
    events.contains { event in
      if case .failed(let candidate, _, _) = event {
        return candidate == generation
      }
      return false
    }
  }

  func hasSlow(generation: UInt64) -> Bool {
    events.contains { event in
      if case .slow(let candidate, _) = event {
        return candidate == generation
      }
      return false
    }
  }

  func contains(generation: UInt64) -> Bool {
    events.contains { event in
      switch event {
      case .builtIn(let candidate, _),
        .starting(let candidate, _, _, _),
        .ready(let candidate, _),
        .slow(let candidate, _),
        .exited(let candidate, _, _),
        .failed(let candidate, _, _):
        candidate == generation
      }
    }
  }

  func failureFallback(generation: UInt64) -> BuiltInPreview? {
    for event in events {
      if case .failed(let candidate, _, let fallback) = event,
        candidate == generation
      {
        return fallback
      }
    }
    return nil
  }
}

private actor SessionFactory {
  private let blocksFirstTermination: Bool
  private let marksRunningOnStart: Bool
  private var created = 0
  private var live = 0
  private var maximumLive = 0
  private var started: [String] = []
  private var signals: [Int32] = []
  private var terminals: [StubTerminalSession] = []
  private var terminationStarts = 0
  private var firstTerminationContinuation: CheckedContinuation<Void, Never>?

  init(
    blocksFirstTermination: Bool = false,
    marksRunningOnStart: Bool = true
  ) {
    self.blocksFirstTermination = blocksFirstTermination
    self.marksRunningOnStart = marksRunningOnStart
  }

  var createdCount: Int { created }
  var liveCount: Int { live }
  var maximumLiveCount: Int { maximumLive }
  var startedLaunchNames: [String] { started }
  var terminationSignals: [Int32] { signals }
  var terminationStartedCount: Int { terminationStarts }

  func make(launch: PreviewLaunch) -> PreviewSessionHandle {
    created += 1
    let terminal = StubTerminalSession()
    terminals.append(terminal)
    return PreviewSessionHandle(
      terminal: terminal,
      start: {
        await self.didStart(launch.adapterName)
        if self.marksRunningOnStart {
          await terminal.setLifecycle(.running)
        }
      },
      terminate: { signal in
        await self.didTerminate(signal)
        await terminal.setLifecycle(.exited(reason: .signal(signal)))
      },
      lifecycle: {
        await terminal.lifecycle
      }
    )
  }

  private func didStart(_ name: String) {
    live += 1
    maximumLive = max(maximumLive, live)
    started.append(name)
  }

  private func didTerminate(_ signal: Int32) async {
    terminationStarts += 1
    signals.append(signal)
    await waitForTerminationReleaseIfNeeded()
    live = max(0, live - 1)
  }

  private func waitForTerminationReleaseIfNeeded() async {
    guard blocksFirstTermination, terminationStarts == 1 else {
      return
    }
    await withCheckedContinuation { continuation in
      firstTerminationContinuation = continuation
    }
  }

  func releaseFirstTermination() {
    firstTerminationContinuation?.resume()
    firstTerminationContinuation = nil
  }

  func produceOutputForLatest() {
    terminals.last?.produceOutput()
  }
}

private final class StubTerminalSession: TerminalSession, @unchecked Sendable {
  private let state = StubTerminalState()
  private let snapshotStorage = Mutex<ForeignGrid>(.empty)

  var cachedSnapshot: ForeignGrid {
    snapshotStorage.withLock { $0 }
  }

  var lifecycle: TerminalLifecycle {
    get async { await state.lifecycle }
  }

  func setLifecycle(_ lifecycle: TerminalLifecycle) async {
    await state.setLifecycle(lifecycle)
  }

  func produceOutput() {
    snapshotStorage.withLock {
      $0 = ForeignGrid(
        size: CellSize(width: 1, height: 1),
        cells: [[RasterCell(character: "x")]]
      )
    }
  }

  func start() async throws {}

  func snapshot() async -> ForeignGrid { cachedSnapshot }

  func currentTitle() async -> String? { nil }

  func currentWorkingDirectory() async -> String? { nil }

  func currentLifecycle() async -> TerminalLifecycle {
    await state.lifecycle
  }

  func send(key _: TerminalEmulatorKey) async {}

  func send(paste _: String) async {}

  func send(mouse _: TerminalEmulatorMouse) async {}

  func resize(_: CellSize) async throws {}

  func events() -> AsyncStream<TerminalEmulatorEvent> {
    AsyncStream { _ in }
  }
}

private actor StubTerminalState {
  private(set) var lifecycle: TerminalLifecycle = .notStarted

  func setLifecycle(_ lifecycle: TerminalLifecycle) {
    self.lifecycle = lifecycle
  }
}

private func waitUntil(
  timeout: Duration = .seconds(2),
  condition: @escaping @Sendable () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  while clock.now < deadline {
    if await condition() {
      return
    }
    await Task.yield()
  }
  Issue.record("condition did not become true before \(timeout)")
}

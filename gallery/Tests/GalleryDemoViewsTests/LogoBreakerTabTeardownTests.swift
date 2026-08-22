import Foundation
@_spi(Runners) @_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews
@testable import SwiftTUICore
@testable import SwiftTUIRuntime

// Integration drilldown for the gallery TODO "transitioning off of the Logo
// Breaker tab takes forever".
//
// Logo Breaker runs a ~25 Hz geometry-driven `.task(id:)` game loop
// (`LogoTab.runGameLoop`). When its lazily-activated `TabView` body leaves, that
// task must be cancelled; a surviving task keeps stepping the simulation and
// requesting frames off-screen — the slowdown that persists after switching
// away and never recovers.
//
// This is the seam-level oracle the coverage report calls for: the framework
// minimal fixture (`swift-tui` `TabAutonomousTaskRuntimeTests`) cancels the task
// correctly because its plain `TabView` shape keeps the body children-reachable.
// The bug, if present, lives behind the gallery's capture-host / lazy-tab seam,
// which only the real `GalleryView` composition reproduces. Mirrors
// `TaskProgressTabTeardownTests` (a sibling autonomous-task tab already
// protected).
@MainActor
@Suite(.serialized)
struct LogoBreakerTabTeardownTests {
  @Test("leaving the Logo Breaker tab cancels its game-loop task")
  func leavingLogoBreakerTabCancelsItsGameLoop() throws {
    let terminalSize = CellSize(width: 120, height: 40)
    let rootIdentity = Identity(components: [.named("GalleryLogoBreakerTeardown")])
    let host = LogoTeardownRecordingHost(size: terminalSize)
    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    environment.terminalAppearance = host.appearance
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: LogoTeardownScriptedInput(),
      signalReader: LogoTeardownEmptySignals(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      environmentValues: environment,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in GalleryView(initialTab: .logo) }
    )
    focusTracker.invalidator = scheduler

    func render() throws {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
    }

    // Settle on the Logo Breaker tab: its geometry-keyed `.task` starts once the
    // field bounds resolve.
    scheduler.requestInvalidation(of: [rootIdentity])
    try render()
    for _ in 0..<3 {
      scheduler.requestInvalidation(of: [rootIdentity])
      try render()
    }

    let onLogo = runLoop.lifecycleCoordinator.activeTaskCount
    #expect(
      onLogo >= 1,
      "expected the Logo Breaker tab to start its autonomous game-loop .task; got \(onLogo)"
    )

    // Switch away to the always-visible Counter tab (no autonomous tasks of its
    // own), then drain frames.
    let surface = try #require(host.lastPresentedSurface)
    let counterCenter = try #require(
      Self.centerOfText("Counter", in: surface),
      """
      could not locate the Counter tab to switch away. Surface:
      \(surface.lines.joined(separator: "\n"))
      """
    )
    #expect(
      runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: counterCenter)))) == nil
    )
    #expect(
      runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: counterCenter)))) == nil
    )
    for _ in 0..<4 {
      scheduler.requestInvalidation(of: [rootIdentity])
      try render()
    }

    let afterLeave = runLoop.lifecycleCoordinator.activeTaskCount
    let remaining = runLoop.lifecycleCoordinator.activeTaskDescriptors.keys.map(\.path).sorted()
    #expect(
      afterLeave == 0,
      """
      Leaving Logo Breaker left \(afterLeave) orphaned task(s) running \
      (was \(onLogo) on the tab): \(remaining). A surviving 25 Hz game loop keeps \
      stepping the simulation off-screen — the slowdown that persists after \
      switching tabs.
      """
    )
  }

  @Test("leaving the Logo Breaker tab reads no @State after its game loop is cancelled")
  func leavingLogoBreakerTabReadsNoStateAfterCancellation() async throws {
    // The game loop sleeps between ticks; teardown cancels it mid-sleep and the
    // sleep returns at once. Touching `@State` after that point reads a node
    // that is already gone — the runtime reports `state.imperativeSeedFallback`
    // — so the loop must check cancellation before it reads anything.
    let terminalSize = CellSize(width: 120, height: 40)
    let rootIdentity = Identity(components: [.named("GalleryLogoBreakerSeedFallback")])
    let host = LogoTeardownRecordingHost(size: terminalSize)
    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    environment.terminalAppearance = host.appearance
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    var issues: [RuntimeIssue] = []
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: LogoTeardownScriptedInput(),
      signalReader: LogoTeardownEmptySignals(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      environmentValues: environment,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in GalleryView(initialTab: .logo) }
    )
    focusTracker.invalidator = scheduler
    runLoop.runtimeIssueSink = RuntimeIssueSink { issue in
      issues.append(issue)
    }

    func render() throws {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    try render()
    for _ in 0..<3 {
      scheduler.requestInvalidation(of: [rootIdentity])
      try render()
    }
    #expect(runLoop.lifecycleCoordinator.activeTaskCount >= 1)
    // Let the loop reach its sleep before the tab departs.
    try await Task.sleep(for: .milliseconds(30))

    let surface = try #require(host.lastPresentedSurface)
    let counterCenter = try #require(Self.centerOfText("Counter", in: surface))
    #expect(
      runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: counterCenter)))) == nil
    )
    #expect(
      runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: counterCenter)))) == nil
    )
    for _ in 0..<2 {
      scheduler.requestInvalidation(of: [rootIdentity])
      try render()
    }
    #expect(runLoop.lifecycleCoordinator.activeTaskCount == 0)

    // The cancelled loop's continuation runs when the main actor yields; give
    // it a few turns, then render once more so dispatch-time issues queued by
    // any stray read surface at a frame head.
    for _ in 0..<5 {
      await Task.yield()
      try await Task.sleep(for: .milliseconds(10))
    }
    scheduler.requestInvalidation(of: [rootIdentity])
    try render()

    let fallbacks = issues.filter { $0.code == "state.imperativeSeedFallback" }
    #expect(
      fallbacks.isEmpty,
      "the game loop read @State after its tab was torn down: \(fallbacks.map(\.message))"
    )
  }

  private static func centerOfText(_ target: String, in surface: RasterSurface) -> Point? {
    for (row, line) in surface.lines.enumerated() {
      guard let range = line.range(of: target) else { continue }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }
}

private final class LogoTeardownScriptedInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}

private final class LogoTeardownEmptySignals: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}

private final class LogoTeardownRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var lastPresentedSurface: RasterSurface?

  init(size: CellSize) { self.surfaceSize = size }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    lastPresentedSurface = surface
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}

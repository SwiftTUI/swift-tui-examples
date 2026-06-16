import Foundation
@_spi(Runners) @_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews
@testable import SwiftTUICore
@testable import SwiftTUIRuntime

// Regression for the residual progress-tab slowdown: the task-progress tab runs
// autonomous animation `.task`s (TimelineView shimmer, Spinner) behind the
// gallery's lazy-tab capture-host seam. When the tab is dismissed those tasks
// must be cancelled; if the disappearance is missed across the seam they orphan
// and keep re-rendering off-screen forever — a slowdown that persists after
// switching to another tab and never recovers.
@MainActor
@Suite(.serialized)
struct TaskProgressTabTeardownTests {
  @Test("leaving the task-progress tab cancels its animation tasks")
  func leavingTaskProgressTabCancelsItsTasks() throws {
    let terminalSize = CellSize(width: 120, height: 40)
    let rootIdentity = Identity(components: [.named("GalleryTaskProgressTeardown")])
    let host = TeardownRecordingHost(size: terminalSize)
    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    environment.terminalAppearance = host.appearance
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: TeardownScriptedInput(),
      signalReader: TeardownEmptySignals(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      environmentValues: environment,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in GalleryView(initialTab: .taskProgress) }
    )
    focusTracker.invalidator = scheduler

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

    let onProgress = runLoop.lifecycleCoordinator.activeTaskCount
    #expect(
      onProgress >= 1,
      "expected the task-progress tab to start at least one autonomous .task; got \(onProgress)"
    )

    // Switch away to the always-visible Logo tab.
    let surface = try #require(host.lastPresentedSurface)
    let logoCenter = try #require(
      Self.centerOfText("Logo", in: surface),
      """
      could not locate the Logo tab to switch away. Surface:
      \(surface.lines.joined(separator: "\n"))
      """
    )
    #expect(
      runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: logoCenter)))) == nil
    )
    #expect(
      runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: logoCenter)))) == nil
    )
    for _ in 0..<4 {
      scheduler.requestInvalidation(of: [rootIdentity])
      try render()
    }

    let afterLeave = runLoop.lifecycleCoordinator.activeTaskCount
    let remaining = runLoop.lifecycleCoordinator.activeTaskDescriptors.keys.map(\.path).sorted()
    // The Logo tab is a static splash with no autonomous tasks, so once the
    // progress tab's animation tasks are cancelled the live count must be zero.
    // A surviving task is an orphan (its node's viewNodeID churned, so it was
    // never cancelled) that keeps re-rendering off-screen — the slowdown that
    // persists across tab switches.
    #expect(
      afterLeave == 0,
      """
      Leaving the task-progress tab left \(afterLeave) orphaned animation task(s) \
      running (was \(onProgress) on the tab): \(remaining). These keep \
      re-rendering off-screen — a slowdown that persists after switching tabs.
      """
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

private final class TeardownScriptedInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}

private final class TeardownEmptySignals: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}

private final class TeardownRecordingHost: PresentationSurface {
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

import Foundation
@_spi(Runners) @_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews
@testable import SwiftTUICore
@testable import SwiftTUIRuntime

// Regression drilldown for the "Life tab freezes" user report: the Life tab
// runs one autonomous `.task(id:)` auto-tick loop (`LifeTab.runAutoTick`)
// behind the gallery's lazy-tab capture-host seam. Leaving the tab must cancel
// that task (mirrors `LogoBreakerTabTeardownTests`), and — the reported bug —
// RETURNING to the tab must start a fresh one. A revisit that reuses the
// retained subtree without restarting the task leaves the tab frozen at its
// stale grid with no way to animate again.
@MainActor
@Suite(.serialized)
struct LifeTabRevisitTests {
  @Test("leaving the Life tab cancels its auto-tick task and returning restarts it")
  func leavingAndRevisitingLifeTabRestartsAutoTick() throws {
    let terminalSize = CellSize(width: 120, height: 40)
    let rootIdentity = Identity(components: [.named("GalleryLifeTabRevisit")])
    let host = LifeRevisitRecordingHost(size: terminalSize)
    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    environment.terminalAppearance = host.appearance
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: LifeRevisitScriptedInput(),
      signalReader: LifeRevisitEmptySignals(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      environmentValues: environment,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in GalleryView(initialTab: .life) }
    )
    focusTracker.invalidator = scheduler

    func render() throws {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
    }

    func click(_ target: String) throws {
      let surface = try #require(host.lastPresentedSurface)
      let center = try #require(
        Self.centerOfText(target, in: surface),
        """
        could not locate "\(target)" to click. Surface:
        \(surface.lines.joined(separator: "\n"))
        """
      )
      #expect(
        runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: center)))) == nil
      )
      #expect(
        runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: center)))) == nil
      )
    }

    // Settle on the Life tab: its auto-tick `.task(id:)` starts on adoption.
    scheduler.requestInvalidation(of: [rootIdentity])
    try render()
    for _ in 0..<3 {
      scheduler.requestInvalidation(of: [rootIdentity])
      try render()
    }

    let onLife = runLoop.lifecycleCoordinator.activeTaskCount
    #expect(
      onLife >= 1,
      "expected the Life tab to start its autonomous auto-tick .task; got \(onLife)"
    )

    // Switch away to Counter (no autonomous tasks of its own), then drain.
    try click("Counter")
    for _ in 0..<4 {
      scheduler.requestInvalidation(of: [rootIdentity])
      try render()
    }

    let afterLeave = runLoop.lifecycleCoordinator.activeTaskCount
    let remaining = runLoop.lifecycleCoordinator.activeTaskDescriptors.keys.map(\.path).sorted()
    #expect(
      afterLeave == 0,
      """
      Leaving the Life tab left \(afterLeave) orphaned task(s) running \
      (was \(onLife) on the tab): \(remaining).
      """
    )

    // Return to the Life tab. The reported bug: the tab renders its stale
    // grid but the auto-tick task never restarts — the tab stays frozen.
    try click("Life")
    for _ in 0..<4 {
      scheduler.requestInvalidation(of: [rootIdentity])
      try render()
    }

    let surfaceText = try #require(host.lastPresentedSurface).lines.joined(separator: "\n")
    #expect(
      surfaceText.contains("Conway's Life"),
      "expected the Life tab to be selected again; surface was:\n\(surfaceText)"
    )

    let afterReturn = runLoop.lifecycleCoordinator.activeTaskCount
    #expect(
      afterReturn >= 1,
      """
      Returning to the Life tab did not restart its auto-tick .task \
      (active tasks: \(afterReturn)). The tab renders but never animates — \
      the frozen-on-revisit bug.
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

private final class LifeRevisitScriptedInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}

private final class LifeRevisitEmptySignals: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}

private final class LifeRevisitRecordingHost: PresentationSurface {
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

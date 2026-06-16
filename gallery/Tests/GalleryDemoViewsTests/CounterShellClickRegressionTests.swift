import Foundation
@_spi(Runners) @_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews
@testable import SwiftTUICore
@testable import SwiftTUIRuntime

// Regression for the live gallery: clicking the Counter "+" button through the
// *full GalleryView shell* (lazy-tab capture-host seam + toolbar strip) must
// keep incrementing the displayed figlet. Unlike `CalculatorTabClickTests`,
// which renders the tab as the root view (no seam), this drives the gallery
// shell so the tab content sits behind the capture-host seam, then issues a
// scoped publication frame (the click) and clicks again — the case where a
// seam-stranded action handler stops responding.
@MainActor
@Suite(.serialized)
struct CounterShellClickRegressionTests {
  @Test("clicking the Counter + button through the gallery shell increments repeatedly")
  func counterIncrementThroughGalleryShell() throws {
    let terminalSize = CellSize(width: 120, height: 36)
    let rootIdentity = Identity(components: [.named("CounterShellClickRegression")])
    let host = CounterShellRecordingHost(size: terminalSize)
    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    environment.terminalAppearance = host.appearance
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: CounterShellScriptedInput(),
      signalReader: CounterShellEmptySignals(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      environmentValues: environment,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in GalleryView() }
    )
    focusTracker.invalidator = scheduler

    func settle(maxFrames: Int = 8) throws -> RasterSurface {
      var last: RasterSurface?
      for _ in 0..<maxFrames {
        var rendered = 0
        try runLoop.renderPendingFrames(renderedFrames: &rendered)
        let surface = host.lastPresentedSurface
        if let surface, let last, Self.lineSignature(surface) == Self.lineSignature(last) {
          return surface
        }
        last = surface ?? last
      }
      return try #require(last)
    }

    // Initial render + settle (full publication establishes handlers). The
    // gallery opens on the Logo splash; switch to the Counter tab so its
    // content materializes behind the lazy-tab capture-host seam — exactly the
    // user's flow.
    scheduler.requestInvalidation(of: [rootIdentity])
    let initialSurface = try settle()
    let counterTabCenter = try #require(
      Self.centerOfText("Counter", in: initialSurface),
      """
      Could not locate the Counter tab. Surface:
      \(initialSurface.lines.joined(separator: "\n"))
      """
    )
    #expect(
      runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: counterTabCenter)))) == nil
    )
    #expect(
      runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: counterTabCenter)))) == nil
    )
    _ = try settle()
    for _ in 0..<3 {
      scheduler.requestInvalidation(of: [rootIdentity])
      _ = try settle()
    }

    let settledSurface = try #require(host.lastPresentedSurface)
    let plusCenter = try #require(
      Self.centerOfText(" + ", in: settledSurface)
        ?? Self.centerOfText("+", in: settledSurface),
      """
      Could not locate the Counter + button in the gallery shell. Surface:
      \(initialSurface.lines.joined(separator: "\n"))
      """
    )

    var signatures = [Self.lineSignature(settledSurface)]
    for clickIndex in 1...3 {
      #expect(
        runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: plusCenter)))) == nil
      )
      #expect(
        runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: plusCenter)))) == nil
      )
      let surface = try settle()
      signatures.append(Self.lineSignature(surface))
      #expect(
        signatures[clickIndex] != signatures[clickIndex - 1],
        """
        Counter + click #\(clickIndex) did not change the display — the action handler \
        appears to have been stranded behind the lazy-tab seam by scoped publication. \
        Surface:
        \(surface.lines.joined(separator: "\n"))
        """
      )
    }
  }

  // MARK: - Helpers

  /// Glyph-only signature (no color), so color/foreground animation does not add
  /// noise — only the figlet count digit changes the line characters.
  private static func lineSignature(_ surface: RasterSurface) -> String {
    surface.lines.joined(separator: "\n")
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

private final class CounterShellScriptedInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class CounterShellEmptySignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}

private final class CounterShellRecordingHost: PresentationSurface {
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

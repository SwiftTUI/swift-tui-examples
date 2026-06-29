import Foundation
@_spi(Runners) @_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews
@testable import SwiftTUICore
@testable import SwiftTUIRuntime

// Integration drilldown for the gallery TODO "when opening the presentation lab
// overlays they are sometimes un-closable. in this case the background remains
// interactive."
//
// Drives the real `PresentationLabTab` through a live run loop and asserts the
// two halves of the symptom against an open sheet:
//   1. The background trigger ("Confirm") must NOT fire while the sheet is open
//      (no "background remains interactive").
//   2. The sheet's own "Close" control must dismiss it, and the background must
//      then be live again (no "un-closable").
//
// The framework minimal fixture (`swift-tui` `PresentationRouteSuppressionTests`)
// passes for these families; this exercises the real gallery composition where
// the reported intermittent failure occurs. If the symptom reproduces here it
// fails loud; if it does not, it guards the modal routing contract and narrows
// the bug to the intermittent / seam-specific conditions it was reported under.
@MainActor
@Suite(.serialized)
struct PresentationLabModalRoutingTests {
  @Test("an open Presentation Lab sheet blocks the background trigger and still closes")
  func openSheetBlocksBackgroundTriggerAndStillCloses() throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryPresentationLabModalRouting")])
    let host = ModalRoutingRecordingHost(size: terminalSize)
    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    environment.terminalAppearance = host.appearance
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: ModalRoutingScriptedInput(),
      signalReader: ModalRoutingEmptySignals(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      environmentValues: environment,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in PresentationLabTab() }
    )
    focusTracker.invalidator = scheduler

    func render() throws -> String {
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
      return host.lastPresentedSurface?.lines.joined(separator: "\n") ?? ""
    }

    func settle(_ rounds: Int = 4) throws -> String {
      var text = ""
      for _ in 0..<rounds {
        scheduler.requestInvalidation(of: [rootIdentity])
        text = try render()
      }
      return text
    }

    func click(_ point: Point) throws -> String {
      #expect(
        runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: point)))) == nil
      )
      _ = try settle(2)
      #expect(
        runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: point)))) == nil
      )
      return try settle()
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    let initial = try settle()
    #expect(initial.contains("Presentation Lab"))

    // Record the background "Confirm" trigger location while no overlay is up.
    let confirmPoint = try #require(
      ModalRoutingRecordingHost.centerOfText("Confirm", in: host.lastPresentedSurface),
      "could not locate the background Confirm trigger. Surface:\n\(initial)"
    )
    let sheetPoint = try #require(
      ModalRoutingRecordingHost.centerOfText("Sheet", in: host.lastPresentedSurface),
      "could not locate the Sheet trigger. Surface:\n\(initial)"
    )

    // Open the sheet.
    let opened = try click(sheetPoint)
    #expect(opened.contains("Sheet content"), "sheet did not open; surface:\n\(opened)")

    // Click the background Confirm trigger while the sheet is open. If base
    // interaction is correctly disabled, the confirmation dialog does NOT open
    // and the sheet stays up. The reported bug would let the background fire.
    let afterBackgroundClick = try click(confirmPoint)
    #expect(
      !afterBackgroundClick.contains("Reset presentation state?"),
      "background Confirm trigger fired while the sheet was open (background remained interactive); surface:\n\(afterBackgroundClick)"
    )
    #expect(
      afterBackgroundClick.contains("Sheet content"),
      "the sheet must stay open after a suppressed background click; surface:\n\(afterBackgroundClick)"
    )

    // The sheet's own Close control must dismiss it (not un-closable).
    let closePoint = try #require(
      ModalRoutingRecordingHost.centerOfText("Close", in: host.lastPresentedSurface),
      "could not locate the sheet Close control; surface:\n\(afterBackgroundClick)"
    )
    let closed = try click(closePoint)
    #expect(
      !closed.contains("Sheet content"),
      "the sheet was un-closable via its Close control; surface:\n\(closed)"
    )

    // Background is live again: the Confirm trigger now opens the confirmation.
    let afterReopen = try click(confirmPoint)
    #expect(
      afterReopen.contains("Reset presentation state?"),
      "background routing was not restored after dismissing the sheet; surface:\n\(afterReopen)"
    )
  }
}

private final class ModalRoutingScriptedInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}

private final class ModalRoutingEmptySignals: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}

private final class ModalRoutingRecordingHost: PresentationSurface {
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

  static func centerOfText(_ target: String, in surface: RasterSurface?) -> Point? {
    guard let surface else { return nil }
    for (row, line) in surface.lines.enumerated() {
      guard let range = line.range(of: target) else { continue }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }
}

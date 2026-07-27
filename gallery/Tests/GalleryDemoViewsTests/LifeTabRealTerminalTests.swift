import Dispatch
@_spi(Runners) @_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews
@testable import SwiftTUICore
@testable import SwiftTUIRuntime

// Real-terminal (PTY) drilldown for the "Life tab freezes" user report, run in
// the production `.async` render mode:
//
//   1. the auto-tick animation sometimes never starts on entry, and the tab
//      cannot be left afterwards;
//   2. after switching away and back, the tab renders but never ticks again.
//
// The deterministic sync-harness sibling (`LifeTabRevisitTests`) passes, so
// the failure needs real wall-clock task scheduling and async frame delivery
// to reproduce.
@MainActor
@Suite(.serialized)
struct LifeTabRealTerminalTests {
  @Test(
    "real terminal Life tab ticks, survives leaving, and resumes on revisit",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func lifeTabTicksAndResumesAcrossRevisit() async throws {
    let terminalSize = CellSize(width: 120, height: 40)
    let rootIdentity = Identity(components: [.named("GalleryLifeRealTerminalRevisit")])
    let pty = try RealTerminalPTYPair.open(size: terminalSize)
    defer { pty.close() }

    let host = TerminalHost(
      inputFileDescriptor: pty.slave,
      outputFileDescriptor: pty.slave,
      fallbackSize: terminalSize,
      capabilityProfile: .previewUnicode
    )
    let inputReader = InputReader(fileDescriptor: pty.slave)

    let runTask = Task {
      try await Self.runHarness(
        presentationSurface: host,
        terminalInputReader: inputReader,
        terminalSize: terminalSize,
        rootIdentity: rootIdentity,
        viewBuilder: { GalleryView(initialTab: .life) }
      )
    }

    var screen = ANSIVisibleScreen(size: terminalSize)

    // Leg 1 — the auto-tick loop must start: `gen` advances past its seed.
    let tickingScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { rendered in
      rendered.contains("Conway's Life") && (Self.generation(in: rendered) ?? 0) >= 2
    }
    #expect(
      tickingScreen.contains("Conway's Life"),
      "expected the Life tab to render and tick; screen was:\n\(tickingScreen)"
    )

    // Leg 2 — leaving the tab must work while (or after) it animates.
    let counterCenter = try #require(
      Self.centerOfText("Counter", in: tickingScreen),
      "could not locate the Counter tab label; screen was:\n\(tickingScreen)"
    )
    try writeAllBytes(Self.sgrPrimaryClick(at: counterCenter), to: pty.master)
    let counterScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { rendered in
      rendered.contains("A SwiftUI-shaped terminal UI")
    }
    #expect(
      counterScreen.contains("A SwiftUI-shaped terminal UI"),
      "expected the Counter tab after clicking it; screen was:\n\(counterScreen)"
    )

    // Leg 3 — returning must resume ticking (fresh or continued, but alive).
    let lifeCenter = try #require(
      Self.centerOfText("Life", in: counterScreen),
      "could not locate the Life tab label; screen was:\n\(counterScreen)"
    )
    try writeAllBytes(Self.sgrPrimaryClick(at: lifeCenter), to: pty.master)
    let revisitScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { rendered in
      rendered.contains("Conway's Life")
    }
    let revisitGeneration = Self.generation(in: revisitScreen) ?? -1

    let resumedScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { rendered in
      guard rendered.contains("Conway's Life"),
        let generation = Self.generation(in: rendered)
      else {
        return false
      }
      return generation != revisitGeneration && generation >= 1
    }
    let resumedGeneration = Self.generation(in: resumedScreen)
    #expect(
      resumedGeneration != nil && resumedGeneration != revisitGeneration,
      """
      expected the Life tab to resume ticking after revisit (was gen \
      \(revisitGeneration)); screen was:\n\(resumedScreen)
      """
    )

    pty.closeMaster()
    _ = try await runTask.value
  }

  // MARK: - Screen parsing

  private static func generation(in rendered: String) -> Int? {
    guard let range = rendered.range(of: "gen ") else { return nil }
    let digits = rendered[range.upperBound...].prefix(while: \.isNumber)
    guard !digits.isEmpty else { return nil }
    return Int(digits)
  }

  private static func centerOfText(_ target: String, in rendered: String) -> Point? {
    for (row, line) in rendered.split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
    {
      guard let range = line.range(of: target) else { continue }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }

  // MARK: - Harness (mirrors GalleryTabSwitchTests, production async mode)

  @MainActor
  private static func runHarness<V: View>(
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    terminalSize: CellSize,
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader,
      signalReader: LifeRealTerminalEmptySignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: env,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder() }
    )
    // Production default: exercise the async frame tail the user actually runs.
    runLoop.renderMode = .async
    return try await runLoop.run()
  }

  private static func sgrPrimaryClick(at point: Point) -> [UInt8] {
    sgrMouse(encodedButton: 0, terminator: "M", at: point)
      + sgrMouse(encodedButton: 0, terminator: "m", at: point)
  }

  private static func sgrMouse(
    encodedButton: Int,
    terminator: String,
    at point: Point
  ) -> [UInt8] {
    let cell = point.containingCell
    return Array(
      "\u{001B}[<\(encodedButton);\(cell.x + 1);\(cell.y + 1)\(terminator)".utf8
    )
  }

}

private final class LifeRealTerminalEmptySignals: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}

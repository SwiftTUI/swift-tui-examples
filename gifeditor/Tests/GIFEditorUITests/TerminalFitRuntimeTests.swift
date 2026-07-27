import Foundation
import GIFEditorCore
import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GIFEditorUI

/// The too-small guard, driven through the real editor and a real run loop.
///
/// A snapshot test can say what the layout *would* be at 63 columns. It cannot
/// say whether the editor still reaches a settled frame there, and that is the
/// failure this guard is aimed at: the one time the editor's layout stopped
/// converging — an 18-cell-wide timeline column that would not fit at 80×24 —
/// no unit test noticed, and every runtime test in the suite timed out at once
/// with nothing to attribute it to. So both sides of the threshold are exercised
/// here, on the harness that would have caught it, with a time limit that turns
/// a hang into a named failure instead of a stalled suite.
///
/// The pair is deliberately one column apart. A guard that fires at 40 and not
/// at 63 would pass a test written at 20.
@MainActor
@Suite("GIF editor terminal fit runtime")
struct TerminalFitRuntimeTests {
  @Test(
    "one column under the floor, the editor says so instead of overflowing",
    .timeLimit(.minutes(1))
  )
  func belowTheFloorTheEditorExplainsItself() async throws {
    let width = EditorLayoutFloor.minimumWidth - 1
    let terminal = FitRecordingTerminalHost(surfaceSize: .init(width: width, height: 24))

    let result = try await run(
      terminal: terminal,
      identity: "gifeditor.terminal-fit.under-floor",
      until: { terminal.latestFrame?.contains("Terminal too small") == true }
    )

    #expect(result.exitReason == .inputEnded)
    let frame = try #require(terminal.latestFrame)
    #expect(frame.contains("Terminal too small"))
    #expect(frame.contains("\(EditorLayoutFloor.minimumWidth) columns"))
    #expect(frame.contains("\(width)×24"))
    // The editor itself is gone, not merely covered: every one of these is a
    // region of the stack the fit gate replaced.
    #expect(!frame.contains("Palette"))
    #expect(!frame.contains("Layers"))
    #expect(!frame.contains("Frames"))
    #expect(!frame.contains("File ▾"))
    // And nothing overflows the terminal it is complaining about.
    #expect(
      frame.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy {
        $0.count <= width
      },
      "the too-small screen overran the terminal it was drawn into"
    )
  }

  @Test("at the floor exactly, the editor lays out normally", .timeLimit(.minutes(1)))
  func atTheFloorTheEditorRuns() async throws {
    let width = EditorLayoutFloor.minimumWidth
    let terminal = FitRecordingTerminalHost(surfaceSize: .init(width: width, height: 24))

    let result = try await run(
      terminal: terminal,
      identity: "gifeditor.terminal-fit.at-floor",
      until: { terminal.latestFrame?.contains("Palette") == true }
    )

    #expect(result.exitReason == .inputEnded)
    let frame = try #require(terminal.latestFrame)
    #expect(!frame.contains("Terminal too small"))
    // Every region of the editor is on screen and addressable.
    #expect(frame.contains("File ▾"))
    #expect(frame.contains("Palette"))
    #expect(frame.contains("Layers"))
    #expect(frame.contains("Frames"))
    #expect(frame.contains("Ready"))
  }

  /// The size the rest of the suite runs at, so the guard can be shown to be
  /// inert where the editor already worked.
  @Test(
    "the guard stays out of the way at the size the editor documents",
    .timeLimit(.minutes(1))
  )
  func theGuardIsInertAtEightyColumns() async throws {
    let terminal = FitRecordingTerminalHost(surfaceSize: .init(width: 80, height: 24))

    _ = try await run(
      terminal: terminal,
      identity: "gifeditor.terminal-fit.eighty",
      until: { terminal.latestFrame?.contains("Ready") == true }
    )

    #expect(terminal.frames.allSatisfy { !$0.contains("Terminal too small") })
  }

  // MARK: - Harness

  private func run(
    terminal: FitRecordingTerminalHost,
    identity: String,
    until predicate: @escaping @MainActor () -> Bool
  ) async throws -> RunLoopResult<Int> {
    let rootIdentity = Identity(components: [identity])
    let document = GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 8, height: 8))
    return try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: FitInputReader(
        frameSignal: terminal.frameSignal,
        until: predicate
      ),
      signalReader: FitEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: terminal.surfaceSize.width, height: terminal.surfaceSize.height),
      viewBuilder: { _, _ in
        EditorView(document: document, stateDirectory: fitStateDirectory)
      }
    ).run()
  }
}

/// A throwaway state directory with the first-run hint already claimed, so the
/// nudge never lands in a status line these tests read and no run touches the
/// developer's real config.
private let fitStateDirectory: URL = {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-terminal-fit-\(UUID().uuidString)")
  FirstRunHint.claim(inStateDirectory: directory)
  return directory
}()

private final class FitRecordingTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []

  var latestFrame: String? { frames.last }

  let frameSignal = MainActorConditionSignal()

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
    append(rendered)
    return TerminalPresentationMetrics(
      bytesWritten: rendered.utf8.count,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_ output: String) throws {
    append(output)
  }

  private func append(_ output: String) {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
  }
}

/// Sends nothing and ends the run once the frame under test has landed.
///
/// No key press at all, on purpose: what is being checked is what the editor
/// renders when it is *started* in a terminal of a given size, and a key press
/// would leave open the question of whether the frame arrived because of it.
private final class FitInputReader: TerminalInputReading {
  private let frameSignal: MainActorConditionSignal
  private let predicate: @MainActor () -> Bool

  init(frameSignal: MainActorConditionSignal, until predicate: @escaping @MainActor () -> Bool) {
    self.frameSignal = frameSignal
    self.predicate = predicate
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let frameSignal = self.frameSignal
      let predicate = self.predicate
      let task = Task { @MainActor in
        await frameSignal.wait(until: predicate)
        continuation.finish()
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class FitEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

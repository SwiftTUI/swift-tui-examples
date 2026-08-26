import Foundation
import GIFEditorCore
import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GIFEditorUI

/// The `?` overlay below the fold.
///
/// The overlay shows thirteen rows of a hundred-odd, and twelve sections
/// do not fit on one 80×24 screen — they never will, so the fold is
/// permanent. What was missing is that nothing below it could be *reached*:
/// a sheet seats focus on its own chrome button, key presses bubble from
/// the focused node upward, and the overlay's content is a sibling of that
/// button rather than an ancestor — so neither the scroll view's built-in
/// arrow handling nor anything the content registered was ever on the path
/// a key travels. No test could assert on a late section either, and an
/// overlay assertion had to be demoted to the catalog level ("the catalog
/// has a Help row"), where it proves nothing about what an author can see.
///
/// So these press the scroll keys and read the last catalog row — "Show
/// this keyboard reference", the single `Help` entry and the last row of
/// the list — off the rendered terminal. A row that renders only after
/// `End` is a row that is reachable.
@MainActor
@Suite("GIF editor keyboard overlay runtime", .serialized)
struct KeyBindingHelpRuntimeTests {

  /// A row near the top of the first section, and the last row of the
  /// last — which cannot both be on a thirteen-row screen.
  private static let firstRow = "Bucket fill"
  private static let lastRow = "Show this keyboard reference"

  /// Enough single steps to clear the first section's opening rows from
  /// the viewport, and few enough to walk back.
  private static let stepCount = 20

  @Test("End reaches the last catalog section, Home comes back", .timeLimit(.minutes(5)))
  func scrollKeysReachTheFoldedContent() async throws {
    let terminal = HelpRecordingTerminalHost(surfaceSize: .init(width: 80, height: 24))
    let rootIdentity = Identity(components: ["gifeditor.help-runtime.scroll"])

    var steps: [HelpInputStep] = [
      .press(KeyPress(.character("?"), modifiers: [])),
      .awaitCondition {
        terminal.latestFrame?.contains("Keyboard shortcuts") == true
          && terminal.latestFrame?.contains(Self.firstRow) == true
      },
    ]
    steps += Self.awaitFocusFrame(terminal, FrameMark())
    steps += [
      .press(KeyPress(.end, modifiers: [])),
      .awaitCondition {
        terminal.latestFrame?.contains(Self.lastRow) == true
      },
      .press(KeyPress(.home, modifiers: [])),
      .awaitCondition {
        terminal.latestFrame?.contains(Self.firstRow) == true
          && terminal.latestFrame?.contains(Self.lastRow) != true
      },
    ]

    let inputReader = HelpInputReader(frameSignal: terminal.frameSignal, steps: steps)
    let result = try await run(terminal: terminal, rootIdentity: rootIdentity, reader: inputReader)

    #expect(result.exitReason == .inputEnded)
    // The premise, checked rather than assumed: the last row is *not* on
    // the screen the overlay opens with. Without this the suite would
    // pass on an overlay that simply grew until everything fit.
    let opened = terminal.frames.first { $0.contains("Keyboard shortcuts") }
    #expect(opened?.contains(Self.lastRow) != true, "the fold is not real; this proves nothing")
    #expect(terminal.frames.contains { $0.contains(Self.lastRow) })
    // And back at the top, so `End` moved a viewport rather than the list
    // re-laying itself out at a size that happened to fit.
    #expect(terminal.latestFrame?.contains(Self.firstRow) == true)
    #expect(terminal.latestFrame?.contains(Self.lastRow) != true)
  }

  /// A page and a step are both offered, and both move — the two verbs a
  /// reference card is actually read with. The arrows have to walk back
  /// as far as they walked forward, which a one-directional clamp would
  /// fail.
  @Test("PgDn pages, and the arrows step both ways", .timeLimit(.minutes(5)))
  func pageAndLineKeysBothScroll() async throws {
    let terminal = HelpRecordingTerminalHost(surfaceSize: .init(width: 80, height: 24))
    let rootIdentity = Identity(components: ["gifeditor.help-runtime.paging"])

    var steps: [HelpInputStep] = [
      .press(KeyPress(.character("?"), modifiers: [])),
      .awaitCondition { terminal.latestFrame?.contains(Self.firstRow) == true },
    ]
    steps += Self.awaitFocusFrame(terminal, FrameMark())
    steps += [
      .press(KeyPress(.pageDown, modifiers: [])),
      .awaitCondition { terminal.latestFrame?.contains(Self.firstRow) != true },
      .press(KeyPress(.pageUp, modifiers: [])),
      .awaitCondition { terminal.latestFrame?.contains(Self.firstRow) == true },
    ]
    steps += Array(repeating: .press(KeyPress(.arrowDown, modifiers: [])), count: Self.stepCount)
    steps.append(.awaitCondition { terminal.latestFrame?.contains(Self.firstRow) != true })
    steps += Array(repeating: .press(KeyPress(.arrowUp, modifiers: [])), count: Self.stepCount)
    steps.append(.awaitCondition { terminal.latestFrame?.contains(Self.firstRow) == true })

    let inputReader = HelpInputReader(frameSignal: terminal.frameSignal, steps: steps)
    let result = try await run(terminal: terminal, rootIdentity: rootIdentity, reader: inputReader)

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.latestFrame?.contains("Keyboard shortcuts") == true)
    #expect(terminal.latestFrame?.contains(Self.firstRow) == true)
  }

  /// The overlay owns its scroll keys even when there is nowhere left to
  /// scroll: a `↓` that fell through would reach the editor root behind
  /// the sheet and move the canvas cursor under an overlay the author is
  /// still reading. The footer prints the cursor as `[x,y]`, so a run
  /// that hammers `↓` at the bottom and still reads `[0,0]` afterwards is
  /// a run in which none of them escaped.
  @Test("an exhausted scroll key does not fall through to the editor", .timeLimit(.minutes(5)))
  func scrollKeysAreConsumedAtTheEdges() async throws {
    let terminal = HelpRecordingTerminalHost(surfaceSize: .init(width: 80, height: 24))
    let rootIdentity = Identity(components: ["gifeditor.help-runtime.edges"])

    var steps: [HelpInputStep] = [
      .press(KeyPress(.character("?"), modifiers: [])),
      .awaitCondition { terminal.latestFrame?.contains(Self.firstRow) == true },
    ]
    steps += Self.awaitFocusFrame(terminal, FrameMark())
    steps += [
      .press(KeyPress(.end, modifiers: [])),
      .awaitCondition { terminal.latestFrame?.contains(Self.lastRow) == true },
      // Past the bottom, repeatedly.
      .press(KeyPress(.arrowDown, modifiers: [])),
      .press(KeyPress(.arrowDown, modifiers: [])),
      .press(KeyPress(.pageDown, modifiers: [])),
      .press(KeyPress(.escape, modifiers: [])),
      .awaitCondition {
        terminal.latestFrame?.contains("Keyboard shortcuts") != true
          && terminal.latestFrame?.contains("[0,0]") == true
      },
    ]

    let inputReader = HelpInputReader(frameSignal: terminal.frameSignal, steps: steps)
    let result = try await run(terminal: terminal, rootIdentity: rootIdentity, reader: inputReader)

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains(Self.lastRow) })
    #expect(
      terminal.latestFrame?.contains("[0,0]") == true,
      "an arrow key escaped the overlay and moved the canvas cursor"
    )
  }

  // MARK: - Harness

  /// Two steps that together wait for the frame on which focus lands.
  ///
  /// The overlay asks for focus from a `.task`, which cannot run before
  /// the frame that first shows the sheet; the frame *after* that one is
  /// the first with focus on the list, and a key pressed in between still
  /// goes to the sheet's chrome button. That gap is imperceptible to a
  /// hand on a keyboard and a guaranteed race for a script that presses
  /// keys as fast as the run loop will take them.
  private static func awaitFocusFrame(
    _ terminal: HelpRecordingTerminalHost,
    _ mark: FrameMark
  ) -> [HelpInputStep] {
    [
      .awaitCondition { mark.record(terminal.frames.count) },
      .awaitCondition { terminal.frames.count > (mark.value ?? .max) },
    ]
  }

  private func run(
    terminal: HelpRecordingTerminalHost,
    rootIdentity: Identity,
    reader: HelpInputReader
  ) async throws -> RunLoopResult<Int> {
    try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: reader,
      signalReader: HelpEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 16, height: 16)),
          stateDirectory: helpStateDirectory
        )
      }
    ).run()
  }
}

/// A throwaway state directory with the first-run hint already claimed, so
/// the nudge never lands in a status line these tests read and no run
/// touches the developer's real config.
private let helpStateDirectory: URL = {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-help-\(UUID().uuidString)")
  FirstRunHint.claim(inStateDirectory: directory)
  return directory
}()

/// A one-shot record of the frame count at a moment in a script.
@MainActor
private final class FrameMark {
  private(set) var value: Int?

  /// Records `count` the first time it is asked, and always answers
  /// `true` so it can stand as an `awaitCondition` that resolves
  /// immediately while capturing when it did.
  func record(_ count: Int) -> Bool {
    if value == nil { value = count }
    return true
  }
}

private final class HelpRecordingTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []

  var latestFrame: String? { frames.last }

  /// Notified after every appended frame, so an awaited input step
  /// re-checks its predicate the instant a frame lands instead of polling.
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

private enum HelpInputStep {
  case press(KeyPress)
  /// Suspends the script until `predicate` holds, re-evaluated when the
  /// host appends a frame rather than on a clock.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class HelpInputReader: TerminalInputReading {
  private let steps: [HelpInputStep]
  private let frameSignal: MainActorConditionSignal

  init(frameSignal: MainActorConditionSignal, steps: [HelpInputStep]) {
    self.frameSignal = frameSignal
    self.steps = steps
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let task = Task { @MainActor in
        for step in steps {
          switch step {
          case .press(let event):
            continuation.yield(.key(event))
          case .awaitCondition(let predicate):
            await frameSignal.wait(until: predicate)
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class HelpEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

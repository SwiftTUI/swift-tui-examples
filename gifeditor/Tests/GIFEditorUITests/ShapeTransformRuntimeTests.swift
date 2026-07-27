import Foundation
import GIFEditorCore
import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GIFEditorUI

/// The new bare keys, driven through the real editor and a real run loop.
///
/// The unit suites pin what each command does to the document. What they
/// cannot see is whether a key press arrives at all: a catalog row, a
/// `perform` case and a model method still leave the whole input path
/// untested, and every one of these commands is dispatched off the single
/// `onKeyPress(.any)` handler rather than a registered chord — so if that
/// route stopped resolving, fifteen bindings would go quiet at once and
/// no unit test would notice.
///
/// One session per suite rather than one per key: booting the editor at
/// 80×24 and waiting for it to settle is the expensive part, and the
/// status strip makes a sequence of presses individually readable.
@MainActor
@Suite("GIF editor shape and transform runtime")
struct ShapeTransformRuntimeTests {
  @Test("the shape and symmetry keys reach the editor", .timeLimit(.minutes(1)))
  func toolKeysReachTheEditor() async throws {
    let terminal = ShapeRuntimeTerminalHost(surfaceSize: .init(width: 80, height: 24))
    let inputReader = ShapeRuntimeInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("r"), modifiers: [])),
        .awaitCondition { terminal.latestFrame?.contains("Tool: Rectangle") == true },
        .press(KeyPress(.character("f"), modifiers: [])),
        .awaitCondition { terminal.latestFrame?.contains("Shapes: filled") == true },
        .press(KeyPress(.character("c"), modifiers: [])),
        .awaitCondition { terminal.latestFrame?.contains("Tool: Ellipse") == true },
        .press(KeyPress(.character("s"), modifiers: [])),
        .awaitCondition { terminal.latestFrame?.contains("Mirror-X on") == true },
      ]
    )

    let result = try await run(
      terminal: terminal,
      identity: "gifeditor.shape-runtime.tools",
      inputReader: inputReader
    )

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Tool: Rectangle") })
    #expect(terminal.frames.contains { $0.contains("Shapes: filled") })
    #expect(terminal.latestFrame?.contains("Mirror-X on") == true)
  }

  @Test("the transform and timeline keys reach the editor", .timeLimit(.minutes(1)))
  func commandKeysReachTheEditor() async throws {
    let terminal = ShapeRuntimeTerminalHost(surfaceSize: .init(width: 80, height: 24))
    let inputReader = ShapeRuntimeInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        // Shifted letters, which the terminal delivers as their own
        // characters rather than as `Shift` plus a letter — the same
        // route the onion skin's `O` already takes.
        .press(KeyPress(.character("H"), modifiers: [])),
        .awaitCondition { terminal.latestFrame?.contains("Flipped layer") == true },
        .press(KeyPress(.character("R"), modifiers: [])),
        .awaitCondition { terminal.latestFrame?.contains("Rotated layer") == true },
        .press(KeyPress(.character("d"), modifiers: [])),
        .awaitCondition { terminal.latestFrame?.contains("Frame disposal: keep") == true },
        .press(KeyPress(.character(")"), modifiers: [])),
        .awaitCondition { terminal.latestFrame?.contains("Plays once") == true },
        .press(KeyPress(.character("."), modifiers: [])),
        .awaitCondition { terminal.latestFrame?.contains("Moved frame to 2/2") == true },
      ]
    )

    let result = try await run(
      terminal: terminal,
      identity: "gifeditor.shape-runtime.commands",
      inputReader: inputReader
    )

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Flipped layer") })
    #expect(terminal.frames.contains { $0.contains("Rotated layer") })
    #expect(terminal.frames.contains { $0.contains("Frame disposal: keep") })
    #expect(terminal.frames.contains { $0.contains("Plays once") })
    // The timeline's own readout followed the loop count the key set.
    #expect(terminal.latestFrame?.contains("once") == true)
  }

  // MARK: - Harness

  private func run(
    terminal: ShapeRuntimeTerminalHost,
    identity: String,
    inputReader: ShapeRuntimeInputReader
  ) async throws -> RunLoopResult<Int> {
    let rootIdentity = Identity(components: [identity])
    let document = twoFrameDocument()
    return try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: ShapeRuntimeEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(document: document, stateDirectory: shapeRuntimeStateDirectory)
      }
    ).run()
  }

  /// Two frames, so the frame-position key has somewhere to move to, and
  /// filled rather than blank so a flip or a rotation has something to
  /// act on.
  private func twoFrameDocument() -> GIFDocument {
    let size = GIFEditorCore.PixelSize(width: 8, height: 8)
    let frames = (0..<2).map { index -> EditorFrame in
      var pixels = PixelBuffer(size: size, fill: PaletteIndex(1 + index))
      pixels[GIFEditorCore.PixelPoint(x: 0, y: 0)] = 6
      return EditorFrame(
        layers: [EditorLayer(name: "Layer 1", pixels: pixels)],
        delayCentiseconds: 10
      )
    }
    return GIFDocument(size: size, frames: frames)
  }
}

/// A throwaway state directory with the first-run hint already claimed, so
/// the nudge never lands in a status line these tests read and no run
/// touches the developer's real config.
private let shapeRuntimeStateDirectory: URL = {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-shape-runtime-\(UUID().uuidString)")
  FirstRunHint.claim(inStateDirectory: directory)
  return directory
}()

private final class ShapeRuntimeTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []

  var latestFrame: String? { frames.last }

  /// Notified after every appended frame, so an awaited input step
  /// re-checks its predicate the instant a frame lands instead of
  /// polling.
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

private enum ShapeRuntimeInputStep {
  case press(KeyPress)
  /// Suspends the script until `predicate` holds, re-evaluated when the
  /// host appends a frame rather than on a clock.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class ShapeRuntimeInputReader: TerminalInputReading {
  private let steps: [ShapeRuntimeInputStep]
  private let frameSignal: MainActorConditionSignal

  init(frameSignal: MainActorConditionSignal, steps: [ShapeRuntimeInputStep]) {
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

private final class ShapeRuntimeEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

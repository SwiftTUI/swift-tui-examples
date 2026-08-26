import Foundation
import GIFEditorCore
import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GIFEditorUI

/// The onion-skin keys, driven through the real editor and a real run loop.
///
/// The unit tests pin the blend and the frame selection. What they cannot
/// see is whether the four bare keys reach anything: onion skin is the first
/// feature to go through `KeyBindingCatalog`, and a catalog row plus a
/// `perform` case still leaves "does the key press arrive" untested. These
/// press the keys and read the editor's own status strip back.
///
/// They also carry the strongest available statement of *display only*: the
/// menu bar's dirty marker is `●` when the document has unsaved work and `✓`
/// when it does not, so a run that toggles every onion-skin control and never
/// paints a `●` is a run in which none of them wrote to the document.
@MainActor
@Suite("GIF editor onion skin runtime", .serialized)
struct OnionSkinRuntimeTests {
  @Test("o toggles onion skin, and the status strip says so", .timeLimit(.minutes(1)))
  func bareOTogglesOnionSkin() async throws {
    let terminal = OnionSkinRecordingTerminalHost(surfaceSize: .init(width: 80, height: 24))
    let rootIdentity = Identity(components: ["gifeditor.onionskin-runtime.toggle"])

    let inputReader = OnionSkinInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("o"), modifiers: [])),
        .awaitCondition {
          terminal.latestFrame?.contains("Onion skin on") == true
        },
        .press(KeyPress(.character("o"), modifiers: [])),
        .awaitCondition {
          terminal.latestFrame?.contains("Onion skin off") == true
        },
      ]
    )

    let result = try await run(
      terminal: terminal,
      rootIdentity: rootIdentity,
      inputReader: inputReader
    )

    #expect(result.exitReason == .inputEnded)
    // On: the announcement and the persistent readout both appear.
    #expect(terminal.frames.contains { $0.contains("Onion skin on (both ×1)") })
    #expect(terminal.frames.contains { $0.contains("onion both×1") })
    // Off: the readout goes away again rather than lingering.
    #expect(terminal.latestFrame?.contains("Onion skin off") == true)
    #expect(terminal.latestFrame?.contains("onion both") != true)
    expectTheDocumentStayedClean(terminal)
  }

  @Test("O cycles the ghosted sides and { } change the count", .timeLimit(.minutes(1)))
  func onionSkinSettingKeysReachTheEditor() async throws {
    let terminal = OnionSkinRecordingTerminalHost(surfaceSize: .init(width: 80, height: 24))
    let rootIdentity = Identity(components: ["gifeditor.onionskin-runtime.settings"])

    let inputReader = OnionSkinInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        // `}` on its own turns onion skin on, which is the whole reason
        // the count keys are allowed to enable it.
        .press(KeyPress(.character("}"), modifiers: [])),
        .awaitCondition {
          terminal.latestFrame?.contains("Onion skin on (both ×2)") == true
        },
        .press(KeyPress(.character("{"), modifiers: [])),
        .awaitCondition {
          terminal.latestFrame?.contains("Onion skin on (both ×1)") == true
        },
        .press(KeyPress(.character("O"), modifiers: [])),
        .awaitCondition {
          terminal.latestFrame?.contains("Onion skin on (prev ×1)") == true
        },
        .press(KeyPress(.character("O"), modifiers: [])),
        .awaitCondition {
          terminal.latestFrame?.contains("Onion skin on (next ×1)") == true
        },
      ]
    )

    let result = try await run(
      terminal: terminal,
      rootIdentity: rootIdentity,
      inputReader: inputReader
    )

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Onion skin on (both ×2)") })
    #expect(terminal.frames.contains { $0.contains("Onion skin on (prev ×1)") })
    #expect(terminal.latestFrame?.contains("onion next×1") == true)
    expectTheDocumentStayedClean(terminal)
  }

  // MARK: - Harness

  /// The menu bar's trailing marker is `●` when the document has unsaved
  /// work and `✓` when it does not. It is the first line of every rendered
  /// frame, which is why this reads that line rather than the whole frame —
  /// `●` is also the layer list's visibility glyph.
  private func expectTheDocumentStayedClean(_ terminal: OnionSkinRecordingTerminalHost) {
    let topLines = terminal.frames.compactMap {
      $0.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init)
    }
    #expect(
      topLines.contains { $0.contains("✓") },
      "the clean marker must actually be on screen, or the check below is vacuous"
    )
    #expect(
      topLines.allSatisfy { !$0.contains("●") },
      "onion skin is display state and must never mark the document dirty"
    )
  }

  private func run(
    terminal: OnionSkinRecordingTerminalHost,
    rootIdentity: Identity,
    inputReader: OnionSkinInputReader
  ) async throws -> RunLoopResult<Int> {
    let document = twoFrameDocument()
    return try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: OnionSkinEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(document: document, stateDirectory: onionSkinStateDirectory)
      }
    ).run()
  }

  private func twoFrameDocument() -> GIFDocument {
    let size = GIFEditorCore.PixelSize(width: 8, height: 8)
    let first = EditorFrame(
      layers: [EditorLayer(name: "Frame 1", pixels: PixelBuffer(size: size, fill: 1))],
      delayCentiseconds: 10
    )
    let second = EditorFrame(
      layers: [EditorLayer(name: "Frame 2", pixels: PixelBuffer(size: size, fill: 2))],
      delayCentiseconds: 10
    )
    return GIFDocument(size: size, frames: [first, second])
  }
}

/// A throwaway state directory with the first-run hint already claimed, so
/// the nudge never lands in a status line these tests read and no run touches
/// the developer's real config.
private let onionSkinStateDirectory: URL = {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-onionskin-\(UUID().uuidString)")
  FirstRunHint.claim(inStateDirectory: directory)
  return directory
}()

private final class OnionSkinRecordingTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []

  var latestFrame: String? { frames.last }

  /// Notified after every appended frame, so an awaited input step re-checks
  /// its predicate the instant a frame lands instead of polling.
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

private enum OnionSkinInputStep {
  case press(KeyPress)
  /// Suspends the script until `predicate` holds, re-evaluated when the host
  /// appends a frame rather than on a clock.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class OnionSkinInputReader: TerminalInputReading {
  private let steps: [OnionSkinInputStep]
  private let frameSignal: MainActorConditionSignal

  init(frameSignal: MainActorConditionSignal, steps: [OnionSkinInputStep]) {
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

private final class OnionSkinEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

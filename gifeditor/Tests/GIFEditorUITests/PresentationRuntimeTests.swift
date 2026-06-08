import GIFEditorCore
import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GIFEditorUI

@MainActor
@Suite("GIF editor presentation runtime")
struct PresentationRuntimeTests {
  @Test("Ctrl+S opens the unified save sheet with encoded preview")
  func ctrlSOpensUnifiedSaveSheetWithEncodedPreview() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.save-sheet"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("s"), modifiers: .ctrl)),
        .awaitCondition {
          terminal.latestFrame?.contains("Save GIF") == true
            && terminal.latestFrame?.contains("Encoded preview") == true
            && terminal.latestFrame?.contains("Destination") == true
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(document: GIFDocument.blank(size: .init(width: 16, height: 16)))
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Save GIF") })
    #expect(!terminal.frames.contains { $0.contains("Save As") })
  }

  @Test("Alt+P toggles playback mode")
  func altPTogglesPlaybackMode() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.playback"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("p"), modifiers: .alt)),
        .awaitCondition {
          terminal.latestFrame?.contains("Playback started") == true
            && terminal.latestFrame?.contains("PLAY") == true
        },
        .press(KeyPress(.character("p"), modifiers: .alt)),
        .awaitCondition {
          terminal.latestFrame?.contains("Playback paused") == true
            && terminal.latestFrame?.contains("PLAY") == false
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(document: playbackDocument())
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Playback started") })
    #expect(terminal.latestFrame?.contains("Playback paused") == true)
    #expect(!terminal.frames.contains { $0.contains("Keyboard help") })
  }

  @Test("question mark no longer opens keyboard help")
  func questionMarkNoLongerOpensKeyboardHelp() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.no-help"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("?"), modifiers: [])),
        .press(KeyPress(.character("]"), modifiers: [])),
        .awaitCondition {
          terminal.frames.contains { $0.contains("B2") }
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(document: GIFDocument.blank(size: .init(width: 16, height: 16)))
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    #expect(!terminal.frames.contains { $0.contains("Keyboard help") })
    #expect(terminal.frames.contains { $0.contains("B2") })
  }

}

private func playbackDocument() -> GIFDocument {
  let size = GIFEditorCore.PixelSize(width: 4, height: 4)
  let first = EditorFrame(
    layers: [EditorLayer(name: "Frame 1", pixels: PixelBuffer(size: size, fill: 1))],
    delayCentiseconds: 1
  )
  let second = EditorFrame(
    layers: [EditorLayer(name: "Frame 2", pixels: PixelBuffer(size: size, fill: 2))],
    delayCentiseconds: 1
  )
  return GIFDocument(size: size, frames: [first, second])
}

private final class GIFEditorPresentationRecordingTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  private(set) var frames: [String] = []

  var latestFrame: String? {
    frames.last
  }

  /// Notified after every appended frame, so an awaited input step can
  /// re-check its predicate the instant a frame lands instead of polling.
  let frameSignal = MainActorConditionSignal()

  init(
    surfaceSize: CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSize = surfaceSize
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    ).render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
    return TerminalPresentationMetrics(
      bytesWritten: rendered.utf8.count,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
  }

  /// The run loop only ever presents on the MainActor; `assumeIsolated`
  /// bridges these nonisolated protocol witnesses to the MainActor-isolated
  /// signal.
  private func notifyFrameObservers() {
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
  }
}

private enum GIFEditorPresentationInputStep {
  case press(KeyPress)
  case click(CellPoint)
  /// Suspends the input script until `predicate` holds, re-evaluated only when
  /// the host appends a frame (`frameSignal.notify()`) rather than on a clock.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class GIFEditorPresentationInputReader: TerminalInputReading {
  private let steps: [GIFEditorPresentationInputStep]
  private let frameSignal: MainActorConditionSignal

  init(
    frameSignal: MainActorConditionSignal,
    steps: [GIFEditorPresentationInputStep]
  ) {
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
          case .click(let cell):
            continuation.yield(
              .mouse(.init(kind: .down(.primary), location: .cellFallback(cell)))
            )
            continuation.yield(
              .mouse(.init(kind: .up(.primary), location: .cellFallback(cell)))
            )
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

private final class GIFEditorPresentationEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

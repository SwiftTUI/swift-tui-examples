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
///
/// The height cases are here for a sharper reason. Every runtime test in this
/// package runs at 80×24 and, for as long as they existed, every one of them
/// was asserting against a **28-row surface presented into a 24-row terminal**
/// — the run loop handed the host a surface taller than the screen and nothing
/// clipped it, so the four rows that fell off the bottom were invisible to a
/// test that only ever asked what the frame *contained*. So the test that
/// would have caught it asks the one question none of them did: how tall is
/// the surface the run loop presented.
@MainActor
@Suite("GIF editor terminal fit runtime")
struct TerminalFitRuntimeTests {
  @Test(
    "one column under the floor, the editor says so instead of overflowing",
    .timeLimit(.minutes(5))
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

  @Test("at the floor exactly, the editor lays out normally", .timeLimit(.minutes(5)))
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
    .timeLimit(.minutes(5))
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

  // MARK: - Height

  /// **The test the defect survived the absence of.**
  ///
  /// 80×24 is the terminal a default window opens at and the size every other
  /// runtime test in this package runs at. What is checked here is not what
  /// the frame says but what shape it is: every surface the run loop presents
  /// has to fit inside the terminal it is presented into, on both axes, and
  /// every region of the editor has to still be in it.
  ///
  /// The document is deliberately not the blank one — six layers and twelve
  /// frames, so the layer list is past its window and the timeline strip has
  /// to scroll. A blank document is the *easiest* case, and the editor's
  /// height has to be a property of the layout rather than of the file.
  @Test("at 80×24 the presented surface fits the terminal", .timeLimit(.minutes(5)))
  func theEditorFitsTheDefaultTerminal() async throws {
    let terminal = FitRecordingTerminalHost(surfaceSize: .init(width: 80, height: 24))

    let result = try await run(
      terminal: terminal,
      identity: "gifeditor.terminal-fit.eighty-by-twentyfour",
      document: Self.crowdedDocument,
      until: { terminal.latestFrame?.contains("Ready") == true }
    )
    #expect(result.exitReason == .inputEnded)

    let surfaces = terminal.surfaces
    #expect(!surfaces.isEmpty, "the run loop presented nothing to measure")
    for surface in surfaces {
      #expect(
        surface.size.height <= 24,
        """
        the run loop presented a \(surface.size.height)-row surface into a \
        24-row terminal. The rows past the 24th are not clipped by anything — \
        they are simply not on screen, and nothing in the editor says so.
        """
      )
      #expect(
        surface.size.width <= 80,
        "the run loop presented a \(surface.size.width)-column surface into 80 columns"
      )
    }

    // And it is the editor, whole — not a shorter surface that fits because
    // something fell off it.
    let frame = try #require(terminal.latestFrame)
    #expect(!frame.contains("Terminal too small"))
    #expect(frame.contains("File ▾"), "the menu bar is missing")
    #expect(frame.contains("Pen"), "the tool options bar is missing")
    #expect(frame.contains("Palette"), "the inspector is missing")
    #expect(frame.contains("Layers"), "the layer list is missing")
    #expect(frame.contains("New layer"), "the inspector's last row fell off the bottom")
    #expect(frame.contains("Frames"), "the timeline is missing")
    #expect(frame.contains("Ready"), "the status strip is missing")
    for tool in ActiveTool.allCases {
      #expect(
        frame.contains(tool.iconGlyph),
        "\(tool.label)'s dock icon is not on screen at 80×24"
      )
    }
  }

  /// The height floor, both sides of it, through the run loop — the same pair
  /// the width cases make, on the axis that had no answer at all until the
  /// editor learned to compress.
  @Test("one row under the height floor, the editor says so", .timeLimit(.minutes(5)))
  func belowTheHeightFloorTheEditorExplainsItself() async throws {
    let height = EditorLayoutFloor.minimumHeight - 1
    let terminal = FitRecordingTerminalHost(surfaceSize: .init(width: 80, height: height))

    _ = try await run(
      terminal: terminal,
      identity: "gifeditor.terminal-fit.under-height-floor",
      document: Self.crowdedDocument,
      until: { terminal.latestFrame?.contains("Terminal too small") == true }
    )

    let frame = try #require(terminal.latestFrame)
    #expect(frame.contains("\(EditorLayoutFloor.minimumHeight) rows"))
    #expect(frame.contains("80×\(height)"))
    #expect(!frame.contains("Palette"), "the editor is still on screen under its own floor")
    for surface in terminal.surfaces {
      #expect(surface.size.height <= height, "even the apology overran the terminal")
    }
  }

  @Test("at the height floor exactly, the editor lays out", .timeLimit(.minutes(5)))
  func atTheHeightFloorTheEditorRuns() async throws {
    let height = EditorLayoutFloor.minimumHeight
    let terminal = FitRecordingTerminalHost(surfaceSize: .init(width: 80, height: height))

    _ = try await run(
      terminal: terminal,
      identity: "gifeditor.terminal-fit.at-height-floor",
      document: Self.crowdedDocument,
      until: { terminal.latestFrame?.contains("Ready") == true }
    )

    let frame = try #require(terminal.latestFrame)
    #expect(!frame.contains("Terminal too small"))
    #expect(frame.contains("Palette"))
    #expect(frame.contains("Frames"))
    #expect(frame.contains("New layer"))
    for surface in terminal.surfaces {
      #expect(
        surface.size.height <= height,
        "the editor presented \(surface.size.height) rows into its own \(height)-row floor"
      )
    }
  }

  // MARK: - Harness

  /// Six layers and twelve frames: the two things in a document that make the
  /// editor taller, both past the point where the layout has to bound them.
  private static let crowdedDocument: GIFDocument = {
    let size = GIFEditorCore.PixelSize(width: 8, height: 8)
    let frame = EditorFrame(
      layers: (0..<6).map {
        EditorLayer(name: "Layer \($0 + 1)", pixels: PixelBuffer(size: size))
      },
      delayCentiseconds: 10
    )
    return GIFDocument(size: size, frames: Array(repeating: frame, count: 12))
  }()

  private func run(
    terminal: FitRecordingTerminalHost,
    identity: String,
    document: GIFDocument = GIFDocument.blank(
      size: GIFEditorCore.PixelSize(width: 8, height: 8)
    ),
    until predicate: @escaping @MainActor () -> Bool
  ) async throws -> RunLoopResult<Int> {
    let rootIdentity = Identity(components: [identity])
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
  /// Every surface the run loop handed over, kept unrendered.
  ///
  /// The rendered string cannot answer the question the height cases ask: a
  /// terminal renderer emits escape sequences, so counting its lines counts
  /// styling as well as rows. The surface knows its own size, and that size —
  /// against the size of the terminal it was presented into — is the whole
  /// claim.
  private(set) var surfaces: [RasterSurface] = []

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
    surfaces.append(surface)
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

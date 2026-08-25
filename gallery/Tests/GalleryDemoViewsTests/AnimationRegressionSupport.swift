import Foundation
@_spi(Testing) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import Testing

// Shared harness pieces for the Animations tab's runtime tests
// (`AnimationRegressionTests`, `AnimationSectionRuntimeTests`): a recording
// presentation surface, an awaited-input reader whose steps re-check their
// predicates only when a frame lands (under the gallery wait ceiling), and
// the static-render helpers that locate a control before the run loop starts.

enum AnimationRegressionAwaitedInputStep {
  case event(InputEvent)
  /// Suspends the input script until `predicate` holds, re-evaluated only when
  /// the host presents a new frame (`frameSignal.notify()`) rather than on a
  /// clock, so a merely *starved* run loop slows the test rather than failing
  /// it.
  ///
  /// The wait carries a last-resort wall-clock ceiling (see
  /// ``withGalleryWaitCeiling``): if the animation stops presenting entirely,
  /// no further `notify()` ever arrives and the predicate can never be
  /// re-checked. Before that ceiling existed this step could park forever; on
  /// 2026-08-19 it hung the org examples gate for its full 1h15m cap three
  /// runs running, silent for 47 minutes.
  case awaitCondition(predicate: @MainActor () -> Bool)
  /// Paces the script: waits `duration` before the next step. Not a
  /// synchronization tool (waits on state use `awaitCondition`); it spaces
  /// synthetic pointer samples so a drag's velocity is plausible.
  case sleep(Duration)
  /// Yields `events` every `interval` until `predicate` holds, checking the
  /// predicate before each nudge. For state the runtime only advances on
  /// its next committed turn: a run loop that has gone idle never presents
  /// again on its own, so `awaitCondition` alone could not observe it.
  /// Bounded by the same ceiling as `awaitCondition`.
  case nudge([InputEvent], every: Duration, until: @MainActor () -> Bool)

  /// A primary-button press and release at `location`.
  static func click(_ location: Point) -> [Self] {
    [
      .event(.mouse(.init(kind: .down(.primary), location: location))),
      .event(.mouse(.init(kind: .up(.primary), location: location))),
    ]
  }

  /// Ctrl+C, the framework's default exit binding (swift-tui 11a77aa0).
  static let exit: Self = .event(.key(KeyPress(.character("c"), modifiers: .ctrl)))
}

extension [AnimationRegressionAwaitedInputStep] {
  /// The events of a script made only of `.event` steps (a click), for
  /// replaying inside a `.nudge`.
  var events: [InputEvent] {
    compactMap { step in
      if case .event(let event) = step {
        return event
      }
      return nil
    }
  }
}

final class AnimationRegressionAwaitedInputReader: TerminalInputReading {
  private let steps: [AnimationRegressionAwaitedInputStep]
  private let frameSignal: MainActorConditionSignal
  private let waitCeilingNanoseconds: UInt64
  private let waitFailure = GalleryWaitFailureRecorder()

  init(
    frameSignal: MainActorConditionSignal,
    waitCeilingNanoseconds: UInt64 = galleryWaitCeilingNanoseconds,
    steps: [AnimationRegressionAwaitedInputStep]
  ) {
    self.frameSignal = frameSignal
    self.waitCeilingNanoseconds = waitCeilingNanoseconds
    self.steps = steps
  }

  @MainActor
  func requireNoWaitFailure() async throws {
    try await waitFailure.requireNoFailure()
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let waitCeilingNanoseconds = self.waitCeilingNanoseconds
      let waitFailure = self.waitFailure
      let task = Task { @MainActor in
        for (index, step) in steps.enumerated() {
          switch step {
          case .event(let event):
            continuation.yield(event)
          case .sleep(let duration):
            try? await Task.sleep(for: duration)
          case .nudge(let events, let interval, let predicate):
            let started = MonotonicInstant.now()
            let ceiling = Duration.nanoseconds(Int64(waitCeilingNanoseconds))
            while !predicate() {
              if started.duration(to: .now()) >= ceiling {
                await waitFailure.record(
                  GalleryWaitCeilingExceeded(
                    label: "animation regression nudged input step \(index)",
                    nanoseconds: waitCeilingNanoseconds
                  )
                )
                continuation.finish()
                return
              }
              try? await Task.sleep(for: interval)
              guard !Task.isCancelled else {
                continuation.finish()
                return
              }
              for event in events {
                continuation.yield(event)
              }
            }
          case .awaitCondition(let predicate):
            do {
              try await withGalleryWaitCeiling(
                "animation regression awaited input step \(index)",
                nanoseconds: waitCeilingNanoseconds
              ) {
                await frameSignal.wait(until: predicate)
              }
            } catch let failure as GalleryWaitCeilingExceeded {
              await waitFailure.record(failure)
              continuation.finish()
              return
            } catch {
              continuation.finish()
              return
            }
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

final class AnimationRegressionEmptySignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

final class AnimationRegressionRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var surfaces: [RasterSurface] = []
  /// When each surface was presented, measured from the host's creation, so
  /// a frame strip can carry a timestamp per frame.
  private(set) var presentedAt: [Duration] = []
  private let epoch = MonotonicInstant.now()

  /// Notified after every present, so an awaited input step can re-check its
  /// predicate the instant a frame lands instead of polling under a timeout.
  let frameSignal = MainActorConditionSignal()

  init(size: CellSize) {
    surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    surfaces.append(surface)
    presentedAt.append(epoch.duration(to: .now()))
    // The run loop only ever presents on the MainActor; `assumeIsolated`
    // bridges this nonisolated witness to the MainActor-isolated signal.
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }
}

@MainActor
enum AnimationRegressionHarness {
  /// The center of the first occurrence of `target` in a static render of
  /// `view`, for aiming a pointer event before the run loop starts. With
  /// `after`, the search starts on the first row containing that anchor.
  static func centerOfText(
    _ target: String,
    after anchor: String? = nil,
    in view: some View,
    terminalSize: CellSize,
    rootIdentity: Identity
  ) throws -> Point {
    let surface = renderSurface(view, terminalSize: terminalSize, rootIdentity: rootIdentity)
    var firstRow = 0
    if let anchor {
      firstRow = try #require(
        surface.lines.firstIndex { $0.contains(anchor) },
        "\(anchor) is not on the static render of the view"
      )
    }
    let bounds = try #require(
      boundsOfText(target, in: surface, from: firstRow),
      "\(target) is not on the static render of the view below row \(firstRow)"
    )
    return Point(
      CellPoint(
        x: bounds.origin.x + bounds.size.width / 2,
        y: bounds.origin.y + bounds.size.height / 2
      )
    )
  }

  static func renderSurface(
    _ view: some View,
    terminalSize: CellSize,
    rootIdentity: Identity
  ) -> RasterSurface {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let artifacts = DefaultRenderer().render(
      AnyView(view),
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )
    return artifacts.rasterSurface
  }

  static func boundsOfText(
    _ target: String,
    in surface: RasterSurface,
    from firstRow: Int = 0
  ) -> CellRect? {
    for (row, line) in surface.lines.enumerated() where row >= firstRow {
      guard let range = line.range(of: target) else {
        continue
      }

      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return CellRect(
        origin: CellPoint(x: column, y: row),
        size: CellSize(width: target.count, height: 1)
      )
    }
    return nil
  }

  /// The column `target` starts at in the first line of `surface` containing
  /// it, or `nil`.
  static func column(of target: String, in surface: RasterSurface) -> Int? {
    boundsOfText(target, in: surface)?.origin.x
  }

  static func run<V: View>(
    host: AnimationRegressionRecordingHost,
    terminalSize: CellSize,
    rootIdentity: Identity,
    inputReader: any TerminalInputReading,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var env = EnvironmentValues()
    env.terminalAppearance = host.appearance
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: inputReader,
      signalReader: AnimationRegressionEmptySignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      environmentValues: env,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder() }
    )
    return try await runLoop.run()
  }
}

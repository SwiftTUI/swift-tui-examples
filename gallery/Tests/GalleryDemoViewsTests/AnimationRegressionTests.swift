import Foundation
@_spi(Testing) import SwiftTUI
@_spi(Runners) import SwiftTUIProfiling
@_spi(Runners) import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite(.serialized)
struct AnimationRegressionTests {
  @Test(
    "AnimationsTab offset button commits animated offset on the Basics page")
  func animationsTabOffsetButtonCommitsAnimatedOffsetWhilePhaseAnimatorIsVisible()
    async throws
  {
    let terminalSize = CellSize(width: 96, height: 60)
    let rootIdentity = Identity(components: [.named("AnimationsTabOffsetRegression")])
    let buttonLocation = try AnimationRegressionHarness.centerOfText(
      "right",
      in: AnimationsTab(initialPage: .basics),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity
    )
    let host = AnimationRegressionRecordingHost(size: terminalSize)
    var initialColumn: Int?
    var framesBeforeToggle = 0
    var markerColumnsAfterToggle: [Int] = []

    let inputReader = AnimationRegressionAwaitedInputReader(
      frameSignal: host.frameSignal,
      steps: [
        .awaitCondition {
          let markerColumns = Self.slideMarkerColumns(in: host.surfaces)
          guard let latestColumn = markerColumns.last else {
            return false
          }
          initialColumn = latestColumn
          framesBeforeToggle = host.surfaces.count
          return true
        },
        .event(.mouse(.init(kind: .down(.primary), location: buttonLocation))),
        .event(.mouse(.init(kind: .up(.primary), location: buttonLocation))),
        .awaitCondition {
          guard let initialColumn else {
            return false
          }
          markerColumnsAfterToggle = Array(
            Self.slideMarkerColumns(in: host.surfaces)
              .dropFirst(framesBeforeToggle)
          )
          return markerColumnsAfterToggle.contains(initialColumn + 30)
        },
        // Ctrl+C is the framework's default exit binding (swift-tui 11a77aa0).
        .event(.key(KeyPress(.character("c"), modifiers: .ctrl))),
      ])

    let result = try await AnimationRegressionHarness.run(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      inputReader: inputReader,
      viewBuilder: { AnimationsTab(initialPage: .basics) }
    )

    // Fails with the named budget diagnostic if the animation stopped
    // presenting frames, instead of leaving the assertions below to report a
    // confusing mismatch against a truncated capture.
    try await inputReader.requireNoWaitFailure()

    let startingColumn = try #require(initialColumn)
    let finalColumn = startingColumn + 30
    let renderedFinalFrame = markerColumnsAfterToggle.contains(finalColumn)

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(
      renderedFinalFrame,
      """
      Expected clicking the real AnimationsTab "right" button to move the \
      slide marker from column \(startingColumn) to \(finalColumn). Captured \
      marker columns after input: \(markerColumnsAfterToggle).
      """
    )
  }

  @Test(
    "diagnostics expose animation intent and cancellation state on the gallery path")
  func diagnosticsExposeAnimationIntentAndCancellationStateOnGalleryPath()
    async throws
  {
    let terminalSize = CellSize(width: 96, height: 60)
    let sceneID = "AnimationsTabOffsetDiagnostics"
    let rootIdentity = Self.sceneRootIdentity(sceneID)
    let buttonLocation = try AnimationRegressionHarness.centerOfText(
      "right",
      in: AnimationsTab(initialPage: .basics),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity
    )
    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-animation-regression-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }
    let host = AnimationRegressionRecordingHost(size: terminalSize)
    var initialColumn: Int?
    var framesBeforeToggle = 0
    var markerColumnsAfterToggle: [Int] = []

    let inputReader = AnimationRegressionAwaitedInputReader(
      frameSignal: host.frameSignal,
      steps: [
        .awaitCondition {
          let markerColumns = Self.slideMarkerColumns(in: host.surfaces)
          guard let latestColumn = markerColumns.last else {
            return false
          }
          initialColumn = latestColumn
          framesBeforeToggle = host.surfaces.count
          return true
        },
        .event(.mouse(.init(kind: .down(.primary), location: buttonLocation))),
        .event(.mouse(.init(kind: .up(.primary), location: buttonLocation))),
        .awaitCondition {
          guard let initialColumn else {
            return false
          }
          markerColumnsAfterToggle = Array(
            Self.slideMarkerColumns(in: host.surfaces)
              .dropFirst(framesBeforeToggle)
          )
          return markerColumnsAfterToggle.contains(initialColumn + 30)
        },
        .event(.key(KeyPress(.character("c"), modifiers: .ctrl))),
      ])

    let result = try await Self.runDiagnosticsSceneHarness(
      host: host,
      terminalSize: terminalSize,
      sceneID: sceneID,
      inputReader: inputReader,
      diagnosticsPath: diagnosticsURL.path,
      viewBuilder: { AnimationsTab(initialPage: .basics) }
    )

    try await inputReader.requireNoWaitFailure()

    let startingColumn = try #require(initialColumn)
    let finalColumn = startingColumn + 30
    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(
      markerColumnsAfterToggle.contains(finalColumn),
      "expected the diagnostic probe to click the real gallery offset button"
    )

    let rows = Self.diagnosticRows(
      try String(contentsOf: diagnosticsURL, encoding: .utf8)
    )
    let animationCommitIndex = rows.firstIndex { row in
      row["tail_job_state"] == "completed"
        && row["stale_frame_policy"] == "commit_ordered"
        && row["scheduled_animation_request"] == "animate"
        && (Int(row["animation_controller_active_animations"] ?? "") ?? 0) > 0
    }
    #expect(
      animationCommitIndex != nil,
      """
      Expected diagnostics to record the real gallery button click committing \
      under explicit animation intent. Rows: \(rows).
      """
    )

    let cancellationRows = rows.filter { row in
      row["tail_job_state"] == "cancelled_before_start"
    }
    #expect(
      cancellationRows.allSatisfy { row in
        row["tail_cancel_reason"] == "newer_render_intent"
          && row["stale_frame_policy"] == "cancel_pending_before_start"
          && row["scheduled_animation_request"] != nil
          && row["animation_controller_pending_work"] != nil
      },
      """
      Expected any gallery pre-start cancellation diagnostics to include the \
      cancellation reason, policy, animation request, and pending-work fields. \
      Rows: \(rows).
      """
    )

    let cancelledAnimationIndex = rows.firstIndex { row in
      row["tail_job_state"] == "cancelled_before_start"
        && row["tail_cancel_reason"] == "newer_render_intent"
        && row["scheduled_animation_request"] == "animate"
        && row["scheduled_animation_batch"] == "-"
    }
    if let cancelledAnimationIndex {
      let replayedAnimationCommit = rows.suffix(from: rows.index(after: cancelledAnimationIndex))
        .contains { row in
          row["tail_job_state"] == "completed"
            && row["stale_frame_policy"] == "commit_ordered"
            && row["scheduled_animation_request"] == "animate"
            && row["scheduled_animation_batch"] == "-"
        }
      #expect(
        replayedAnimationCommit,
        """
        Expected an animation-bearing cancelled frame to be followed by a \
        committed frame that still carries animation intent. A committed final \
        visual state under inherited animation means the one-shot transaction \
        was consumed before commit. Rows: \(rows).
        """
      )
    }
  }

  private static func sceneRootIdentity(_ sceneID: String) -> Identity {
    Identity(components: ["App", WindowIdentifier(sceneID).rawValue])
  }

  private static func slideMarkerColumns(
    in surfaces: [RasterSurface]
  ) -> [Int] {
    surfaces.compactMap { surface in
      surface.lines.compactMap { line in
        line.range(of: "slide me")?.lowerBound.utf16Offset(in: line)
      }
      .first
    }
  }

  private static func runDiagnosticsSceneHarness<V: View>(
    host: AnimationRegressionRecordingHost,
    terminalSize _: CellSize,
    sceneID: String,
    inputReader: any TerminalInputReading,
    diagnosticsPath: String,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<SceneSessionState> {
    let scene = WindowGroup(id: WindowIdentifier(sceneID)) {
      viewBuilder()
    }
    let selections = collectWindowSceneSelections(from: scene)
    let selection = try #require(selections.first)
    #expect(selections.count == 1)

    let frameSink = try #require(TSVFileSink(path: diagnosticsPath))
    return try await selection.run(
      sessionName: "AnimationRegressionTests.\(sceneID)",
      resources: SceneSessionResources(
        presentationSurface: host,
        terminalInputReader: inputReader,
        signalReader: AnimationRegressionEmptySignals(),
        scheduler: FrameScheduler(),
        frameSink: frameSink,
        renderMode: .sync
      ),
      stateContainer: StateContainer(
        initialState: SceneSessionState(),
        invalidationIdentities: [selection.rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [selection.rootIdentity])
    )
  }

  private static func diagnosticRows(_ text: String) -> [[String: String]] {
    let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
    guard let headerLine = lines.first else {
      return []
    }
    let headers = headerLine.components(separatedBy: "\t")
    return lines.dropFirst().map { line in
      let fields = line.components(separatedBy: "\t")
      var row: [String: String] = [:]
      for (index, header) in headers.enumerated() where index < fields.count {
        row[header] = fields[index]
      }
      return row
    }
  }
}

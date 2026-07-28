import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

/// The timeline verbs that had no keyboard route: send-to-either-end,
/// the disposal cycle, the loop-count steppers and the delay reset.
///
/// `TimelineCompletenessTests` already pins what these edits *do* — it
/// was written alongside the pointer controls that drove them. What is
/// new is that a key now runs them, and the property that matters most
/// once a key can be leaned on is the one the timeline column proved for
/// the mouse: **none of these four touch a composited colour**, so none
/// of them may recomposite a frame. Every assertion below runs with the
/// oracle on, so "recomputed nothing" is checked against "and what it
/// served instead was still right".
@MainActor
@Suite("GIF editor timeline commands")
struct TimelineCommandTests {

  // MARK: - Send to either end

  @Test("Send-to-start is the same edit as a drag onto the first slot")
  func moveToStartMatchesTheReorderDrag() {
    // One document, two view models: `EditorFrame` mints a fresh id per
    // instance, so comparing ids is the only comparison that says the two
    // paths moved the *same* frames rather than merely arriving at the
    // same colours.
    let document = filledDocument(frames: 5)
    let sent = EditingSession(document: document)
    let dragged = EditingSession(document: document)

    sent.selectFrame(at: 3)
    sent.moveCurrentFrameToStart()
    dragged.moveFrame(from: 3, to: 0)

    #expect(sent.document.frames.map(\.id) == dragged.document.frames.map(\.id))
    #expect(sent.currentFrameIndex == dragged.currentFrameIndex)
    #expect(sent.currentFrameIndex == 0)
    #expect(sent.document.frames.map(\.id) != document.frames.map(\.id))
  }

  @Test("Send-to-end is the same edit as a drag onto the last slot")
  func moveToEndMatchesTheReorderDrag() {
    let document = filledDocument(frames: 5)
    let sent = EditingSession(document: document)
    let dragged = EditingSession(document: document)

    sent.selectFrame(at: 1)
    sent.moveCurrentFrameToEnd()
    dragged.moveFrame(from: 1, to: 4)

    #expect(sent.document.frames.map(\.id) == dragged.document.frames.map(\.id))
    #expect(sent.currentFrameIndex == 4)
  }

  @Test("Sending a frame where it already is records nothing")
  func sendingToTheEndItIsAlreadyAtIsANoOp() {
    let model = EditingSession(document: filledDocument(frames: 3))
    let original = model.document.frames.map(\.id)

    model.moveCurrentFrameToStart()

    #expect(model.document.frames.map(\.id) == original)
    #expect(!model.canUndo)
    #expect(!model.isDirty)
    #expect(model.statusMessage == "Frame is already first")
  }

  /// A move that goes nowhere says so by where the frame is, not by which
  /// way it was pushed.
  ///
  /// Reading the sign of the step — which is what this said before a
  /// send-to-either-end key existed to ask for a zero step — described a
  /// drag back onto a frame's own slot as "Frame is already last" no
  /// matter where in the timeline it sat.
  @Test("A no-op move is described by where the frame is")
  func aNoOpMoveNamesTheFramesActualPosition() {
    let model = EditingSession(document: filledDocument(frames: 4))

    model.moveFrame(from: 2, to: 2)
    #expect(model.statusMessage == "Frame is already in that slot")

    model.selectFrame(at: 0)
    model.moveCurrentFrame(by: -1)
    #expect(model.statusMessage == "Frame is already first")

    model.selectFrame(at: 3)
    model.moveCurrentFrame(by: 1)
    #expect(model.statusMessage == "Frame is already last")

    model.moveCurrentFrameToEnd()
    #expect(model.statusMessage == "Frame is already last")
    #expect(!model.canUndo)
  }

  @Test("Sending a frame to an end is one undo step")
  func sendingToAnEndIsOneUndoStep() {
    let model = EditingSession(document: filledDocument(frames: 4))
    let original = model.document.frames.map(\.id)

    model.moveCurrentFrameToEnd()
    #expect(model.document.frames.map(\.id) != original)

    model.undo()

    #expect(model.document.frames.map(\.id) == original)
    #expect(!model.canUndo)
  }

  @Test("A single-frame document has no end to send anything to")
  func sendingWithOneFrameIsHarmless() {
    let model = EditingSession(document: filledDocument(frames: 1))

    model.moveCurrentFrameToStart()
    model.moveCurrentFrameToEnd()

    #expect(model.document.frames.count == 1)
    #expect(!model.canUndo)
  }

  // MARK: - Delay reset

  @Test("Reset delay returns the frame to the delay a new frame is born with")
  func resetDelayReturnsToTheDefault() {
    let model = EditingSession(document: filledDocument(frames: 2))
    model.setCurrentFrameDelay(77)
    #expect(model.currentFrame.delayCentiseconds == 77)

    model.resetCurrentFrameDelay()

    #expect(
      model.currentFrame.delayCentiseconds == EditingSession.defaultFrameDelayCentiseconds
    )
    // And it really is the delay a frame is born with, not a second
    // number that happens to look like one today.
    let bornWith = EditorFrame(
      layers: [
        EditorLayer(name: "Layer 1", pixels: PixelBuffer(size: model.document.size))
      ]
    ).delayCentiseconds
    #expect(EditingSession.defaultFrameDelayCentiseconds == bornWith)
  }

  @Test("Reset delay is one undo step")
  func resetDelayIsOneUndoStep() {
    let model = EditingSession(document: filledDocument(frames: 2))

    model.resetCurrentFrameDelay()
    #expect(model.canUndo)

    model.undo()

    #expect(model.currentFrame.delayCentiseconds == Self.filledDocumentDelay)
    #expect(!model.canUndo)
  }

  // MARK: - Invalidation

  /// The whole reason these verbs are cheap. A loop count lives in the
  /// GIF's application extension, a disposal describes what a *decoder*
  /// does between frames, a delay is playback timing, and a reorder moves
  /// frames whose ids and pixels are untouched — so
  /// `GIFDocument.flattenedColors(for:)` reads none of them and no
  /// composite may be thrown away for any of them.
  @Test("No timeline command recomposites a single frame")
  func timelineCommandsRecompositeNothing() {
    for command in Self.commands {
      let model = EditingSession(document: filledDocument(frames: 4))
      model.compositeOracleEnabled = true
      let before = model.compositedFrames()
      let baseline = model.compositeRecomputeCount
      model.selectFrame(at: 1)

      command.run(model)
      let after = model.compositedFrames()

      #expect(
        model.compositeRecomputeCount == baseline,
        "\(command.name) recomposited \(model.compositeRecomputeCount - baseline) frame(s)"
      )
      // A reorder permutes the composites without recomputing any, so
      // what survives is the set rather than the order.
      #expect(after.count == before.count)
      #expect(Set(after) == Set(before), "\(command.name) changed a composited frame")
    }
  }

  @Test("Each timeline command actually changed something")
  func timelineCommandsAreNotVacuous() {
    // The invalidation sweep above would pass just as well if these were
    // no-ops, so each one is checked here for having done its job.
    let model = EditingSession(document: filledDocument(frames: 4))
    model.selectFrame(at: 1)

    model.cycleCurrentFrameDisposal()
    #expect(model.currentFrame.disposal != .background)

    model.adjustLoopCount(by: 3)
    #expect(model.document.loopCount == 3)

    model.toggleLoopsForever()
    #expect(model.document.loopCount == 0)

    model.resetCurrentFrameDelay()
    #expect(
      model.currentFrame.delayCentiseconds == EditingSession.defaultFrameDelayCentiseconds
    )

    let order = model.document.frames.map(\.id)
    model.moveCurrentFrameToEnd()
    #expect(model.document.frames.map(\.id) != order)
  }

  private struct Command {
    let name: String
    let run: @MainActor (EditingSession) -> Void
  }

  private static let commands: [Command] = [
    Command(name: "cycle disposal") { $0.cycleCurrentFrameDisposal() },
    Command(name: "step the loop count") { $0.adjustLoopCount(by: 2) },
    Command(name: "toggle looping forever") { $0.toggleLoopsForever() },
    Command(name: "reset the frame delay") { $0.resetCurrentFrameDelay() },
    Command(name: "send the frame to the start") { $0.moveCurrentFrameToStart() },
    Command(name: "send the frame to the end") { $0.moveCurrentFrameToEnd() },
  ]

  // MARK: - Fixtures

  private static let filledDocumentDelay = 9

  private func filledDocument(frames count: Int) -> GIFDocument {
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)
    let frames = (0..<count).map { index in
      EditorFrame(
        layers: [
          EditorLayer(
            name: "Layer 1",
            pixels: PixelBuffer(size: size, fill: PaletteIndex(1 + index))
          )
        ],
        delayCentiseconds: Self.filledDocumentDelay
      )
    }
    return GIFDocument(size: size, frames: frames)
  }
}

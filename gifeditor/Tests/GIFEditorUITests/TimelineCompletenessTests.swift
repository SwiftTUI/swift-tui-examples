import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

/// Behaviour of the timeline's four authoring surfaces — loop count,
/// per-frame disposal, the scrubbable delay readout, and drag-to-reorder —
/// plus the invalidation scopes each of them declares.
///
/// The scope assertions carry most of the weight here. Three of these four
/// edits change document state that no composited colour depends on, so the
/// only thing standing between them and a document-wide recomposite is the
/// scope named at each write site, and the only thing standing between a
/// *wrong* scope and a silently stale frame is the oracle. Every test that
/// asserts a recompute count therefore also runs with
/// `compositeOracleEnabled`, so "recomputed nothing" is checked against
/// "and what it served instead was still correct".
@MainActor
@Suite("GIF editor timeline completeness")
struct TimelineCompletenessTests {

  // MARK: - Loop count

  @Test("Setting the loop count is undoable and clamped to the format's range")
  func loopCountIsUndoableAndClamped() {
    let model = EditingSession(document: filledDocument(frames: 2))
    #expect(model.document.loopCount == 0)

    model.setLoopCount(3)
    #expect(model.document.loopCount == 3)
    #expect(model.canUndo)

    model.undo()
    #expect(model.document.loopCount == 0)

    model.redo()
    #expect(model.document.loopCount == 3)

    // A GIF carries the count as a little-endian UInt16, so the editor
    // refuses to show a number the file could not hold.
    model.setLoopCount(999_999)
    #expect(model.document.loopCount == EditingSession.maximumLoopCount)
    model.setLoopCount(-4)
    #expect(model.document.loopCount == 0)
  }

  @Test("Setting the loop count to what it already is records no undo step")
  func redundantLoopCountEditIsNotAnUndoStep() {
    let model = EditingSession(document: filledDocument(frames: 2))
    model.setLoopCount(0)
    #expect(!model.canUndo)
    #expect(!model.isDirty)
  }

  @Test("Zero is spelled out as forever everywhere the editor says it")
  func loopCountReadsAsProse() {
    #expect(EditingSession.loopDescription(0) == "forever")
    #expect(EditingSession.loopDescription(1) == "once")
    #expect(EditingSession.loopDescription(4) == "4 times")
  }

  @Test("The infinity toggle is reversible and remembers the finite count")
  func infiniteLoopToggleIsReversible() {
    let model = EditingSession(document: filledDocument(frames: 2))
    model.setLoopCount(6)

    model.toggleLoopsForever()
    #expect(model.document.loopCount == 0)
    #expect(model.statusMessage == "Plays forever")

    model.toggleLoopsForever()
    #expect(model.document.loopCount == 6)
  }

  @Test("Stepping down from one lands on forever rather than on nothing")
  func loopStepDownFromOneReachesForever() {
    let model = EditingSession(document: filledDocument(frames: 2))
    model.setLoopCount(1)

    model.adjustLoopCount(by: -1)

    #expect(model.document.loopCount == 0)
    #expect(model.statusMessage == "Plays forever")
  }

  @Test("A loop-count edit recomposites nothing")
  func loopCountEditRecompositesNothing() {
    let model = EditingSession(document: filledDocument(frames: 4))
    model.compositeOracleEnabled = true
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount

    model.setLoopCount(7)
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline)
    #expect(after == before)
  }

  /// The lossless promise, end to end. A GIF that declares three plays has
  /// to still declare three plays after being imported, saved as a
  /// project, closed, reopened and exported — the exact path on which the
  /// importer's dropped loop count used to turn a three-play banner into
  /// an infinite one, silently and permanently.
  @Test("A finite loop count survives GIF import, project save, reopen and GIF export")
  func loopCountSurvivesTheWholeRoundTrip() throws {
    try withTemporaryStateDirectory { directory in
      let source = try Self.fixtureURL("Fixtures", "finite-loop-3.gif")

      let imported = try GIFDocumentIO.open(contentsOf: source)
      let model = EditingSession(document: imported)
      #expect(model.document.loopCount == 3)

      let project = directory.appendingPathComponent("looped.halfcell")
      guard case .saved = GIFDocumentIO.saveProject(
        document: model.document,
        to: project,
        overwriteExisting: false
      ) else {
        Issue.record("expected the project write to succeed")
        return
      }

      // A fresh session, so nothing survives in memory between the two
      // halves of the round trip.
      let reopened = EditingSession(document: try GIFDocumentIO.open(contentsOf: project))
      #expect(reopened.document.loopCount == 3)

      let exported = directory.appendingPathComponent("looped.gif")
      guard case .saved = GIFDocumentIO.save(
        document: reopened.document,
        to: exported,
        overwriteExisting: false
      ) else {
        Issue.record("expected GIF export to succeed")
        return
      }

      let bytes = try Data(contentsOf: exported)
      let reimported = try GIFLoader.load(data: bytes)
      #expect(GIFLoader.declaredLoopCount(in: bytes) == 3)
      #expect(reimported.loopCount == 3)
    }
  }

  @Test("An edited loop count is what the export declares")
  func editedLoopCountReachesTheExportedFile() throws {
    try withTemporaryStateDirectory { directory in
      let model = EditingSession(document: filledDocument(frames: 2))
      model.setLoopCount(12)

      let exported = directory.appendingPathComponent("twelve.gif")
      guard case .saved = GIFDocumentIO.save(
        document: model.document,
        to: exported,
        overwriteExisting: false
      ) else {
        Issue.record("expected GIF export to succeed")
        return
      }

      let bytes = try Data(contentsOf: exported)
      #expect(GIFLoader.declaredLoopCount(in: bytes) == 12)
    }
  }

  // MARK: - Disposal

  @Test("Setting a frame's disposal is undoable and touches only that frame")
  func disposalEditIsUndoableAndScopedToOneFrame() {
    let model = EditingSession(document: filledDocument(frames: 3))
    model.selectFrame(at: 1)

    model.setCurrentFrameDisposal(.keep)

    #expect(model.document.frames.map(\.disposal) == [.background, .keep, .background])
    #expect(model.canUndo)

    model.undo()
    #expect(model.document.frames.allSatisfy { $0.disposal == .background })

    model.redo()
    #expect(model.document.frames[1].disposal == .keep)
  }

  @Test("The disposal cycle visits every mode and returns to background")
  func disposalCycleVisitsEveryMode() {
    let model = EditingSession(document: filledDocument(frames: 1))
    var seen: [EditorFrame.FrameDisposal] = [model.currentFrame.disposal]
    for _ in 0..<EditingSession.disposalOrder.count {
      model.cycleCurrentFrameDisposal()
      seen.append(model.currentFrame.disposal)
    }
    #expect(seen == EditingSession.disposalOrder + [.background])
  }

  @Test("Re-setting a frame's existing disposal records no undo step")
  func redundantDisposalEditIsNotAnUndoStep() {
    let model = EditingSession(document: filledDocument(frames: 2))
    model.setCurrentFrameDisposal(.background)
    #expect(!model.canUndo)
    #expect(!model.isDirty)
  }

  @Test("A disposal edit recomposites nothing")
  func disposalEditRecompositesNothing() {
    let model = EditingSession(document: filledDocument(frames: 4))
    model.compositeOracleEnabled = true
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount
    model.selectFrame(at: 2)

    model.setCurrentFrameDisposal(.previous)
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline)
    #expect(after == before)
  }

  /// The interaction the timeline exists to surface: an authored disposal
  /// costs the *whole document* its delta coding, not just the frame it was
  /// set on. `GIFEncoder.deltaCodedFrames` declines outright rather than
  /// half-honouring the sequence, so the editor has to say so before the
  /// author discovers it from a file size.
  @Test("An authored disposal switches the export off delta coding, and the model says so")
  func authoredDisposalDisablesDeltaCoding() throws {
    // Deliberately the *quiet* document, not `filledDocument`: frames that
    // differ everywhere delta-code to the same size as full frames, so
    // they could not tell the two codings apart by byte count. Here each
    // frame changes one pixel, which is where delta coding earns its name.
    let model = EditingSession(document: quietDocument(frames: 4))
    #expect(model.exportUsesDeltaFrames)
    #expect(!model.authoredDisposalDisablesDeltaCoding)

    let deltaBytes = try GIFEncoder.encode(document: model.document)

    model.selectFrame(at: 2)
    model.setCurrentFrameDisposal(.keep)

    #expect(!model.exportUsesDeltaFrames)
    #expect(model.authoredDisposalDisablesDeltaCoding)
    #expect(model.statusMessage.contains("full frames"))

    // And the claim is true of the encoder, not just of the flag: one
    // frame's disposal grew every frame in the file.
    let fullBytes = try GIFEncoder.encode(document: model.document)
    let explicitlyFull = try GIFEncoder.encode(
      document: model.document,
      frameCoding: .fullFrames
    )
    #expect(fullBytes.count > deltaBytes.count)
    #expect(fullBytes == explicitlyFull)
  }

  @Test("A single-frame document is not accused of losing delta coding it never had")
  func singleFrameDocumentDoesNotWarn() {
    let model = EditingSession(document: filledDocument(frames: 1))
    #expect(!model.exportUsesDeltaFrames)
    #expect(!model.authoredDisposalDisablesDeltaCoding)
  }

  @Test("Disposal round-trips through the project format")
  func disposalRoundTripsThroughTheProjectFormat() throws {
    try withTemporaryStateDirectory { directory in
      let model = EditingSession(document: filledDocument(frames: 3))
      model.selectFrame(at: 1)
      model.setCurrentFrameDisposal(.previous)
      model.selectFrame(at: 2)
      model.setCurrentFrameDisposal(.keep)
      let authored = model.document.frames.map(\.disposal)

      let target = directory.appendingPathComponent("disposal.halfcell")
      guard case .saved = GIFDocumentIO.saveProject(
        document: model.document,
        to: target,
        overwriteExisting: false
      ) else {
        Issue.record("expected the project write to succeed")
        return
      }

      let reopened = try GIFDocumentIO.open(contentsOf: target)
      #expect(reopened.frames.map(\.disposal) == authored)
      #expect(authored == [.background, .previous, .keep])
    }
  }

  // MARK: - Delay scrubbing

  @Test("A delay scrub is absolute, not cumulative")
  func delayScrubIsMeasuredFromItsBaseline() {
    let model = EditingSession(document: filledDocument(frames: 2))
    model.setCurrentFrameDelay(10)

    model.beginDelayScrub()
    #expect(model.isScrubbingDelay)
    model.updateDelayScrub(by: 5)
    #expect(model.currentFrame.delayCentiseconds == 15)
    // The second sample is the same drag seen further along, not a second
    // drag: a cumulative reading would land on 22.
    model.updateDelayScrub(by: 12)
    #expect(model.currentFrame.delayCentiseconds == 22)
    model.updateDelayScrub(by: -3)
    #expect(model.currentFrame.delayCentiseconds == 7)
    model.endDelayScrub()

    #expect(!model.isScrubbingDelay)
  }

  @Test("A whole delay scrub is one undo step")
  func delayScrubIsOneUndoStep() {
    let model = EditingSession(document: filledDocument(frames: 2))
    model.setCurrentFrameDelay(10)
    #expect(model.canUndo)

    model.beginDelayScrub()
    for cells in 1...8 {
      model.updateDelayScrub(by: cells)
    }
    model.endDelayScrub()
    #expect(model.currentFrame.delayCentiseconds == 18)

    model.undo()
    #expect(model.currentFrame.delayCentiseconds == 10)
    // Exactly one step: the delay before the scrub is still one undo away
    // from the document's original delay, not eight.
    model.undo()
    #expect(model.currentFrame.delayCentiseconds == filledDocumentDelay)
    #expect(!model.canUndo)
  }

  @Test("A scrub floors the delay at one centisecond")
  func delayScrubFloorsAtOne() {
    let model = EditingSession(document: filledDocument(frames: 2))
    model.setCurrentFrameDelay(4)
    model.beginDelayScrub()
    model.updateDelayScrub(by: -99)
    model.endDelayScrub()
    #expect(model.currentFrame.delayCentiseconds == 1)
  }

  @Test("Scrub updates outside a scrub do nothing")
  func delayScrubUpdateWithoutBeginIsInert() {
    let model = EditingSession(document: filledDocument(frames: 2))
    let before = model.currentFrame.delayCentiseconds

    model.updateDelayScrub(by: 20)
    model.endDelayScrub()

    #expect(model.currentFrame.delayCentiseconds == before)
    #expect(!model.canUndo)
  }

  @Test("A delay scrub recomposites nothing")
  func delayScrubRecompositesNothing() {
    let model = EditingSession(document: filledDocument(frames: 4))
    model.compositeOracleEnabled = true
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount

    model.beginDelayScrub()
    model.updateDelayScrub(by: 6)
    model.updateDelayScrub(by: 9)
    model.endDelayScrub()
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline)
    #expect(after == before)
  }

  // MARK: - Drag-to-reorder

  @Test("A reorder drag lands on the same document as the equivalent move")
  func dragReorderMatchesMoveCurrentFrame() {
    // One document, two view models. `EditorFrame` mints a fresh id per
    // instance, so two separately-built documents could never be compared
    // by frame identity — which is the only comparison that says the two
    // paths reordered the *same* frames rather than merely arriving at the
    // same colours.
    let document = filledDocument(frames: 5)
    let dragged = EditingSession(document: document)
    let moved = EditingSession(document: document)

    dragged.moveFrame(from: 1, to: 4)

    moved.selectFrame(at: 1)
    moved.moveCurrentFrame(by: 3)

    #expect(dragged.document.frames.map(\.id) == moved.document.frames.map(\.id))
    #expect(dragged.currentFrameIndex == moved.currentFrameIndex)
    #expect(dragged.currentFrameIndex == 4)
  }

  @Test("A reorder drag is one undo step")
  func dragReorderIsOneUndoStep() {
    let model = EditingSession(document: filledDocument(frames: 4))
    let original = model.document.frames.map(\.id)

    model.moveFrame(from: 0, to: 3)
    #expect(model.document.frames.map(\.id) != original)

    model.undo()

    #expect(model.document.frames.map(\.id) == original)
    #expect(!model.canUndo)
  }

  @Test("A drag that ends on its own slot changes nothing")
  func dragReorderToTheSameSlotIsANoOp() {
    let model = EditingSession(document: filledDocument(frames: 4))
    let original = model.document.frames.map(\.id)

    model.moveFrame(from: 2, to: 2)

    #expect(model.document.frames.map(\.id) == original)
    #expect(!model.canUndo)
    #expect(!model.isDirty)
    // The grab still moved the selection, which is what a click on that
    // thumbnail would have done anyway.
    #expect(model.currentFrameIndex == 2)
  }

  @Test("A drag from a slot that is not there is ignored")
  func dragReorderFromAnAbsentSlotIsIgnored() {
    let model = EditingSession(document: filledDocument(frames: 2))
    let original = model.document.frames.map(\.id)

    model.moveFrame(from: 7, to: 0)

    #expect(model.document.frames.map(\.id) == original)
    #expect(!model.canUndo)
  }

  @Test("A reorder recomposites nothing")
  func dragReorderRecompositesNothing() {
    let model = EditingSession(document: filledDocument(frames: 4))
    model.compositeOracleEnabled = true
    let before = model.compositedFrames()
    let baseline = model.compositeRecomputeCount

    model.moveFrame(from: 0, to: 2)
    let after = model.compositedFrames()

    #expect(model.compositeRecomputeCount == baseline)
    #expect(after == [before[1], before[2], before[0], before[3]])
  }

  // MARK: - Layout budget

  /// The timeline's export column competes for width with three other
  /// columns inside an 80-cell terminal, and overrunning that budget does
  /// not produce a tidy layout assertion — it stops the editor settling at
  /// 80×24, which times out every test in `PresentationRuntimeTests` at
  /// once. Measured while building this column: 18 cells hangs, 16
  /// settles. That one-cell margin is too thin to leave to a comment.
  ///
  /// Asserted on the rendered strings rather than by rendering, so the
  /// guard is cheap enough to sit next to the other unit tests and still
  /// fails on the change that would cause the hang — a longer label.
  @Test("The export column stays within its width budget")
  func exportColumnStaysWithinItsWidthBudget() {
    let budget = TimelineExportSettingsView.widestCell

    for disposal in EditingSession.disposalOrder {
      // `disp <code>` plus the space and `!` the warning state adds.
      let row = "disp \(EditingSession.disposalCode(disposal)) !"
      #expect(row.count <= budget, "disposal row '\(row)' is \(row.count) cells")
    }

    for count in [0, 1, 2, 999, EditingSession.maximumLoopCount] {
      // `loop <code> - +`.
      let row = "loop \(EditingSession.loopCode(count)) - +"
      #expect(row.count <= budget, "loop row '\(row)' is \(row.count) cells")
    }
  }

  @Test("The compact loop code still spells the zero out")
  func compactLoopCodeSpellsOutForever() {
    // The whole reason the control exists: `0` in a timeline strip reads
    // as "never", so the one value that must never be shown as a digit is
    // the one the format encodes as zero.
    #expect(EditingSession.loopCode(0) == "forever")
    #expect(EditingSession.loopCode(1) == "once")
    #expect(EditingSession.loopCode(9) == "9×")
  }

  // MARK: - Drag arithmetic

  @Test("Reorder travel resolves to a slot at the halfway mark")
  func reorderDestinationRoundsAtTheHalfwayMark() {
    // A 6-cell thumbnail plus its border and the stack's gap: 9 cells.
    let pitch = TimelineDragMath.slotPitch(thumbnailWidth: 6)
    #expect(pitch == 9)

    func destination(_ cells: Double, source: Int = 2, frames: Int = 5) -> Int {
      TimelineDragMath.reorderDestination(
        source: source,
        translationCells: cells,
        thumbnailWidth: 6,
        frameCount: frames
      )
    }

    #expect(destination(0) == 2)
    #expect(destination(4) == 2)
    #expect(destination(5) == 3)
    #expect(destination(9) == 3)
    #expect(destination(18) == 4)
    #expect(destination(-5) == 1)
    #expect(destination(-18) == 0)

    // Clamped to the strip: a drag off either end parks at the end.
    #expect(destination(900) == 4)
    #expect(destination(-900) == 0)
  }

  @Test("Reorder arithmetic survives a nonsense pointer sample")
  func reorderDestinationRejectsNonFiniteTravel() {
    #expect(
      TimelineDragMath.reorderDestination(
        source: 1,
        translationCells: .nan,
        thumbnailWidth: 6,
        frameCount: 4
      ) == 1
    )
    #expect(
      TimelineDragMath.reorderDestination(
        source: 1,
        translationCells: .infinity,
        thumbnailWidth: 6,
        frameCount: 4
      ) == 1
    )
    // An empty strip has no slot to land on and must not index into one.
    #expect(
      TimelineDragMath.reorderDestination(
        source: 0,
        translationCells: 20,
        thumbnailWidth: 6,
        frameCount: 0
      ) == 0
    )
  }

  @Test("Delay travel is one centisecond per cell, rounded")
  func delayDeltaIsOneCentisecondPerCell() {
    #expect(TimelineDragMath.delayDelta(translationCells: 0) == 0)
    #expect(TimelineDragMath.delayDelta(translationCells: 7) == 7)
    #expect(TimelineDragMath.delayDelta(translationCells: 7.4) == 7)
    #expect(TimelineDragMath.delayDelta(translationCells: 7.6) == 8)
    #expect(TimelineDragMath.delayDelta(translationCells: -3) == -3)
    #expect(TimelineDragMath.delayDelta(translationCells: .nan) == 0)
  }

  // MARK: - Fixtures

  /// Resolved relative to this source file rather than the working
  /// directory, and a hard failure when absent — a test that quietly
  /// passes because its input vanished is worse than no test.
  static func fixtureURL(_ components: String...) throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Tests/GIFEditorUITests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // <package root>/
    let url = components.reduce(packageRoot) { $0.appendingPathComponent($1) }
    guard FileManager.default.fileExists(atPath: url.path) else {
      Issue.record("fixture \(components.joined(separator: "/")) is missing at \(url.path)")
      throw CocoaError(.fileNoSuchFile)
    }
    return url
  }

  /// The delay every frame of ``filledDocument(frames:)`` starts with.
  private let filledDocumentDelay = 9

  /// `count` single-layer frames, each flooded with a distinct opaque
  /// palette slot, so a composite the cache served staler than it should
  /// have shows up as the wrong colour rather than as an empty frame.
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
        delayCentiseconds: filledDocumentDelay
      )
    }
    return GIFDocument(size: size, frames: frames)
  }

  /// `count` frames that are identical apart from a single pixel each, so
  /// delta coding has something real to save and the two frame codings
  /// differ by a measurable number of bytes.
  private func quietDocument(frames count: Int) -> GIFDocument {
    let size = GIFEditorCore.PixelSize(width: 16, height: 16)
    let frames = (0..<count).map { index -> EditorFrame in
      var pixels = PixelBuffer(size: size, fill: 1)
      pixels[GIFEditorCore.PixelPoint(x: index, y: index)] = 4
      return EditorFrame(
        layers: [EditorLayer(name: "Layer 1", pixels: pixels)],
        delayCentiseconds: filledDocumentDelay
      )
    }
    return GIFDocument(size: size, frames: frames)
  }
}

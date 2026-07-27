import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

/// Runs `body` with a fresh temporary directory that stands in for
/// `~/.config/halfcell/`, and removes it afterwards.
///
/// Every test in this file passes one to `EditorViewModel`, so nothing
/// here can read or write the developer's real state directory, and
/// nothing writes into the package directory either. There is no
/// "couldn't make a temp dir, skip" branch: a test that cannot set up is
/// a failing test, not a passing one.
func withTemporaryStateDirectory<T>(_ body: (URL) throws -> T) throws -> T {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-ui-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  return try body(directory)
}

/// A 2-frame, 2-layer document with named layers, a hidden layer, mixed
/// delays and a non-default loop count — every field the GIF encoder
/// would destroy, so a round-trip through it is visibly lossy and a
/// round-trip through the project format is visibly not.
func layeredDocument() -> GIFDocument {
  let size = GIFEditorCore.PixelSize(width: 4, height: 4)
  func frame(fill: PaletteIndex, delay: Int) -> EditorFrame {
    EditorFrame(
      layers: [
        EditorLayer(name: "Background", pixels: PixelBuffer(size: size, fill: fill)),
        EditorLayer(name: "Sparkle", isVisible: false, pixels: PixelBuffer(size: size, fill: 3)),
      ],
      delayCentiseconds: delay
    )
  }
  return GIFDocument(
    size: size,
    frames: [frame(fill: 1, delay: 7), frame(fill: 2, delay: 11)],
    loopCount: 5
  )
}

@MainActor
@Suite("GIF editor file lifecycle")
struct FileLifecycleTests {

  // MARK: - The release gate: Save must not flatten

  /// The headline fix. A document that came from a GIF has a `path`, and
  /// the obvious "Save writes back to `path`" would push a layered
  /// document through the GIF encoder and destroy every layer — under
  /// the one verb whose entire promise is that it does not.
  @Test("Save writes back to a project path and falls through to Save As for a GIF")
  func saveRoutesByWhereTheDocumentCameFrom() throws {
    try withTemporaryStateDirectory { directory in
      let model = EditorViewModel(document: layeredDocument(), stateDirectory: directory)

      // Never saved: nothing to write back to.
      guard case .promptForLocation(let untitled) = model.saveRoute else {
        Issue.record("expected .promptForLocation for an untitled document")
        return
      }
      #expect(untitled.lastPathComponent == "untitled.halfcell")

      // Imported from a GIF: has a path, and Save must still refuse it.
      let gif = directory.appendingPathComponent("nyan.gif")
      let fromGIF = EditorViewModel(
        document: {
          var document = layeredDocument()
          document.path = gif
          return document
        }(),
        stateDirectory: directory
      )
      guard case .promptForLocation(let suggestion) = fromGIF.saveRoute else {
        Issue.record("expected .promptForLocation for a document imported from a GIF")
        return
      }
      #expect(suggestion.lastPathComponent == "nyan.halfcell")

      // And the sheet says *why*, rather than silently asking again.
      let reason = EditorView.saveFallThroughReason(for: fromGIF.document)
      #expect(reason?.contains("nyan.gif") == true)
      #expect(reason?.contains("flatten") == true)

      // Came from a project: writes straight back, no prompt.
      let project = directory.appendingPathComponent("session.halfcell")
      let fromProject = EditorViewModel(
        document: {
          var document = layeredDocument()
          document.path = project
          return document
        }(),
        stateDirectory: directory
      )
      #expect(fromProject.saveRoute == .writeBack(project))
    }
  }

  /// The other half of the same contract: exporting a GIF must not leave
  /// the editor believing the layered work is safe on disk.
  @Test("Exporting a GIF leaves the document dirty and does not move its path")
  func exportingGIFLeavesTheDocumentDirtyAndUnmoved() throws {
    try withTemporaryStateDirectory { directory in
      let project = directory.appendingPathComponent("session.halfcell")
      var document = layeredDocument()
      document.path = project
      let model = EditorViewModel(document: document, stateDirectory: directory)
      model.primaryColorIndex = 9
      model.applyToolAtCursor()
      #expect(model.isDirty)

      let gif = directory.appendingPathComponent("export.gif")
      #expect(model.exportGIF(to: gif, overwriteExisting: true))

      #expect(FileManager.default.fileExists(atPath: gif.path))
      // Still dirty, still pointed at the project: an export is a copy,
      // not a save.
      #expect(model.isDirty)
      #expect(model.document.path == project)
      #expect(model.saveRoute == .writeBack(project))
    }
  }

  // MARK: - Round trip through the UI layer

  @Test("A project survives save and reopen through the view model")
  func projectRoundTripsThroughTheViewModel() throws {
    try withTemporaryStateDirectory { directory in
      let target = directory.appendingPathComponent("round-trip.halfcell")
      let model = EditorViewModel(document: layeredDocument(), stateDirectory: directory)

      // Edit through the real verbs so the saved bytes describe work the
      // editor actually produced.
      model.primaryColorIndex = 6
      model.cursor = GIFEditorCore.PixelPoint(x: 2, y: 2)
      model.applyToolAtCursor()
      model.sortPalette()
      let expected = model.document

      #expect(model.saveProject(to: target, overwriteExisting: false))
      #expect(!model.isDirty)

      let reopened = EditorViewModel(
        document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 2, height: 2)),
        stateDirectory: directory
      )
      #expect(reopened.openDocument(contentsOf: target))

      let actual = reopened.document
      #expect(actual.size == expected.size)
      #expect(actual.loopCount == expected.loopCount)
      #expect(actual.palette.usedColors == expected.palette.usedColors)
      #expect(actual.frames.map(\.delayCentiseconds) == expected.frames.map(\.delayCentiseconds))
      #expect(
        actual.frames.map { $0.layers.map(\.name) } == expected.frames.map { $0.layers.map(\.name) }
      )
      #expect(
        actual.frames.map { $0.layers.map(\.isVisible) }
          == expected.frames.map { $0.layers.map(\.isVisible) }
      )
      #expect(
        actual.frames.map { $0.layers.map(\.pixels) }
          == expected.frames.map { $0.layers.map(\.pixels) }
      )
      // Reopening is not a modification.
      #expect(!reopened.isDirty)
      #expect(reopened.document.path == target)
    }
  }

  @Test("Open routes on bytes, so a GIF opens as an import and keeps Save honest")
  func openRoutesOnBytes() throws {
    try withTemporaryStateDirectory { directory in
      let gif = directory.appendingPathComponent("art.gif")
      let source = EditorViewModel(document: layeredDocument(), stateDirectory: directory)
      #expect(source.exportGIF(to: gif, overwriteExisting: true))

      let model = EditorViewModel(
        document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 2, height: 2)),
        stateDirectory: directory
      )
      #expect(model.openDocument(contentsOf: gif))

      // The importer's shape, and — the point — a Save that refuses to
      // write back over the GIF it came from.
      #expect(model.document.path == gif)
      #expect(model.document.frames.allSatisfy { $0.layers.count == 1 })
      guard case .promptForLocation = model.saveRoute else {
        Issue.record("a document imported from a GIF must not write back over it")
        return
      }
    }
  }

  // MARK: - Recents

  @Test("Opening and saving both record a recent document, most-recent first")
  func recentsRecordOpensAndSaves() throws {
    try withTemporaryStateDirectory { directory in
      let first = directory.appendingPathComponent("first.halfcell")
      let second = directory.appendingPathComponent("second.halfcell")
      let model = EditorViewModel(document: layeredDocument(), stateDirectory: directory)

      #expect(model.recentDocuments.isEmpty)
      #expect(model.saveProject(to: first, overwriteExisting: false))
      #expect(model.recentDocuments.urls.map(\.lastPathComponent) == ["first.halfcell"])

      #expect(model.saveProject(to: second, overwriteExisting: false))
      #expect(
        model.recentDocuments.urls.map(\.lastPathComponent)
          == ["second.halfcell", "first.halfcell"]
      )

      // Re-opening moves an entry to the front rather than duplicating.
      #expect(model.openDocument(contentsOf: first))
      #expect(
        model.recentDocuments.urls.map(\.lastPathComponent)
          == ["first.halfcell", "second.halfcell"]
      )

      // And it survives into the next session.
      let next = EditorViewModel(
        document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 2, height: 2)),
        stateDirectory: directory
      )
      #expect(
        next.recentDocuments.urls.map(\.lastPathComponent)
          == ["first.halfcell", "second.halfcell"]
      )
    }
  }

  /// Losing the recents file costs a menu section. It must never cost a
  /// save.
  @Test("A recents file that cannot be written does not fail the save")
  func recentsWriteFailureIsCosmetic() throws {
    try withTemporaryStateDirectory { directory in
      // A *file* where the state directory should be, so creating it and
      // writing into it both fail.
      let blocked = directory.appendingPathComponent("blocked")
      try Data("not a directory".utf8).write(to: blocked)

      let target = directory.appendingPathComponent("session.halfcell")
      let model = EditorViewModel(document: layeredDocument(), stateDirectory: blocked)

      #expect(model.saveProject(to: target, overwriteExisting: false))
      #expect(!model.isDirty)
      #expect(model.statusMessage.hasPrefix("Saved to"))
    }
  }

  // MARK: - Autosave and recovery

  @Test("Autosave writes a layered document and recovers it losslessly")
  func autosaveRoundTripsALayeredDocument() throws {
    try withTemporaryStateDirectory { directory in
      let project = directory.appendingPathComponent("session.halfcell")
      var document = layeredDocument()
      document.path = project
      let model = EditorViewModel(document: document, stateDirectory: directory)

      // Nothing to lose yet, so nothing is written — a clean session
      // must not leave a recovery file behind for the next launch to
      // offer.
      #expect(!model.writeAutosaveSnapshot(at: Date(timeIntervalSince1970: 1_753_574_400)))
      #expect(!FileManager.default.fileExists(atPath: model.autosaveURL.path))

      model.primaryColorIndex = 6
      model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 1)
      model.applyToolAtCursor()
      let stamp = Date(timeIntervalSince1970: 1_753_574_400)
      #expect(model.writeAutosaveSnapshot(at: stamp))

      let recovered = try #require(try AutosaveStore.recover(from: model.autosaveURL))
      #expect(recovered.savedAt == stamp)
      #expect(recovered.originalPath == project)
      #expect(
        recovered.document.frames.map { $0.layers.map(\.name) }
          == model.document.frames.map { $0.layers.map(\.name) })
      #expect(
        recovered.document.frames.map { $0.layers.map(\.isVisible) }
          == model.document.frames.map { $0.layers.map(\.isVisible) })
      #expect(
        recovered.document.frames.map { $0.layers.map(\.pixels) }
          == model.document.frames.map { $0.layers.map(\.pixels) })
      #expect(recovered.document.loopCount == 5)
    }
  }

  @Test("A successful save clears the recovery file")
  func savingClearsTheRecoveryFile() throws {
    try withTemporaryStateDirectory { directory in
      let model = EditorViewModel(document: layeredDocument(), stateDirectory: directory)
      model.primaryColorIndex = 9
      model.applyToolAtCursor()
      #expect(model.writeAutosaveSnapshot(at: Date()))
      #expect(AutosaveStore.snapshotExists(at: model.autosaveURL))

      #expect(
        model.saveProject(
          to: directory.appendingPathComponent("session.halfcell"),
          overwriteExisting: false
        )
      )

      // The work is on disk under its own name now; offering to recover
      // it at the next launch would be offering something the author
      // already has.
      #expect(!AutosaveStore.snapshotExists(at: model.autosaveURL))
    }
  }

  @Test("A recovered document opens dirty, so quitting over it still asks")
  func recoveredDocumentOpensDirty() throws {
    try withTemporaryStateDirectory { directory in
      let model = EditorViewModel(
        document: layeredDocument(),
        stateDirectory: directory,
        startsDirty: true
      )
      #expect(model.isDirty)
      // Nothing to undo *back* to — the interrupted history is gone —
      // but the document still differs from what is on disk.
      #expect(!model.canUndo)
    }
  }

  // MARK: - Dirty guard

  /// The *effect* of confirming a discard, from the model's side.
  ///
  /// The refusal itself is a conversation the view owns — the model
  /// verbs are unconditional by design, so the guard can offer Save as
  /// well as Discard rather than silently doing nothing — and it is
  /// pinned end-to-end through real key presses by
  /// `newOnADirtyDocumentAsksFirst` and its clean-document control in
  /// `PresentationRuntimeTests`. What belongs here is the other half:
  /// once the author *has* confirmed, the replacement is total.
  @Test("Confirming a discard replaces the document and its history outright")
  func discardingReplacesTheDocumentEntirely() throws {
    try withTemporaryStateDirectory { directory in
      let model = EditorViewModel(document: layeredDocument(), stateDirectory: directory)
      model.primaryColorIndex = 9
      model.applyToolAtCursor()
      model.selection = Selection(rect: PixelRect(x: 0, y: 0, width: 2, height: 2))
      model.copySelection()
      #expect(model.isDirty)
      let guarded = model.document

      model.newDocument(size: GIFEditorCore.PixelSize(width: 8, height: 8))

      #expect(model.document != guarded)
      #expect(model.document.size == GIFEditorCore.PixelSize(width: 8, height: 8))
      #expect(!model.isDirty)
      // None of the old document's context survives into the new one —
      // an undo stack, a marquee or a clipboard of palette indices are
      // all claims about a document that is gone.
      #expect(!model.canUndo)
      #expect(model.selection == nil)
      #expect(model.clipboard == nil)
      #expect(model.currentFrameIndex == 0)
      #expect(model.cursor == GIFEditorCore.PixelPoint.zero)
    }
  }

  @Test("The quit guard re-arms after any further edit")
  func quitGuardReArmsAfterAnEdit() throws {
    try withTemporaryStateDirectory { directory in
      let model = EditorViewModel(document: layeredDocument(), stateDirectory: directory)
      model.primaryColorIndex = 9
      model.applyToolAtCursor()
      #expect(model.isDirty)

      // The author said "discard and quit"…
      model.allowsQuitWithUnsavedChanges = true
      // …and then kept drawing. Consent to lose the work as it stood is
      // not consent to lose what came next.
      model.cursor = GIFEditorCore.PixelPoint(x: 3, y: 3)
      model.applyToolAtCursor()
      #expect(!model.allowsQuitWithUnsavedChanges)
    }
  }

  @Test("The unsaved-changes prompt names the verb that raised it")
  func unsavedChangesMessageNamesTheVerb() {
    #expect(EditorView.unsavedChangesMessage(for: .new).contains("new document"))
    #expect(EditorView.unsavedChangesMessage(for: .open).contains("another document"))
    #expect(
      EditorView.unsavedChangesMessage(for: .openRecent(URL(fileURLWithPath: "/a.halfcell")))
        .contains("another document")
    )
    #expect(EditorView.unsavedChangesMessage(for: .quit).contains("Quitting"))
  }

  // MARK: - Document replacement and the composite cache

  /// Replacing the document invalidates **every** frame, and the oracle
  /// is the only thing that can catch getting this wrong.
  ///
  /// The subtle case is a frame id that survives the swap — a document
  /// saved and reopened carries the same `EditorFrame.id` values — so a
  /// per-frame invalidation would look correct and serve stale pixels.
  /// With `compositeOracleEnabled` on, every cache *hit* is re-derived
  /// and compared, so a wrong scope traps instead of rendering.
  @Test("Replacing the document declares .everyFrame")
  func documentReplacementInvalidatesEveryFrame() throws {
    try withTemporaryStateDirectory { directory in
      let target = directory.appendingPathComponent("session.halfcell")
      let model = EditorViewModel(document: layeredDocument(), stateDirectory: directory)
      model.compositeOracleEnabled = true

      let before = model.compositedFrames()
      #expect(model.compositeRecomputeCount == 2)
      // A second pass is all hits, so the oracle audits both frames.
      #expect(model.compositedFrames() == before)
      #expect(model.compositeRecomputeCount == 2)

      #expect(model.saveProject(to: target, overwriteExisting: false))

      // Reopening the *same* bytes brings back the same frame ids, which
      // is exactly the case a per-frame stamp would mishandle.
      let savedIDs = model.document.frames.map(\.id)
      #expect(model.openDocument(contentsOf: target))
      #expect(model.document.frames.map(\.id) == savedIDs)

      let afterOpen = model.compositedFrames()
      #expect(model.compositeRecomputeCount == 4, "every frame recomposites after a replacement")
      #expect(afterOpen == before)
      // All hits now, every one of them audited by the oracle.
      #expect(model.compositedFrames() == afterOpen)
      #expect(model.compositeRecomputeCount == 4)

      // Same again for New, whose replacement has nothing in common with
      // what it replaced.
      model.newDocument(size: GIFEditorCore.PixelSize(width: 3, height: 3))
      let blank = model.compositedFrames()
      #expect(model.compositeRecomputeCount == 5)
      #expect(blank == [Array(repeating: nil, count: 9)])
      #expect(model.compositedFrames() == blank)
      #expect(model.compositeRecomputeCount == 5)
    }
  }

  // MARK: - I10: undo restores the colour selection

  /// Sorting the palette renumbers every slot, and the artwork, the two
  /// colour selections and the clipboard are all renumbered with it as
  /// one edit. Undo used to restore only the artwork, leaving the
  /// primary colour pointing at the slot the sort had moved it to — so
  /// the next stroke painted a colour the author never picked.
  @Test("Undo after a palette sort restores the colour selection and clipboard")
  func undoAfterPaletteSortRestoresColourSelection() throws {
    try withTemporaryStateDirectory { directory in
      let model = EditorViewModel(document: layeredDocument(), stateDirectory: directory)
      model.primaryColorIndex = 3
      model.secondaryColorIndex = 5
      model.copySelection()
      let clipboardBefore = try #require(model.clipboard)
      let paletteBefore = model.document.palette

      model.sortPalette()
      #expect(model.document.palette != paletteBefore, "the sort must actually renumber")
      // The whole point of the sort: the selections followed their
      // colours to new slots.
      let primaryAfterSort = model.primaryColorIndex
      let secondaryAfterSort = model.secondaryColorIndex
      #expect(primaryAfterSort != 3 || secondaryAfterSort != 5)

      model.undo()

      #expect(model.document.palette == paletteBefore)
      #expect(model.primaryColorIndex == 3)
      #expect(model.secondaryColorIndex == 5)
      #expect(model.clipboard == clipboardBefore)

      // And redo puts the post-sort numbering back, selections included.
      model.redo()
      #expect(model.primaryColorIndex == primaryAfterSort)
      #expect(model.secondaryColorIndex == secondaryAfterSort)
    }
  }

  // MARK: - Path completion

  @Test("Path completion extends as far as the matching names agree")
  func pathCompletionExtendsToTheSharedPrefix() throws {
    try withTemporaryStateDirectory { directory in
      for name in ["alpha.halfcell", "alpine.gif", "beta.gif", ".hidden"] {
        try Data("x".utf8).write(to: directory.appendingPathComponent(name))
      }
      try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("frames"),
        withIntermediateDirectories: true
      )

      // Two matches: stop at the shared prefix and report both.
      let ambiguous = GIFDocumentIO.completePath(directory.path + "/al")
      #expect(ambiguous.text == directory.path + "/alp")
      #expect(ambiguous.matches == ["alpha.halfcell", "alpine.gif"])
      #expect(!ambiguous.isUnique)

      // One match: complete it fully.
      let unique = GIFDocumentIO.completePath(directory.path + "/be")
      #expect(unique.text == directory.path + "/beta.gif")
      #expect(unique.isUnique)

      // A directory gains a trailing separator so the next completion
      // descends into it rather than re-completing its own name.
      let intoDirectory = GIFDocumentIO.completePath(directory.path + "/fra")
      #expect(intoDirectory.text == directory.path + "/frames/")

      // Nothing matches: the typed text is never thrown away.
      let miss = GIFDocumentIO.completePath(directory.path + "/zzz")
      #expect(miss.text == directory.path + "/zzz")
      #expect(miss.isEmpty)

      // Dotfiles stay out until the fragment asks for them.
      #expect(!GIFDocumentIO.completePath(directory.path + "/").matches.contains(".hidden"))
      #expect(GIFDocumentIO.completePath(directory.path + "/.h").matches == [".hidden"])
    }
  }
}

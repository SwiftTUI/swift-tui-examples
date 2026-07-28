import GIFEditorCore
import Testing

@testable import GIFEditorUI

@MainActor
@Suite("Editing session save generations")
struct EditingSessionSaveTests {
  @Test("Semantic intents return immutable session state")
  func intentsReturnState() {
    let session = EditingSession(
      document: GIFDocument.blank(size: PixelSize(width: 3, height: 2))
    )
    let before = session.state

    let moved = session.dispatch(.moveCursor(dx: 1, dy: 0))
    #expect(moved.result == .updated)
    #expect(moved.state.cursor == PixelPoint(x: 1, y: 0))
    #expect(before.cursor == .zero)
    #expect(before.generation == moved.state.generation)

    let painted = session.dispatch(.applyActiveTool)
    #expect(painted.result == .changed)
    #expect(painted.state.isDirty)
    #expect(painted.state.canUndo)
    #expect(painted.state.generation != before.generation)
  }

  @Test("A save receipt cannot clear edits made after its snapshot")
  func staleReceiptStaysDirty() {
    let session = EditingSession(
      document: GIFDocument.blank(size: PixelSize(width: 2, height: 2))
    )
    session.primaryColorIndex = 4
    session.applyToolAtCursor()
    let saved = session.makeSaveSnapshot()

    session.moveCursor(dx: 1, dy: 0)
    session.primaryColorIndex = 5
    session.applyToolAtCursor()

    #expect(session.acknowledgeSave(saved) == .superseded)
    #expect(session.isDirty)
    #expect(session.document != saved.document)
  }

  @Test("Undoing to the acknowledged generation becomes clean")
  func undoToSavedGenerationIsClean() {
    let session = EditingSession(
      document: GIFDocument.blank(size: PixelSize(width: 2, height: 2))
    )
    session.primaryColorIndex = 4
    session.applyToolAtCursor()
    let saved = session.makeSaveSnapshot()

    session.moveCursor(dx: 1, dy: 0)
    session.primaryColorIndex = 5
    session.applyToolAtCursor()
    _ = session.acknowledgeSave(saved)
    #expect(session.isDirty)

    session.undo()
    #expect(session.document == saved.document)
    #expect(!session.isDirty)

    session.redo()
    #expect(session.isDirty)
  }

  @Test("An older completion cannot supersede a newer save receipt")
  func reverseCompletionOrderRejectsOlderReceipt() {
    let session = EditingSession(
      document: GIFDocument.blank(size: PixelSize(width: 2, height: 2))
    )
    let older = session.makeSaveSnapshot()
    let newer = session.makeSaveSnapshot()

    #expect(session.acknowledgeSave(newer) == .current)
    #expect(session.acknowledgeSave(older) == .rejected)
    #expect(!session.isDirty)
  }

  @Test("Replacing the document invalidates in-flight save receipts")
  func replacementRejectsOldReceipt() {
    let outgoing = EditingSession(
      document: GIFDocument.blank(size: PixelSize(width: 2, height: 2))
    )
    let oldDocument = outgoing.makeSaveSnapshot()
    let replacement = EditingSession(
      document: GIFDocument.blank(size: PixelSize(width: 5, height: 4))
    )

    #expect(replacement.acknowledgeSave(oldDocument) == .rejected)
    #expect(replacement.document.size == PixelSize(width: 5, height: 4))
  }
}

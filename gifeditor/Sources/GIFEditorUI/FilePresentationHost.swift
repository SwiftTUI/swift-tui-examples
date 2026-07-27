import Foundation
import GIFEditorCore
import SwiftTUI

/// Carries the file-lifecycle presentations — the unsaved-changes guard
/// and the New / Open / Save As sheets — on a view node of its own.
///
/// This is a depth budget, not a style preference, and it is the same
/// shape of constraint that put the autosave timer on its own node.
/// `EditorView`'s root already wears roughly forty nested modifiers: a
/// panel, six keybinding chains totalling ~35 `keyCommand`s, three
/// sheets and a task. Resolution recurses once per layer through the
/// generic `ModifiedContent` nesting, and in a debug build those frames
/// are large — hanging two more presentation modifiers off that chain
/// overflows the stack of the task a test runs in, and takes the whole
/// editor down rather than just the new sheets.
///
/// Presentations are portal-based: they hoist to the terminal surface
/// from wherever they are attached, so nothing about them requires the
/// root. Moving them onto a zero-size sibling buys the depth back and
/// costs nothing at render time.
///
/// The parameter list is long and flat on purpose. Every one of these is
/// state `EditorView` owns and this view only forwards; bundling them
/// into a context struct would hide which of them are bindings that
/// write back.
struct FilePresentationHost: View {
  @Binding var isUnsavedChangesPresented: Bool
  @Binding var fileSheet: FileSheet?
  @Binding var openPathText: String
  @Binding var projectSavePathText: String
  @Binding var overwriteProjectSaveConfirmed: Bool

  /// The verb the guard is holding, so its message can name it.
  let pendingAction: PendingDocumentAction?
  let recentDocuments: [URL]
  let openErrorMessage: String?
  let isOpening: Bool
  let isSavingProject: Bool
  /// Why `Save` sent the author to `Save As`, when it did.
  let saveAsFallThroughReason: String?

  let onGuardSave: @MainActor @Sendable () -> Void
  let onGuardDiscard: @MainActor @Sendable () -> Void
  let onGuardCancel: @MainActor @Sendable () -> Void
  let onCreateDocument: @MainActor @Sendable (GIFEditorCore.PixelSize) -> Void
  let onOpenDocument: @MainActor @Sendable (URL) -> Void
  let onSaveProject: @MainActor @Sendable (URL, Bool) -> Void
  /// Dismisses whichever sheet is up, and undoes whatever presenting it
  /// had staged.
  let onCancelSheet: @MainActor @Sendable () -> Void

  var body: some View {
    Text("")
      .frame(width: 0, height: 0)
      .confirmationDialog(
        "Unsaved changes",
        isPresented: $isUnsavedChangesPresented,
        actions: {
          Button("Save…", action: onGuardSave)
          Button("Discard", action: onGuardDiscard)
          Button("Cancel", action: onGuardCancel)
        },
        message: {
          Text(EditorView.unsavedChangesMessage(for: pendingAction))
        }
      )
      .sheet(item: $fileSheet) { sheet in
        content(for: sheet)
      }
  }

  @ViewBuilder
  private func content(for sheet: FileSheet) -> some View {
    switch sheet {
    case .new:
      NewDocumentSheetView(
        onCreate: onCreateDocument,
        onCancel: onCancelSheet
      )
    case .open:
      OpenDocumentSheetView(
        pathText: $openPathText,
        recentDocuments: recentDocuments,
        errorMessage: openErrorMessage,
        isOpening: isOpening,
        onOpen: onOpenDocument,
        onCancel: onCancelSheet
      )
    case .saveAs:
      SaveProjectSheetView(
        pathText: $projectSavePathText,
        overwriteConfirmed: $overwriteProjectSaveConfirmed,
        isSaving: isSavingProject,
        fallThroughReason: saveAsFallThroughReason,
        onSave: onSaveProject,
        onCancel: onCancelSheet
      )
    }
  }
}

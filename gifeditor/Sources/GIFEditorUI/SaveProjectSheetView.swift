import Foundation
import GIFEditorCore
import SwiftTUI

/// Modal sheet for `Save As`: pick a destination for the lossless
/// project file.
///
/// Deliberately much plainer than the GIF export sheet, and the
/// difference is the point. The export sheet shows an encoded preview
/// because export is a *conversion* — quantized, flattened, and worth
/// looking at before you commit. A project save writes what is on
/// screen, so there is nothing to preview and no honest reason to make
/// the author wait for one.
///
/// This is also where the `Save`-verb fall-through lands: a document
/// imported from `nyan.gif` has a path, and `Save` refuses to write a
/// layered document back over it, so the author arrives here with
/// `nyan.halfcell` pre-filled rather than silently losing every layer.
struct SaveProjectSheetView: View {
  @Binding var pathText: String
  @Binding var overwriteConfirmed: Bool
  /// True while a save is in flight, so the button cannot be pressed
  /// twice into two concurrent writes of the same file.
  let isSaving: Bool
  /// Why the author is here, when they did not choose `Save As`
  /// themselves. Nil when they did.
  let fallThroughReason: String?
  let onSave: @MainActor @Sendable (URL, Bool) -> Void
  let onCancel: @MainActor @Sendable () -> Void

  @FocusState private var pathFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Save project").foregroundStyle(.tint)
      if let fallThroughReason {
        Text(fallThroughReason).foregroundStyle(.muted)
      }
      pathField
      Divider()
      targetStatus
      if requiresOverwriteConfirmation {
        overwriteConfirmation
      }
      HStack(spacing: 1) {
        Spacer(minLength: 1)
        Button("Cancel", action: onCancel)
          .systemHint("Esc")
        Button("Save") {
          guard let targetURL, canSave else { return }
          onSave(targetURL, requiresOverwriteConfirmation)
        }
        .disabled(!canSave)
      }
    }
    .padding(1)
    .onChange(of: pathText) {
      overwriteConfirmed = false
    }
  }

  private var pathField: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Destination").foregroundStyle(.muted)
      TextField("Path", text: $pathText)
        .focused($pathFocused)
        .onAppear {
          pathFocused = true
        }
        .textFieldStyle(.plain)
        .frame(width: 58, alignment: .leading)
    }
  }

  @ViewBuilder
  private var targetStatus: some View {
    if targetURL == nil {
      Text("Enter a destination path").foregroundStyle(.warning)
    } else if isSaving {
      Text("Saving…").foregroundStyle(.muted)
    } else if requiresOverwriteConfirmation {
      Text("A file already exists at this path. Confirm overwrite to enable Save.")
        .foregroundStyle(.warning)
    } else if !namesProjectFile {
      // Not an error — the format is decided by the bytes, not the
      // name — but a project saved as `sketch.gif` will confuse the
      // author far more than this line will.
      Text("Tip: `.\(ProjectFile.fileExtension)` keeps layers on reopen.")
        .foregroundStyle(.muted)
    } else {
      Text("Ready to save").foregroundStyle(.success)
    }
  }

  private var overwriteConfirmation: some View {
    Button {
      overwriteConfirmed.toggle()
    } label: {
      HStack(spacing: 1) {
        Text(overwriteConfirmed ? "[✓]" : "[ ]")
          .foregroundStyle(overwriteConfirmed ? .tint : .muted)
        Text("Confirm overwrite").foregroundStyle(.foreground)
      }
    }
    .buttonStyle(.plain)
  }

  private var targetURL: URL? {
    GIFDocumentIO.saveURL(from: pathText)
  }

  private var namesProjectFile: Bool {
    guard let targetURL else { return false }
    return GIFDocumentIO.isProjectFile(targetURL)
  }

  private var requiresOverwriteConfirmation: Bool {
    guard let targetURL else { return false }
    return FileManager.default.fileExists(atPath: targetURL.path)
  }

  private var canSave: Bool {
    targetURL != nil
      && !isSaving
      && (!requiresOverwriteConfirmation || overwriteConfirmed)
  }
}

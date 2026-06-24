import Foundation
import GIFEditorCore

/// Document load/save/encode for the editor. Stateless: every entry
/// takes the document (or a target URL) and returns a value, so the
/// coordinator keeps ownership of `document` and the dirty flag while
/// this type owns only the encoding and filesystem details.
enum GIFDocumentIO {
  /// Outcome of a save attempt, surfaced so the coordinator can update
  /// `document.path`, the clean generation, and the status line without
  /// this type reaching back into the view model.
  enum SaveOutcome {
    case needsOverwriteConfirmation
    case saved
    case failed(any Error)
  }

  /// The URL a save defaults to: the document's existing path, or
  /// `untitled.gif` in the current working directory.
  static func defaultSaveURL(for document: GIFDocument) -> URL {
    document.path
      ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("untitled.gif")
  }

  /// Resolves user-entered save path text into a URL, expanding `~` and
  /// rooting relative paths at the current working directory. Returns
  /// `nil` for blank input.
  static func saveURL(from pathText: String) -> URL? {
    let trimmed = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let expanded = (trimmed as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") {
      return URL(fileURLWithPath: expanded)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(expanded)
  }

  /// Encodes `document` and writes it to `target`. Refuses to clobber an
  /// existing file unless `overwriteExisting` is set, matching the
  /// editor's save-confirmation contract.
  static func save(
    document: GIFDocument,
    to target: URL,
    overwriteExisting: Bool
  ) -> SaveOutcome {
    if FileManager.default.fileExists(atPath: target.path) && !overwriteExisting {
      return .needsOverwriteConfirmation
    }

    do {
      let bytes = try GIFEncoder.encode(document: document)
      try Data(bytes).write(to: target, options: .atomic)
      return .saved
    } catch {
      return .failed(error)
    }
  }
}

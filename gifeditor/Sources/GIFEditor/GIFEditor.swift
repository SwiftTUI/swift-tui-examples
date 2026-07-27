import Foundation
import GIFEditorCore
import GIFEditorUI
import SwiftTUI

/// Composition root for the editor.
///
/// It resolves a document from an optional file path, offers back any
/// unsaved work a previous session left behind, and hands the result to
/// `EditorView`. A future SwiftUI port would have a sibling factory
/// function that returns a SwiftUI view fed the same `GIFDocument`.
///
/// Recovery is settled *before* the editor exists rather than as a sheet
/// over it. The alternative — build the editor around the on-disk
/// document and swap the document out from under it when the author
/// accepts — means a recovery's first act is to discard a freshly built
/// view model, and means there is a moment where the editor is showing
/// work nobody has been offered yet.
public struct GIFEditor: View {
  let path: String?
  /// Where the recents list and the recovery file live. A parameter so a
  /// test never reads or writes the developer's real
  /// `~/.config/halfcell/`.
  let stateDirectory: URL
  @State private var loadedDocument: GIFEditorDocumentLoad?
  @State private var recovery: GIFEditorRecoveryOffer?

  public init(path: String? = nil, stateDirectory: URL? = nil) {
    self.path = path
    self.stateDirectory = stateDirectory ?? EditorViewModel.stateDirectory()
  }

  public var body: some View {
    content
      .task(id: path) {
        @MainActor in
        loadedDocument = nil
        recovery = nil
        let autosaveURL = EditorViewModel.autosaveURL(inStateDirectory: stateDirectory)
        let loaded = await Self.loadDocument(path: path, autosaveURL: autosaveURL)
        guard !Task.isCancelled else {
          return
        }
        if let snapshot = loaded.recoverable {
          recovery = GIFEditorRecoveryOffer(snapshot: snapshot, fallback: loaded)
        } else {
          loadedDocument = loaded
        }
      }
  }

  @ViewBuilder
  private var content: some View {
    if let recovery {
      RecoveryPromptView(
        offer: recovery,
        onRecover: {
          loadedDocument = GIFEditorDocumentLoad(
            document: recovery.snapshot.document,
            statusMessage: "Recovered unsaved changes",
            recoverable: nil,
            recoveredUnsavedWork: true
          )
          self.recovery = nil
        },
        onDiscard: {
          try? AutosaveStore.clear(
            at: EditorViewModel.autosaveURL(inStateDirectory: stateDirectory)
          )
          loadedDocument = recovery.fallback
          self.recovery = nil
        }
      )
    } else if let loadedDocument {
      EditorView(
        document: loadedDocument.document,
        initialStatusMessage: loadedDocument.statusMessage,
        stateDirectory: stateDirectory,
        recoveredUnsavedWork: loadedDocument.recoveredUnsavedWork
      )
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Text("gifeditor").foregroundStyle(.foreground)
        Text(path == nil ? "Preparing blank document..." : "Loading GIF...")
          .foregroundStyle(.muted)
      }
      .padding(1)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private nonisolated static func loadDocument(
    path: String?,
    autosaveURL: URL
  ) async -> GIFEditorDocumentLoad {
    await Task.detached(priority: .userInitiated) {
      loadDocumentSynchronously(path: path, autosaveURL: autosaveURL)
    }.value
  }

  /// Internal rather than private so the launch-path tests can exercise
  /// all three recovery outcomes without driving a terminal.
  nonisolated static func loadDocumentSynchronously(
    path: String?,
    autosaveURL: URL
  ) -> GIFEditorDocumentLoad {
    var load = loadRequestedDocument(path: path)

    // The three outcomes of `recover` are three different things to say.
    //
    //   nil   — the normal launch. No file, no prompt, and no mention of
    //           a feature the author never used.
    //   value — there is work to offer back; the caller raises the
    //           prompt.
    //   throw — a file existed and this build cannot turn it back into a
    //           document. That is unsaved work being lost, and folding
    //           it into a clean-looking launch is the one response that
    //           is definitely wrong.
    do {
      load.recoverable = try AutosaveStore.recover(from: autosaveURL)
    } catch {
      load.recoverable = nil
      // Left on disk deliberately. The bytes may still be worth
      // something to a person with a text editor, and deleting the only
      // copy of unrecovered work on the author's behalf is not this
      // build's call to make.
      load.statusMessage =
        "Recovery file at \(autosaveURL.path) is damaged and was left in place — \(error)"
    }
    return load
  }

  private nonisolated static func loadRequestedDocument(
    path: String?
  ) -> GIFEditorDocumentLoad {
    guard let path else {
      return GIFEditorDocumentLoad(
        document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 32, height: 32)),
        statusMessage: ""
      )
    }
    let url = URL(fileURLWithPath: path)
    do {
      // Routed through the sniffing loader rather than straight at
      // `GIFLoader`, so a `.halfcell` named on the command line opens as
      // the project it is instead of being handed to the GIF importer.
      return GIFEditorDocumentLoad(
        document: try EditorViewModel.loadDocument(contentsOf: url),
        statusMessage: "Loaded \(url.path)"
      )
    } catch {
      // Fall back to a blank document anchored at the requested path so
      // a later Save has somewhere to start from.
      var doc = GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 32, height: 32))
      doc.path = url
      return GIFEditorDocumentLoad(
        document: doc,
        statusMessage: "Load failed: \(error)"
      )
    }
  }
}

/// What the launch path resolved, before the recovery question is asked.
struct GIFEditorDocumentLoad: Sendable {
  var document: GIFDocument
  var statusMessage: String
  /// Unsaved work a previous session left behind, if any.
  var recoverable: AutosaveSnapshot?
  /// True once the author has accepted a recovery, so the editor knows
  /// to open dirty.
  var recoveredUnsavedWork: Bool = false
}

/// A recovery offer, plus the document to fall back to if it is declined.
struct GIFEditorRecoveryOffer: Sendable {
  var snapshot: AutosaveSnapshot
  var fallback: GIFEditorDocumentLoad
}

/// The launch-time prompt for unsaved work a previous session left
/// behind.
///
/// It names the document and how old the snapshot is, because "there is
/// unsaved work" makes the author guess whether it is worth taking, and
/// "changes to nyan.halfcell, 14 minute(s) ago" is a decision they can
/// actually make.
struct RecoveryPromptView: View {
  let offer: GIFEditorRecoveryOffer
  let onRecover: @MainActor @Sendable () -> Void
  let onDiscard: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Unsaved work was found").foregroundStyle(.tint)
      Text(Self.describe(offer.snapshot)).foregroundStyle(.foreground)
      Text(Self.describeContents(offer.snapshot)).foregroundStyle(.muted)
      HStack(spacing: 2) {
        Button("Recover", action: onRecover)
        Button("Discard", action: onDiscard)
      }
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  static func describe(_ snapshot: AutosaveSnapshot) -> String {
    let name = snapshot.originalPath?.lastPathComponent ?? "an untitled document"
    return "Changes to \(name), \(relativeAge(of: snapshot.savedAt))."
  }

  static func describeContents(_ snapshot: AutosaveSnapshot) -> String {
    let frames = snapshot.document.frames.count
    let layers = snapshot.document.frames.reduce(0) { $0 + $1.layers.count }
    let size = snapshot.document.size
    return "\(size.width)×\(size.height), \(frames) frame(s), \(layers) layer(s)."
  }

  /// Plain-language age. Hand-rolled rather than
  /// `RelativeDateTimeFormatter` because the granularity that matters
  /// here is "is this from this session or from last week", and a
  /// formatter would drag a locale dependency into a binary that has
  /// none.
  static func relativeAge(of date: Date, now: Date = Date()) -> String {
    let seconds = Int(max(0, now.timeIntervalSince(date)))
    switch seconds {
    case ..<60: return "less than a minute ago"
    case ..<3600: return "\(seconds / 60) minute(s) ago"
    case ..<86400: return "\(seconds / 3600) hour(s) ago"
    default: return "\(seconds / 86400) day(s) ago"
    }
  }
}

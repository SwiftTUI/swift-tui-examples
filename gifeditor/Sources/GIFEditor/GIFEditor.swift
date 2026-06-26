import Foundation
import GIFEditorCore
import GIFEditorUI
import SwiftTUI

/// Composition root for the editor.
///
/// Today this is mostly a thin façade — it loads or creates a document
/// based on an optional file path, then hands it to `EditorView`. A future
/// SwiftUI port would have a sibling factory function that returns a
/// SwiftUI view fed the same `GIFDocument`.
public struct GIFEditor: View {
  let path: String?
  @State private var loadedDocument: GIFEditorDocumentLoad?

  public init(path: String? = nil) {
    self.path = path
  }

  public var body: some View {
    content
      .task(id: path) {
        @MainActor in
        loadedDocument = nil
        let loaded = await Self.loadDocument(path: path)
        guard !Task.isCancelled else {
          return
        }
        loadedDocument = loaded
      }
  }

  @ViewBuilder
  private var content: some View {
    if let loadedDocument {
      EditorView(
        document: loadedDocument.document,
        initialStatusMessage: loadedDocument.statusMessage
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

  private nonisolated static func loadDocument(path: String?) async -> GIFEditorDocumentLoad {
    await Task.detached(priority: .userInitiated) {
      loadDocumentSynchronously(path: path)
    }.value
  }

  private nonisolated static func loadDocumentSynchronously(path: String?) -> GIFEditorDocumentLoad {
    guard let path else {
      return GIFEditorDocumentLoad(
        document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 32, height: 32)),
        statusMessage: ""
      )
    }
    let url = URL(fileURLWithPath: path)
    do {
      return GIFEditorDocumentLoad(
        document: try GIFLoader.load(contentsOf: url),
        statusMessage: "Loaded \(url.path)"
      )
    } catch {
      // Fall back to a blank document anchored at the requested path so
      // a future Ctrl+S writes there.
      var doc = GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 32, height: 32))
      doc.path = url
      return GIFEditorDocumentLoad(
        document: doc,
        statusMessage: "Load failed: \(error)"
      )
    }
  }
}

private struct GIFEditorDocumentLoad: Sendable {
  var document: GIFDocument
  var statusMessage: String
}

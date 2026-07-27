import Foundation
import GIFEditorCore
import SwiftTUI

/// Modal sheet for opening a document: a path field with filesystem
/// prefix completion, plus the recent-documents list.
///
/// A real file browser is a later nicety. What a terminal author needs
/// first is the two things a shell already gives them — type a prefix,
/// press a key, get the rest — and a short list of what they were
/// working on. Completion is a `Button` rather than `Tab` because `Tab`
/// belongs to focus traversal inside a sheet that has more than one
/// focusable control.
///
/// The sheet does no routing of its own: it hands a URL back, and
/// ``GIFDocumentIO/open(contentsOf:dithering:)`` decides from the bytes
/// whether that is an import or a project. A file named `.halfcell` that
/// is really a GIF opens correctly from here, because nothing here ever
/// looked at the extension.
struct OpenDocumentSheetView: View {
  @Binding var pathText: String
  /// Most-recent first, as ``RecentDocuments`` keeps them.
  let recentDocuments: [URL]
  /// Set when the last attempt from this sheet failed, so the sheet can
  /// stay up and say why instead of vanishing over a typo.
  let errorMessage: String?
  let isOpening: Bool
  let onOpen: @MainActor @Sendable (URL) -> Void
  let onCancel: @MainActor @Sendable () -> Void

  @State private var completionHint: String = ""
  @FocusState private var pathFocused: Bool

  /// How many recents to show. The list itself holds ten; a sheet that
  /// scrolls to reach the fifth-most-recent file is worse than one that
  /// shows six and leaves the rest to the path field.
  private static let visibleRecentCount = 6

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Open a GIF or .\(ProjectFile.fileExtension) project").foregroundStyle(.tint)
      pathField
      Divider()
      recentSection
      Divider()
      status
      HStack(spacing: 1) {
        Spacer(minLength: 1)
        Button("Cancel", action: onCancel)
          .systemHint("Esc")
        Button("Open") {
          guard let targetURL, !isOpening else { return }
          onOpen(targetURL)
        }
        .disabled(targetURL == nil || isOpening)
      }
    }
    .padding(1)
    .onChange(of: pathText) {
      completionHint = ""
    }
  }

  // MARK: - Path entry

  private var pathField: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Path").foregroundStyle(.muted)
      HStack(spacing: 1) {
        TextField("Path", text: $pathText)
          .focused($pathFocused)
          .onAppear {
            pathFocused = true
          }
          .textFieldStyle(.plain)
          .frame(width: 52, alignment: .leading)
        Button("Complete", action: complete)
          .buttonStyle(.plain)
          .fixedSize(horizontal: true, vertical: true)
      }
      Text(completionHint).foregroundStyle(.separator)
    }
  }

  /// Extends the typed text as far as the matching names agree and
  /// summarises what else it could have been.
  ///
  /// The hint is a summary rather than the full list: a directory of two
  /// hundred PNGs must not push the Open button off the sheet.
  private func complete() {
    let completion = GIFDocumentIO.completePath(pathText)
    pathText = completion.text
    if completion.isEmpty {
      completionHint = "Nothing here matches that."
    } else if completion.isUnique {
      completionHint = ""
    } else {
      let shown = completion.matches.prefix(4).joined(separator: "  ")
      let extra = completion.matches.count - min(4, completion.matches.count)
      completionHint = extra > 0 ? "\(shown)  … +\(extra) more" : shown
    }
  }

  // MARK: - Recents

  @ViewBuilder
  private var recentSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Recent").foregroundStyle(.muted)
      if recentDocuments.isEmpty {
        Text("Nothing opened yet.").foregroundStyle(.separator)
      } else {
        ForEach(Array(recentDocuments.prefix(Self.visibleRecentCount)), id: \.path) { url in
          Button {
            guard !isOpening else { return }
            onOpen(url)
          } label: {
            HStack(spacing: 1) {
              Text(url.lastPathComponent).foregroundStyle(.foreground)
              Text(url.deletingLastPathComponent().path).foregroundStyle(.separator)
            }
          }
          .buttonStyle(.plain)
          .fixedSize(horizontal: true, vertical: true)
        }
      }
    }
  }

  // MARK: - Status

  @ViewBuilder
  private var status: some View {
    if let errorMessage {
      Text(errorMessage).foregroundStyle(.warning)
    } else if isOpening {
      Text("Opening…").foregroundStyle(.muted)
    } else if targetURL == nil {
      Text("Enter a path, or pick a recent document").foregroundStyle(.muted)
    } else if !targetExists {
      Text("No file at that path yet").foregroundStyle(.warning)
    } else {
      Text("Ready to open").foregroundStyle(.success)
    }
  }

  private var targetURL: URL? {
    EditorViewModel.saveURL(from: pathText)
  }

  private var targetExists: Bool {
    guard let targetURL else { return false }
    return FileManager.default.fileExists(atPath: targetURL.path)
  }
}

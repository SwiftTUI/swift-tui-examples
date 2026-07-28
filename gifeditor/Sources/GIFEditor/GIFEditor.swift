import Foundation
import GIFEditorCore
import GIFEditorUI
import SwiftTUI

/// Composition root for the editor.
///
/// It asks `DocumentLifecycle` to resolve an optional launch path and any
/// recovery snapshot, then hands that same lifecycle to `EditorView`.
public struct GIFEditor: View {
  let path: String?
  let stateDirectory: URL?
  @State private var lifecycle: DocumentLifecycle?
  @State private var revision = 0

  public init(path: String? = nil, stateDirectory: URL? = nil) {
    self.path = path
    self.stateDirectory = stateDirectory
  }

  public var body: some View {
    _ = revision
    content
      .task(id: path) {
        @MainActor in
        lifecycle = nil
        let prepared = await DocumentLifecycle.launch(
          path: path,
          stateDirectory: stateDirectory
        )
        guard !Task.isCancelled else {
          return
        }
        lifecycle = prepared
      }
  }

  @ViewBuilder
  private var content: some View {
    if let lifecycle, let snapshot = lifecycle.recoverySnapshot {
      RecoveryPromptView(
        snapshot: snapshot,
        onRecover: {
          lifecycle.resolveRecovery(.recover)
          revision &+= 1
        },
        onDiscard: {
          lifecycle.resolveRecovery(.discard)
          revision &+= 1
        }
      )
    } else if let lifecycle {
      EditorView(lifecycle: lifecycle)
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
}

/// The launch-time prompt for unsaved work a previous session left
/// behind.
///
/// It names the document and how old the snapshot is, because "there is
/// unsaved work" makes the author guess whether it is worth taking, and
/// "changes to nyan.halfcell, 14 minute(s) ago" is a decision they can
/// actually make.
struct RecoveryPromptView: View {
  let snapshot: AutosaveSnapshot
  let onRecover: @MainActor @Sendable () -> Void
  let onDiscard: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Unsaved work was found").foregroundStyle(.tint)
      Text(Self.describe(snapshot)).foregroundStyle(.foreground)
      Text(Self.describeContents(snapshot)).foregroundStyle(.muted)
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

import Foundation
import GIFEditorCore
import SwiftTUI

/// Modal sheet for starting a new document: the same square presets the
/// resize sheet offers, plus arbitrary `width × height` entry.
///
/// It shares `ResizeCanvasSheetView`'s parser rather than restating the
/// bounds, so "what counts as a size the editor will hand you" is one
/// rule with one place to change. The wording is its own, because a
/// sheet that says "Resize" while creating a document is a small lie
/// that the author has to work out for themselves.
///
/// Any unsaved-work question has already been answered by the time this
/// appears — the guard runs before the size prompt, so an author who
/// cancels here has lost nothing and an author who confirms has already
/// said what to do about the old document.
struct NewDocumentSheetView: View {
  let onCreate: @MainActor @Sendable (GIFEditorCore.PixelSize) -> Void
  let onCancel: @MainActor @Sendable () -> Void

  @State private var widthText: String = ""
  @State private var heightText: String = ""

  private static let presetColumns = 3

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("New document").foregroundStyle(.tint)
      Text("Pick a square canvas size:").foregroundStyle(.muted)
      ForEach(0..<Self.presetRowCount, id: \.self) { row in
        HStack(spacing: 1) {
          ForEach(Self.presetRow(row), id: \.self) { dimension in
            presetButton(for: dimension)
          }
          Spacer(minLength: 1)
        }
      }
      Divider()
      customEntry
      Divider()
      HStack(spacing: 1) {
        Spacer(minLength: 1)
        Button("Cancel", action: onCancel)
          .systemHint("Esc")
      }
    }
    .padding(1)
  }

  // MARK: - Presets

  private func presetButton(for dimension: Int) -> some View {
    let size = GIFEditorCore.PixelSize(width: dimension, height: dimension)
    return Button("\(dimension) × \(dimension)") {
      onCreate(size)
    }
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: true)
  }

  private static var presetRowCount: Int {
    let count = EditorViewModel.canvasSizeProgression.count
    return (count + presetColumns - 1) / presetColumns
  }

  private static func presetRow(_ row: Int) -> [Int] {
    let progression = EditorViewModel.canvasSizeProgression
    let start = row * presetColumns
    let end = min(start + presetColumns, progression.count)
    guard start < end else { return [] }
    return Array(progression[start..<end])
  }

  // MARK: - Custom size

  private var customEntry: some View {
    let entry = ResizeCanvasSheetView.parseCustomSize(width: widthText, height: heightText)
    return VStack(alignment: .leading, spacing: 0) {
      Text("…or enter any size up to \(EditorViewModel.maximumCanvasDimension) per axis:")
        .foregroundStyle(.muted)
      HStack(spacing: 1) {
        TextField("W", text: $widthText)
          .textFieldStyle(.plain)
          .frame(width: 6, alignment: .leading)
        Text("×").foregroundStyle(.muted)
        TextField("H", text: $heightText)
          .textFieldStyle(.plain)
          .frame(width: 6, alignment: .leading)
        Button("Create") {
          guard let size = entry.size else { return }
          onCreate(size)
        }
        .disabled(entry.size == nil)
      }
      Text(entry.isInvalid ? entry.message : createHint(for: entry))
        .foregroundStyle(entry.isInvalid ? .warning : .muted)
    }
  }

  /// The valid/empty half of the entry's own wording, restated in this
  /// sheet's voice — the shared parser speaks of resizing.
  private func createHint(for entry: ResizeCanvasSheetView.CustomSizeEntry) -> String {
    guard let size = entry.size else { return "Both fields are needed." }
    return "Create a \(size.width) × \(size.height) document."
  }
}

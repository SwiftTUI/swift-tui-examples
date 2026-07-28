import Foundation
import GIFEditorCore
import SwiftTUI

/// Modal sheet for choosing a new canvas size: the square presets from
/// `EditingSession.canvasSizeProgression`, plus arbitrary `width ×
/// height` entry.
///
/// The keyboard binding `Ctrl+R` and the File → Resize Canvas menu
/// item both open this sheet so users can either cycle from muscle
/// memory or jump directly to a specific size.
///
/// The presets are laid out three to a row rather than as one column:
/// the progression runs to 256 now, and nine stacked rows would push
/// the custom fields below the fold on a short terminal.
///
/// The `1...256` bound enforced here is a **UI** cap and lives only
/// here. The project format stores arbitrary dimensions and the GIF
/// loader opens whatever it is handed, so an oversized document is
/// something the editor can still show — it is just not a size the New /
/// Resize flow will hand you.
struct ResizeCanvasSheetView: View {
  let currentSize: GIFEditorCore.PixelSize
  let onSelect: @MainActor @Sendable (GIFEditorCore.PixelSize) -> Void
  let onCancel: @MainActor @Sendable () -> Void

  @State private var widthText: String = ""
  @State private var heightText: String = ""

  private static let presetColumns = 3

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Pick a square canvas size:").foregroundStyle(.muted)
      ForEach(0..<Self.presetRowCount, id: \.self) { row in
        HStack(spacing: 1) {
          ForEach(Self.presetRow(row), id: \.self) { dimension in
            sizeRow(for: dimension)
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

  private func sizeRow(for dimension: Int) -> some View {
    let target = GIFEditorCore.PixelSize(width: dimension, height: dimension)
    let isCurrent = target == currentSize
    return Button {
      onSelect(target)
    } label: {
      HStack(spacing: 1) {
        Text(isCurrent ? "✓" : " ")
          .foregroundStyle(isCurrent ? .tint : .muted)
        Text("\(dimension) × \(dimension)")
          .foregroundStyle(isCurrent ? .tint : .foreground)
      }
    }
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: true)
  }

  private static var presetRowCount: Int {
    let count = EditingSession.canvasSizeProgression.count
    return (count + presetColumns - 1) / presetColumns
  }

  private static func presetRow(_ row: Int) -> [Int] {
    let progression = EditingSession.canvasSizeProgression
    let start = row * presetColumns
    let end = min(start + presetColumns, progression.count)
    guard start < end else { return [] }
    return Array(progression[start..<end])
  }

  // MARK: - Custom size

  private var customEntry: some View {
    let entry = Self.parseCustomSize(width: widthText, height: heightText)
    return VStack(alignment: .leading, spacing: 0) {
      Text("…or enter any size up to \(EditingSession.maximumCanvasDimension) per axis:")
        .foregroundStyle(.muted)
      HStack(spacing: 1) {
        TextField("W", text: $widthText)
          .textFieldStyle(.plain)
          .frame(width: 6, alignment: .leading)
        Text("×").foregroundStyle(.muted)
        TextField("H", text: $heightText)
          .textFieldStyle(.plain)
          .frame(width: 6, alignment: .leading)
        Button("Resize") {
          guard case .valid(let size) = entry else { return }
          onSelect(size)
        }
        .disabled(entry.size == nil)
      }
      Text(entry.message).foregroundStyle(entry.isInvalid ? .warning : .muted)
    }
  }

  /// The three states the two custom-dimension fields can be in.
  ///
  /// Pulled out as a value with a pure parser so the cap, the bounds and
  /// the wording are testable without rendering a sheet or driving a
  /// terminal.
  enum CustomSizeEntry: Equatable {
    /// Nothing typed yet (or only whitespace).
    case empty
    /// Typed, but not a size — carries the message shown under the row.
    case invalid(String)
    case valid(GIFEditorCore.PixelSize)

    var size: GIFEditorCore.PixelSize? {
      if case .valid(let size) = self { return size }
      return nil
    }

    var isInvalid: Bool {
      if case .invalid = self { return true }
      return false
    }

    var message: String {
      switch self {
      case .empty:
        return "Both fields are needed."
      case .invalid(let text):
        return text
      case .valid(let size):
        return "Resize to \(size.width) × \(size.height)."
      }
    }
  }

  /// Parses the custom width/height fields.
  ///
  /// Rejects rather than clamps: silently turning a typed `512` into
  /// `256` would hand back a canvas the author did not ask for, and the
  /// whole point of the field is that the author is naming an exact
  /// size.
  static func parseCustomSize(width: String, height: String) -> CustomSizeEntry {
    let widthText = width.trimmingCharacters(in: .whitespaces)
    let heightText = height.trimmingCharacters(in: .whitespaces)
    guard !widthText.isEmpty, !heightText.isEmpty else { return .empty }

    guard let parsedWidth = Int(widthText), let parsedHeight = Int(heightText) else {
      return .invalid("Enter whole numbers.")
    }
    guard parsedWidth >= 1, parsedHeight >= 1 else {
      return .invalid("Each side must be at least 1.")
    }
    let cap = EditingSession.maximumCanvasDimension
    guard parsedWidth <= cap, parsedHeight <= cap else {
      return .invalid("The editor caps new canvases at \(cap) per axis.")
    }
    return .valid(GIFEditorCore.PixelSize(width: parsedWidth, height: parsedHeight))
  }
}

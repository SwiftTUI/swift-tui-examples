import GIFEditorCore
import SwiftTUI

/// Top sub-panel of the right column — Photoshop-style "Color"
/// inspector. Shows the active primary and secondary colors as
/// labeled swatches with their hex codes.
///
/// The chips are decorative readouts; swapping primary/secondary is a
/// click away in the tool-options bar and the tool dock (and on the
/// `x` keyboard shortcut), so the inspector stays a compact readout.
struct ColorPanelView: View {
  let primaryColor: EditorColor
  let secondaryColor: EditorColor

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Color").foregroundStyle(.muted)
      colorRow(label: "P", color: primaryColor)
      colorRow(label: "S", color: secondaryColor)
    }
    .padding(.horizontal, 1)
  }

  private func colorRow(label: String, color: EditorColor) -> some View {
    HStack(spacing: 1) {
      Text(label).foregroundStyle(.muted)
      Rectangle()
        .fill(color.toTerminalColor())
        .frame(width: 4, height: 1)
      Text("#\(hex(color))").foregroundStyle(.separator)
    }
  }

  private func hex(_ c: EditorColor) -> String {
    String(format: "%02X%02X%02X", c.red, c.green, c.blue)
  }
}

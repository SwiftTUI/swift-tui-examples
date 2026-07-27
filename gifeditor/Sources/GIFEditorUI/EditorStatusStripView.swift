import SwiftTUI

/// Single-row status strip at the bottom of the editor: the transient
/// message on the left, the cursor / layer / brush-size / render-mode
/// readout on the right. Document identity and dirty state live in the menu
/// bar's trailing slot instead.
///
/// Its own view, and taking two ready-made strings rather than the model,
/// for the reason ``InspectorColumnView`` is: it is a term in
/// ``EditorLayoutFloor``'s height, and a term that cannot be handed to the
/// layout system on its own cannot be measured. It is also the region the
/// editor gives up *last* — every command that changes something the canvas
/// cannot show says so here, so a layout that dropped this row would make
/// those commands look like they did nothing.
struct EditorStatusStripView: View {
  /// What just happened, or `Ready` when nothing has.
  let message: String
  /// The always-on readout: playback, frame, cursor, layer, brush, zoom,
  /// onion skin, pixel-grid mode.
  let readout: String

  var body: some View {
    HStack(spacing: 2) {
      Text(message.isEmpty ? "Ready" : message)
        .foregroundStyle(.muted)
      Spacer(minLength: 1)
      Text(readout)
        .foregroundStyle(.separator)
    }
    .padding(.horizontal, 1)
    // One row, and exactly one. The `Spacer` that holds the readout against
    // the trailing edge would otherwise make this strip look vertically
    // unbounded to the editor's stack, which would hand it the terminal's
    // spare rows — the canvas's rows — and leave them blank.
    .fixedSize(horizontal: false, vertical: true)
  }
}

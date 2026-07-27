import GIFEditorCore
import SwiftTUI

/// The right-hand inspector: the color readout over the palette grid over
/// the layer list, in one fixed-width column.
///
/// A view of its own rather than three sub-panels stacked inline in
/// ``EditorView``'s body, for a reason that is more than tidiness: this
/// column is the tallest thing in the body row, so it is the region that
/// sets the editor's minimum height, and
/// `EditorLayoutFloorTests` can only *measure* that if there is something to
/// hand the layout system. Inline in a 90-line stack it was unmeasurable,
/// and the height floor would have had to be asserted from arithmetic
/// instead of from the layout system's own answer.
///
/// The sub-panels compress under ``EditorLayoutDensity/compact`` — see that
/// type for the ladder — and the rules between them are the first thing to
/// go: each heading already names the panel under it.
struct InspectorColumnView: View {
  let primaryColor: EditorColor
  let secondaryColor: EditorColor
  let palette: ColorPalette
  let primaryIndex: PaletteIndex
  let secondaryIndex: PaletteIndex
  let layers: [EditorLayer]
  let selectedLayerIndex: Int
  let model: EditorViewModel
  let refresh: @MainActor @Sendable () -> Void
  let fidelity: EditorColorFidelity
  var density: EditorLayoutDensity = .regular

  /// Fixed width of the column. Pinning it (rather than `.fixedSize`) keeps
  /// the canvas the sole flexible child of the body row, so reclaimed
  /// horizontal space flows to the canvas instead of pooling as dead margin
  /// to the right of the panel.
  ///
  /// Not `private` because it is also a term in ``EditorLayoutFloor`` — the
  /// body row cannot be narrower than this column plus the tool dock — and a
  /// floor computed from a copy of the number would drift from the layout it
  /// claims to describe.
  static let width = 28

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ColorPanelView(
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        density: density
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      if density.drawsRedundantRules {
        Divider()
      }
      PaletteView(
        palette: palette,
        primaryIndex: primaryIndex,
        secondaryIndex: secondaryIndex,
        model: model,
        refresh: refresh,
        fidelity: fidelity,
        density: density
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      if density.drawsRedundantRules {
        Divider()
      }
      LayerListView(
        layers: layers,
        selectedIndex: selectedLayerIndex,
        model: model,
        refresh: refresh,
        density: density
      )
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .border(.separator, set: .single)
    .frame(width: Self.width)
  }
}

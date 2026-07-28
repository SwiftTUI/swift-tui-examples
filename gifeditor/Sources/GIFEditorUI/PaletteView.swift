import GIFEditorCore
import SwiftTUI

/// Middle sub-panel of the right column — a grid of the first 32 palette
/// slots, eight to a row, and of the first 16 where the terminal is too
/// short for four rows of them (see ``rows``). Every swatch is a clickable
/// `Button` that sets the
/// primary color slot. The active primary slot wears a `P` overlay,
/// the secondary slot wears `S`, and slots 1..9 carry a trailing digit
/// label that advertises the keyboard shortcut. `Alt+1..9` continues
/// to set the secondary slot via keyboard (mouse parity for that
/// secondary-pick path lands in a future pass once the framework's
/// pointer model exposes shift-click cleanly).
///
/// Users editing a loaded GIF still have access to the full 256 slots
/// via the eyedropper; this grid surfaces the first 32 as quick-pick
/// swatches.
///
/// On a 256-color terminal two slots the artist chose deliberately apart can
/// arrive as the same cell color — the cube quantizes each channel to six
/// levels, so anything inside a fifth of the range collapses. The grid cannot
/// move the artist's colors, so it says so instead: a swatch that will reach
/// the terminal as the same color as the one before it wears a `▏` on its
/// leading cell, which draws the boundary the colors no longer do. The marker
/// only ever appears under ``EditorColorFidelity/reduced``, and never on a
/// swatch already wearing `P` or `S` — those are boundaries too.
struct PaletteView: View {
  let palette: ColorPalette
  let primaryIndex: PaletteIndex
  let secondaryIndex: PaletteIndex
  let model: EditingSession
  let refresh: @MainActor @Sendable () -> Void
  var fidelity: EditorColorFidelity = .full
  var density: EditorLayoutDensity = .regular

  private static let columns = 8

  /// Grid rows at this density — four (32 slots) where there is height for
  /// them, two (16) where there is not.
  ///
  /// Halving the grid is the fourth rung of the compression ladder and the
  /// first one that costs the author anything, which is why it comes after
  /// the rules, the box and the thumbnails: 16 swatches leave, and what
  /// makes that affordable is that they are the *quietest* 16. Slots 1–9
  /// carry the digit labels that advertise their own keyboard shortcut and
  /// all sit in the first two rows, and every slot in the palette — all 256
  /// of them, not just these 32 — stays reachable with the eyedropper and in
  /// the palette editor.
  private var rows: Int { density.paletteRows }

  /// The glyph that stands in for a boundary the colors stopped drawing.
  static let collisionMarker: Character = "▏"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Palette").foregroundStyle(.muted)
      ForEach(0..<rows, id: \.self) { row in
        HStack(spacing: 0) {
          ForEach(0..<Self.columns, id: \.self) { column in
            let slot = row * Self.columns + column
            swatch(for: PaletteIndex(slot))
          }
        }
      }
    }
    .padding(.horizontal, 1)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func swatch(for index: PaletteIndex) -> some View {
    let color = palette[index]
    let isPrimary = index == primaryIndex
    let isSecondary = index == secondaryIndex
    // Leading column: P/S role marker (highest priority since the
    // active slot is the most important to telegraph), then the
    // collision marker, which is only needed where neither one is.
    let leading: String
    if isPrimary {
      leading = "P"
    } else if isSecondary {
      leading = "S"
    } else if collidesWithNeighbour(index) {
      leading = String(Self.collisionMarker)
    } else {
      leading = " "
    }
    // Trailing column: 1..9 keyboard-shortcut hint for the first nine
    // slots so the keyboard mapping reads at a glance even when no
    // keyboard help is open.
    let slotNumber = Int(index)
    let trailing: String
    if slotNumber >= 1, slotNumber <= 9 {
      trailing = String(slotNumber)
    } else {
      trailing = " "
    }
    // Both glyphs sit *on* the swatch, so their color has to answer to the
    // swatch's rather than to the theme's — a white `P` on a white slot is
    // an invisible marker on whichever background the terminal has.
    let ink = color.toTerminalColor().legibleInk
    return Button {
      model.dispatch(.setPrimaryColor(index))
      refresh()
    } label: {
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(color.toTerminalColor())
          .frame(width: 2, height: 1)
        HStack(spacing: 0) {
          Text(leading).foregroundStyle(ink)
          Text(trailing).foregroundStyle(ink)
        }
      }
    }
    .buttonStyle(.plain)
  }

  /// Whether `index` will reach the terminal as the same color as the swatch
  /// to its left, or — in the first column, which has no left — the one above
  /// it.
  ///
  /// Both neighbours count because both are adjacent on screen, and a
  /// collision the artist cannot see is a collision either way. Always
  /// `false` under ``EditorColorFidelity/full``, where two distinct colors
  /// stay two colors and the marker would be noise.
  func collidesWithNeighbour(_ index: PaletteIndex) -> Bool {
    guard fidelity == .reduced else {
      return false
    }
    let slot = Int(index)
    let neighbour = slot % Self.columns == 0 ? slot - Self.columns : slot - 1
    guard neighbour >= 0 else {
      return false
    }
    return !TerminalColorCube.areDistinguishable(
      palette[index].toTerminalColor(),
      palette[PaletteIndex(neighbour)].toTerminalColor(),
      fidelity: fidelity
    )
  }
}

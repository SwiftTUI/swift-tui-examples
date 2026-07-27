import SwiftTUI

/// The narrowest terminal the editor can lay itself out in, and the check that
/// decides whether this one qualifies.
///
/// **Why a width and not a size.** Ask the layout system to fit `EditorView`
/// into nothing and it answers `64 × 27`. The width half of that is a real
/// floor: propose 64 columns and the rendered surface is 64 columns; propose
/// 63 and it is *still* 64, because the menu bar's six triggers cannot
/// compress any further. Everything past that point overflows the terminal —
/// the right inspector runs off the edge, the timeline's labels stack one
/// letter per row, and words in the status strip break mid-syllable. That is
/// the state this guard exists to replace with a sentence.
///
/// The height half is not a floor of the same kind, and pretending otherwise
/// would be a lie the guard could not keep. The editor's vertical layout is
/// not responsive at all: from a 28-row proposal down to a 12-row one it
/// renders the identical 28-row surface, and the terminal simply shows fewer
/// of those rows. There is no height at which it *fails* to lay out, only
/// heights at which rows are clipped off the bottom — and the smallest size
/// the editor's own tests exercise, 80×24, is already one of them. Gating on
/// 28 rows would declare the documented size unusable; gating on some smaller
/// round number would be a number picked rather than measured. So the guard
/// gates on the axis that has an answer, and the message reports the size the
/// terminal actually is.
/// `@MainActor` only because ``bodyRowWidth`` names
/// ``EditorView/rightPanelWidth`` — reading the real constant rather than a
/// copy of it is worth inheriting the isolation of the view it belongs to,
/// and every caller (a `body`, a test) is already on the main actor.
@MainActor
enum EditorLayoutFloor {
  /// The menu bar's contribution, and the binding constraint.
  ///
  /// Six triggers (`File ▾` … `View ▾`), each a `.plain` `Button` with the
  /// focus-rail gutter the framework reserves, two cells of `HStack` spacing
  /// between them, one cell of padding on each side, and the trailing
  /// document label and dirty marker. Pinned rather than recomputed from
  /// ``MenuBarMenu`` because the focus rail and the trailing label are the
  /// framework's arithmetic, not the editor's — and pinned honestly:
  /// `EditorLayoutFloorTests` measures `MenuBarView`'s own floor and fails if
  /// this number and the layout system stop agreeing.
  static let menuBarWidth = 64

  /// The body row's contribution: the 4-cell tool dock inside its border, one
  /// cell of `HStack` spacing, the canvas region's border around a single
  /// column of artwork, another cell of spacing, and the fixed-width right
  /// inspector. Comfortably under the menu bar, and here so a future change
  /// to either one has something to be compared against.
  static let bodyRowWidth = (4 + 2) + 1 + (2 + 1) + 1 + EditorView.rightPanelWidth

  /// The narrowest terminal `EditorView` renders into without overflowing it.
  static let minimumWidth = max(menuBarWidth, bodyRowWidth)

  /// Whether the editor can lay itself out in `size`.
  static func fits(_ size: CellSize) -> Bool {
    size.width >= minimumWidth
  }
}

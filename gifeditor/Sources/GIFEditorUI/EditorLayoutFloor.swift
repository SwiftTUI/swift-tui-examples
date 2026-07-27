import SwiftTUI

/// The smallest terminal the editor can lay itself out in, and the check that
/// decides whether this one qualifies.
///
/// **Width.** Ask the layout system to fit `EditorView` into nothing and the
/// width half of its answer is a real floor: propose 64 columns and the
/// rendered surface is 64 columns; propose 63 and it is *still* 64, because
/// the menu bar's six triggers cannot compress any further. Everything past
/// that point overflows the terminal — the right inspector runs off the edge,
/// the timeline's labels stack one letter per row, and words in the status
/// strip break mid-syllable. That is the state this guard exists to replace
/// with a sentence.
///
/// **Height** is a different kind of question, and for a long time the editor
/// had no answer to it at all. From a 28-row proposal down to a 12-row one it
/// rendered the identical 28-row surface: there was no height at which it
/// *failed* to lay out, only heights at which rows fell off the bottom — and
/// 80×24, the size a terminal opens at and the size this package's own tests
/// run at, was one of them. Asking the layout system for the height at which
/// the surface stops shrinking would have measured the wrong thing, because
/// that height is already four rows into the clipping: a stack's minimum lets
/// rules collapse to nothing and lets the last child overdraw a border.
///
/// So the height floor is derived the other way round — by asking each region
/// how tall it is when it is *whole*, and adding those up. Each term below is
/// a region's own measured height, `EditorLayoutFloorTests` re-measures every
/// one of them on every run, and the sum is the height at which the editor
/// lays out with nothing clipped and the canvas at its own minimum. Below it
/// the guard shows ``TerminalTooSmallView`` rather than a surface the terminal
/// cannot hold.
///
/// What brought the floor under 24 at all is ``EditorLayoutDensity``: the same
/// regions, measured twice, because at 24 rows the chrome has to cost less
/// than it does at 40.
///
/// `@MainActor` only because ``bodyRowWidth`` names
/// ``InspectorColumnView/width`` — reading the real constant rather than a
/// copy of it is worth inheriting the isolation of the view it belongs to,
/// and every caller (a `body`, a test) is already on the main actor.
@MainActor
enum EditorLayoutFloor {
  // MARK: - Width

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

  /// The body row's contribution: the tool dock inside its border, one cell
  /// of `HStack` spacing, the canvas region's border around a single column
  /// of artwork, another cell of spacing, and the fixed-width right
  /// inspector. Measured against the *widest* dock, which is the compact
  /// one — it spends columns to buy rows. Comfortably under the menu bar, and
  /// here so a future change to either one has something to be compared
  /// against.
  static let bodyRowWidth =
    (widestToolDockWidth + 2) + 1 + (2 + 1) + 1 + InspectorColumnView.width

  private static let widestToolDockWidth =
    EditorLayoutDensity.allCases.map(\.toolDockWidth).max() ?? 0

  /// The narrowest terminal `EditorView` renders into without overflowing it.
  static let minimumWidth = max(menuBarWidth, bodyRowWidth)

  // MARK: - Height

  /// The menu bar is one row of triggers at either density; there is nothing
  /// in it to compress.
  static let menuBarHeight = 1

  /// The status strip is one row, and the last one the editor would give up:
  /// it is where every command that changed something invisible says so.
  static let statusStripHeight = 1

  /// The tool-options bar: one row of controls, plus the two rows of box it
  /// wears only at ``EditorLayoutDensity/regular``.
  static func toolOptionsBarHeight(at density: EditorLayoutDensity) -> Int {
    density.boxesToolOptionsBar ? 3 : 1
  }

  /// The tool dock: its border, one row per row of tool icons, the rule
  /// under them, the primary/secondary swatches and the swap button.
  static func toolDockHeight(at density: EditorLayoutDensity) -> Int {
    switch density {
    case .regular: 15
    case .compact: 10
    }
  }

  /// The right inspector, at its tallest — a layer list filled to
  /// ``EditorLayoutDensity/visibleLayerRows``. The tallest is the number
  /// that matters: a floor that only held for a one-layer document would be
  /// a floor the next `Alt+N` breaks.
  static func inspectorHeight(at density: EditorLayoutDensity) -> Int {
    switch density {
    case .regular: 21
    case .compact: 12
    }
  }

  /// The timeline strip: its border around the tallest of its four columns,
  /// which is always the thumbnail strip, plus the scroll indicator the strip
  /// grows once it holds more frames than fit across.
  ///
  /// The indicator is in the number for the same reason the layer list's
  /// window is: a document with two frames must not produce an editor that a
  /// document with twelve overflows.
  static func timelineHeight(at density: EditorLayoutDensity) -> Int {
    switch density {
    case .regular: 8
    case .compact: 7
    }
  }

  /// The body row is as tall as its tallest column. The canvas is not a term:
  /// it is the region that takes whatever the others leave, which is the
  /// whole point of compressing them.
  static func bodyRowHeight(at density: EditorLayoutDensity) -> Int {
    max(toolDockHeight(at: density), inspectorHeight(at: density))
  }

  /// The shortest terminal the whole stack fits in at `density`, region by
  /// region, top to bottom.
  static func minimumHeight(at density: EditorLayoutDensity) -> Int {
    menuBarHeight
      + toolOptionsBarHeight(at: density)
      + bodyRowHeight(at: density)
      + timelineHeight(at: density)
      + (density.drawsRedundantRules ? 1 : 0)
      + statusStripHeight
  }

  /// The shortest terminal `EditorView` renders into without running off the
  /// bottom of it — the compact layout's own minimum, because compact is what
  /// the editor falls back to before it gives up.
  static let minimumHeight = minimumHeight(at: .compact)

  /// The height at which the regular layout fits, and therefore the height at
  /// which the editor stops compressing. Not a floor — a switch: below it the
  /// editor is still perfectly usable, just denser.
  static let regularMinimumHeight = minimumHeight(at: .regular)

  // MARK: - Decisions

  /// Which layout `size` can hold. See ``EditorLayoutDensity`` for what the
  /// two of them differ by.
  ///
  /// The switch point is the regular layout's own measured minimum rather
  /// than a round number, so it moves when the layout does: add a row to the
  /// inspector and the terminal that no longer fits the regular layout
  /// automatically stops being offered it.
  static func density(for size: CellSize) -> EditorLayoutDensity {
    size.height >= regularMinimumHeight ? .regular : .compact
  }

  /// Whether the editor can lay itself out in `size`.
  static func fits(_ size: CellSize) -> Bool {
    size.width >= minimumWidth && size.height >= minimumHeight
  }
}

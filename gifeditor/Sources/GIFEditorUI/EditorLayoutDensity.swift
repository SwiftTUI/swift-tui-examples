/// How much vertical room the editor has, and therefore how much of it the
/// chrome is allowed to spend.
///
/// The editor's regions do not compete for height the way the body row's
/// columns compete for width: the menu bar, the options bar, the timeline and
/// the status strip each want a fixed number of rows, and whatever is left
/// over is the canvas. So a terminal too short for the sum is not a layout the
/// stack can solve by squeezing — every region simply keeps its rows and the
/// bottom of the editor falls off the screen. That is precisely what used to
/// happen at 80×24, where a 28-row editor was presented into a 24-row
/// terminal and nothing clipped it.
///
/// This is the seam that fixes it. Each case is a whole set of choices about
/// what the chrome may cost, and ``EditorLayoutFloor/density(for:)`` picks
/// between them from the terminal's own height. The properties below are the
/// compression ladder in the order things give way — read top to bottom, they
/// are the answer to "what goes first".
///
/// 1. **Rules that repeat a boundary something else already draws.** The
///    inspector's sub-panels are named by their headings and the status strip
///    is under the timeline's own bottom border, so those three rules cost
///    three rows and carry nothing. Nothing is lost.
/// 2. **The options bar's box.** The bar keeps every control; it loses the
///    two rows of border around them. Nothing is lost.
/// 3. **The timeline's pictures.** Every frame and every control stays; the
///    thumbnails go from 6×6 to 4×4, which is one row of half-blocks.
/// 4. **The palette's second half.** 16 quick-pick swatches instead of 32.
///    Slots 1–9 — the ones that print their own keyboard shortcut — are all
///    in the first two rows, and every other slot is still reachable with the
///    eyedropper and in the palette editor.
/// 5. **The tool dock's column count.** Every tool stays; the dock spends two
///    columns of width to give back five rows of height, and the primary and
///    secondary swatches sit side by side instead of stacked.
/// 6. **The canvas** — last, and only in the sense that it is what all of the
///    above is *for*: it is the one region with no fixed height, so every row
///    the chrome gives up lands there.
///
/// The layer list is not on the ladder because it is not a compression: it is
/// a *bound*. A list that grows with the document would make the editor's
/// minimum height a property of the file rather than of the layout, so at both
/// densities it shows a window around the selected layer and counts the rest
/// in its heading.
enum EditorLayoutDensity: Sendable, CaseIterable {
  /// Every region at full height: a boxed options bar, rules between the
  /// inspector's sub-panels, a 32-slot palette grid, one column of tools.
  case regular

  /// What the editor falls back to when the terminal is shorter than the
  /// regular layout's own minimum — which, at the 24 rows a default terminal
  /// opens at, it always is.
  case compact

  /// Whether to draw the rules that only restate a boundary a heading or a
  /// border already draws. Step 1 of the ladder.
  var drawsRedundantRules: Bool { self == .regular }

  /// Whether the tool-options bar wears its box. Step 2.
  var boxesToolOptionsBar: Bool { self == .regular }

  /// The side, in source pixels, of a timeline thumbnail. Halved rows: a 6×6
  /// thumbnail is three rows of half-blocks, a 4×4 is two. Step 3.
  var timelineThumbnailSide: Int {
    switch self {
    case .regular: 6
    case .compact: 4
    }
  }

  /// Rows of the palette quick-pick grid, eight swatches to a row. Step 4.
  var paletteRows: Int {
    switch self {
    case .regular: 4
    case .compact: 2
    }
  }

  /// Columns of tool icons in the dock. Step 5.
  var toolDockColumns: Int {
    switch self {
    case .regular: 1
    case .compact: 2
    }
  }

  /// The dock's width, which is the price of ``toolDockColumns``.
  ///
  /// A `.plain` `Button` is two cells wide — the focus-rail gutter the
  /// framework reserves, plus the icon — and the dock adds a cell of slack on
  /// each side so an icon sits visually centred whether or not it is the
  /// active tool.
  var toolDockWidth: Int { 2 * toolDockColumns + 2 }

  /// Layer rows the inspector shows at once.
  ///
  /// A budget decision rather than a measurement, and the only number here
  /// that is: three is what the compact inspector's rows leave once the color
  /// readout, the palette grid, the heading and the new-layer footer are
  /// paid for, and six is a deeper stack than a frame of pixel art usually
  /// has, on a layout that only ever appears in a terminal tall enough to
  /// afford it. Both are *verified* rather than trusted —
  /// `EditorLayoutFloorTests` measures what the inspector actually costs at
  /// each density and fails if these stop adding up.
  var visibleLayerRows: Int {
    switch self {
    case .regular: 6
    case .compact: 3
    }
  }

  /// Whether the color readout wears its own heading. Its two rows are
  /// already labelled `P` and `S`, so in compact the heading is a row spent
  /// on a word the rows underneath it already say.
  var showsColorPanelHeading: Bool { self == .regular }
}

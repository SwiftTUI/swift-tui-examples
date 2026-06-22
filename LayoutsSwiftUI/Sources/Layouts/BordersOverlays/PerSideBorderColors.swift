import SwiftUI

/// A single bordered box with each of the four sides painted a
/// different color.
///
/// SwiftUI port: the original used SwiftTUI's
/// `BorderEdgeStyle(top:right:bottom:left:)` plus a `.heavy` border
/// set — neither has a one-liner SwiftUI equivalent. This port
/// reaches the divergence by stacking four `.overlay` rectangles, one
/// per edge, each a single-cell-thick stroke (`cell(1)`) so the result
/// reads as a four-color *border frame* — not filled quadrant bands.
/// That matches SwiftTUI's one-cell `.heavy` ring: readers comparing
/// rasters should expect SwiftUI to paint thin colored strokes rather
/// than `━ ┃ ┏ ┓ ┗ ┛` glyphs. (The padding stays `cell(2)`; only the
/// stroke thickness is one cell.)
public struct PerSideBorderColors: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: cell(1)) {
      Text("Per-side border colors").foregroundStyle(.secondary)
      Text("X")
        .padding(cell(2))
        .overlay(alignment: .top) {
          Rectangle().fill(Color.red).frame(height: cell(1))
        }
        .overlay(alignment: .trailing) {
          Rectangle().fill(Color.yellow).frame(width: cell(1))
        }
        .overlay(alignment: .bottom) {
          Rectangle().fill(Color.green).frame(height: cell(1))
        }
        .overlay(alignment: .leading) {
          Rectangle().fill(Color.blue).frame(width: cell(1))
        }
    }
    .padding(cell(1))
  }
}

import SwiftTUI
import Testing

@testable import Layouts

/// A/B variant: the same wrap algorithm as ``FlowLayout`` (every call
/// forwards to it) but without the horizontal `layoutProperties`
/// declaration.  Its children therefore inherit whichever stack
/// encloses the flow — here the fixture's `VStack` — so a `Divider`
/// child measures as a full-width horizontal rule and wraps onto its
/// own row.  This proves the single-row `[a]│[b]` raster of the
/// declared layout comes from the orientation declaration, not from
/// the wrap algorithm.
private struct UndeclaredFlowLayout: Layout {
  var spacing: Int

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) -> LayoutSize {
    FlowLayout(spacing: spacing).sizeThatFits(
      proposal: proposal, subviews: subviews, cache: &cache)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) {
    FlowLayout(spacing: spacing).placeSubviews(
      in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
  }
}

@MainActor
private struct FlowLayoutDividerProbe<Flow: Layout>: View {
  let flow: Flow

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Flow layout divider").foregroundStyle(.muted)
      flow {
        Text("[a]")
        Divider()
        Text("[b]")
      }
      .frame(width: 20)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct FlowLayoutOrientationBehaviourTests {
  /// ``FlowLayout`` declares `stackOrientation = .horizontal`
  /// (org T8, the custom `Layout` container contract shipped in
  /// swift-tui 0.10.0).  A `Divider` directly inside the flow then
  /// takes the row axis exactly as it would inside an `HStack`: it
  /// measures one cell wide and draws as a vertical rule between its
  /// neighbours, so `[a]`, the rule, and `[b]` share one row.
  ///
  /// Observed raster (excerpt) at 40×8:
  ///
  /// ```
  /// Flow layout divider
  /// [a] │ [b]
  /// ```
  @Test("a Divider inside the declared FlowLayout follows the row")
  func dividerFollowsTheDeclaredRow() throws {
    let raster = render(
      FlowLayoutDividerProbe(flow: FlowLayout(spacing: 1)),
      width: 40,
      height: 8
    ).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    let aRow = try #require(raster.firstRow(containing: "[a]"), "missing [a]\n\(joined)")
    let bRow = try #require(raster.firstRow(containing: "[b]"), "missing [b]\n\(joined)")
    #expect(aRow == bRow, "expected [a] and [b] on one row; got \(aRow) vs \(bRow)\n\(joined)")

    let line = try #require(raster.row(at: aRow), "\(joined)")
    let aColumn = try #require(column(of: "[a]", in: line), "\(joined)")
    let bColumn = try #require(column(of: "[b]", in: line), "\(joined)")
    let between = line.dropFirst(aColumn + 3).prefix(bColumn - aColumn - 3)
    #expect(
      between.contains("│"),
      "expected a vertical rule between [a] and [b]; got '\(between)'\n\(joined)"
    )
    #expect(
      !raster.lines.contains { $0.contains("──") },
      "expected no horizontal rule anywhere in the flow\n\(joined)"
    )
  }

  /// A/B vacuity: dropping the declaration makes the divider inherit
  /// the enclosing `VStack`'s column axis.  It then measures as a
  /// 20-cell horizontal rule, which the wrap algorithm pushes onto
  /// its own row between `[a]` and `[b]`.
  @Test("without the declaration the divider inherits the column and wraps")
  func undeclaredFlowInheritsTheEnclosingColumn() throws {
    let raster = render(
      FlowLayoutDividerProbe(flow: UndeclaredFlowLayout(spacing: 1)),
      width: 40,
      height: 8,
      id: "undeclared"
    ).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    let aRow = try #require(raster.firstRow(containing: "[a]"), "missing [a]\n\(joined)")
    let bRow = try #require(raster.firstRow(containing: "[b]"), "missing [b]\n\(joined)")
    #expect(aRow < bRow, "expected [a] above [b]; got \(aRow) vs \(bRow)\n\(joined)")

    let ruleRows = raster.lines.enumerated().filter { $0.element.contains("──") }.map(\.offset)
    #expect(
      ruleRows.contains { $0 > aRow && $0 < bRow },
      "expected a horizontal rule row between [a] and [b]\n\(joined)"
    )
  }
}

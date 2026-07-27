public import SwiftTUI

public struct MillerLayout: Layout, Sendable {
  public static let preferredColumnWidth = 30
  public static let browserMinimumWidth = 22
  public static let previewMinimumWidth = 40
  public static let separatorWidth = 1

  public init() {}

  public static func columnWidths(
    totalWidth: Int,
    columnCount: Int
  ) -> [Int] {
    guard columnCount > 0 else {
      return []
    }
    guard totalWidth > 0 else {
      return Array(repeating: 0, count: columnCount)
    }
    guard columnCount > 1 else {
      return [totalWidth]
    }

    let browserCount = columnCount - 1
    let minimumBrowserAllocation = browserMinimumWidth + separatorWidth
    let availableBrowserWidth = totalWidth - previewMinimumWidth
    let browserWidth = min(
      preferredColumnWidth,
      availableBrowserWidth / browserCount
    )
    if browserWidth >= minimumBrowserAllocation {
      let browserWidths = Array(repeating: browserWidth, count: browserCount)
      return browserWidths
        + [totalWidth - browserWidths.reduce(0, +)]
    }

    // This shape is unreachable through BrowserLayoutPolicy's breakpoints,
    // but a fair fallback keeps the Layout total-preserving for arbitrary
    // direct composition.
    let fairWidth = totalWidth / columnCount
    let leading = Array(repeating: fairWidth, count: columnCount - 1)
    return leading + [totalWidth - leading.reduce(0, +)]
  }

  public func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    guard !subviews.isEmpty else {
      return .zero
    }

    let width = finiteDimension(proposal.width) ?? intrinsicWidth(for: subviews)
    let widths = Self.columnWidths(totalWidth: width, columnCount: subviews.count)
    let height = finiteDimension(proposal.height) ?? intrinsicHeight(for: subviews, widths: widths)
    return .init(width: width, height: height)
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    let widths = Self.columnWidths(totalWidth: bounds.size.width, columnCount: subviews.count)
    var x = bounds.origin.x

    for (index, subview) in subviews.enumerated() {
      let width = widths[index]
      subview.place(
        at: .init(x: x, y: bounds.origin.y),
        anchor: .topLeading,
        proposal: .init(width: width, height: bounds.size.height)
      )
      x += width
    }
  }

  private func intrinsicWidth(for subviews: LayoutSubviews) -> Int {
    subviews
      .map { $0.sizeThatFits(.unspecified).width }
      .reduce(0, +)
  }

  private func intrinsicHeight(
    for subviews: LayoutSubviews,
    widths: [Int]
  ) -> Int {
    zip(subviews, widths)
      .map { subview, width in
        subview.sizeThatFits(.init(width: width, height: nil)).height
      }
      .max() ?? 0
  }

  private func finiteDimension(_ dimension: ProposedDimension) -> Int? {
    switch dimension {
    case .finite(let value):
      return max(0, value)
    case .infinity, .unspecified:
      return nil
    }
  }
}

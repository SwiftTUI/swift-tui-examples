import SwiftTUI
import Synchronization

struct MarkdownTableView: View {
  var table: MarkdownTable
  var theme: ViewerTheme
  var searchQuery: String?
  var offeredWidth: Int
  var tableTop: Int?
  var documentScrollOffset: Int
  var viewportHeight: Int
  var horizontalScrollPosition: Binding<ScrollCellOffset>?
  // Supplied by the document tree so metrics come from the model-owned
  // identity-keyed cache; standalone constructions compute directly.
  var metricsProvider: ((MarkdownTable) -> MarkdownTableLayoutMetrics)? = nil
  @State private var internalHorizontalScrollPosition = ScrollCellOffset.zero

  var body: some View {
    let metrics = metricsProvider?(table) ?? MarkdownTableLayout.metrics(for: table)
    let visibleSlice = MarkdownTableLayout.visibleSlice(
      metrics,
      tableTop: tableTop ?? documentScrollOffset,
      documentScrollOffset: documentScrollOffset,
      viewportHeight: viewportHeight
    )
    let position = horizontalScrollPosition ?? $internalHorizontalScrollPosition
    let visibleColumns = MarkdownTableLayout.visibleColumns(
      metrics,
      horizontalOffset: position.wrappedValue.x,
      viewportWidth: offeredWidth
    )
    ScrollView(
      .horizontal,
      position: position
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Spacer(minLength: visibleSlice.topSpacerHeight)
          .frame(height: visibleSlice.topSpacerHeight)
        ForEach(Array(visibleSlice.rows.enumerated()), id: \.offset) { _, rowIndex in
          if rowIndex == 0 {
            tableRow(
              table.header,
              header: true,
              rowHeight: metrics.headerRowHeight,
              metrics: metrics,
              visibleColumns: visibleColumns
            )
          } else if rowIndex == 1 {
            Text(metrics.separator)
              .foregroundStyle(theme.tableBorder.swiftTUIColor)
          } else {
            let bodyRowIndex = rowIndex - 2
            tableRow(
              table.rows[bodyRowIndex],
              header: false,
              rowHeight: metrics.bodyRowHeights[bodyRowIndex],
              metrics: metrics,
              visibleColumns: visibleColumns
            )
          }
        }
        Spacer(minLength: visibleSlice.bottomSpacerHeight)
          .frame(height: visibleSlice.bottomSpacerHeight)
      }
    }
    .frame(
      width: max(1, offeredWidth),
      alignment: .topLeading
    )
  }

  private func tableRow(
    _ cells: [[InlineRun]],
    header: Bool,
    rowHeight: Int,
    metrics: MarkdownTableLayoutMetrics,
    visibleColumns: MarkdownTableVisibleColumnSlice
  ) -> some View {
    HStack(spacing: 0) {
      Spacer(minLength: visibleColumns.leadingSpacerWidth)
        .frame(width: visibleColumns.leadingSpacerWidth)
      ForEach(Array(visibleColumns.columns.enumerated()), id: \.offset) { _, column in
        tableBorder(height: rowHeight)
        InlineTextView(
          runs: cells.indices.contains(column) ? cells[column] : [],
          theme: theme,
          bold: header,
          searchQuery: searchQuery
        )
        .frame(width: metrics.columnWidths[column], alignment: alignment(for: column))
        .padding(.init(horizontal: 1, vertical: 0))
      }
      if visibleColumns.columns.upperBound == metrics.columnWidths.count {
        tableBorder(height: rowHeight)
      }
      Spacer(minLength: visibleColumns.trailingSpacerWidth)
        .frame(width: visibleColumns.trailingSpacerWidth)
    }
  }

  private func tableBorder(height: Int) -> some View {
    Text(
      Array(repeating: "│", count: max(1, height))
        .joined(separator: "\n")
    )
    .foregroundStyle(theme.tableBorder.swiftTUIColor)
  }

  private func alignment(for column: Int) -> Alignment {
    guard table.alignments.indices.contains(column) else { return .leading }
    return switch table.alignments[column] {
    case .leading, .unspecified: Alignment.leading
    case .center: Alignment.center
    case .trailing: Alignment.trailing
    }
  }
}

struct MarkdownTableLayoutMetrics: Equatable, Sendable {
  var columnWidths: [Int]
  var separator: String
  var headerRowHeight: Int
  var bodyRowHeights: [Int]
  var rowOffsets: [Int]
  var columnOffsets: [Int]

  var totalHeight: Int {
    rowOffsets.last ?? 0
  }

  var totalWidth: Int {
    (columnOffsets.last ?? 0) + (columnWidths.isEmpty ? 0 : 1)
  }
}

struct MarkdownTableVisibleSlice: Equatable, Sendable {
  var rows: Range<Int>
  var topSpacerHeight: Int
  var bottomSpacerHeight: Int

  func renderedHeight(in metrics: MarkdownTableLayoutMetrics) -> Int {
    guard
      metrics.rowOffsets.indices.contains(rows.lowerBound),
      metrics.rowOffsets.indices.contains(rows.upperBound)
    else {
      return 0
    }
    return metrics.rowOffsets[rows.upperBound] - metrics.rowOffsets[rows.lowerBound]
  }
}

struct MarkdownTableVisibleColumnSlice: Equatable, Sendable {
  var columns: Range<Int>
  var leadingSpacerWidth: Int
  var trailingSpacerWidth: Int
}

enum MarkdownTableLayout {
  private static let viewportOverscan = 2
  private static let columnOverscan = 1

  /// The uncached pure computation. Metrics are width-independent — column
  /// widths derive from cell content clamped to [3, 32] — which is why the
  /// cache key carries no viewport bucket.
  static func metrics(for table: MarkdownTable) -> MarkdownTableLayoutMetrics {
    computeMetrics(for: table)
  }

  fileprivate static func computeMetrics(
    for table: MarkdownTable
  ) -> MarkdownTableLayoutMetrics {
    let allRows = [table.header] + table.rows
    let columnCount = allRows.map(\.count).max() ?? 0
    let columnWidths = (0..<columnCount).map { column in
      let intrinsic =
        allRows.compactMap { row -> Int? in
          guard row.indices.contains(column) else { return nil }
          return terminalDisplayWidth(of: row[column].map(\.text).joined())
        }.max() ?? 1
      return min(max(intrinsic, 3), 32)
    }
    let separator =
      columnWidths.isEmpty
      ? ""
      : "├"
        + columnWidths
        .map { String(repeating: "─", count: $0 + 2) }
        .joined(separator: "┼")
        + "┤"
    let headerRowHeight = rowHeight(
      table.header,
      columnWidths: columnWidths
    )
    let bodyRowHeights = table.rows.map {
      rowHeight($0, columnWidths: columnWidths)
    }
    let rowOffsets =
      ([headerRowHeight, 1] + bodyRowHeights)
      .reduce(into: [0]) { offsets, height in
        offsets.append(offsets[offsets.count - 1] + height)
      }
    let columnOffsets =
      columnWidths.reduce(into: [0]) { offsets, width in
        offsets.append(offsets[offsets.count - 1] + width + 3)
      }
    return MarkdownTableLayoutMetrics(
      columnWidths: columnWidths,
      separator: separator,
      headerRowHeight: headerRowHeight,
      bodyRowHeights: bodyRowHeights,
      rowOffsets: rowOffsets,
      columnOffsets: columnOffsets
    )
  }

  private static func rowHeight(
    _ cells: [[InlineRun]],
    columnWidths: [Int]
  ) -> Int {
    max(
      1,
      columnWidths.enumerated().map { column, width in
        let source =
          cells.indices.contains(column)
          ? cells[column].map(\.text).joined()
          : ""
        return layoutText(for: source, width: width).size.height
      }.max() ?? 1
    )
  }

  static func visibleSlice(
    _ metrics: MarkdownTableLayoutMetrics,
    tableTop: Int,
    documentScrollOffset: Int,
    viewportHeight: Int,
    overscan: Int = viewportOverscan
  ) -> MarkdownTableVisibleSlice {
    let localViewportTop = documentScrollOffset - tableTop
    let expandedTop = localViewportTop - max(0, overscan)
    let expandedBottom =
      localViewportTop + max(1, viewportHeight) + max(0, overscan)
    let visibleTop = max(0, expandedTop)
    let visibleBottom = min(metrics.totalHeight, expandedBottom)

    guard visibleTop < visibleBottom, metrics.rowOffsets.count >= 2 else {
      return MarkdownTableVisibleSlice(
        rows: 0..<0,
        topSpacerHeight: expandedBottom <= 0 ? 0 : metrics.totalHeight,
        bottomSpacerHeight: expandedBottom <= 0 ? metrics.totalHeight : 0
      )
    }

    let firstRow = firstRowEnding(after: visibleTop, in: metrics.rowOffsets)
    let endRow = firstRowStarting(atOrAfter: visibleBottom, in: metrics.rowOffsets)
    return MarkdownTableVisibleSlice(
      rows: firstRow..<endRow,
      topSpacerHeight: metrics.rowOffsets[firstRow],
      bottomSpacerHeight: metrics.totalHeight - metrics.rowOffsets[endRow]
    )
  }

  static func visibleColumns(
    _ metrics: MarkdownTableLayoutMetrics,
    horizontalOffset: Int,
    viewportWidth: Int,
    overscan: Int = columnOverscan
  ) -> MarkdownTableVisibleColumnSlice {
    guard !metrics.columnWidths.isEmpty, metrics.columnOffsets.count >= 2 else {
      return MarkdownTableVisibleColumnSlice(
        columns: 0..<0,
        leadingSpacerWidth: 0,
        trailingSpacerWidth: 0
      )
    }

    let visibleLeft = min(
      max(0, horizontalOffset),
      max(0, metrics.totalWidth - 1)
    )
    let visibleRight = min(
      metrics.totalWidth,
      visibleLeft + max(1, viewportWidth)
    )
    let intersectingFirst = firstRowEnding(
      after: visibleLeft,
      in: metrics.columnOffsets
    )
    let intersectingEnd = firstRowStarting(
      atOrAfter: visibleRight,
      in: metrics.columnOffsets
    )
    let firstColumn = max(0, intersectingFirst - max(0, overscan))
    let endColumn = min(
      metrics.columnWidths.count,
      intersectingEnd + max(0, overscan)
    )
    return MarkdownTableVisibleColumnSlice(
      columns: firstColumn..<endColumn,
      leadingSpacerWidth: metrics.columnOffsets[firstColumn],
      trailingSpacerWidth:
        endColumn == metrics.columnWidths.count
        ? 0
        : metrics.totalWidth - metrics.columnOffsets[endColumn]
    )
  }

  private static func firstRowEnding(
    after offset: Int,
    in rowOffsets: [Int]
  ) -> Int {
    var lowerBound = 1
    var upperBound = rowOffsets.count
    while lowerBound < upperBound {
      let middle = lowerBound + (upperBound - lowerBound) / 2
      if rowOffsets[middle] <= offset {
        lowerBound = middle + 1
      } else {
        upperBound = middle
      }
    }
    return min(rowOffsets.count - 2, lowerBound - 1)
  }

  private static func firstRowStarting(
    atOrAfter offset: Int,
    in rowOffsets: [Int]
  ) -> Int {
    var lowerBound = 0
    var upperBound = rowOffsets.count - 1
    while lowerBound < upperBound {
      let middle = lowerBound + (upperBound - lowerBound) / 2
      if rowOffsets[middle] < offset {
        lowerBound = middle + 1
      } else {
        upperBound = middle
      }
    }
    return lowerBound
  }
}

final class MarkdownTableLayoutCache: Sendable {
  struct Statistics: Equatable, Sendable {
    var entryCount: Int
    var computationCount: Int
    var hitCount: Int
    var evictionCount: Int
  }

  private struct Key: Equatable, Hashable, Sendable {
    var blockID: BlockID
    var contentRevision: UInt64
  }

  private struct Entry: Sendable {
    var metrics: MarkdownTableLayoutMetrics
    var lastUse: UInt64
  }

  private struct State: Sendable {
    var entries: [Key: Entry] = [:]
    var useCounter: UInt64 = 0
    var computationCount = 0
    var hitCount = 0
    var evictionCount = 0
  }

  private let capacity: Int
  private let state = Mutex(State())

  init(capacity: Int = 16) {
    self.capacity = max(1, capacity)
  }

  var statistics: Statistics {
    state.withLock { state in
      Statistics(
        entryCount: state.entries.count,
        computationCount: state.computationCount,
        hitCount: state.hitCount,
        evictionCount: state.evictionCount
      )
    }
  }

  func metrics(
    for table: MarkdownTable,
    identity: BlockID,
    contentRevision: UInt64
  ) -> MarkdownTableLayoutMetrics {
    let key = Key(blockID: identity, contentRevision: contentRevision)
    return state.withLock { state in
      state.useCounter &+= 1
      if var cached = state.entries[key] {
        state.hitCount += 1
        cached.lastUse = state.useCounter
        state.entries[key] = cached
        return cached.metrics
      }

      let metrics = MarkdownTableLayout.metrics(for: table)
      state.computationCount += 1
      if state.entries.count == capacity,
        let evicted = state.entries.min(by: { $0.value.lastUse < $1.value.lastUse })?.key
      {
        state.entries.removeValue(forKey: evicted)
        state.evictionCount += 1
      }
      state.entries[key] = Entry(metrics: metrics, lastUse: state.useCounter)
      return metrics
    }
  }
}

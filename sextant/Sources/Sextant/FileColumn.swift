import Foundation
import SwiftTUI

enum FileColumnWindowPolicy {
  static let minimumAuthoredRows = 48
  static let viewportOverscanRows = 8

  static func authoredRange(
    entryCount: Int,
    viewportTop: Int,
    viewportHeight: Int = 0
  ) -> Range<Int> {
    let authoredRowCount = min(
      entryCount,
      max(
        minimumAuthoredRows,
        max(0, viewportHeight) + viewportOverscanRows
      )
    )
    guard entryCount > authoredRowCount else {
      return 0..<max(0, entryCount)
    }
    let clampedViewportTop = min(max(0, viewportTop), entryCount - 1)
    let maximumLowerBound = entryCount - authoredRowCount
    let lowerBound = min(
      clampedViewportTop,
      maximumLowerBound
    )
    return lowerBound..<(lowerBound + authoredRowCount)
  }

  static func selectionIndex(
    entries: [BrowserItem],
    selection: BrowserItemID?
  ) -> Int? {
    guard let selection else {
      return nil
    }
    return entries.firstIndex(where: { $0.id == selection })
  }
}

struct FileColumn: View {
  var directory: URL
  var entries: [BrowserItem]
  var selection: BrowserItemID?
  var isActive: Bool
  var isLoading: Bool = false
  var emptyLabel: String = "(empty)"
  var accentStyle: AnyShapeStyle = AnyShapeStyle(SemanticShapeStyle(.tint))
  var mutedStyle: AnyShapeStyle = AnyShapeStyle(SemanticShapeStyle(.muted))
  /// Cells this column occupies, used to size the accent bars. `MillerLayout`
  /// already computes this statically, so it is passed in rather than measured
  /// through a `GeometryReader` — a layout-realized boundary around the column
  /// body cost ~10 ms of the interaction budget at 10,000 entries.
  var contentWidth: Int = 0
  var onSelect: (BrowserItemID) -> Void = { _ in }

  @State private var scrollPosition = ScrollCellOffset.zero

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      columnTitle(
        directory.lastPathComponent.isEmpty
          ? directory.path
          : directory.lastPathComponent
      )
      Divider()

      if entries.isEmpty {
        Text(isLoading ? "(loading)" : emptyLabel)
          .foregroundStyle(.separator)
      } else {
        GeometryReader { proxy in
          let window = authoredEntryWindow(
            viewportHeight: proxy.size.height
          )
          ScrollView(
            .vertical,
            position: $scrollPosition
          ) {
            LazyVStack(alignment: .leading, spacing: 0) {
              if window.lowerBound > 0 {
                Spacer().frame(height: window.lowerBound)
              }
              ForEach(window.entries) { entry in
                row(for: entry)
              }
              if window.upperBound < entries.count {
                Spacer().frame(height: entries.count - window.upperBound)
              }
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onChange(of: selectedEntryIndex, initial: true) { _, index in
      scrollPosition = ScrollCellOffset(y: max(0, (index ?? 0) - 1))
    }
  }

  /// The directory name above the column.
  ///
  /// Deliberately plain: the active column is already marked by its barred
  /// selection and by the breadcrumb, so a second full-width bar up here only
  /// competed with it. The accent foreground still says which column is
  /// active without painting a block of background across the title.
  private func columnTitle(_ label: String) -> some View {
    Text(label)
      .foregroundStyle(isActive ? accentStyle : mutedStyle)
      .lineLimit(1)
      .truncationMode(.middle)
  }

  /// A full-width accent bar drawn as one `Text` node.
  ///
  /// The obvious spelling — `.frame(maxWidth: .infinity)` then
  /// `.background { Rectangle() }` — is what the framework's own controls use,
  /// but that decoration measured ~4.5 ms into this column's 50 ms interaction
  /// budget at 10,000 entries. Padding the string to the column width and
  /// letting the terminal swap foreground and background paints the same bar
  /// with no extra layout node at all, and gets the contrast from the
  /// terminal's real colors rather than a guessed pairing. Only the active
  /// column's selected row is barred, so at most one row per column pays the
  /// padding.
  private func accentBar(
    _ label: String,
    isHighlighted: Bool,
    idleStyle: AnyShapeStyle
  ) -> some View {
    Text(isHighlighted ? padded(label, to: contentWidth) : label)
      .foregroundStyle(isHighlighted ? accentStyle : idleStyle)
      .reverse(isHighlighted)
      .lineLimit(1)
      .truncationMode(.middle)
  }

  /// Right-pads to `width` so a reversed run covers the whole column. Measured
  /// in characters, so a name built from wide glyphs pads a cell short.
  private func padded(_ label: String, to width: Int) -> String {
    let deficit = width - label.count
    guard deficit > 0 else {
      return label
    }
    return label + String(repeating: " ", count: deficit)
  }

  /// One entry row.
  ///
  /// `FileColumn` authors up to 48 rows at once and `FileColumnRenderingTests`
  /// holds the whole column under 80 resolved nodes, so every row has to stay
  /// a single `Text`. Ordinary entries read in the primary foreground — these
  /// are the content, not chrome, so dimming them to the separator tone made
  /// the whole browser look disabled. Only the active column's selection is
  /// barred; the trail column's selection, which is the directory you came out
  /// of, keeps the accent foreground so it stays legible as a marker without a
  /// second bar on screen.
  private func row(for entry: BrowserItem) -> some View {
    let label = entry.name + (entry.kind.isDirectoryLike ? "/" : "")
    let isSelected = entry.id == selection
    return accentBar(
      label,
      isHighlighted: isActive && isSelected,
      idleStyle: isSelected
        ? accentStyle
        : AnyShapeStyle(SemanticShapeStyle(.foreground))
    )
    .onTapGesture {
      onSelect(entry.id)
    }
  }

  private var selectedEntryIndex: Int? {
    FileColumnWindowPolicy.selectionIndex(
      entries: entries,
      selection: selection
    )
  }

  private func authoredEntryWindow(
    viewportHeight: Int
  ) -> (
    lowerBound: Int,
    upperBound: Int,
    entries: ArraySlice<BrowserItem>
  ) {
    let range = FileColumnWindowPolicy.authoredRange(
      entryCount: entries.count,
      viewportTop: scrollPosition.y,
      viewportHeight: viewportHeight
    )
    return (
      range.lowerBound,
      range.upperBound,
      entries[range]
    )
  }
}

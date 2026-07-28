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

  @State private var scrollPosition = ScrollPosition.zero

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      accentBar(
        directory.lastPathComponent.isEmpty
          ? directory.path
          : directory.lastPathComponent,
        isHighlighted: isActive,
        idleStyle: mutedStyle
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
            showsIndicators: true,
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
      scrollPosition = ScrollPosition(y: max(0, (index ?? 0) - 1))
    }
  }

  /// A full-width accent bar drawn as one `Text` node.
  ///
  /// The obvious spelling — `.frame(maxWidth: .infinity)` then
  /// `.background { Rectangle() }` — is what the framework's own controls use,
  /// but each decoration measured ~4.5 ms into this column's 50 ms interaction
  /// budget at 10,000 entries, and there are two of them. Padding the string to
  /// the column width and letting the terminal swap foreground and background
  /// paints the same bar with no extra layout node at all, and gets the
  /// contrast from the terminal's real colors rather than a guessed pairing.
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
  /// a single `Text`. Only the active column's selection is barred; a
  /// selection in a column you have navigated out of stays a plain
  /// foreground/separator contrast.
  private func row(for entry: BrowserItem) -> some View {
    let label = entry.name + (entry.kind.isDirectoryLike ? "/" : "")
    let isSelected = entry.id == selection
    return accentBar(
      label,
      isHighlighted: isActive && isSelected,
      idleStyle: isSelected
        ? AnyShapeStyle(SemanticShapeStyle(.foreground))
        : AnyShapeStyle(SemanticShapeStyle(.separator))
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

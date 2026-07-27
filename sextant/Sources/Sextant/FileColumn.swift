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
  var onSelect: (BrowserItemID) -> Void = { _ in }

  @State private var scrollPosition = ScrollPosition.zero

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(directory.lastPathComponent.isEmpty ? directory.path : directory.lastPathComponent)
        .foregroundStyle(isActive ? .tint : .muted)
        .lineLimit(1)
        .truncationMode(.middle)
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

  private func row(for entry: BrowserItem) -> some View {
    Text(entry.name + (entry.kind.isDirectoryLike ? "/" : ""))
      .foregroundStyle(entry.id == selection ? .foreground : .separator)
      .lineLimit(1)
      .truncationMode(.middle)
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

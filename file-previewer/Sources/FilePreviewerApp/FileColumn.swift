import Foundation
import SwiftTUI

struct FileColumn: View {
  var directory: URL
  var entries: [FileEntry]
  var selection: URL?
  var isActive: Bool
  var isLoading: Bool = false

  @State private var scrollPosition = ScrollPosition.zero

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(directory.lastPathComponent.isEmpty ? directory.path : directory.lastPathComponent)
        .foregroundStyle(isActive ? .tint : .muted)
        .lineLimit(1)
        .truncationMode(.middle)
      Divider()

      if entries.isEmpty {
        Text(isLoading ? "(loading)" : "(empty)")
          .foregroundStyle(.separator)
      } else {
        ScrollView(
          .vertical,
          showsIndicators: true,
          position: $scrollPosition
        ) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(entries, id: \.url) { entry in
              row(for: entry)
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .border(isActive ? .tint : .separator)
    .onChange(of: selection, initial: true) { _, selected in
      keepSelectionVisible(selected)
    }
  }

  private func row(for entry: FileEntry) -> some View {
    HStack(spacing: 1) {
      Text(entry.url == selection ? ">" : " ")
        .foregroundStyle(.tint)
      Text(entry.displayName)
        .foregroundStyle(entry.url == selection ? .foreground : .separator)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  private func keepSelectionVisible(_ selected: URL?) {
    guard let selected,
      let index = entries.firstIndex(where: { $0.url == selected })
    else {
      scrollPosition = .zero
      return
    }
    scrollPosition = ScrollPosition(y: max(0, index - 1))
  }
}

import Foundation
import SwiftTUI

struct MarkdownBlockView: View {
  var block: MarkdownBlock
  var state: ViewerState
  var offeredWidth: Int
  var documentGeometryTop: (BlockID) -> Int?
  var resourceVisibilityChanged: (BlockID, Bool) -> Void
  // Leaf-time readers for the model properties that live outside `state`
  // (scroll offset, resource presentations): calling them inside this view's
  // body scopes the observation dependency to the block that reads them.
  var documentScrollOffset: () -> Int
  var imagePresentation: (BlockID) -> ImagePresentation?
  var tableMetrics: (BlockID, MarkdownTable) -> MarkdownTableLayoutMetrics

  var body: some View {
    rendered
      .id(block.id)
      .background(
        isSelectedSearchBlock
          ? state.theme.selectionBackground.swiftTUIColor
          : Color.clear
      )
      .onAppear {
        guard isAsynchronousResource else { return }
        resourceVisibilityChanged(block.id, true)
      }
      .onDisappear {
        guard isAsynchronousResource else { return }
        resourceVisibilityChanged(block.id, false)
      }
  }

  private var isAsynchronousResource: Bool {
    if case .image = block { return true }
    return false
  }

  private var isSelectedSearchBlock: Bool {
    guard let selected = state.selectedSearchMatch,
      state.searchMatches.indices.contains(selected)
    else {
      return false
    }
    return state.searchMatches[selected].blockID == block.id
  }

  private var rendered: AnyView {
    switch block {
    case .heading(_, let level, _, let content, _):
      return AnyView(
        VStack(alignment: .leading, spacing: 0) {
          InlineTextView(
            runs: content,
            theme: state.theme,
            baseColor: state.theme.headingColor(level: level),
            bold: level <= 3,
            searchQuery: state.searchQuery
          )
          if level <= 2 {
            Divider()
              .foregroundStyle(state.theme.rule.swiftTUIColor)
          }
        }
        .accessibilityRole(.heading(level: level))
        .accessibilityLabel(content.map(\.text).joined())
      )
    case .paragraph(_, let content, _):
      return AnyView(
        InlineTextView(
          runs: content,
          theme: state.theme,
          searchQuery: state.searchQuery
        )
      )
    case .quote(_, let blocks, _):
      return AnyView(
        HStack(alignment: .top, spacing: 1) {
          Text("│").foregroundStyle(state.theme.quote.swiftTUIColor)
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(blocks, id: \.id) {
              MarkdownBlockView(
                block: $0,
                state: state,
                offeredWidth: MarkdownBlockLayout.quoteContentWidth(offeredWidth),
                documentGeometryTop: documentGeometryTop,
                resourceVisibilityChanged: resourceVisibilityChanged,
                documentScrollOffset: documentScrollOffset,
                imagePresentation: imagePresentation,
                tableMetrics: tableMetrics
              )
            }
          }
          .foregroundStyle(state.theme.quote.swiftTUIColor)
        }
      )
    case .list(_, let list, _):
      return AnyView(
        MarkdownListView(
          list: list,
          state: state,
          offeredWidth: offeredWidth,
          documentGeometryTop: documentGeometryTop,
          resourceVisibilityChanged: resourceVisibilityChanged,
          documentScrollOffset: documentScrollOffset,
          imagePresentation: imagePresentation,
          tableMetrics: tableMetrics
        )
      )
    case .code(_, let language, let source, _):
      return AnyView(
        VStack(alignment: .leading, spacing: 0) {
          if let language {
            Text(language)
              .foregroundStyle(state.theme.muted.swiftTUIColor)
          }
          ScrollView(.horizontal, showsIndicators: true) {
            Text(source)
              .foregroundStyle(state.theme.codeForeground.swiftTUIColor)
              .padding(.init(horizontal: 1, vertical: 0))
          }
          .background(state.theme.codeBackground.swiftTUIColor)
        }
      )
    case .table(let id, let table, _):
      return AnyView(
        MarkdownTableView(
          table: table,
          theme: state.theme,
          searchQuery: state.searchQuery,
          offeredWidth: offeredWidth,
          tableTop: documentGeometryTop(id).map { $0 + 1 },
          documentScrollOffset: documentScrollOffset(),
          viewportHeight: state.viewport.documentHeight,
          horizontalScrollPosition: nil,
          metricsProvider: { tableMetrics(id, $0) }
        )
      )
    case .rule:
      return AnyView(
        Divider().foregroundStyle(state.theme.rule.swiftTUIColor)
      )
    case .image(let id, let image, _):
      return AnyView(
        ImageBlockView(
          image: image,
          documentURL: state.snapshot.url,
          presentation: imagePresentation(id),
          theme: state.theme
        ))
    case .html(_, let source, _):
      return AnyView(
        Text(source)
          .foregroundStyle(state.theme.codeForeground.swiftTUIColor)
          .padding(.init(horizontal: 1, vertical: 0))
          .background(state.theme.codeBackground.swiftTUIColor)
      )
    case .unsupported(_, let kind, let source, _):
      return AnyView(
        VStack(alignment: .leading, spacing: 0) {
          Text(MarkdownBlockLayout.unsupportedLabel(kind))
            .foregroundStyle(state.theme.error.swiftTUIColor)
          Text(source).foregroundStyle(state.theme.muted.swiftTUIColor)
        }
      )
    }
  }
}

private struct MarkdownListView: View {
  var list: MarkdownList
  var state: ViewerState
  var offeredWidth: Int
  var documentGeometryTop: (BlockID) -> Int?
  var resourceVisibilityChanged: (BlockID, Bool) -> Void
  var documentScrollOffset: () -> Int
  var imagePresentation: (BlockID) -> ImagePresentation?
  var tableMetrics: (BlockID, MarkdownTable) -> MarkdownTableLayoutMetrics

  var body: some View {
    let contentWidth = MarkdownBlockLayout.listContentWidth(
      list,
      offeredWidth: offeredWidth
    )
    let markerWidth = MarkdownBlockLayout.listMarkerWidth(list)
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
        HStack(alignment: .top, spacing: 1) {
          Text(
            MarkdownBlockLayout.alignedListMarker(
              list,
              item: item,
              index: index,
              width: markerWidth
            )
          )
          .foregroundStyle(state.theme.muted.swiftTUIColor)
          .accessibilityLabel(accessibilityMarker(for: item, index: index))
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(item.blocks, id: \.id) {
              MarkdownBlockView(
                block: $0,
                state: state,
                offeredWidth: contentWidth,
                documentGeometryTop: documentGeometryTop,
                resourceVisibilityChanged: resourceVisibilityChanged,
                documentScrollOffset: documentScrollOffset,
                imagePresentation: imagePresentation,
                tableMetrics: tableMetrics
              )
            }
          }
        }
      }
    }
  }

  private func accessibilityMarker(for item: MarkdownListItem, index: Int) -> String {
    if let checked = item.checkbox {
      return checked ? "checked task" : "unchecked task"
    }
    return MarkdownBlockLayout.listMarker(list, item: item, index: index)
  }
}

struct ImageBlockView: View {
  var image: ImageReference
  var documentURL: URL?
  var presentation: ImagePresentation?
  var theme: ViewerTheme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      switch presentation {
      case .ready(let loaded)?:
        Image(data: Array(loaded.data))
          .resizable()
          .scaledToFit()
          .frame(maxWidth: 72, maxHeight: 24, alignment: .topLeading)
          .accessibilityLabel(accessibleDescription(url: loaded.url))
        metadata(url: loaded.url)
      case .loading(let resolvedURL)?:
        Text(MarkdownBlockLayout.imageStatusText(presentation) ?? "")
          .foregroundStyle(theme.muted.swiftTUIColor)
        metadata(url: resolvedURL)
      case .blocked(let resolvedURL, _)?:
        Text(MarkdownBlockLayout.imageStatusText(presentation) ?? "")
          .foregroundStyle(theme.muted.swiftTUIColor)
        metadata(url: resolvedURL)
      case .failed(let resolvedURL, _)?:
        Text(MarkdownBlockLayout.imageStatusText(presentation) ?? "")
          .foregroundStyle(theme.error.swiftTUIColor)
        metadata(url: resolvedURL)
      case .terminalFallback(let resolvedURL, _)?:
        Text(MarkdownBlockLayout.imageStatusText(presentation) ?? "")
          .foregroundStyle(theme.muted.swiftTUIColor)
        metadata(url: resolvedURL)
      case nil:
        metadata(url: resolvedURL)
      }
    }
  }

  private var resolvedURL: URL? {
    MarkdownBlockLayout.imageURL(
      image: image,
      documentURL: documentURL,
      presentation: presentation
    )
  }

  private func accessibleDescription(url: URL?) -> String {
    let alt = image.altText.isEmpty ? "image" : image.altText
    let title = image.title.map { ", \($0)" } ?? ""
    let destination = url.map { ", \($0.absoluteString)" } ?? ""
    return alt + title + destination
  }

  private func metadata(url: URL?) -> some View {
    Text(MarkdownBlockLayout.imageMetadataText(image: image, url: url))
      .foregroundStyle(theme.muted.swiftTUIColor)
      .accessibilityLabel(accessibleDescription(url: url))
  }
}

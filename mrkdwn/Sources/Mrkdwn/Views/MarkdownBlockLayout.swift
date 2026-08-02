import Foundation
import SwiftTUI

enum MarkdownBlockLayout {
  static let mermaidPendingText = "◇ Rendering Mermaid…"

  static func mermaidDiagnosticText(_ diagnostic: String) -> String {
    "Mermaid: \(diagnostic)"
  }

  static func mermaidUnavailableText(_ diagnostic: String) -> String {
    "Mermaid unavailable: \(diagnostic)"
  }

  static func imageStatusText(_ presentation: ImagePresentation?) -> String? {
    switch presentation {
    case .ready?, nil:
      return nil
    case .loading?:
      return "Image loading"
    case .blocked(_, let hint)?:
      return "Image blocked: \(hint)"
    case .failed(_, let diagnostic)?:
      return "Image unavailable: \(diagnostic)"
    case .terminalFallback(_, let diagnostic)?:
      return "Image attachment fallback: \(diagnostic)"
    }
  }

  static func imageURL(
    image: ImageReference,
    documentURL: URL?,
    presentation: ImagePresentation?
  ) -> URL? {
    switch presentation {
    case .ready(let loaded)?:
      return loaded.url
    case .loading(let resolvedURL)?,
      .blocked(let resolvedURL, _)?,
      .failed(let resolvedURL, _)?,
      .terminalFallback(let resolvedURL, _)?:
      return resolvedURL
    case nil:
      return try? ResourceLoader.resolveURL(image.source, relativeTo: documentURL)
    }
  }

  static func imageMetadataText(image: ImageReference, url: URL?) -> String {
    let alt = image.altText.isEmpty ? "(no alt text)" : image.altText
    let title = image.title.map { " — \($0)" } ?? ""
    let destination = url?.absoluteString ?? image.source
    return "Image: \(alt)\(title) · \(destination)"
  }

  static func unsupportedLabel(_ kind: String) -> String {
    "Unsupported Markdown: \(kind)"
  }

  struct Descriptor {
    var block: MarkdownBlock
    var offeredWidth: Int
  }

  static func flattened(
    _ blocks: [MarkdownBlock],
    offeredWidth: Int
  ) -> [Descriptor] {
    blocks.flatMap { block in
      let descriptor = Descriptor(
        block: block,
        offeredWidth: max(1, offeredWidth)
      )
      switch block {
      case .quote(_, let nested, _):
        return [descriptor]
          + flattened(
            nested,
            offeredWidth: quoteContentWidth(offeredWidth)
          )
      case .list(_, let list, _):
        let nestedWidth = listContentWidth(list, offeredWidth: offeredWidth)
        return [descriptor]
          + list.items.flatMap {
            flattened($0.blocks, offeredWidth: nestedWidth)
          }
      default:
        return [descriptor]
      }
    }
  }

  static func quoteContentWidth(_ offeredWidth: Int) -> Int {
    max(1, offeredWidth - 2)
  }

  static func listContentWidth(
    _ list: MarkdownList,
    offeredWidth: Int
  ) -> Int {
    max(1, offeredWidth - listIndentation(list))
  }

  static func listMarker(
    _ list: MarkdownList,
    item: MarkdownListItem,
    index: Int
  ) -> String {
    if let checked = item.checkbox {
      return checked ? "☑" : "☐"
    }
    switch list.kind {
    case .unordered:
      return "•"
    case .ordered(let start):
      let (offset, overflow) = start.addingReportingOverflow(UInt(index))
      return "\(overflow ? UInt.max : offset)."
    }
  }

  static func alignedListMarker(
    _ list: MarkdownList,
    item: MarkdownListItem,
    index: Int,
    width: Int
  ) -> String {
    let marker = listMarker(list, item: item, index: index)
    let padding = max(0, width - terminalDisplayWidth(of: marker))
    return String(repeating: " ", count: padding) + marker
  }

  private static func listIndentation(_ list: MarkdownList) -> Int {
    listMarkerWidth(list) + 1
  }

  static func listMarkerWidth(_ list: MarkdownList) -> Int {
    list.items.enumerated().map { index, item in
      terminalDisplayWidth(of: listMarker(list, item: item, index: index))
    }.max() ?? 1
  }

  /// The presentation state renderedGeometry needs, passed explicitly: the
  /// resource presentations live on `ViewerModel` as their own observed
  /// properties (not in `ViewerState`), so geometry cannot read them from the
  /// state value.
  struct GeometryInputs {
    var mermaid: [BlockID: MermaidPresentation] = [:]
    var images: [BlockID: ImagePresentation] = [:]
    var revealedMermaidSources: Set<BlockID> = []
    var documentURL: URL?
    // Model-owned identity-keyed metrics; nil computes directly (tests).
    var tableMetrics: ((BlockID, MarkdownTable) -> MarkdownTableLayoutMetrics)? = nil
  }

  struct GeometryEntry: Equatable, Sendable {
    var blockID: BlockID
    var stableIdentity: String
    var sourceLine: Int?
    var headingAnchor: String?
    var top: Int
    var height: Int
  }

  static func renderedGeometry(
    _ blocks: [MarkdownBlock],
    inputs: GeometryInputs,
    offeredWidth: Int
  ) -> [GeometryEntry] {
    geometryForBlocks(
      blocks,
      inputs: inputs,
      offeredWidth: max(1, offeredWidth),
      originY: 0
    ).entries
  }

  private static func geometryForBlocks(
    _ blocks: [MarkdownBlock],
    inputs: GeometryInputs,
    offeredWidth: Int,
    originY: Int,
    siblingSpacing: Int = 0
  ) -> (height: Int, entries: [GeometryEntry]) {
    var cursor = originY
    var entries: [GeometryEntry] = []
    for (index, block) in blocks.enumerated() {
      if index > 0 { cursor += siblingSpacing }
      let geometry = geometryForBlock(
        block,
        inputs: inputs,
        offeredWidth: offeredWidth,
        originY: cursor
      )
      entries.append(contentsOf: geometry.entries)
      cursor += geometry.height
    }
    return (max(0, cursor - originY), entries)
  }

  private static func geometryForBlock(
    _ block: MarkdownBlock,
    inputs: GeometryInputs,
    offeredWidth: Int,
    originY: Int
  ) -> (height: Int, entries: [GeometryEntry]) {
    let width = max(1, offeredWidth)
    var nestedEntries: [GeometryEntry] = []
    let height: Int
    let headingAnchor: String?

    switch block {
    case .heading(_, let level, let anchor, let content, _):
      headingAnchor = anchor
      height = textHeight(content.map(\.text).joined(), width: width) + (level <= 2 ? 1 : 0)
    case .paragraph(_, let content, _):
      headingAnchor = nil
      height = textHeight(content.map(\.text).joined(), width: width)
    case .quote(_, let nested, _):
      headingAnchor = nil
      let nestedGeometry = geometryForBlocks(
        nested,
        inputs: inputs,
        offeredWidth: quoteContentWidth(width),
        originY: originY
      )
      nestedEntries = nestedGeometry.entries
      height = max(1, nestedGeometry.height)
    case .list(_, let list, _):
      headingAnchor = nil
      var itemOrigin = originY
      let contentWidth = listContentWidth(list, offeredWidth: width)
      for item in list.items {
        let itemGeometry = geometryForBlocks(
          item.blocks,
          inputs: inputs,
          offeredWidth: contentWidth,
          originY: itemOrigin,
          siblingSpacing: 0
        )
        nestedEntries.append(contentsOf: itemGeometry.entries)
        itemOrigin += max(1, itemGeometry.height)
      }
      height = max(1, itemOrigin - originY)
    case .code(_, let language, let source, _):
      headingAnchor = nil
      height = (language == nil ? 0 : 1) + literalHeight(source)
    case .mermaid(let id, let value, _):
      headingAnchor = nil
      let sourceHeight = literalHeight(value.source)
      switch inputs.mermaid[id] {
      case .ready(let rendered)?, .reflowing(let rendered)?:
        height =
          max(1, rendered.height)
          + (rendered.isPartial
            ? rendered.diagnostics.first.map {
              textHeight(mermaidDiagnosticText($0), width: width)
            } ?? 0
            : 0)
          + (inputs.revealedMermaidSources.contains(id) ? sourceHeight : 0)
      case .unavailable(let diagnostic)?:
        height =
          textHeight(mermaidUnavailableText(diagnostic), width: width)
          + sourceHeight
      case .pending?, nil:
        height =
          textHeight(mermaidPendingText, width: width)
          + (inputs.revealedMermaidSources.contains(id) ? sourceHeight : 0)
      }
    case .table(let id, let table, _):
      headingAnchor = nil
      let metrics =
        inputs.tableMetrics?(id, table) ?? MarkdownTableLayout.metrics(for: table)
      height = metrics.totalHeight
    case .rule:
      headingAnchor = nil
      height = 1
    case .image(let id, let image, _):
      headingAnchor = nil
      let presentation = inputs.images[id]
      let url = imageURL(
        image: image,
        documentURL: inputs.documentURL,
        presentation: presentation
      )
      let metadataHeight = textHeight(
        imageMetadataText(image: image, url: url),
        width: width
      )
      if case .ready(let loaded)? = presentation {
        let imageWidth = min(72, width)
        let dimensions = loaded.image.dimensions
        let scaledHeight =
          dimensions.width > 0
          ? (imageWidth * dimensions.height + dimensions.width - 1) / dimensions.width
          : 1
        height = min(24, max(1, scaledHeight)) + metadataHeight
      } else {
        height =
          (imageStatusText(presentation).map {
            textHeight($0, width: width)
          } ?? 0)
          + metadataHeight
      }
    case .html(_, let source, _):
      headingAnchor = nil
      height = textHeight(source, width: max(1, width - 2))
    case .unsupported(_, let kind, let source, _):
      headingAnchor = nil
      height =
        textHeight(unsupportedLabel(kind), width: width)
        + textHeight(source, width: width)
    }

    let own = GeometryEntry(
      blockID: block.id,
      stableIdentity: stableRestorationIdentity(for: block),
      sourceLine: block.sourceSpan?.start.line,
      headingAnchor: headingAnchor,
      top: originY,
      height: max(1, height)
    )
    return (max(1, height), [own] + nestedEntries)
  }

  private static func textHeight(_ source: String, width: Int) -> Int {
    max(1, layoutText(for: source, width: max(1, width)).size.height)
  }

  private static func literalHeight(_ source: String) -> Int {
    max(1, source.split(separator: "\n", omittingEmptySubsequences: false).count)
  }

  private static func stableRestorationIdentity(for block: MarkdownBlock) -> String {
    if case .heading(_, _, let anchor, _, _) = block {
      return "heading:\(anchor)"
    }
    let kind: String
    switch block {
    case .paragraph: kind = "paragraph"
    case .quote: kind = "quote"
    case .list: kind = "list"
    case .code: kind = "code"
    case .mermaid: kind = "mermaid"
    case .table: kind = "table"
    case .rule: kind = "rule"
    case .image: kind = "image"
    case .html: kind = "html"
    case .unsupported: kind = "unsupported"
    case .heading: kind = "heading"
    }
    var digest: UInt64 = 1_469_598_103_934_665_603
    for byte in block.searchableText.utf8 {
      digest = (digest ^ UInt64(byte)) &* 1_099_511_628_211
    }
    return "\(kind):\(String(digest, radix: 16))"
  }
}

/// Uses the same cached terminal-cell measurement path that SwiftTUI uses to
/// lay out the corresponding rendered text.
func terminalDisplayWidth(of source: String) -> Int {
  layoutText(for: source, width: nil).size.width
}

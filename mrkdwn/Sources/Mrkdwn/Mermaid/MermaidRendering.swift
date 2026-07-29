import SwiftTUI

struct MermaidForeignPayload: ForeignSurfacePayload {
  let grid: ForeignGrid

  init(rendered: RenderedMermaid, theme: ViewerTheme) {
    let rows = rendered.cells.map { row in
      row.map { cell in
        RasterCell(
          character: cell.character,
          spanWidth: cell.spanWidth,
          continuationLeadX: cell.continuationLeadX,
          style: ResolvedTextStyle(
            foregroundColor: theme.mermaidColor(for: cell.role),
            backgroundColor: theme.mermaid.background.swiftTUIColor
          )
        )
      }
    }
    grid = ForeignGrid(
      size: CellSize(width: rendered.width, height: rendered.height),
      cells: rows
    )
  }
}

struct MermaidBlockView: View {
  var blockID: BlockID
  var source: String
  var presentation: MermaidPresentation?
  var theme: ViewerTheme
  var offeredWidth: Int
  var revealsSource: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      switch presentation {
      case .ready(let rendered)?, .reflowing(let rendered)?:
        renderedView(rendered)
        if rendered.isPartial, let diagnostic = rendered.diagnostics.first {
          Text(MarkdownBlockLayout.mermaidDiagnosticText(diagnostic))
            .foregroundStyle(theme.muted.swiftTUIColor)
        }
      case .unavailable(let diagnostic)?:
        fallback(diagnostic)
      case .pending?, nil:
        Text(MarkdownBlockLayout.mermaidPendingText)
          .foregroundStyle(theme.muted.swiftTUIColor)
      }
      if revealsSource && !presentationIncludesSource {
        sourceView
      }
    }
    .id(blockID)
  }

  @ViewBuilder
  private func renderedView(_ rendered: RenderedMermaid) -> some View {
    if rendered.width > offeredWidth {
      ScrollView(.horizontal, showsIndicators: true) {
        ForeignSurface(payload: MermaidForeignPayload(rendered: rendered, theme: theme))
          .frame(width: rendered.width, height: rendered.height, alignment: .topLeading)
      }
      .frame(maxWidth: .finite(offeredWidth))
    } else {
      ForeignSurface(payload: MermaidForeignPayload(rendered: rendered, theme: theme))
        .frame(width: rendered.width, height: rendered.height, alignment: .topLeading)
    }
  }

  private func fallback(_ diagnostic: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(MarkdownBlockLayout.mermaidUnavailableText(diagnostic))
        .foregroundStyle(theme.error.swiftTUIColor)
      sourceView
    }
  }

  private var presentationIncludesSource: Bool {
    if case .unavailable? = presentation { return true }
    return false
  }

  private var sourceView: some View {
    ScrollView(.horizontal, showsIndicators: true) {
      Text(source)
        .foregroundStyle(theme.codeForeground.swiftTUIColor)
        .padding(.init(horizontal: 1, vertical: 0))
    }
    .background(theme.codeBackground.swiftTUIColor)
  }
}

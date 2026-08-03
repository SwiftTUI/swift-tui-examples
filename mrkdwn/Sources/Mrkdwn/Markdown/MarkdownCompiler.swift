public import Foundation
import Markdown

public struct MarkdownCompiler: Sendable {
  public init() {}

  public func compile(source: String, sourceURL: URL?) -> CompiledDocument {
    let document = Document(
      parsing: source,
      source: sourceURL,
      options: [.disableSmartOpts]
    )
    var visitor = CompilerVisitor(source: source)
    let blocks = visitor.visit(document)
    return CompiledDocument(
      blocks: blocks,
      outline: visitor.outline,
      links: visitor.links,
      diagnostics: visitor.diagnostics
    )
  }
}

private struct CompilerVisitor: MarkupVisitor {
  typealias Result = [MarkdownBlock]

  let source: String
  var slugger = HeadingSlugger()
  var outline: [OutlineEntry] = []
  var links: [CompiledLink] = []
  var diagnostics: [CompilerDiagnostic] = []
  private var fallbackOrdinal = 0

  init(source: String) {
    self.source = source
  }

  mutating func defaultVisit(_ markup: Markup) -> [MarkdownBlock] {
    if markup.childCount > 0 {
      return blocks(in: markup)
    }
    return unsupported(markup)
  }

  mutating func visitDocument(_ document: Document) -> [MarkdownBlock] {
    blocks(in: document)
  }

  mutating func visitHeading(_ heading: Heading) -> [MarkdownBlock] {
    let runs = inlineChildren(of: heading)
    let title = runs.map(\.text).joined()
    let anchor = slugger.slug(for: title)
    let span = sourceSpan(heading)
    let id = blockID(kind: "heading-\(heading.level)", span: span)
    outline.append(
      OutlineEntry(id: id, level: heading.level, title: title, anchor: anchor, source: span)
    )
    return [.heading(id: id, level: heading.level, anchor: anchor, content: runs, source: span)]
  }

  mutating func visitParagraph(_ paragraph: Paragraph) -> [MarkdownBlock] {
    let runs = inlineChildren(of: paragraph)
    let span = sourceSpan(paragraph)
    let id = blockID(kind: "paragraph", span: span)
    if runs.count == 1, let image = runs[0].image {
      return [.image(id: id, value: image, source: span)]
    }
    return [.paragraph(id: id, content: runs, source: span)]
  }

  mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> [MarkdownBlock] {
    let span = sourceSpan(blockQuote)
    return [
      .quote(
        id: blockID(kind: "quote", span: span),
        blocks: blocks(in: blockQuote),
        source: span
      )
    ]
  }

  mutating func visitOrderedList(_ orderedList: OrderedList) -> [MarkdownBlock] {
    compileList(orderedList, kind: .ordered(start: orderedList.startIndex))
  }

  mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> [MarkdownBlock] {
    compileList(unorderedList, kind: .unordered)
  }

  mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> [MarkdownBlock] {
    let span = sourceSpan(codeBlock)
    let language = normalizedLanguage(codeBlock.language)
    return [
      .code(
        id: blockID(kind: "code", span: span),
        language: language,
        sourceText: codeBlock.code,
        source: span
      )
    ]
  }

  mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> [MarkdownBlock] {
    let span = sourceSpan(thematicBreak)
    return [.rule(id: blockID(kind: "rule", span: span), source: span)]
  }

  mutating func visitHTMLBlock(_ html: HTMLBlock) -> [MarkdownBlock] {
    let span = sourceSpan(html)
    return [
      .html(
        id: blockID(kind: "html", span: span),
        sourceText: html.rawHTML,
        source: span
      )
    ]
  }

  mutating func visitTable(_ table: Table) -> [MarkdownBlock] {
    let span = sourceSpan(table)
    let header = table.head.children.compactMap { child -> [InlineRun]? in
      guard let cell = child as? Table.Cell else { return nil }
      return inlineChildren(of: cell)
    }
    var rows: [[[InlineRun]]] = []
    for row in table.body.rows {
      let cells = row.children.compactMap { child -> [InlineRun]? in
        guard let cell = child as? Table.Cell else { return nil }
        return inlineChildren(of: cell)
      }
      rows.append(cells)
    }
    let alignments: [TableAlignment] = table.columnAlignments.map {
      switch $0 {
      case .some(.left): return .leading
      case .some(.center): return .center
      case .some(.right): return .trailing
      case .none: return .unspecified
      }
    }
    return [
      .table(
        id: blockID(kind: "table", span: span),
        value: MarkdownTable(header: header, rows: rows, alignments: alignments),
        source: span
      )
    ]
  }

  mutating func visitCustomBlock(_ customBlock: CustomBlock) -> [MarkdownBlock] {
    unsupported(customBlock)
  }

  mutating func visitBlockDirective(_ blockDirective: BlockDirective) -> [MarkdownBlock] {
    unsupported(blockDirective)
  }

  private mutating func blocks(in markup: Markup) -> [MarkdownBlock] {
    markup.children.flatMap { visit($0) }
  }

  private mutating func compileList(
    _ list: some ListItemContainer,
    kind: MarkdownList.Kind
  ) -> [MarkdownBlock] {
    let span = sourceSpan(list)
    var items: [MarkdownListItem] = []
    for item in list.listItems {
      items.append(
        MarkdownListItem(
          checkbox: checkboxValue(item.checkbox),
          blocks: blocks(in: item)
        )
      )
    }
    return [
      .list(
        id: blockID(kind: "list", span: span),
        value: MarkdownList(kind: kind, items: items),
        source: span
      )
    ]
  }

  private func checkboxValue(_ checkbox: Checkbox?) -> Bool? {
    switch checkbox {
    case .checked?: true
    case .unchecked?: false
    case nil: nil
    }
  }

  private mutating func inlineChildren(
    of markup: Markup,
    traits: InlineTraits = []
  ) -> [InlineRun] {
    normalizeInlineRuns(
      markup.children.flatMap { inline($0, traits: traits) }
    )
  }

  private mutating func inline(_ markup: Markup, traits: InlineTraits) -> [InlineRun] {
    if let text = markup as? Markdown.Text {
      return [InlineRun(text: text.string, traits: traits)]
    }
    if markup is SoftBreak {
      return [InlineRun(text: " ", traits: traits)]
    }
    if markup is LineBreak {
      return [InlineRun(text: "\n", traits: traits)]
    }
    if let code = markup as? InlineCode {
      return [InlineRun(text: code.code, traits: traits.union(.code))]
    }
    if let html = markup as? InlineHTML {
      return [InlineRun(text: html.rawHTML, traits: traits.union(.html))]
    }
    if let emphasis = markup as? Emphasis {
      return inlineChildren(of: emphasis, traits: traits.union(.emphasis))
    }
    if let strong = markup as? Strong {
      return inlineChildren(of: strong, traits: traits.union(.strong))
    }
    if let strike = markup as? Strikethrough {
      return inlineChildren(of: strike, traits: traits.union(.strikethrough))
    }
    if let link = markup as? Markdown.Link {
      let labelRuns = inlineChildren(of: link, traits: traits)
      guard let destination = link.destination, !destination.isEmpty else {
        return labelRuns
      }
      let label = labelRuns.map(\.text).joined()
      links.append(
        CompiledLink(destination: destination, label: label, source: sourceSpan(link))
      )
      return labelRuns.map {
        var run = $0
        run.destination = destination
        return run
      }
    }
    if let image = markup as? Markdown.Image {
      let alt = plainText(of: image)
      let source = image.source ?? ""
      let reference = ImageReference(source: source, altText: alt, title: image.title)
      return [
        InlineRun(
          text: alt.isEmpty ? source : alt,
          traits: traits,
          destination: source.isEmpty ? nil : source,
          image: reference
        )
      ]
    }
    if markup.childCount > 0 {
      return inlineChildren(of: markup, traits: traits)
    }
    let span = sourceSpan(markup)
    diagnostics.append(
      CompilerDiagnostic(
        kind: .unsupportedNode,
        message: "Unsupported inline node \(String(describing: type(of: markup)))",
        source: span
      )
    )
    return [
      InlineRun(
        text: sourceExcerpt(span) ?? "⟦unsupported inline⟧",
        traits: traits
      )
    ]
  }

  private func plainText(of markup: Markup) -> String {
    if let text = markup as? Markdown.Text { return text.string }
    if let code = markup as? InlineCode { return code.code }
    if let html = markup as? InlineHTML { return html.rawHTML }
    if markup is SoftBreak { return " " }
    if markup is LineBreak { return "\n" }
    return markup.children.map(plainText(of:)).joined()
  }

  private func normalizeInlineRuns(_ runs: [InlineRun]) -> [InlineRun] {
    var normalized: [InlineRun] = []
    for run in runs where !run.text.isEmpty || run.image != nil {
      if var previous = normalized.last,
        previous.traits == run.traits,
        previous.destination == run.destination,
        previous.image == nil,
        run.image == nil
      {
        previous.text += run.text
        normalized[normalized.count - 1] = previous
      } else {
        normalized.append(run)
      }
    }
    return normalized
  }

  private mutating func unsupported(_ markup: Markup) -> [MarkdownBlock] {
    let span = sourceSpan(markup)
    let kind = String(describing: type(of: markup))
    let excerpt = sourceExcerpt(span) ?? "⟦unsupported \(kind)⟧"
    diagnostics.append(
      CompilerDiagnostic(
        kind: .unsupportedNode,
        message: "Unsupported Markdown node \(kind)",
        source: span
      )
    )
    return [
      .unsupported(
        id: blockID(kind: "unsupported-\(kind)", span: span),
        kind: kind,
        sourceText: excerpt,
        source: span
      )
    ]
  }

  private func normalizedLanguage(_ language: String?) -> String? {
    guard var value = language?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    value = String(value.split(whereSeparator: \.isWhitespace).first ?? "")
    if value.hasPrefix("{.") && value.hasSuffix("}") {
      value = String(value.dropFirst(2).dropLast())
    }
    return value.lowercased()
  }

  private func sourceSpan(_ markup: Markup) -> SourceSpan? {
    guard let range = markup.range else { return nil }
    return SourceSpan(
      start: SourcePosition(line: range.lowerBound.line, column: range.lowerBound.column),
      end: SourcePosition(line: range.upperBound.line, column: range.upperBound.column)
    )
  }

  private mutating func blockID(kind: String, span: SourceSpan?) -> BlockID {
    if let span {
      return BlockID(
        "\(kind):\(span.start.line):\(span.start.column)-\(span.end.line):\(span.end.column)"
      )
    }
    defer { fallbackOrdinal += 1 }
    return BlockID("\(kind):generated:\(fallbackOrdinal)")
  }

  private func sourceExcerpt(_ span: SourceSpan?) -> String? {
    guard let span else { return nil }
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
    guard span.start.line > 0, span.start.line <= lines.count else { return nil }
    let endLine = min(max(span.end.line, span.start.line), lines.count)
    return lines[(span.start.line - 1)..<endLine].joined(separator: "\n")
  }
}

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
  private let referenceLiterals: NumericReferenceLiterals?
  var slugger = HeadingSlugger()
  var outline: [OutlineEntry] = []
  var links: [CompiledLink] = []
  var diagnostics: [CompilerDiagnostic] = []
  private var fallbackOrdinal = 0

  init(source: String) {
    self.source = source
    referenceLiterals = NumericReferenceLiterals(source: source)
  }

  mutating func defaultVisit(_ markup: any Markup) -> [MarkdownBlock] {
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
    // swift-markdown keeps the fence's final newline in `code`; stored as-is
    // it renders (and measures) as a phantom blank row under every block.
    var sourceText = codeBlock.code
    if sourceText.hasSuffix("\n") {
      sourceText.removeLast()
    }
    return [
      .code(
        id: blockID(kind: "code", span: span),
        language: language,
        sourceText: sourceText,
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

  private mutating func blocks(in markup: any Markup) -> [MarkdownBlock] {
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
    of markup: any Markup,
    traits: InlineTraits = []
  ) -> [InlineRun] {
    normalizeInlineRuns(
      markup.children.flatMap { inline($0, traits: traits) }
    )
  }

  private mutating func inline(_ markup: any Markup, traits: InlineTraits) -> [InlineRun] {
    if let text = markup as? Markdown.Text {
      return [InlineRun(text: literalText(text), traits: traits)]
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

  private func literalText(_ text: Markdown.Text) -> String {
    referenceLiterals?.literalText(for: text) ?? text.string
  }

  private func plainText(of markup: any Markup) -> String {
    if let text = markup as? Markdown.Text { return literalText(text) }
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

  private mutating func unsupported(_ markup: any Markup) -> [MarkdownBlock] {
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

  private func sourceSpan(_ markup: any Markup) -> SourceSpan? {
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

/// Keeps numeric character references that CommonMark rejects literal (STUI-1185).
///
/// CommonMark 0.31.2 §2.5 allows 1–7 decimal or 1–6 hexadecimal digits. The
/// pinned swift-cmark 0.8.0 accepts up to eight of either
/// (`src/houdini_html_u.c`), so `&#87654321;` decoded to U+FFFD instead of
/// staying literal; no tagged swift-cmark or swift-markdown release changes
/// that. Nothing is rewritten before parsing. A text node is re-decoded only
/// when its own source excerpt holds such a reference and an isolated parse of
/// that excerpt reproduces the node's text exactly; any other node keeps the
/// parser's text. Destinations, titles and fence info strings are decoded inside
/// the parser, before any text node exists, and keep the parser's decoding.
private struct NumericReferenceLiterals {
  private let bytes: [UInt8]
  private let lines: [Range<Int>]

  /// Returns `nil`, leaving compilation unchanged, unless the source contains
  /// an eight-digit decimal or seven- or eight-digit hexadecimal reference.
  init?(source: String) {
    let bytes = Array(source.utf8)
    var index = 0
    var found = false
    while index < bytes.count, !found {
      if let reference = Self.reference(in: bytes, at: index, end: bytes.count) {
        found = reference.rejectedByCommonMark
      }
      index += 1
    }
    guard found else { return nil }
    self.bytes = bytes
    lines = Self.lines(in: bytes)
  }

  func literalText(for text: Markdown.Text) -> String? {
    guard let excerpt = excerpt(text.range) else { return nil }
    let references = Self.rejectedReferences(in: bytes, excerpt)
    guard !references.isEmpty else { return nil }
    let parsed = Self.isolatedText(sentinel(bytes[excerpt]))
    guard let parsed, parsed.unicodeScalars.elementsEqual(sentinel(text.string).unicodeScalars)
    else { return nil }
    var escaped: [UInt8] = []
    var start = excerpt.lowerBound
    for reference in references {
      escaped += bytes[start..<reference.lowerBound]
      escaped += Array("&amp;".utf8)
      escaped += bytes[(reference.lowerBound + 1)..<reference.upperBound]
      start = reference.upperBound
    }
    escaped += bytes[start..<excerpt.upperBound]
    guard var scalars = Self.isolatedText(sentinel(escaped[...]))?.unicodeScalars,
      scalars.first == "a", scalars.last == "a"
    else { return nil }
    scalars.removeFirst()
    scalars.removeLast()
    let growth = references.reduce(0) { $0 + $1.count - 1 }
    guard scalars.count == text.string.unicodeScalars.count + growth else { return nil }
    return String(scalars)
  }

  /// The node's single-line source range as UTF-8 offsets (swift-markdown
  /// columns are 1-based UTF-8 byte columns with an exclusive upper bound).
  private func excerpt(_ range: SourceRange?) -> Range<Int>? {
    guard let range, range.lowerBound.line == range.upperBound.line,
      range.lowerBound.line >= 1, range.lowerBound.line <= lines.count,
      range.lowerBound.column >= 1, range.lowerBound.column <= range.upperBound.column
    else { return nil }
    let line = lines[range.lowerBound.line - 1]
    let lower = line.lowerBound + range.lowerBound.column - 1
    let upper = line.lowerBound + range.upperBound.column - 1
    guard upper <= line.upperBound else { return nil }
    return lower..<upper
  }

  private func sentinel(_ text: some StringProtocol) -> String { "a" + text + "a" }

  private func sentinel(_ text: ArraySlice<UInt8>) -> String {
    sentinel(String(decoding: text, as: UTF8.self))
  }

  /// Line content ranges, ending at LF, CR or CRLF as cmark does.
  private static func lines(in bytes: [UInt8]) -> [Range<Int>] {
    var lines: [Range<Int>] = []
    var start = 0
    var index = 0
    while index < bytes.count {
      switch bytes[index] {
      case UInt8(ascii: "\n"):
        lines.append(start..<index)
        index += 1
        start = index
      case UInt8(ascii: "\r"):
        lines.append(start..<index)
        index += index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "\n") ? 2 : 1
        start = index
      default:
        index += 1
      }
    }
    lines.append(start..<bytes.count)
    return lines
  }

  /// Out-of-grammar references in a text excerpt, tokenized as cmark does:
  /// a backslash escapes ASCII punctuation, and a reference cmark accepts is
  /// consumed whole, so `\&#…;` and `&#38;#…;` hold no reference.
  private static func rejectedReferences(in bytes: [UInt8], _ excerpt: Range<Int>) -> [Range<Int>] {
    var references: [Range<Int>] = []
    var index = excerpt.lowerBound
    while index < excerpt.upperBound {
      if bytes[index] == UInt8(ascii: "\\"), index + 1 < excerpt.upperBound,
        isASCIIPunctuation(bytes[index + 1])
      {
        index += 2
      } else if let reference = reference(in: bytes, at: index, end: excerpt.upperBound) {
        if reference.rejectedByCommonMark {
          references.append(index..<(index + reference.length))
        }
        index += reference.length
      } else {
        index += 1
      }
    }
    return references
  }

  /// A numeric reference that swift-cmark 0.8.0 decodes: `&#`, 1–8 decimal
  /// digits or `x`/`X` and 1–8 hexadecimal digits, then `;`.
  private static func reference(
    in bytes: [UInt8], at index: Int, end: Int
  ) -> (length: Int, rejectedByCommonMark: Bool)? {
    guard index + 2 < end, bytes[index] == UInt8(ascii: "&"), bytes[index + 1] == UInt8(ascii: "#")
    else { return nil }
    let hexadecimal = bytes[index + 2] == UInt8(ascii: "x") || bytes[index + 2] == UInt8(ascii: "X")
    let digitsStart = index + (hexadecimal ? 3 : 2)
    var digitsEnd = digitsStart
    while digitsEnd < end, isDigit(bytes[digitsEnd], hexadecimal: hexadecimal) {
      digitsEnd += 1
    }
    let count = digitsEnd - digitsStart
    guard (1...8).contains(count), digitsEnd < end, bytes[digitsEnd] == UInt8(ascii: ";")
    else { return nil }
    return (digitsEnd + 1 - index, count > (hexadecimal ? 6 : 7))
  }

  private static func isDigit(_ byte: UInt8, hexadecimal: Bool) -> Bool {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): true
    case UInt8(ascii: "a")...UInt8(ascii: "f"), UInt8(ascii: "A")...UInt8(ascii: "F"): hexadecimal
    default: false
    }
  }

  private static func isASCIIPunctuation(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E: true
    default: false
    }
  }

  /// The text of a source that parses, with the compiler's options, to exactly
  /// one paragraph holding one text node; otherwise `nil`.
  private static func isolatedText(_ source: String) -> String? {
    let document = Document(parsing: source, options: [.disableSmartOpts])
    guard document.childCount == 1, let paragraph = document.child(at: 0) as? Paragraph,
      paragraph.childCount == 1, let text = paragraph.child(at: 0) as? Markdown.Text
    else { return nil }
    return text.string
  }
}

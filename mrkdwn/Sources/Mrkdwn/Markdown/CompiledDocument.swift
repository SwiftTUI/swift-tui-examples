import Foundation

public struct SourcePosition: Equatable, Hashable, Sendable {
  public var line: Int
  public var column: Int

  public init(line: Int, column: Int) {
    self.line = line
    self.column = column
  }
}

public struct SourceSpan: Equatable, Hashable, Sendable {
  public var start: SourcePosition
  public var end: SourcePosition

  public init(start: SourcePosition, end: SourcePosition) {
    self.start = start
    self.end = end
  }
}

public struct BlockID: Equatable, Hashable, Sendable, CustomStringConvertible {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

public struct InlineTraits: OptionSet, Equatable, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let emphasis = Self(rawValue: 1 << 0)
  public static let strong = Self(rawValue: 1 << 1)
  public static let strikethrough = Self(rawValue: 1 << 2)
  public static let code = Self(rawValue: 1 << 3)
  public static let html = Self(rawValue: 1 << 4)
}

public struct ImageReference: Equatable, Hashable, Sendable {
  public var source: String
  public var altText: String
  public var title: String?

  public init(source: String, altText: String, title: String? = nil) {
    self.source = source
    self.altText = altText
    self.title = title
  }
}

public struct InlineRun: Equatable, Hashable, Sendable {
  public var text: String
  public var traits: InlineTraits
  public var destination: String?
  public var image: ImageReference?

  public init(
    text: String,
    traits: InlineTraits = [],
    destination: String? = nil,
    image: ImageReference? = nil
  ) {
    self.text = text
    self.traits = traits
    self.destination = destination
    self.image = image
  }
}

public enum TableAlignment: Equatable, Hashable, Sendable {
  case leading
  case center
  case trailing
  case unspecified
}

public struct MarkdownTable: Equatable, Sendable {
  public var header: [[InlineRun]]
  public var rows: [[[InlineRun]]]
  public var alignments: [TableAlignment]

  public init(
    header: [[InlineRun]],
    rows: [[[InlineRun]]],
    alignments: [TableAlignment]
  ) {
    self.header = header
    self.rows = rows
    self.alignments = alignments
  }
}

public struct MarkdownListItem: Equatable, Sendable {
  public var checkbox: Bool?
  public var blocks: [MarkdownBlock]

  public init(checkbox: Bool? = nil, blocks: [MarkdownBlock]) {
    self.checkbox = checkbox
    self.blocks = blocks
  }
}

public struct MarkdownList: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case unordered
    case ordered(start: UInt)
  }

  public var kind: Kind
  public var items: [MarkdownListItem]

  public init(kind: Kind, items: [MarkdownListItem]) {
    self.kind = kind
    self.items = items
  }
}

public struct MermaidBlock: Equatable, Sendable {
  public var source: String
  public var language: String

  public init(source: String, language: String = "mermaid") {
    self.source = source
    self.language = language
  }
}

public indirect enum MarkdownBlock: Equatable, Sendable {
  case heading(
    id: BlockID,
    level: Int,
    anchor: String,
    content: [InlineRun],
    source: SourceSpan?
  )
  case paragraph(id: BlockID, content: [InlineRun], source: SourceSpan?)
  case quote(id: BlockID, blocks: [MarkdownBlock], source: SourceSpan?)
  case list(id: BlockID, value: MarkdownList, source: SourceSpan?)
  case code(id: BlockID, language: String?, sourceText: String, source: SourceSpan?)
  case mermaid(id: BlockID, value: MermaidBlock, source: SourceSpan?)
  case table(id: BlockID, value: MarkdownTable, source: SourceSpan?)
  case rule(id: BlockID, source: SourceSpan?)
  case image(id: BlockID, value: ImageReference, source: SourceSpan?)
  case html(id: BlockID, sourceText: String, source: SourceSpan?)
  case unsupported(id: BlockID, kind: String, sourceText: String, source: SourceSpan?)

  public var id: BlockID {
    switch self {
    case .heading(let id, _, _, _, _),
      .paragraph(let id, _, _),
      .quote(let id, _, _),
      .list(let id, _, _),
      .code(let id, _, _, _),
      .mermaid(let id, _, _),
      .table(let id, _, _),
      .rule(let id, _),
      .image(let id, _, _),
      .html(let id, _, _),
      .unsupported(let id, _, _, _):
      id
    }
  }

  public var sourceSpan: SourceSpan? {
    switch self {
    case .heading(_, _, _, _, let span),
      .paragraph(_, _, let span),
      .quote(_, _, let span),
      .list(_, _, let span),
      .code(_, _, _, let span),
      .mermaid(_, _, let span),
      .table(_, _, let span),
      .rule(_, let span),
      .image(_, _, let span),
      .html(_, _, let span),
      .unsupported(_, _, _, let span):
      span
    }
  }

  public var searchableText: String {
    switch self {
    case .heading(_, _, _, let content, _), .paragraph(_, let content, _):
      content.map(\.text).joined()
    case .quote(_, let blocks, _):
      blocks.map(\.searchableText).joined(separator: "\n")
    case .list(_, let list, _):
      list.items.flatMap(\.blocks).map(\.searchableText).joined(separator: "\n")
    case .code(_, _, let source, _), .html(_, let source, _):
      source
    case .mermaid(_, let value, _):
      value.source
    case .table(_, let table, _):
      (table.header + table.rows.flatMap { $0 })
        .flatMap { $0 }
        .map(\.text)
        .joined(separator: " ")
    case .image(_, let image, _):
      image.altText
    case .unsupported(_, _, let source, _):
      source
    case .rule:
      ""
    }
  }
}

public struct OutlineEntry: Equatable, Hashable, Sendable {
  public var id: BlockID
  public var level: Int
  public var title: String
  public var anchor: String
  public var source: SourceSpan?

  public init(
    id: BlockID,
    level: Int,
    title: String,
    anchor: String,
    source: SourceSpan?
  ) {
    self.id = id
    self.level = level
    self.title = title
    self.anchor = anchor
    self.source = source
  }
}

public struct CompiledLink: Equatable, Hashable, Sendable {
  public var destination: String
  public var label: String
  public var source: SourceSpan?

  public init(destination: String, label: String, source: SourceSpan?) {
    self.destination = destination
    self.label = label
    self.source = source
  }
}

public struct CompilerDiagnostic: Equatable, Hashable, Sendable {
  public enum Kind: Equatable, Hashable, Sendable {
    case unsupportedNode
    case invalidDestination
  }

  public var kind: Kind
  public var message: String
  public var source: SourceSpan?

  public init(kind: Kind, message: String, source: SourceSpan?) {
    self.kind = kind
    self.message = message
    self.source = source
  }
}

public struct SearchMatch: Equatable, Hashable, Sendable {
  public var blockID: BlockID
  public var range: Range<String.Index>

  public init(blockID: BlockID, range: Range<String.Index>) {
    self.blockID = blockID
    self.range = range
  }
}

public struct SearchResultSet: Equatable, Sendable {
  public var matches: [SearchMatch]
  public var isTruncated: Bool

  public init(matches: [SearchMatch], isTruncated: Bool) {
    self.matches = matches
    self.isTruncated = isTruncated
  }
}

public struct SearchIndex: Equatable, Sendable {
  public static let maximumRetainedMatches = 1_000
  public static let maximumScannedCharacters = 16 * 1_024 * 1_024
  public static let maximumQueryCharacters = 1_024
  private static let scanChunkCharacters = 64 * 1_024

  public var entries: [(id: BlockID, text: String)]

  public init(entries: [(id: BlockID, text: String)]) {
    self.entries = entries
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    guard lhs.entries.count == rhs.entries.count else { return false }
    return zip(lhs.entries, rhs.entries).allSatisfy {
      $0.id == $1.id && $0.text == $1.text
    }
  }

  public func matches(for query: String) -> [SearchMatch] {
    results(for: query).matches
  }

  public func results(
    for query: String,
    maximumRetainedMatches: Int = Self.maximumRetainedMatches,
    maximumScannedCharacters: Int = Self.maximumScannedCharacters
  ) -> SearchResultSet {
    guard !query.isEmpty, maximumRetainedMatches > 0, maximumScannedCharacters > 0 else {
      return SearchResultSet(matches: [], isTruncated: false)
    }
    let retainedLimit = min(maximumRetainedMatches, Self.maximumRetainedMatches)
    let scanLimit = min(maximumScannedCharacters, Self.maximumScannedCharacters)
    let queryLimit = query.index(
      query.startIndex,
      offsetBy: Self.maximumQueryCharacters,
      limitedBy: query.endIndex
    )
    guard queryLimit == nil || queryLimit == query.endIndex else {
      return SearchResultSet(matches: [], isTruncated: true)
    }
    let queryCharacters = query.distance(from: query.startIndex, to: query.endIndex)

    var results: [SearchMatch] = []
    results.reserveCapacity(min(retainedLimit, 256))
    var remainingCharacters = scanLimit
    for entry in entries {
      var scanStart = entry.text.startIndex
      var nextMatchStart = scanStart
      while scanStart < entry.text.endIndex {
        guard !Task.isCancelled else {
          return SearchResultSet(matches: [], isTruncated: false)
        }
        guard remainingCharacters > 0 else {
          return SearchResultSet(matches: results, isTruncated: true)
        }

        let chunkCharacters = min(remainingCharacters, Self.scanChunkCharacters)
        let chunkEnd =
          entry.text.index(
            scanStart,
            offsetBy: chunkCharacters,
            limitedBy: entry.text.endIndex
          ) ?? entry.text.endIndex
        let scannedCharacters = entry.text.distance(from: scanStart, to: chunkEnd)
        let searchEnd =
          entry.text.index(
            chunkEnd,
            offsetBy: max(0, queryCharacters - 1),
            limitedBy: entry.text.endIndex
          ) ?? entry.text.endIndex
        var remainder = max(scanStart, nextMatchStart)..<searchEnd
        while let found = entry.text.range(
          of: query,
          options: [.caseInsensitive, .diacriticInsensitive],
          range: remainder
        ) {
          guard !Task.isCancelled else {
            return SearchResultSet(matches: [], isTruncated: false)
          }
          if chunkEnd < entry.text.endIndex, found.lowerBound >= chunkEnd {
            break
          }
          guard results.count < retainedLimit else {
            return SearchResultSet(matches: results, isTruncated: true)
          }
          results.append(SearchMatch(blockID: entry.id, range: found))
          nextMatchStart = found.upperBound
          guard found.upperBound < searchEnd else { break }
          remainder = found.upperBound..<searchEnd
        }
        remainingCharacters -= scannedCharacters
        scanStart = chunkEnd
      }
    }
    return SearchResultSet(matches: results, isTruncated: false)
  }
}

public struct CompiledDocument: Equatable, Sendable {
  public var blocks: [MarkdownBlock]
  public var outline: [OutlineEntry]
  public var links: [CompiledLink]
  public var searchableText: SearchIndex
  public var diagnostics: [CompilerDiagnostic]

  public init(
    blocks: [MarkdownBlock],
    outline: [OutlineEntry],
    links: [CompiledLink],
    diagnostics: [CompilerDiagnostic]
  ) {
    self.blocks = blocks
    self.outline = outline
    self.links = links
    searchableText = SearchIndex(
      entries: blocks.map { ($0.id, $0.searchableText) }
    )
    self.diagnostics = diagnostics
  }
}

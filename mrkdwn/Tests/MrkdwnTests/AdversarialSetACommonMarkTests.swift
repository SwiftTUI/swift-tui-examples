import Foundation
import Testing

@testable import Mrkdwn

@Suite("Campaign E1 selected CommonMark contracts", .serialized)
struct AdversarialSetACommonMarkTests {
  @Test(arguments: Array(61...100))
  func commonmark(id: Int) throws {
    let fixture = e1CommonMarkCases[id - 61]
    let expected = try JSONDecoder().decode(
      E1MarkdownReference.self, from: Data(fixture.expected.utf8))
    let compiled = MarkdownCompiler().compile(source: fixture.source, sourceURL: nil)
    #expect(compiled.diagnostics.isEmpty, "CommonMark example \(fixture.example)")
    let actual = E1MarkdownReference(
      blocks: compiled.blocks.map(e1ReferenceBlock),
      links: compiled.links.map { .init(destination: $0.destination, label: $0.label) })
    #expect(actual == expected, "CommonMark example \(fixture.example): \(actual)")
  }
}

private struct E1MarkdownReference: Decodable, Equatable {
  var blocks: [E1MarkdownBlock]
  var links: [E1MarkdownLink]
}
private struct E1MarkdownBlock: Decodable, Equatable {
  var kind: String
  var level: Int?
  var text: String
  var runs: [E1MarkdownRun]
}
private struct E1MarkdownRun: Decodable, Equatable {
  var text: String
  var traits: [String]
  var destination: String?
}
private struct E1MarkdownLink: Decodable, Equatable {
  var destination: String
  var label: String
}

private func e1ReferenceRuns(_ runs: [InlineRun]) -> [E1MarkdownRun] {
  runs.map { run in
    #expect(run.image == nil)
    let names: [(InlineTraits, String)] = [
      (.emphasis, "emphasis"), (.strong, "strong"), (.code, "code"),
      (.strikethrough, "strikethrough"), (.html, "html"),
    ]
    return E1MarkdownRun(
      text: run.text, traits: names.filter { run.traits.contains($0.0) }.map(\.1).sorted(),
      destination: run.destination)
  }
}
private func e1ReferenceBlock(_ block: MarkdownBlock) -> E1MarkdownBlock {
  switch block {
  case .heading(_, let level, _, let runs, _):
    .init(kind: "heading", level: level, text: "", runs: e1ReferenceRuns(runs))
  case .paragraph(_, let runs, _):
    .init(kind: "paragraph", level: nil, text: "", runs: e1ReferenceRuns(runs))
  case .code(_, _, let text, _):
    .init(kind: "code", level: nil, text: text, runs: [])
  case .rule:
    .init(kind: "rule", level: nil, text: "", runs: [])
  default:
    .init(kind: "unmodeled", level: nil, text: block.searchableText, runs: [])
  }
}

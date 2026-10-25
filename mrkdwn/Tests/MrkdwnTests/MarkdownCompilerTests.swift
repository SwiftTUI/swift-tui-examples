import Foundation
import Testing

@testable import Mrkdwn

@Suite("Markdown compiler")
struct MarkdownCompilerTests {
  @Test("heading slugs are stable and duplicate-aware")
  func headingSlugs() {
    var slugger = HeadingSlugger()
    #expect(slugger.slug(for: "Hello, World!") == "hello-world")
    #expect(slugger.slug(for: "Héllo World") == "hello-world-1")
    #expect(slugger.slug(for: "!!!") == "section")
    #expect(slugger.slug(for: "???") == "section-1")
  }

  @Test("complete GFM surface compiles into app-owned values")
  func fullSurface() {
    let source = """
      # Heading

      Text with *emphasis*, **strong**, ~~strike~~, `code`, <https://example.com>,
      and [local](next.md).

      > quoted

      4. fourth
      5. fifth

      - [x] done
      - [ ] open

      ``` Swift extra
      print("hello")
      ```

      | Left | Center | Right |
      | :--- | :----: | ----: |
      | a | b | c |

      ![diagram](image.png "title")

      ---

      <div>literal</div>
      """
    let documentURL = URL(fileURLWithPath: "/tmp/docs/readme.md")
    let compiled = MarkdownCompiler().compile(source: source, sourceURL: documentURL)

    #expect(compiled.outline.map(\.anchor) == ["heading"])
    #expect(compiled.blocks.allSatisfy { $0.sourceSpan != nil })
    #expect(compiled.links.map(\.destination).contains("next.md"))
    #expect(compiled.blocks.contains { if case .quote = $0 { true } else { false } })
    #expect(
      compiled.blocks.contains { block in
        guard case .list(_, let list, _) = block else { return false }
        return list.kind == .ordered(start: 4)
      })
    #expect(
      compiled.blocks.contains { block in
        guard case .list(_, let list, _) = block else { return false }
        return list.items.map(\.checkbox) == [true, false]
      })
    #expect(
      compiled.blocks.contains { block in
        guard case .code(_, let language, let source, _) = block else { return false }
        return language == "swift" && source.contains("print")
      })
    #expect(
      compiled.blocks.contains { block in
        guard case .table(_, let table, _) = block else { return false }
        return table.alignments == [.leading, .center, .trailing]
          && table.header.count == 3
          && table.rows.count == 1
      })
    #expect(compiled.blocks.contains { if case .image = $0 { true } else { false } })
    #expect(compiled.blocks.contains { if case .rule = $0 { true } else { false } })
    #expect(compiled.blocks.contains { if case .html = $0 { true } else { false } })

    let paragraphRuns = compiled.blocks.compactMap { block -> [InlineRun]? in
      if case .paragraph(_, let runs, _) = block { return runs }
      return nil
    }.flatMap { $0 }
    #expect(paragraphRuns.contains { $0.traits.contains(.emphasis) })
    #expect(paragraphRuns.contains { $0.traits.contains(.strong) })
    #expect(paragraphRuns.contains { $0.traits.contains(.strikethrough) })
    #expect(paragraphRuns.contains { $0.traits.contains(.code) })
    #expect(!compiled.searchableText.matches(for: "HEADING").isEmpty)
  }

  // CommonMark 0.31.2 §2.5 allows 1–7 decimal or 1–6 hexadecimal digits in a
  // numeric reference; longer forms stay literal (STUI-1185). w2m cases are
  // repairs, w2n cases neighbours that must not change. Example 28's text is
  // CommonMark 0.31.2 by John MacFarlane, CC BY-SA 4.0.
  @Test("numeric references follow the CommonMark digit limits", arguments: textContractCases)
  func numericReferenceDigitLimits(_ testCase: TextContractCase) {
    let compiled = MarkdownCompiler().compile(source: testCase.source, sourceURL: nil)
    #expect(compiled.diagnostics.isEmpty, "\(testCase.id)")
    #expect(describe(compiled) == testCase.expected, "\(testCase.id)")
  }
}

// Wave-2 regression hunt, part CA (STUI-1165): neighbours of the STUI-1185
// correction. Cases w2ca022-w2ca024; the hypotheses precede these tests in the
// hunt's evidence directory.
@Suite("Wave-2 hunt CA: numeric reference correction neighbours")
struct Wave2RegressionHuntMarkdownTests {
  @Test("w2ca022 a reference before a trailing space and a soft break stays literal")
  func w2ca022ReferenceBeforeTrailingSpaceSoftBreakStaysLiteral() {
    let compiled = MarkdownCompiler().compile(source: "foo &#87654321; \nbar", sourceURL: nil)
    #expect(compiled.diagnostics.isEmpty)
    w2HuntKnown(
      """
      NEW-5: a reference before a trailing space and a soft break still decodes to U+FFFD; \
      cmark right-trims the text before a line ending but keeps its untrimmed end \
      column, so the source excerpt holds spaces the node text lacks and the \
      isolated-parse check rejects the correction; contract: CommonMark 0.31.2 §2.5, \
      858fc70, mrkdwn/README.md:145-150; adjacent STUI-1185
      """
    ) {
      #expect(describe(compiled) == #"p["foo &#87654321; bar"]"#)
    }
  }

  @Test("w2ca023 a reference before a two-space hard line break stays literal")
  func w2ca023ReferenceBeforeTwoSpaceHardBreakStaysLiteral() {
    let compiled = MarkdownCompiler().compile(source: "foo &#87654321;  \nbar", sourceURL: nil)
    #expect(compiled.diagnostics.isEmpty)
    w2HuntKnown(
      """
      NEW-5: a reference before a two-space hard line break still decodes to U+FFFD; \
      cmark right-trims the text before a line ending but keeps its untrimmed end \
      column, so the source excerpt holds spaces the node text lacks and the \
      isolated-parse check rejects the correction; contract: CommonMark 0.31.2 §2.5, \
      858fc70, mrkdwn/README.md:145-150; adjacent STUI-1185
      """
    ) {
      #expect(describe(compiled) == "p[\"foo &#87654321;\nbar\"]")
    }
  }

  @Test("w2ca024 a reference in an unchecked task-list item stays literal")
  func w2ca024TaskListItemReferenceStaysLiteral() throws {
    let compiled = MarkdownCompiler().compile(source: "- [ ] task &#87654321;", sourceURL: nil)
    #expect(compiled.diagnostics.isEmpty)
    guard case .list(_, let list, _) = try #require(compiled.blocks.first) else {
      Issue.record("expected a list, got \(describe(compiled))")
      return
    }
    let item = try #require(list.items.first)
    #expect(list.items.count == 1)
    #expect(item.checkbox == false)
    #expect(item.blocks.map(describe(block:)) == [#"p["task &#87654321;"]"#])
  }
}

/// Preserves an unmarked reproduction while guarding only confirmed assertions.
private func w2HuntKnown(_ comment: Comment, _ body: () -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_W2HUNT_UNMARKED"] == "1" {
    body()
  } else {
    withKnownIssue(comment) { body() }
  }
}

struct TextContractCase: Sendable, CustomTestStringConvertible {
  let id: String
  let source: String
  let expected: String
  var testDescription: String { id }
}

private let textContractCases: [TextContractCase] = [
  .init(id: "w2m01", source: "&#87654321;", expected: #"p["&#87654321;"]"#),
  .init(
    id: "w2m02", source: "&nbsp &x; &#; &#x;\n&#87654321;\n&#abcdef0;\n&ThisIsNotDefined; &hi?;\n",
    expected: #"p["&nbsp &x; &#; &#x; &#87654321; &#abcdef0; &ThisIsNotDefined; &hi?;"]"#),
  .init(id: "w2m03", source: "foo &#00000065; bar", expected: #"p["foo &#00000065; bar"]"#),
  .init(
    id: "w2m04", source: "&#x0000041; &#X0010FFFF;", expected: #"p["&#x0000041; &#X0010FFFF;"]"#),
  .init(
    id: "w2m05", source: "Tom &amp; Jerry &#87654321;",
    expected: #"p["Tom & Jerry &#87654321;"]"#),
  .init(
    id: "w2m06", source: "# Title &#87654321;",
    expected: #"h1["Title &#87654321;"] outline[Title &#87654321;]"#),
  .init(
    id: "w2m07", source: "*&#87654321;* [&#87654321;](/u)",
    expected: #"p["&#87654321;"/emphasis " " "&#87654321;"->/u] links[&#87654321;->/u]"#),
  .init(
    id: "w2m08", source: "| a |\n| - |\n| &#87654321; |",
    expected: #"table{["a"]|["&#87654321;"]}"#),
  .init(id: "w2m09", source: "![&#87654321;](i.png)", expected: "image[&#87654321;->i.png]"),
  .init(
    id: "w2m10", source: "> quote\n> &#87654321;", expected: #"quote{p["quote &#87654321;"]}"#),
  .init(
    id: "w2m11", source: "[link](/u) &#87654321; *em*",
    expected: #"p["link"->/u " &#87654321; " "em"/emphasis] links[link->/u]"#),
  .init(
    id: "w2m12", source: "`&#87654321;` and &#87654321;",
    expected: #"p["&#87654321;"/code " and &#87654321;"]"#),
  .init(
    id: "w2n01", source: "&#35; &#1234567; &#x10FFFF; &#x110000; &#xD800; &#X22;",
    expected: "p[\"# \u{FFFD} \u{10FFFF} \u{FFFD} \u{FFFD} \"\"]"),
  .init(
    id: "w2n02", source: "&#123456789; &#x123456789;",
    expected: #"p["&#123456789; &#x123456789;"]"#),
  .init(
    id: "w2n03", source: #"\&#87654321; &#38;#87654321;"#,
    expected: #"p["&#87654321; &#87654321;"]"#),
  .init(
    id: "w2n04", source: "`&#87654321;`\n\n    &#87654321;",
    expected: #"p["&#87654321;"/code] code()[&#87654321;]"#),
  .init(
    id: "w2n05", source: "*foo* £ €\n\n*$*alpha.",
    expected: #"p["foo"/emphasis " £ €"] p["*$*alpha."]"#),
]

private func describe(_ document: CompiledDocument) -> String {
  var parts = document.blocks.map(describe(block:))
  if !document.outline.isEmpty {
    parts.append("outline" + document.outline.map { "[\($0.title)]" }.joined())
  }
  if !document.links.isEmpty {
    parts.append("links" + document.links.map { "[\($0.label)->\($0.destination)]" }.joined())
  }
  return parts.joined(separator: " ")
}

private func describe(block: MarkdownBlock) -> String {
  switch block {
  case .heading(_, let level, _, let runs, _):
    "h\(level)" + describe(runs: runs)
  case .paragraph(_, let runs, _):
    "p" + describe(runs: runs)
  case .quote(_, let blocks, _):
    "quote{" + blocks.map(describe(block:)).joined(separator: " ") + "}"
  case .code(_, let language, let text, _):
    "code(\(language ?? ""))[\(text)]"
  case .table(_, let table, _):
    describe(table: table)
  case .image(_, let image, _):
    "image[\(image.altText)->\(image.source)]"
  default:
    "other[\(block.searchableText)]"
  }
}

private func describe(table: MarkdownTable) -> String {
  let cells = table.header + table.rows.flatMap { $0 }
  return "table{" + cells.map(describe(runs:)).joined(separator: "|") + "}"
}

private func describe(runs: [InlineRun]) -> String {
  let names: [(InlineTraits, String)] = [
    (.emphasis, "emphasis"), (.strong, "strong"), (.code, "code"),
    (.strikethrough, "strikethrough"), (.html, "html"),
  ]
  let described = runs.map { run in
    let traits = names.filter { run.traits.contains($0.0) }.map { "/" + $0.1 }.joined()
    return "\"\(run.text)\"" + traits + (run.destination.map { "->" + $0 } ?? "")
  }
  return "[" + described.joined(separator: " ") + "]"
}

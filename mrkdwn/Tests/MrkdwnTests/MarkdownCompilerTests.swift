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
}

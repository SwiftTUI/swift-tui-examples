import Foundation
import Mrkdwn
import MrkdwnMermaid
import Testing

@Suite("mrkdwn smoke")
struct SmokeTests {
  @Test("full surface compiles and Mermaid renders")
  func fullSurface() throws {
    let url = try #require(
      Bundle.module.url(
        forResource: "full-surface",
        withExtension: "md",
        subdirectory: "Fixtures"
      )
    )
    let source = try String(contentsOf: url, encoding: .utf8)
    let compiled = MarkdownCompiler().compile(source: source, sourceURL: url)

    #expect(compiled.outline.map(\.anchor) == ["full-surface"])
    #expect(
      compiled.blocks.contains { block in
        if case .mermaid = block { return true }
        return false
      })

    let report = MermaidRenderer().renderSurface(
      "flowchart LR\nA[Start] --> B[Finish]",
      forWidth: 60
    )
    #expect(report.output != nil)
  }
}

import Foundation
import Mrkdwn
import Testing

@Suite("mrkdwn smoke")
struct SmokeTests {
  @Test("full surface compiles")
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
    #expect(compiled.blocks.contains { if case .code = $0 { true } else { false } })
  }
}

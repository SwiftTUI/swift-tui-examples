import Foundation
import Testing

@testable import Mrkdwn

// Reduced from CommonMark 0.31.2 examples 28 and 354 by John MacFarlane.
// The example text is licensed CC BY-SA 4.0:
// https://spec.commonmark.org/0.31.2/ and https://creativecommons.org/licenses/by-sa/4.0/
// These are reducers of the supplemental census, not additional set-A scenario IDs.
@Suite("Campaign E1 CommonMark census reducers", .serialized)
struct AdversarialSetACommonMarkCensusRegressionTests {
  @Test(arguments: [28, 354])
  func corpusReducer(id: Int) throws {
    let source = id == 28 ? "&#87654321;" : "*£*bravo."
    let compiled = MarkdownCompiler().compile(source: source, sourceURL: nil)
    #expect(compiled.diagnostics.isEmpty)
    #expect(compiled.links.isEmpty)
    #expect(compiled.blocks.count == 1)
    let block = try #require(compiled.blocks.first)
    guard case .paragraph(_, let runs, _) = block else {
      Issue.record("CommonMark reducer must produce a paragraph")
      return
    }
    if id == 28 {
      #expect(runs.map(\.text).joined() == source)
      #expect(runs.allSatisfy { $0.traits.isEmpty })
    } else {
      e1CensusKnown("STUI-1186: cm354 omits Unicode symbols from delimiter punctuation") {
        #expect(runs.map(\.text).joined() == source)
        #expect(runs.allSatisfy { $0.traits.isEmpty })
      }
    }
    #expect(runs.allSatisfy { $0.destination == nil && $0.image == nil })
  }
}

private func e1CensusKnown(_ comment: Comment, _ body: () -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_E1_UNMARKED"] == "1" {
    body()
  } else {
    withKnownIssue(comment) { body() }
  }
}

import Foundation
import Testing

@testable import GitViz

@Suite("ProcessGitRunner")
struct ProcessGitRunnerTests {
  /// A fast `git` exits before its pipe readers have necessarily started, so
  /// the runner must join them by completion rather than by "is running";
  /// otherwise it returns an empty buffer for a successful command.
  @Test func fastCommandsAlwaysReturnTheirOutput() throws {
    let runner = ProcessGitRunner()
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    for attempt in 0..<300 {
      let output = try runner.run(["--version"], in: directory)
      #expect(output.hasPrefix("git version"), "attempt \(attempt): \(output.debugDescription)")
      if !output.hasPrefix("git version") { break }
    }
  }
}

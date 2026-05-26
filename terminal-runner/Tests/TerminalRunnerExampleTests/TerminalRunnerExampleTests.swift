import Foundation
import Testing

struct TerminalRunnerExampleTests {
  @Test("example imports SwiftTUICLI and controls TerminalRunner directly")
  func exampleControlsTerminalRunnerDirectly() throws {
    let source = try sourceText()

    #expect(source.contains("import SwiftTUICLI\n"))
    #expect(source.contains("TerminalRunner.run(Self.self, configuration: configuration)"))
    #expect(source.contains("RuntimeConfiguration.detect("))
    #expect(!source.contains("import SwiftTUI\n"))
    #expect(!source.contains("SwiftTUICommand"))
  }

  @Test("example rejects web-host arguments before launch")
  func exampleRejectsWebArgumentsBeforeLaunch() throws {
    let source = try sourceText()

    #expect(source.contains("argument == \"--web\""))
    #expect(source.contains("argument.hasPrefix(\"--web=\")"))
    #expect(source.contains("TerminalRunnerExampleError.webUnsupported"))
    #expect(!source.contains("SwiftTUIWebHostCLI"))
  }

  private func sourceText() throws -> String {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/TerminalRunnerExample/main.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}

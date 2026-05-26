import Foundation
import SwiftTUICLI

@main
struct TerminalRunnerExampleApp: App {
  init() {}

  var body: some Scene {
    WindowGroup("Terminal Runner", id: WindowIdentifier("main")) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Terminal Runner")
          .bold()
        Divider()
        Text("Explicit TerminalRunner launch")
        LabeledContent("Host", value: "terminal")
        LabeledContent("WebHost", value: "rejected before launch")
        LabeledContent("Config", value: "environment-aware")
      }
      .padding(.init(horizontal: 1, vertical: 0))
    }
  }

  @MainActor
  static func main() async throws {
    guard !argumentsRequestWebHost(CommandLine.arguments) else {
      throw TerminalRunnerExampleError.webUnsupported
    }

    let configuration = RuntimeConfiguration.detect(
      environment: ProcessInfo.processInfo.environment,
      isStdoutTTY: RenderOnce.standardOutputIsTTY()
    )
    try await TerminalRunner.run(Self.self, configuration: configuration)
  }

  private static func argumentsRequestWebHost(_ arguments: [String]) -> Bool {
    arguments.dropFirst().contains { argument in
      argument == "--web" || argument.hasPrefix("--web=")
    }
  }
}

enum TerminalRunnerExampleError: Error, CustomStringConvertible, LocalizedError {
  case webUnsupported

  var description: String {
    "terminal-runner is terminal-only. Remove --web, or use WebHostExample for browser hosting."
  }

  var errorDescription: String? {
    description
  }
}

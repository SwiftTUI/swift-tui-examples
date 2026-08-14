import ExampleScenes
import Foundation
import SwiftTUICLI

@main
struct PreviewReadinessTerminalCommand {
  @MainActor
  static func main() async throws {
    let configuration = RuntimeConfiguration.detect(
      environment: ProcessInfo.processInfo.environment,
      isStdoutTTY: RenderOnce.standardOutputIsTTY()
    )
    try await TerminalRunner.run(PreviewReadinessApp.self, configuration: configuration)
  }
}

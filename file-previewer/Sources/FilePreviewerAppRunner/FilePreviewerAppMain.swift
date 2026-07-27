import FilePreviewerApp
import Foundation
import SwiftTUI
import SwiftTUICLI
import SwiftTUIRuntime

@main
struct FilePreviewerAppMain: SwiftTUIRuntime.App {
  @MainActor private static var configuredRoot: FilePreviewerRootView?

  var body: some Scene {
    WindowGroup("File Previewer") {
      Self.configuredRoot ?? FilePreviewerRootView()
    }
  }

  @MainActor
  static func main() async throws {
    let root = FilePreviewerRootView()
    configuredRoot = root
    let configuration = RuntimeConfiguration.detect(
      environment: ProcessInfo.processInfo.environment,
      isStdoutTTY: RenderOnce.standardOutputIsTTY()
    )
    do {
      try await TerminalRunner.run(Self.self, configuration: configuration)
    } catch {
      await root.shutdown()
      throw error
    }
    await root.shutdown()
  }
}

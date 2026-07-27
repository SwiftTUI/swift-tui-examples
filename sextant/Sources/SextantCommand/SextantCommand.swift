import Sextant
import Foundation
import SwiftTUI
import SwiftTUICLI
import SwiftTUIRuntime

@main
struct SextantCommand: SwiftTUI.App {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "sextant",
    abstract: "Inspect files and directories with preview-first terminal navigation.",
    subcommands: [CompletionsCommand.self]
  )

  @MainActor private static var configuredRoot: SextantRootView?

  var body: some Scene {
    WindowGroup("Sextant") {
      Self.configuredRoot ?? SextantRootView()
    }
  }

  mutating func run() async throws {
    let root = SextantRootView()
    Self.configuredRoot = root
    do {
      try await TerminalRunner.run(
        self,
        configuration: runtimeConfiguration(
          environment: ProcessInfo.processInfo.environment,
          isStdoutTTY: RenderOnce.standardOutputIsTTY()
        )
      )
    } catch {
      await root.shutdown()
      throw error
    }
    await root.shutdown()
  }

  @MainActor
  static func main() async {
    do {
      var parsedCommand = try parseSwiftTUIRootCommand()
      if let script = completionScript(forParsedCommand: parsedCommand) {
        FileHandle.standardOutput.write(Data(script.utf8))
        return
      }
      if let installedPath = try installCompletionScript(forParsedCommand: parsedCommand) {
        FileHandle.standardOutput.write(Data("Installed completion script at \(installedPath)\n".utf8))
        return
      }
      guard var command = parsedCommand as? Self else {
        try parsedCommand.run()
        return
      }

      try await command.run()
    } catch {
      exit(withError: error)
    }
  }
}

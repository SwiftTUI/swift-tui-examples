import Foundation
import Mrkdwn
import SwiftTUI
import SwiftTUICLI
import SwiftTUIProfiling
import SwiftTUIRuntime

@main
struct MrkdwnCommand: SwiftTUI.App {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "mrkdwn",
    abstract: "Read Markdown in a responsive terminal viewer.",
    version: "0.1.0",
    subcommands: [CompletionsCommand.self]
  )

  @MainActor private static var configuredRoot: MrkdwnRootView?

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  @Argument(help: "Markdown file to read, or '-' for standard input. Defaults to README.md.")
  var file: String? = nil

  @Option(name: .long, help: "Read the theme from this path.")
  var config: String? = nil

  @Flag(name: .customLong("no-config"), help: "Use the built-in theme only.")
  var noConfig = false

  @Flag(name: .long, help: "Watch a regular file for changes.")
  var watch = false

  @Flag(name: .customLong("no-watch"), help: "Disable live file watching.")
  var noWatch = false

  @Flag(
    name: .customLong("allow-remote-images"),
    help: "Allow bounded HTTP(S) images from literal public IP addresses."
  )
  var allowRemoteImages = false

  @Flag(
    name: .customLong("print-default-theme"),
    help: "Print the complete built-in theme as TOML and exit."
  )
  var printDefaultTheme = false

  var body: some Scene {
    WindowGroup("mrkdwn") {
      if let root = Self.configuredRoot {
        root
      } else {
        Text("mrkdwn launch was not configured")
      }
    }
    .exitOnKeys(CommandCatalog.runtimeExitKeys)
    // Env-gated: a complete no-op unless SWIFTTUI_PROFILE is set.
    .profiling()
  }

  mutating func run() async throws {
    if printDefaultTheme {
      FileHandle.standardOutput.write(Data(ViewerTheme.defaultTOML.utf8))
      return
    }
    guard !(noConfig && config != nil) else {
      throw ValidationError("--config and --no-config cannot be used together")
    }
    guard !(watch && noWatch) else {
      throw ValidationError("--watch and --no-watch cannot be used together")
    }
    let fileManager = FileManager.default
    let environment = ProcessInfo.processInfo.environment
    let isStdoutTTY = RenderOnce.standardOutputIsTTY()
    let resolvedRuntimeConfiguration = runtimeConfiguration(
      environment: environment,
      isStdoutTTY: isStdoutTTY
    )
    let currentDirectory = URL(
      fileURLWithPath: fileManager.currentDirectoryPath,
      isDirectory: true
    )
    let themeSelection = ThemePaths().resolve(
      explicitPath: config,
      noConfig: noConfig,
      environment: environment,
      currentDirectory: currentDirectory,
      homeDirectory: fileManager.homeDirectoryForCurrentUser
    )

    // Both reads are launch preflight: errors appear before the runtime takes
    // over terminal modes or paints the alternate screen.
    let loadedTheme = try ThemeRepository().load(themeSelection)
    let sourceReader = DocumentSource()
    let snapshot: DocumentSnapshot
    let watchesDocument: Bool
    var terminalInputLease: TerminalInputLease?
    if file == "-" {
      guard !watch else {
        throw ValidationError("--watch requires a regular file, not standard input")
      }
      if isStdoutTTY {
        terminalInputLease = try TerminalInputLease()
      }
      snapshot = try sourceReader.readStandardInput()
      try terminalInputLease?.activateControllingTerminal()
      watchesDocument = false
    } else {
      let path = file ?? "README.md"
      let url = URL(
        fileURLWithPath: path,
        relativeTo: currentDirectory
      ).standardizedFileURL
      snapshot = try sourceReader.read(fileURL: url)
      watchesDocument = !noWatch
    }

    let model = ViewerModel(
      snapshot: snapshot,
      theme: loadedTheme.theme,
      themeSelection: themeSelection,
      watchesDocument: watchesDocument,
      allowsRemoteImages: allowRemoteImages
    )
    // Complete the first app-owned document commit before the terminal run
    // loop takes over. A view lifecycle task still provides the reusable-view
    // entry point, while `start()` remains idempotent for this executable path.
    await model.start()
    let root = MrkdwnRootView(model: model)
    Self.configuredRoot = root
    defer { try? terminalInputLease?.restore() }
    do {
      try await TerminalRunner.run(
        self,
        configuration: resolvedRuntimeConfiguration
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
        FileHandle.standardOutput.write(
          Data("Installed completion script at \(installedPath)\n".utf8)
        )
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

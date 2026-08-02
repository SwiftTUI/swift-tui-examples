import CSVUI
import Foundation
import SwiftTUI
import SwiftTUICLI
import SwiftTUIProfiling
import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@main
struct CSVUICommand: SwiftTUI.App {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "csvui",
    abstract: "Inspect and safely edit CSV or TSV files in the terminal.",
    version: "0.1.0",
    subcommands: [CompletionsCommand.self]
  )

  @MainActor private static var configuredRoot: CSVRootView?

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  @Argument(help: "Delimited file to read, or '-' for standard input.")
  var file: String? = nil

  @Option(name: .long, help: "Delimiter: comma, tab, semicolon, pipe, or one ASCII character.")
  var delimiter: String? = nil

  @Flag(name: .customLong("no-headers"), help: "Treat the first record as data.")
  var noHeaders = false

  @Flag(name: .customLong("read-only"), help: "Disable all document mutations.")
  var readOnly = false

  @Option(name: .long, help: "Read the theme from this path.")
  var config: String? = nil

  @Flag(name: .customLong("no-config"), help: "Use the built-in theme only.")
  var noConfig = false

  @Flag(name: .long, help: "Watch a regular file for changes (the default).")
  var watch = false

  @Flag(name: .customLong("no-watch"), help: "Disable live file watching.")
  var noWatch = false

  @Flag(
    name: .customLong("print-default-theme"),
    help: "Print the complete built-in theme as TOML and exit."
  )
  var printDefaultTheme = false

  var body: some Scene {
    WindowGroup("csvui") {
      if let root = Self.configuredRoot {
        root
      } else {
        Text("csvui launch was not configured")
      }
    }
    .exitOnKeys(CSVCommandCatalog.runtimeExitKeys)
    .profiling()
  }

  mutating func run() async throws {
    if printDefaultTheme {
      FileHandle.standardOutput.write(Data(CSVTheme.defaultTOML.utf8))
      return
    }
    guard !(noConfig && config != nil) else {
      throw ValidationError("--config and --no-config cannot be used together")
    }
    guard !(watch && noWatch) else {
      throw ValidationError("--watch and --no-watch cannot be used together")
    }
    guard RenderOnce.standardOutputIsTTY() else {
      throw ValidationError("interactive csvui requires a TTY output")
    }

    let fileManager = FileManager.default
    let currentDirectory = URL(
      fileURLWithPath: fileManager.currentDirectoryPath,
      isDirectory: true
    )
    let environment = ProcessInfo.processInfo.environment
    let themeSelection = CSVThemePaths().resolve(
      explicitPath: config,
      noConfig: noConfig,
      environment: environment,
      currentDirectory: currentDirectory,
      homeDirectory: fileManager.homeDirectoryForCurrentUser
    )
    let loadedTheme = try CSVThemeRepository().load(themeSelection)

    let sourceArgument: String
    if let file {
      sourceArgument = file
    } else if isatty(STDIN_FILENO) == 0 {
      sourceArgument = "-"
    } else {
      throw ValidationError("provide FILE or pipe a CSV/TSV document on standard input")
    }
    if sourceArgument == "-", watch {
      throw ValidationError("--watch requires a regular file, not standard input")
    }

    let sourceReader = CSVSourceReader()
    let source: CSVSourceSnapshot
    var terminalInputLease: CSVTerminalInputLease?
    if sourceArgument == "-" {
      terminalInputLease = try CSVTerminalInputLease()
      source = try sourceReader.readStandardInput()
      try terminalInputLease?.activateControllingTerminal()
    } else {
      let url = URL(
        fileURLWithPath: sourceArgument,
        relativeTo: currentDirectory
      ).standardizedFileURL
      source = try sourceReader.read(fileURL: url)
    }

    let resolvedDelimiter: CSVDelimiter
    var detectionDiagnostic: CSVDiagnostic?
    if let delimiter {
      do { resolvedDelimiter = try CSVDelimiter.parse(delimiter) } catch {
        throw ValidationError(error.localizedDescription)
      }
    } else if sourceArgument != "-", sourceArgument.lowercased().hasSuffix(".tsv") {
      resolvedDelimiter = .tab
    } else if sourceArgument != "-", sourceArgument.lowercased().hasSuffix(".csv") {
      resolvedDelimiter = .comma
    } else {
      let detection = CSVDelimiterDetector().detect(source.bytes)
      resolvedDelimiter = detection.delimiter
      if detection.usedDefault || detection.wasAmbiguous {
        detectionDiagnostic = CSVDiagnostic(
          .information,
          "delimiter guessed: \(detection.delimiter.description)"
        )
      }
    }

    let placeholder = try CSVDocument.parse(
      source: CSVSourceSnapshot(
        origin: .standardInput,
        displayName: source.displayName,
        bytes: Data()
      ),
      delimiter: resolvedDelimiter,
      hasHeaders: !noHeaders
    )
    let model = CSVModel(
      document: placeholder,
      theme: loadedTheme.theme,
      readOnly: readOnly,
      configuration: CSVModelConfiguration(
        watchesDocument: sourceArgument != "-" && !noWatch,
        themeSelection: themeSelection,
        workingDirectory: currentDirectory
      )
    )
    model.loadInitial(
      source: source,
      delimiter: resolvedDelimiter,
      hasHeaders: !noHeaders,
      initialDiagnostic: detectionDiagnostic
    )
    let root = CSVRootView(model: model)
    Self.configuredRoot = root
    defer { try? terminalInputLease?.restore() }
    let runtimeConfiguration = runtimeConfiguration(
      environment: environment,
      isStdoutTTY: true
    )
    do {
      try await TerminalRunner.run(self, configuration: runtimeConfiguration)
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
      if let path = try installCompletionScript(forParsedCommand: parsedCommand) {
        FileHandle.standardOutput.write(Data("Installed completion script at \(path)\n".utf8))
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

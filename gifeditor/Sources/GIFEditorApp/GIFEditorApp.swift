import Foundation
import GIFEditor
import SwiftTUI
import SwiftTUIWebHostCLI

// `SwiftTUI.App` is spelled out because importing `SwiftTUIWebHostCLI` for
// the runner also re-exports `SwiftTUIRuntime.App`, and the two names would
// otherwise be ambiguous. The batteries-included one is the one that carries
// the command surface.
@main
struct GIFEditorApp: SwiftTUI.App, SwiftTUICommand {

  /// The headless subcommands sit beside `completions` rather than under a
  /// group verb: `halfcell info x.gif` is what a script writes, and every
  /// extra level is another thing to remember. The root command with no
  /// subcommand stays the editor, so the interactive path is unchanged.
  ///
  /// Registering them here is what makes `--help` list them and what the
  /// generated completion scripts are built from; it is *not* what routes
  /// them. See ``main()``.
  nonisolated static let configuration = CommandConfiguration(
    commandName: "gifeditor",
    abstract: "Edit a GIF in the terminal.",
    subcommands: [
      CompletionsCommand.self,
      InfoCommand.self,
      OptimizeCommand.self,
      ExportCommand.self,
    ]
  )

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  @Argument(help: "Path to a GIF file. Omit to start with a blank 32×32 document.")
  var path: String?

  var body: some Scene {
    WindowGroup {
      GIFEditor(path: path)
    }
    .exitOnKeys([
      KeyPress(.character("q"), modifiers: .ctrl)
    ])
  }

  /// Why this app spells out an entry point instead of inheriting
  /// `SwiftTUI.App`'s.
  ///
  /// A root command that declares a positional argument shadows its own
  /// subcommands: swift-argument-parser binds a leading bare value to
  /// `<path>` before it looks for a verb, so `gifeditor info x.gif` parses
  /// as "open the file named `info`". SwiftTUI already works around this for
  /// `completions`, by matching that verb against the raw arguments inside
  /// `parseSwiftTUIRootCommand` — but that hook knows only its own verb, and
  /// it is not a protocol requirement, so an app cannot extend it.
  ///
  /// So the headless verbs get the same treatment one level up, and the rest
  /// of this function is the framework's launch sequence: resolve
  /// completions, then hand the parsed app to the runner. Every piece of it
  /// is public API of `SwiftTUIArguments` / `SwiftTUIWebHostCLI`; the cost of
  /// restating it here is that a future change to that sequence has to be
  /// mirrored, which is why it is kept to the shape it has upstream.
  static func main() async {
    HeadlessDispatch.runIfRequested()

    do {
      var command = try parseSwiftTUIRootCommand()
      if let script = completionScript(forParsedCommand: command) {
        print(script, terminator: "")
        return
      }
      if let installedPath = try installCompletionScript(forParsedCommand: command) {
        print("Installed completion script at \(installedPath)")
        return
      }
      if let appCommand = command as? Self {
        try await WebHostCLIRunner.run(
          appCommand,
          configuration: appCommand.runtimeConfiguration()
        )
        return
      }
      try command.run()
    } catch {
      Self.exit(withError: error)
    }
  }
}

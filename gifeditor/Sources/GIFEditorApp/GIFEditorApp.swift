import GIFEditor
import SwiftTUI

@main
struct GIFEditorApp: App, SwiftTUICommand {

  /// The headless subcommands sit beside `completions` rather than under a
  /// group verb: `halfcell info x.gif` is what a script writes, and every
  /// extra level is another thing to remember. The root command with no
  /// subcommand stays the editor, so the interactive path is unchanged.
  ///
  /// Registering them here is what makes `--help` list them and what the
  /// generated completion scripts are built from; it is *not* what routes
  /// them. See ``swiftTUIRootSubcommand(forRawArguments:)``.
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

  /// Routes `gifeditor info x.gif` to the `info` verb rather than to the
  /// editor with a file named `info`.
  ///
  /// A root command that declares a positional argument shadows its own
  /// subcommands: swift-argument-parser binds a leading bare value to
  /// `<path>` before it looks for a verb. This claims the verb from the raw
  /// arguments first, which is the same move SwiftTUI has always made for
  /// `completions` — and `completions` is still resolved by the framework
  /// ahead of this, so it cannot be shadowed here.
  nonisolated static func swiftTUIRootSubcommand(
    forRawArguments arguments: [String]
  ) throws -> (any ParsableCommand)? {
    try registeredSubcommand(forRawArguments: arguments)
  }
}

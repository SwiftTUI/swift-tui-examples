import Foundation
import SwiftTUI
import Testing

@testable import Sextant

@Suite("Command catalog")
struct CommandCatalogTests {
  @Test("identifiers and default chords are unique")
  func uniqueness() {
    let commands = CommandCatalog().commands
    #expect(Set(commands.map(\.id)).count == commands.count)
    #expect(Set(commands.map(\.defaultChord)).count == commands.count)
  }

  @Test("selection actions explain why they are disabled")
  func disabledReasons() {
    let context = CommandContext(
      hasSelection: false,
      hasPreview: false,
      previewFocused: false,
      hasRootRelativeSelection: false
    )
    let catalog = CommandCatalog()
    let open = catalog.command(id: CommandID("workflow.open"))
    let preview = catalog.command(id: CommandID("preview.toggle"))
    #expect(open?.availability(context).isEnabled == false)
    #expect(open?.availability(context).disabledReason != nil)
    #expect(preview?.availability(context).isEnabled == false)
    #expect(preview?.availability(context).disabledReason != nil)
  }

  @Test("validated overrides replace dispatch and presentation together")
  func keyOverrides() throws {
    let catalog = try CommandCatalog().applyingKeyOverrides([
      "navigation.up": "Ctrl-U"
    ])
    let context = CommandContext(
      hasSelection: true,
      hasPreview: true,
      previewFocused: false,
      hasRootRelativeSelection: true
    )

    #expect(
      catalog.command(
        for: KeyPress(.character("u"), modifiers: .ctrl),
        context: context
      )?.0.id == CommandID("navigation.up")
    )
    #expect(
      catalog.command(
        for: KeyPress(.arrowUp),
        context: context
      ) == nil
    )
    #expect(catalog.markdown().contains("| `Ctrl-U` | Move selection up |"))
  }

  @Test("runtime-owned commands reject ineffective key overrides")
  func runtimeOwnedOverride() {
    #expect(
      throws: ConfigurationFailure.runtimeOwnedKeyOverride("application.quit")
    ) {
      _ = try CommandCatalog().applyingKeyOverrides([
        "application.quit": "x"
      ])
    }
  }

  @Test("quit keys fall through to the application runtime")
  func runtimeOwnedQuit() {
    let context = CommandContext(
      hasSelection: false,
      hasPreview: false,
      previewFocused: false,
      hasRootRelativeSelection: false
    )
    let catalog = CommandCatalog()

    for keyPress in [
      KeyPress(.character("q")),
      KeyPress(.character("d"), modifiers: .ctrl),
    ] {
      let command = catalog.command(for: keyPress, context: context)?.0
      #expect(command?.action == .quit)
      #expect(command?.dispatchOwnership == .applicationRuntime)
    }
  }

  @Test("bookmark binding requires a selection")
  func bookmarkBinding() {
    let command = CommandCatalog().command(id: CommandID("workflow.bookmark"))
    #expect(command?.keyPresses == [KeyPress(.character("b"))])
    #expect(
      command?.availability(
        CommandContext(
          hasSelection: false,
          hasPreview: false,
          previewFocused: false,
          hasRootRelativeSelection: false
        )
      ).isEnabled == false
    )
  }

  @Test("checked-in keybindings match generated catalog output")
  func generatedDocument() throws {
    let sourceFile = URL(fileURLWithPath: #filePath)
    let packageRoot =
      sourceFile
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let checkedIn = try String(
      contentsOf: packageRoot.appendingPathComponent("docs/KEYBINDINGS.md"),
      encoding: .utf8
    )
    #expect(checkedIn == CommandCatalog().markdown())
  }
}

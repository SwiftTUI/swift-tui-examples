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

  @Test(
    "shifted characters dispatch as terminals actually report them",
    arguments: [
      ("?", "view.help"),
      ("G", "navigation.last"),
      ("R", "workflow.reveal"),
      ("Y", "workflow.copy-relative"),
    ])
  func shiftedCharacterBindings(character: String, commandID: String) throws {
    // A terminal never reports shift for a printable key — the shifted glyph
    // is the whole report — so `?` arrives with no modifiers at all. Both
    // spellings have to land on the same command.
    let context = CommandContext(
      hasSelection: true,
      hasPreview: true,
      previewFocused: false,
      hasRootRelativeSelection: true
    )
    let catalog = CommandCatalog()
    let key = try #require(character.first)

    #expect(
      catalog.command(for: KeyPress(.character(key)), context: context)?.0.id
        == CommandID(commandID)
    )
    #expect(
      catalog.command(
        for: KeyPress(.character(key), modifiers: .shift),
        context: context
      )?.0.id == CommandID(commandID)
    )
  }

  @Test("ctrl and alt stay significant when shift is normalized away")
  func modifiersOtherThanShiftSurvive() {
    let context = CommandContext(
      hasSelection: true,
      hasPreview: true,
      previewFocused: false,
      hasRootRelativeSelection: true
    )
    let catalog = CommandCatalog()

    // `r` refreshes; Ctrl-R must not be mistaken for it.
    #expect(
      catalog.command(for: KeyPress(.character("r")), context: context)?.0.id
        == CommandID("view.refresh")
    )
    #expect(
      catalog.command(
        for: KeyPress(.character("r"), modifiers: .ctrl),
        context: context
      ) == nil
    )
  }

  @Test("right arrow and Return are separate commands")
  func advanceIsDistinctFromEnter() {
    let context = CommandContext(
      hasSelection: true,
      hasPreview: true,
      previewFocused: false,
      hasRootRelativeSelection: true
    )
    let catalog = CommandCatalog()

    for keyPress in [KeyPress(.arrowRight), KeyPress(.character("l"))] {
      #expect(catalog.command(for: keyPress, context: context)?.0.action == .advance)
    }
    #expect(
      catalog.command(for: KeyPress(.return), context: context)?.0.action == .enter
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

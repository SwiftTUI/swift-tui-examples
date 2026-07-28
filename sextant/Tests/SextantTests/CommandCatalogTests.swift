import Foundation
import SwiftTUI
import Testing

@testable import Sextant

@Suite("Command catalog")
struct CommandCatalogTests {
  private func context(
    hasSelection: Bool = true,
    hasPreview: Bool = true,
    previewFocused: Bool = false,
    hasRootRelativeSelection: Bool = true,
    showsHiddenFiles: Bool = false,
    isOverlayPresented: Bool = false
  ) -> CommandContext {
    CommandContext(
      hasSelection: hasSelection,
      hasPreview: hasPreview,
      previewFocused: previewFocused,
      hasRootRelativeSelection: hasRootRelativeSelection,
      showsHiddenFiles: showsHiddenFiles,
      isOverlayPresented: isOverlayPresented
    )
  }

  /// `BrowserAction` is not `Equatable` — it carries snapshots and stream
  /// events — so assertions compare a short shape of the dispatched action.
  private func action(_ dispatch: CommandDispatch?) -> String {
    guard case .perform(let action)? = dispatch else {
      return "none"
    }
    return switch action {
    case .focusBrowser: "focusBrowser"
    case .focusPreview: "focusPreview"
    case .setHidden(let isOn): "setHidden(\(isOn))"
    case .moveSelection(let movement): "moveSelection(\(movement))"
    case .performHandoff(let command): "handoff(\(command))"
    case .showFilter: "showFilter"
    case .showPalette: "showPalette"
    case .showSearch: "showSearch"
    case .toggleBookmark: "bookmark"
    case .refresh: "refresh"
    case .advanceIntoSelected: "advance"
    case .enterSelected: "enter"
    case .moveToParent: "parent"
    case .showHelp: "help"
    default: "other"
    }
  }

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

  @Test("preview focus keeps preview commands live and browser commands out")
  func previewFocusedDispatch() {
    let catalog = CommandCatalog()
    let focused = context(previewFocused: true)

    // Tab was unreachable for as long as the caller answered the focus
    // question before the catalog was consulted; Escape only worked because
    // it was re-implemented outside the catalog twice.
    #expect(action(catalog.dispatch(KeyPress(.tab), context: focused)) == "focusBrowser")
    #expect(action(catalog.dispatch(KeyPress(.escape), context: focused)) == "focusBrowser")

    // Browser bindings stay out; those keys belong to the preview surface.
    #expect(catalog.dispatch(KeyPress(.arrowDown), context: focused) == nil)
    #expect(catalog.dispatch(KeyPress(.character("/")), context: focused) == nil)
  }

  @Test("the same toggle key moves focus the other way from the browser")
  func toggleSurfaceResolvesAgainstFocus() {
    let catalog = CommandCatalog()
    #expect(
      action(catalog.dispatch(KeyPress(.tab), context: context(previewFocused: false)))
        == "focusPreview"
    )
    #expect(
      action(catalog.dispatch(KeyPress(.tab), context: context(previewFocused: true)))
        == "focusBrowser"
    )
  }

  @Test("hidden-file toggling inverts the policy it is given")
  func toggleHiddenInvertsContext() {
    let catalog = CommandCatalog()
    #expect(
      action(
        catalog.dispatch(
          KeyPress(.character(".")),
          context: context(showsHiddenFiles: false)
        )
      ) == "setHidden(true)"
    )
    #expect(
      action(
        catalog.dispatch(
          KeyPress(.character(".")),
          context: context(showsHiddenFiles: true)
        )
      ) == "setHidden(false)"
    )
  }

  @Test("an overlay owns the keyboard while it is up")
  func overlaySuppressesBindings() {
    let catalog = CommandCatalog()
    let overlaid = context(isOverlayPresented: true)
    for keyPress in [
      KeyPress(.arrowDown), KeyPress(.tab), KeyPress(.character("/")),
      KeyPress(.character("o")),
    ] {
      #expect(catalog.dispatch(keyPress, context: overlaid) == nil)
    }
  }

  @Test("dispatch reports why a binding is unusable instead of dropping it")
  func unavailableBindingsExplainThemselves() {
    let catalog = CommandCatalog()
    guard
      case .unavailable(let reason)? = catalog.dispatch(
        KeyPress(.character("o")),
        context: context(hasSelection: false)
      )
    else {
      Issue.record("open should be unavailable without a selection")
      return
    }
    #expect(reason == "Select an item first.")
  }

  @Test("exit keys are the catalog's runtime-owned bindings, not a copy")
  func runtimeExitKeysAreDerived() {
    let catalog = CommandCatalog()
    let quit = catalog.command(id: CommandID("application.quit"))

    #expect(CommandCatalog.runtimeExitKeys == quit?.keyPresses)
    #expect(!CommandCatalog.runtimeExitKeys.isEmpty)
    for keyPress in CommandCatalog.runtimeExitKeys {
      guard case .runtimeOwned? = catalog.dispatch(keyPress, context: context())
      else {
        Issue.record("\(keyPress) should stay with the application runtime")
        return
      }
    }
  }

  @Test("workflow keys reach the model as handoff requests")
  func handoffBindingsCarryTheirCommand() {
    let catalog = CommandCatalog()
    let ready = context()
    #expect(action(catalog.dispatch(KeyPress(.character("o")), context: ready)) == "handoff(open)")
    #expect(action(catalog.dispatch(KeyPress(.character("e")), context: ready)) == "handoff(edit)")
    #expect(
      action(catalog.dispatch(KeyPress(.character("R")), context: ready))
        == "handoff(reveal)"
    )
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

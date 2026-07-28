public import SwiftTUI

public struct CommandID: Hashable, Sendable {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }
}

public enum CommandSection: String, CaseIterable, Sendable {
  case navigation = "Navigation"
  case preview = "Preview"
  case view = "View"
  case workflow = "Workflow"
  case application = "Application"
}

enum SextantCommandAction: Equatable, Sendable {
  case moveUp
  case moveDown
  case moveParent
  case advance
  case enter
  case first
  case last
  case pageUp
  case pageDown
  case toggleSurface
  case focusBrowser
  case filter
  case toggleHidden
  case refresh
  case help
  case palette
  case search
  case bookmark
  case handoff(BrowserHandoffCommand)
  case quit
}

extension SextantCommandAction {
  /// The browser effect this command amounts to in `context`.
  ///
  /// Two commands are a question about current state rather than a fixed
  /// effect — `toggleSurface` depends on which surface holds focus, and
  /// `toggleHidden` on the policy it is inverting — so resolution reads the
  /// context instead of the model. `nil` means no browser effect: the scene
  /// owns exit.
  func browserAction(in context: CommandContext) -> BrowserAction? {
    switch self {
    case .moveUp: .moveSelection(.offset(-1))
    case .moveDown: .moveSelection(.offset(1))
    case .pageUp: .moveSelection(.offset(-10))
    case .pageDown: .moveSelection(.offset(10))
    case .first: .moveSelection(.first)
    case .last: .moveSelection(.last)
    case .moveParent: .moveToParent
    case .advance: .advanceIntoSelected
    case .enter: .enterSelected
    case .toggleSurface: context.previewFocused ? .focusBrowser : .focusPreview
    case .focusBrowser: .focusBrowser
    case .filter: .showFilter
    case .toggleHidden: .setHidden(!context.showsHiddenFiles)
    case .refresh: .refresh
    case .help: .showHelp
    case .palette: .showPalette
    case .search: .showSearch
    case .bookmark: .toggleBookmark
    case .handoff(let command): .performHandoff(command)
    case .quit: nil
    }
  }
}

public enum CommandDispatchOwnership: Equatable, Sendable {
  case browser
  case applicationRuntime
}

/// Everything a binding's availability, resolution, or eligibility may depend
/// on. A command reads the browser only through this value, which is what lets
/// dispatch be answered without a live model.
public struct CommandContext: Equatable, Sendable {
  public var hasSelection: Bool
  public var hasPreview: Bool
  public var previewFocused: Bool
  public var hasRootRelativeSelection: Bool
  public var showsHiddenFiles: Bool
  public var isOverlayPresented: Bool

  public init(
    hasSelection: Bool,
    hasPreview: Bool,
    previewFocused: Bool,
    hasRootRelativeSelection: Bool,
    showsHiddenFiles: Bool = false,
    isOverlayPresented: Bool = false
  ) {
    self.hasSelection = hasSelection
    self.hasPreview = hasPreview
    self.previewFocused = previewFocused
    self.hasRootRelativeSelection = hasRootRelativeSelection
    self.showsHiddenFiles = showsHiddenFiles
    self.isOverlayPresented = isOverlayPresented
  }
}

/// What a key press amounts to once the catalog has answered every question
/// about it — eligibility, availability, and who owns the effect.
enum CommandDispatch: Sendable {
  /// Send this to the browser model.
  case perform(BrowserAction)
  /// The binding exists but is not usable right now; show this reason.
  case unavailable(String)
  /// The scene owns the effect so it can run the normal shutdown path.
  case runtimeOwned
}

public struct CommandAvailability: Equatable, Sendable {
  public var isEnabled: Bool
  public var disabledReason: String?

  public init(isEnabled: Bool, disabledReason: String? = nil) {
    self.isEnabled = isEnabled
    self.disabledReason = disabledReason
  }
}

public struct CommandDefinition: Sendable {
  public var id: CommandID
  public var defaultChord: String
  public var title: String
  public var section: CommandSection
  var action: SextantCommandAction
  public var keyPresses: [KeyPress]
  public var dispatchOwnership: CommandDispatchOwnership
  public var availability: @Sendable (CommandContext) -> CommandAvailability

  init(
    id: CommandID,
    defaultChord: String,
    title: String,
    section: CommandSection,
    action: SextantCommandAction,
    keyPresses: [KeyPress] = [],
    dispatchOwnership: CommandDispatchOwnership = .browser,
    availability:
      @escaping @Sendable (CommandContext) -> CommandAvailability = { _ in
        CommandAvailability(isEnabled: true)
      }
  ) {
    self.id = id
    self.defaultChord = defaultChord
    self.title = title
    self.section = section
    self.action = action
    self.keyPresses = keyPresses
    self.dispatchOwnership = dispatchOwnership
    self.availability = availability
  }
}

public struct CommandCatalog: Sendable {
  public var commands: [CommandDefinition]

  public init(commands: [CommandDefinition] = CommandCatalog.defaults) {
    self.commands = commands
  }

  public func command(id: CommandID) -> CommandDefinition? {
    commands.first { $0.id == id }
  }

  /// Drops `shift` from a character key press.
  ///
  /// Terminals never report shift for a printable key — the shifted glyph *is*
  /// the report. `?` arrives as byte `0x3F` and decodes to
  /// `KeyPress(.character("?"))` with no modifiers, so a binding declared as
  /// `.character("?"), modifiers: .shift` can never match on any terminal. The
  /// character already carries the shift; only `ctrl` and `alt` remain
  /// significant.
  public static func normalized(_ keyPress: KeyPress) -> KeyPress {
    guard case .character = keyPress.key else {
      return keyPress
    }
    var modifiers = keyPress.modifiers
    modifiers.remove(.shift)
    return KeyPress(keyPress.key, modifiers: modifiers)
  }

  public func command(
    for keyPress: KeyPress,
    context: CommandContext
  ) -> (CommandDefinition, CommandAvailability)? {
    let keyPress = Self.normalized(keyPress)
    guard
      let command = commands.first(where: {
        $0.keyPresses.contains { Self.normalized($0) == keyPress }
      })
    else {
      return nil
    }
    return (command, command.availability(context))
  }

  /// Resolves a key press while the preview surface holds focus.
  ///
  /// Only `.preview` commands stay live there — every other binding drives the
  /// browser and must not fire while keys are destined for the preview. The
  /// rule lives here, beside the availability closures that depend on
  /// `previewFocused`, because a caller that answers it first makes those
  /// closures unreachable.
  public func previewFocusedCommand(
    for keyPress: KeyPress,
    context: CommandContext
  ) -> (CommandDefinition, CommandAvailability)? {
    guard let resolved = command(for: keyPress, context: context),
      resolved.0.section == .preview
    else {
      return nil
    }
    return resolved
  }

  /// The one door from a key press to its effect.
  ///
  /// Eligibility (is this key live given focus and overlays), availability, and
  /// runtime ownership are all answered here. Callers dispatch the result; they
  /// do not re-derive any part of the decision.
  func dispatch(
    _ keyPress: KeyPress,
    context: CommandContext
  ) -> CommandDispatch? {
    // An overlay owns the keyboard while it is up. Its own field handles
    // dismissal; no browser binding fires underneath it.
    guard !context.isOverlayPresented else {
      return nil
    }
    let resolved =
      context.previewFocused
      ? previewFocusedCommand(for: keyPress, context: context)
      : command(for: keyPress, context: context)
    guard let (command, availability) = resolved else {
      return nil
    }
    guard availability.isEnabled else {
      return .unavailable(availability.disabledReason ?? "Command unavailable.")
    }
    guard command.dispatchOwnership == .browser,
      let action = command.action.browserAction(in: context)
    else {
      return .runtimeOwned
    }
    return .perform(action)
  }

  /// The keys the scene must claim so exit runs the normal shutdown path.
  ///
  /// Derived from the catalog rather than restated by the scene, so help
  /// cannot advertise a quit key the runtime does not honour.
  public static var runtimeExitKeys: [KeyPress] {
    CommandCatalog().commands
      .filter { $0.dispatchOwnership == .applicationRuntime }
      .flatMap(\.keyPresses)
  }

  public func applyingKeyOverrides(
    _ overrides: [String: String]
  ) throws -> CommandCatalog {
    var commands = commands
    let indicesByID = Dictionary(
      uniqueKeysWithValues: commands.indices.map {
        (commands[$0].id.rawValue, $0)
      }
    )
    for (commandID, source) in overrides {
      guard let index = indicesByID[commandID] else {
        throw ConfigurationFailure.unknownCommand(commandID)
      }
      guard commands[index].dispatchOwnership != .applicationRuntime else {
        throw ConfigurationFailure.runtimeOwnedKeyOverride(commandID)
      }
      let chord = source.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !chord.isEmpty else {
        throw ConfigurationFailure.emptyChord(commandID)
      }
      guard let keyPress = KeyChordParser.parse(chord) else {
        throw ConfigurationFailure.invalidChord(
          command: commandID,
          chord: chord
        )
      }
      commands[index].defaultChord = chord
      commands[index].keyPresses = [keyPress]
    }
    return CommandCatalog(commands: commands)
  }

  public func markdown() -> String {
    var lines = [
      "# Sextant key bindings",
      "",
      "This file is generated from `CommandCatalog`.",
      "",
    ]
    for section in CommandSection.allCases {
      let sectionCommands = commands.filter { $0.section == section }
      guard !sectionCommands.isEmpty else {
        continue
      }
      lines.append("## \(section.rawValue)")
      lines.append("")
      lines.append("| Key | Command |")
      lines.append("| --- | --- |")
      for command in sectionCommands {
        lines.append("| `\(command.defaultChord)` | \(command.title) |")
      }
      lines.append("")
    }
    return lines.joined(separator: "\n")
  }
}

extension CommandCatalog {
  public static let defaults: [CommandDefinition] = [
    CommandDefinition(
      id: CommandID("navigation.up"),
      defaultChord: "↑ / k",
      title: "Move selection up",
      section: .navigation,
      action: .moveUp,
      keyPresses: [
        KeyPress(.arrowUp),
        KeyPress(.character("k")),
      ]
    ),
    CommandDefinition(
      id: CommandID("navigation.down"),
      defaultChord: "↓ / j",
      title: "Move selection down",
      section: .navigation,
      action: .moveDown,
      keyPresses: [
        KeyPress(.arrowDown),
        KeyPress(.character("j")),
      ]
    ),
    CommandDefinition(
      id: CommandID("navigation.parent"),
      defaultChord: "← / h",
      title: "Move to parent directory",
      section: .navigation,
      action: .moveParent,
      keyPresses: [
        KeyPress(.arrowLeft),
        KeyPress(.character("h")),
      ]
    ),
    CommandDefinition(
      id: CommandID("navigation.advance"),
      defaultChord: "→ / l",
      title: "Enter the selected directory",
      section: .navigation,
      action: .advance,
      keyPresses: [
        KeyPress(.arrowRight),
        KeyPress(.character("l")),
      ]
    ),
    CommandDefinition(
      id: CommandID("navigation.enter"),
      defaultChord: "Return",
      title: "Preview the file or enter the directory",
      section: .navigation,
      action: .enter,
      keyPresses: [KeyPress(.return)]
    ),
    CommandDefinition(
      id: CommandID("navigation.first"),
      defaultChord: "Home / g",
      title: "Select first item",
      section: .navigation,
      action: .first,
      keyPresses: [
        KeyPress(.home),
        KeyPress(.character("g")),
      ]
    ),
    CommandDefinition(
      id: CommandID("navigation.last"),
      defaultChord: "End / G",
      title: "Select last item",
      section: .navigation,
      action: .last,
      keyPresses: [
        KeyPress(.end),
        KeyPress(.character("G")),
      ]
    ),
    CommandDefinition(
      id: CommandID("navigation.page-up"),
      defaultChord: "Page Up",
      title: "Move one page up",
      section: .navigation,
      action: .pageUp,
      keyPresses: [KeyPress(.pageUp)]
    ),
    CommandDefinition(
      id: CommandID("navigation.page-down"),
      defaultChord: "Page Down",
      title: "Move one page down",
      section: .navigation,
      action: .pageDown,
      keyPresses: [KeyPress(.pageDown)]
    ),
    CommandDefinition(
      id: CommandID("preview.toggle"),
      defaultChord: "Tab",
      title: "Switch browser and preview",
      section: .preview,
      action: .toggleSurface,
      keyPresses: [KeyPress(.tab)],
      availability: { context in
        context.hasPreview
          ? CommandAvailability(isEnabled: true)
          : CommandAvailability(
            isEnabled: false,
            disabledReason: "Select a previewable item first."
          )
      }
    ),
    CommandDefinition(
      id: CommandID("preview.escape"),
      defaultChord: "Escape",
      title: "Return focus to browser",
      section: .preview,
      action: .focusBrowser,
      keyPresses: [KeyPress(.escape)],
      availability: { context in
        CommandAvailability(isEnabled: context.previewFocused)
      }
    ),
    CommandDefinition(
      id: CommandID("view.filter"),
      defaultChord: "/",
      title: "Filter the active directory",
      section: .view,
      action: .filter,
      keyPresses: [KeyPress(.character("/"))]
    ),
    CommandDefinition(
      id: CommandID("view.hidden"),
      defaultChord: ".",
      title: "Toggle hidden files",
      section: .view,
      action: .toggleHidden,
      keyPresses: [KeyPress(.character("."))]
    ),
    CommandDefinition(
      id: CommandID("view.refresh"),
      defaultChord: "r",
      title: "Refresh the active directory",
      section: .view,
      action: .refresh,
      keyPresses: [KeyPress(.character("r"))]
    ),
    CommandDefinition(
      id: CommandID("view.help"),
      defaultChord: "?",
      title: "Show help",
      section: .view,
      action: .help,
      keyPresses: [KeyPress(.character("?"))]
    ),
    CommandDefinition(
      id: CommandID("view.search"),
      defaultChord: "s",
      title: "Search filenames or jump to a path",
      section: .view,
      action: .search,
      keyPresses: [KeyPress(.character("s"))]
    ),
    CommandDefinition(
      id: CommandID("view.palette"),
      defaultChord: ":",
      title: "Open command palette",
      section: .view,
      action: .palette,
      keyPresses: [KeyPress(.character(":"))]
    ),
    selectionCommand(
      id: "workflow.bookmark",
      key: "b",
      title: "Toggle bookmark",
      action: .bookmark
    ),
    selectionCommand(
      id: "workflow.open",
      key: "o",
      title: "Open with the system default",
      action: .handoff(.open)
    ),
    selectionCommand(
      id: "workflow.edit",
      key: "e",
      title: "Edit with VISUAL or EDITOR",
      action: .handoff(.edit)
    ),
    selectionCommand(
      id: "workflow.reveal",
      key: "R",
      title: "Reveal in Finder",
      action: .handoff(.reveal)
    ),
    selectionCommand(
      id: "workflow.copy-absolute",
      key: "y",
      title: "Copy absolute path",
      action: .handoff(.copyAbsolutePath)
    ),
    CommandDefinition(
      id: CommandID("workflow.copy-relative"),
      defaultChord: "Y",
      title: "Copy root-relative path",
      section: .workflow,
      action: .handoff(.copyRelativePath),
      keyPresses: [KeyPress(.character("Y"))],
      availability: { context in
        context.hasRootRelativeSelection
          ? CommandAvailability(isEnabled: true)
          : CommandAvailability(
            isEnabled: false,
            disabledReason: "The selection is outside the launch root."
          )
      }
    ),
    CommandDefinition(
      id: CommandID("application.quit"),
      defaultChord: "Ctrl-D / q",
      title: "Quit",
      section: .application,
      action: .quit,
      keyPresses: [
        KeyPress(.character("q")),
        KeyPress(.character("d"), modifiers: .ctrl),
      ],
      dispatchOwnership: .applicationRuntime
    ),
  ]

  /// A workflow command bound to one printable key.
  ///
  /// The key is both the binding and its printed chord, so the two cannot
  /// drift — which a separate action-keyed key table, whose `default` was an
  /// empty binding, previously allowed.
  private static func selectionCommand(
    id: String,
    key: Character,
    title: String,
    action: SextantCommandAction
  ) -> CommandDefinition {
    CommandDefinition(
      id: CommandID(id),
      defaultChord: String(key),
      title: title,
      section: .workflow,
      action: action,
      keyPresses: [KeyPress(.character(key))],
      availability: { context in
        context.hasSelection
          ? CommandAvailability(isEnabled: true)
          : CommandAvailability(
            isEnabled: false,
            disabledReason: "Select an item first."
          )
      }
    )
  }
}

enum KeyChordParser {
  static func parse(_ source: String) -> KeyPress? {
    let parts = source.split(separator: "-", omittingEmptySubsequences: false)
    guard let keySource = parts.last, !keySource.isEmpty else {
      return nil
    }

    var modifiers: EventModifiers = []
    for modifier in parts.dropLast() {
      switch modifier.lowercased() {
      case "shift":
        modifiers.insert(.shift)
      case "alt", "option":
        modifiers.insert(.alt)
      case "ctrl", "control":
        modifiers.insert(.ctrl)
      default:
        return nil
      }
    }

    let key: KeyEvent
    switch keySource.lowercased() {
    case "up", "arrowup":
      key = .arrowUp
    case "down", "arrowdown":
      key = .arrowDown
    case "left", "arrowleft":
      key = .arrowLeft
    case "right", "arrowright":
      key = .arrowRight
    case "return", "enter":
      key = .return
    case "space":
      key = .space
    case "tab":
      key = .tab
    case "escape", "esc":
      key = .escape
    case "home":
      key = .home
    case "end":
      key = .end
    case "pageup":
      key = .pageUp
    case "pagedown":
      key = .pageDown
    case "backspace":
      key = .backspace
    case "delete":
      key = .delete
    default:
      guard keySource.count == 1, var character = keySource.first else {
        return nil
      }
      if character.isUppercase,
        modifiers.contains(.ctrl) || modifiers.contains(.alt)
      {
        character = Character(String(character).lowercased())
      } else if character.isUppercase || "?:+_{}|\"<>".contains(character) {
        modifiers.insert(.shift)
      }
      key = .character(character)
    }
    return KeyPress(key, modifiers: modifiers)
  }
}

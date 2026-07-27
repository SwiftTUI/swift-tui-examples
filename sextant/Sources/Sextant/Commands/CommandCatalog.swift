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

public enum SextantCommandAction: Equatable, Sendable {
  case moveUp
  case moveDown
  case moveParent
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
  case open
  case edit
  case reveal
  case copyAbsolutePath
  case copyRelativePath
  case quit
}

public enum CommandDispatchOwnership: Equatable, Sendable {
  case browser
  case applicationRuntime
}

public struct CommandContext: Equatable, Sendable {
  public var hasSelection: Bool
  public var hasPreview: Bool
  public var previewFocused: Bool
  public var hasRootRelativeSelection: Bool

  public init(
    hasSelection: Bool,
    hasPreview: Bool,
    previewFocused: Bool,
    hasRootRelativeSelection: Bool
  ) {
    self.hasSelection = hasSelection
    self.hasPreview = hasPreview
    self.previewFocused = previewFocused
    self.hasRootRelativeSelection = hasRootRelativeSelection
  }
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
  public var action: SextantCommandAction
  public var keyPresses: [KeyPress]
  public var dispatchOwnership: CommandDispatchOwnership
  public var availability: @Sendable (CommandContext) -> CommandAvailability

  public init(
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

  public func command(
    for keyPress: KeyPress,
    context: CommandContext
  ) -> (CommandDefinition, CommandAvailability)? {
    guard
      let command = commands.first(where: {
        $0.keyPresses.contains(keyPress)
      })
    else {
      return nil
    }
    return (command, command.availability(context))
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
      title: "Move to parent column",
      section: .navigation,
      action: .moveParent,
      keyPresses: [
        KeyPress(.arrowLeft),
        KeyPress(.character("h")),
      ]
    ),
    CommandDefinition(
      id: CommandID("navigation.enter"),
      defaultChord: "→ / l / Return",
      title: "Enter directory or focus preview",
      section: .navigation,
      action: .enter,
      keyPresses: [
        KeyPress(.arrowRight),
        KeyPress(.character("l")),
        KeyPress(.return),
      ]
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
        KeyPress(.character("G"), modifiers: .shift),
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
      keyPresses: [
        KeyPress(.character("?"), modifiers: .shift)
      ]
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
      chord: "b",
      title: "Toggle bookmark",
      action: .bookmark
    ),
    selectionCommand(
      id: "workflow.open",
      chord: "o",
      title: "Open with the system default",
      action: .open
    ),
    selectionCommand(
      id: "workflow.edit",
      chord: "e",
      title: "Edit with VISUAL or EDITOR",
      action: .edit
    ),
    selectionCommand(
      id: "workflow.reveal",
      chord: "R",
      title: "Reveal in Finder",
      action: .reveal
    ),
    selectionCommand(
      id: "workflow.copy-absolute",
      chord: "y",
      title: "Copy absolute path",
      action: .copyAbsolutePath
    ),
    CommandDefinition(
      id: CommandID("workflow.copy-relative"),
      defaultChord: "Y",
      title: "Copy root-relative path",
      section: .workflow,
      action: .copyRelativePath,
      keyPresses: [
        KeyPress(.character("Y"), modifiers: .shift)
      ],
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

  private static func selectionCommand(
    id: String,
    chord: String,
    title: String,
    action: SextantCommandAction
  ) -> CommandDefinition {
    CommandDefinition(
      id: CommandID(id),
      defaultChord: chord,
      title: title,
      section: .workflow,
      action: action,
      keyPresses: keyPresses(for: action),
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

  private static func keyPresses(
    for action: SextantCommandAction
  ) -> [KeyPress] {
    switch action {
    case .bookmark:
      [KeyPress(.character("b"))]
    case .open:
      [KeyPress(.character("o"))]
    case .edit:
      [KeyPress(.character("e"))]
    case .reveal:
      [KeyPress(.character("R"), modifiers: .shift)]
    case .copyAbsolutePath:
      [KeyPress(.character("y"))]
    default:
      []
    }
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

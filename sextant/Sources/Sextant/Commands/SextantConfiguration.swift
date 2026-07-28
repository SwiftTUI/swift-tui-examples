import Foundation
import SwiftTUI

public struct SextantConfiguration: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var version: Int
  public var showsHiddenFiles: Bool
  public var sort: SortConfiguration
  public var watchesFileSystem: Bool
  public var keyOverrides: [String: String]
  public var colors: ColorConfiguration
  public var editor: [String]?
  public var previewAdapters: [ExternalPreviewConfiguration]

  public init(
    version: Int = SextantConfiguration.currentVersion,
    showsHiddenFiles: Bool = false,
    sort: SortConfiguration = SortConfiguration(),
    watchesFileSystem: Bool = true,
    keyOverrides: [String: String] = [:],
    colors: ColorConfiguration = ColorConfiguration(),
    editor: [String]? = nil,
    previewAdapters: [ExternalPreviewConfiguration] = []
  ) {
    self.version = version
    self.showsHiddenFiles = showsHiddenFiles
    self.sort = sort
    self.watchesFileSystem = watchesFileSystem
    self.keyOverrides = keyOverrides
    self.colors = colors
    self.editor = editor
    self.previewAdapters = previewAdapters
  }

  public func validated(
    catalog: CommandCatalog = CommandCatalog()
  ) throws -> SextantConfiguration {
    guard version == Self.currentVersion else {
      throw ConfigurationFailure.unsupportedVersion(version)
    }
    let effectiveCatalog = try catalog.applyingKeyOverrides(keyOverrides)
    var chordOwners: [KeyPress: String] = [:]
    for command in effectiveCatalog.commands {
      // Key the collision check on the same normalized press dispatch uses, so
      // `?` and `shift-?` cannot be handed to two different commands and then
      // resolve to only one of them at runtime.
      for keyPress in command.keyPresses.map(CommandCatalog.normalized) {
        if let owner = chordOwners[keyPress], owner != command.id.rawValue {
          throw ConfigurationFailure.duplicateChord(
            chord: command.defaultChord,
            firstCommand: owner,
            secondCommand: command.id.rawValue
          )
        }
        chordOwners[keyPress] = command.id.rawValue
      }
    }
    for (role, source) in [
      ("accent", colors.accent),
      ("muted", colors.muted),
    ] {
      if let source {
        do {
          _ = try Color(hex: source)
        } catch {
          throw ConfigurationFailure.invalidColor(role: role, value: source)
        }
      }
    }
    if let editor, editor.isEmpty || editor[0].isEmpty {
      throw ConfigurationFailure.invalidEditor
    }
    for adapter in previewAdapters {
      try adapter.validate()
    }
    return self
  }
}

public struct SortConfiguration: Codable, Equatable, Sendable {
  public enum Key: String, Codable, Sendable {
    case name
    case modified
    case size
  }

  public enum Direction: String, Codable, Sendable {
    case ascending
    case descending
  }

  public var key: Key
  public var direction: Direction
  public var directoriesFirst: Bool

  public init(
    key: Key = .name,
    direction: Direction = .ascending,
    directoriesFirst: Bool = true
  ) {
    self.key = key
    self.direction = direction
    self.directoriesFirst = directoriesFirst
  }

  var directorySort: DirectorySort {
    let key: DirectorySort.Key =
      switch self.key {
      case .name:
        .name
      case .modified:
        .modificationDate
      case .size:
        .size
      }
    let direction: SortDirection =
      switch self.direction {
      case .ascending:
        .ascending
      case .descending:
        .descending
      }
    return DirectorySort(key: key, direction: direction)
  }
}

public struct ColorConfiguration: Codable, Equatable, Sendable {
  public var accent: String?
  public var muted: String?

  public init(accent: String? = nil, muted: String? = nil) {
    self.accent = accent
    self.muted = muted
  }

  var accentColor: Color? {
    accent.flatMap { try? Color(hex: $0) }
  }

  var mutedColor: Color? {
    muted.flatMap { try? Color(hex: $0) }
  }
}

public struct ExternalPreviewConfiguration: Codable, Equatable, Sendable {
  public static let currentRulesVersion = 1

  public enum ContentKind: String, Codable, CaseIterable, Sendable {
    case text
    case binary
    case anyFile
  }

  public var id: String
  public var displayName: String
  public var executable: String
  public var arguments: [String]
  public var fileExtensions: [String]
  public var priority: Int
  public var isInteractive: Bool
  public var rulesVersion: Int
  public var contentKinds: [ContentKind]
  public var maximumByteCount: UInt64?

  public init(
    id: String,
    displayName: String,
    executable: String,
    arguments: [String],
    fileExtensions: [String] = [],
    priority: Int = 0,
    isInteractive: Bool = false,
    rulesVersion: Int = ExternalPreviewConfiguration.currentRulesVersion,
    contentKinds: [ContentKind] = [.anyFile],
    maximumByteCount: UInt64? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.executable = executable
    self.arguments = arguments
    self.fileExtensions = fileExtensions
    self.priority = priority
    self.isInteractive = isInteractive
    self.rulesVersion = rulesVersion
    self.contentKinds = contentKinds
    self.maximumByteCount = maximumByteCount
  }

  fileprivate func validate() throws {
    guard !id.isEmpty, !displayName.isEmpty, !executable.isEmpty else {
      throw ConfigurationFailure.invalidPreviewAdapter(id)
    }
    guard arguments.contains("{path}") else {
      throw ConfigurationFailure.previewAdapterMissingPath(id)
    }
    guard rulesVersion == Self.currentRulesVersion else {
      throw ConfigurationFailure.invalidPreviewAdapterRulesVersion(
        id: id,
        version: rulesVersion
      )
    }
    guard !contentKinds.isEmpty,
      !(contentKinds.contains(.anyFile) && contentKinds.count > 1)
    else {
      throw ConfigurationFailure.invalidPreviewAdapterContentRules(id)
    }
    if let maximumByteCount, maximumByteCount == 0 {
      throw ConfigurationFailure.invalidPreviewAdapterMaximumBytes(id)
    }
    guard !executesInterpreterSource else {
      throw ConfigurationFailure.previewAdapterContainsShellSource(id)
    }
    for argument in arguments {
      guard !argument.contains("$("),
        !argument.contains("`"),
        !argument.contains("${")
      else {
        throw ConfigurationFailure.previewAdapterContainsShellSource(id)
      }
    }
  }

  private var executesInterpreterSource: Bool {
    let shellNames: Set<String> = [
      "bash", "csh", "dash", "fish", "ksh", "sh", "tcsh", "zsh",
    ]
    var command = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
    var commandArguments = arguments

    if command == "env" {
      guard
        let commandIndex = commandArguments.firstIndex(where: {
          shellNames.contains(
            URL(fileURLWithPath: $0).lastPathComponent.lowercased()
          )
        })
      else {
        return false
      }
      command = URL(fileURLWithPath: commandArguments[commandIndex])
        .lastPathComponent.lowercased()
      commandArguments = Array(commandArguments.dropFirst(commandIndex + 1))
    }

    guard shellNames.contains(command) else {
      return false
    }
    return commandArguments.contains { argument in
      guard argument.hasPrefix("-"), !argument.hasPrefix("--") else {
        return argument == "--command"
      }
      return argument.dropFirst().lowercased().contains("c")
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case displayName
    case executable
    case arguments
    case fileExtensions
    case priority
    case isInteractive
    case rulesVersion
    case contentKinds
    case maximumByteCount
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    displayName = try container.decode(String.self, forKey: .displayName)
    executable = try container.decode(String.self, forKey: .executable)
    arguments = try container.decode([String].self, forKey: .arguments)
    fileExtensions =
      try container.decodeIfPresent([String].self, forKey: .fileExtensions)
      ?? []
    priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
    isInteractive =
      try container.decodeIfPresent(Bool.self, forKey: .isInteractive)
      ?? false
    rulesVersion =
      try container.decodeIfPresent(Int.self, forKey: .rulesVersion)
      ?? Self.currentRulesVersion
    contentKinds =
      try container.decodeIfPresent([ContentKind].self, forKey: .contentKinds)
      ?? [.anyFile]
    maximumByteCount =
      try container.decodeIfPresent(UInt64.self, forKey: .maximumByteCount)
  }
}

public struct SextantPersistentState: Codable, Equatable, Sendable {
  public var version: Int
  public var hasSeenHelp: Bool
  public var bookmarks: [String]
  public var recents: [String]

  public init(
    version: Int = 1,
    hasSeenHelp: Bool = false,
    bookmarks: [String] = [],
    recents: [String] = []
  ) {
    self.version = version
    self.hasSeenHelp = hasSeenHelp
    self.bookmarks = bookmarks
    self.recents = recents
  }
}

public enum ConfigurationFailure: Error, Equatable, Sendable {
  case unsupportedVersion(Int)
  case unknownCommand(String)
  case emptyChord(String)
  case invalidChord(command: String, chord: String)
  case duplicateChord(
    chord: String,
    firstCommand: String,
    secondCommand: String
  )
  case runtimeOwnedKeyOverride(String)
  case invalidEditor
  case invalidPreviewAdapter(String)
  case previewAdapterMissingPath(String)
  case previewAdapterContainsShellSource(String)
  case invalidPreviewAdapterRulesVersion(id: String, version: Int)
  case invalidPreviewAdapterContentRules(String)
  case invalidPreviewAdapterMaximumBytes(String)
  case invalidColor(role: String, value: String)
}

extension ConfigurationFailure: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version):
      "unsupported Sextant configuration version \(version)"
    case .unknownCommand(let command):
      "key override names unknown command '\(command)'"
    case .emptyChord(let command):
      "key override for '\(command)' is empty"
    case .invalidChord(let command, let chord):
      "key override '\(chord)' for '\(command)' is not representable in a terminal"
    case .duplicateChord(let chord, let firstCommand, let secondCommand):
      "key '\(chord)' is assigned to both '\(firstCommand)' and '\(secondCommand)'"
    case .runtimeOwnedKeyOverride(let command):
      "key override for '\(command)' is unsupported because the terminal runtime owns application exit keys"
    case .invalidEditor:
      "the configured editor argv must begin with a nonempty executable"
    case .invalidPreviewAdapter(let id):
      "preview adapter '\(id)' must declare an id, name, and executable"
    case .previewAdapterMissingPath(let id):
      "preview adapter '\(id)' must include {path} as a standalone argument"
    case .previewAdapterContainsShellSource(let id):
      "preview adapter '\(id)' contains unsupported shell interpolation or inline interpreter source"
    case .invalidPreviewAdapterRulesVersion(let id, let version):
      "preview adapter '\(id)' uses unsupported content-rules version \(version)"
    case .invalidPreviewAdapterContentRules(let id):
      "preview adapter '\(id)' must declare content kinds, and anyFile cannot be combined"
    case .invalidPreviewAdapterMaximumBytes(let id):
      "preview adapter '\(id)' maximumByteCount must be greater than zero"
    case .invalidColor(let role, let value):
      "configured \(role) color '\(value)' is not a valid hex color"
    }
  }
}

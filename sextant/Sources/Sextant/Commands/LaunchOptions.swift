import Foundation
import SwiftTUI

public enum LaunchSort: String, CaseIterable, Sendable, ExpressibleByArgument {
  case name
  case modified
  case size
}

public enum LaunchPreviewMode: String, CaseIterable, Sendable, ExpressibleByArgument {
  case auto
  case builtIn = "built-in"
  case external
  case off
}

/// The command-line values that affect Sextant's product behavior.
///
/// Keeping these separate from `SextantCommand` lets the launch contract be
/// parsed and validated without constructing a renderer or entering the
/// terminal's alternate screen.
public struct LaunchOptions: ParsableArguments, Sendable {
  @Argument(help: "File or directory to inspect. Defaults to the current directory.")
  public var path: String? = nil

  @Flag(name: .long, help: "Include entries whose names begin with a dot.")
  public var hidden = false

  @Option(name: .long, help: "Sort directory entries by name, modified time, or size.")
  public var sort: LaunchSort?

  @Option(
    name: .long,
    help: "Choose automatic, built-in, external, or disabled previews."
  )
  public var preview: LaunchPreviewMode?

  @Flag(name: .customLong("no-watch"), help: "Disable filesystem change watching.")
  public var noWatch = false

  @Option(name: .long, help: "Read configuration from this path.")
  public var config: String? = nil

  public init() {}
}

public enum LaunchPathKind: Equatable, Sendable {
  case file
  case directory
  case missing
  case unreadable
  case unsupported
}

public protocol LaunchPathInspecting: Sendable {
  func kind(of url: URL) -> LaunchPathKind
}

public struct LocalLaunchPathInspector: LaunchPathInspecting {
  public init() {}

  public func kind(of url: URL) -> LaunchPathKind {
    guard (try? url.checkResourceIsReachable()) == true else {
      return .missing
    }

    do {
      let values = try url.resourceValues(forKeys: [
        .isDirectoryKey,
        .isReadableKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
      ])
      guard values.isReadable == true else {
        return .unreadable
      }
      if values.isDirectory == true {
        return .directory
      }
      if values.isRegularFile == true {
        return .file
      }
      if values.isSymbolicLink == true {
        // Resource values can describe the link rather than its destination.
        // Reachability above has already rejected a dangling link; a readable
        // non-directory destination is therefore a file launch.
        return .file
      }
      return .unsupported
    } catch {
      return .unsupported
    }
  }
}

public enum LaunchInputFailure: Error, Equatable, Sendable {
  case missing(URL)
  case unreadable(URL)
  case unsupported(URL)
}

extension LaunchInputFailure: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .missing(let url):
      "cannot open '\(url.path)': path does not exist"
    case .unreadable(let url):
      "cannot open '\(url.path)': path is not readable"
    case .unsupported(let url):
      "cannot open '\(url.path)': unsupported file type"
    }
  }
}

public struct ResolvedLaunchInput: Equatable, Sendable {
  public var rootDirectoryURL: URL
  public var selectedFileURL: URL?
  public var showsHiddenFiles: Bool
  public var sort: LaunchSort
  public var sortDirection: SortConfiguration.Direction
  public var previewMode: LaunchPreviewMode
  public var watchesFileSystem: Bool
  public var configurationURL: URL?
  public var stateURL: URL
  public var configuration: SextantConfiguration

  public init(
    rootDirectoryURL: URL,
    selectedFileURL: URL?,
    showsHiddenFiles: Bool,
    sort: LaunchSort,
    sortDirection: SortConfiguration.Direction = .ascending,
    previewMode: LaunchPreviewMode,
    watchesFileSystem: Bool,
    configurationURL: URL?,
    stateURL: URL = URL(fileURLWithPath: "/dev/null"),
    configuration: SextantConfiguration = SextantConfiguration()
  ) {
    self.rootDirectoryURL = rootDirectoryURL
    self.selectedFileURL = selectedFileURL
    self.showsHiddenFiles = showsHiddenFiles
    self.sort = sort
    self.sortDirection = sortDirection
    self.previewMode = previewMode
    self.watchesFileSystem = watchesFileSystem
    self.configurationURL = configurationURL
    self.stateURL = stateURL
    self.configuration = configuration
  }
}

public struct LaunchInputResolver<Inspector: LaunchPathInspecting>: Sendable {
  public var inspector: Inspector

  public init(inspector: Inspector) {
    self.inspector = inspector
  }

  public func resolve(
    _ options: LaunchOptions,
    currentDirectoryURL: URL,
    configuration: SextantConfiguration = SextantConfiguration(),
    configurationURL: URL? = nil,
    stateURL: URL = URL(fileURLWithPath: "/dev/null")
  ) throws -> ResolvedLaunchInput {
    let launchURL = resolvePath(
      options.path ?? ".",
      relativeTo: currentDirectoryURL
    )

    let rootDirectoryURL: URL
    let selectedFileURL: URL?
    switch inspector.kind(of: launchURL) {
    case .directory:
      rootDirectoryURL = launchURL
      selectedFileURL = nil
    case .file:
      rootDirectoryURL = launchURL.deletingLastPathComponent()
      selectedFileURL = launchURL
    case .missing:
      throw LaunchInputFailure.missing(launchURL)
    case .unreadable:
      throw LaunchInputFailure.unreadable(launchURL)
    case .unsupported:
      throw LaunchInputFailure.unsupported(launchURL)
    }

    return ResolvedLaunchInput(
      rootDirectoryURL: rootDirectoryURL,
      selectedFileURL: selectedFileURL,
      showsHiddenFiles: options.hidden || configuration.showsHiddenFiles,
      sort: options.sort ?? launchSort(configuration.sort.key),
      sortDirection: options.sort.map(defaultSortDirection)
        ?? configuration.sort.direction,
      previewMode: options.preview ?? .auto,
      watchesFileSystem: options.noWatch ? false : configuration.watchesFileSystem,
      configurationURL: configurationURL
        ?? options.config.map {
          resolvePath($0, relativeTo: currentDirectoryURL)
        },
      stateURL: stateURL,
      configuration: configuration
    )
  }

  public func resolveConfigured(
    _ options: LaunchOptions,
    currentDirectoryURL: URL,
    environment: [String: String],
    homeDirectory: URL
  ) throws -> ResolvedLaunchInput {
    let paths = SextantPaths.resolve(
      environment: environment,
      homeDirectory: homeDirectory
    )
    let configurationURL =
      options.config.map {
        resolvePath($0, relativeTo: currentDirectoryURL)
      }
      ?? paths.configurationFile
    let configuration = try JSONFileStore<SextantConfiguration>(
      url: configurationURL
    ).load(default: SextantConfiguration()).validated()
    return try resolve(
      options,
      currentDirectoryURL: currentDirectoryURL,
      configuration: configuration,
      configurationURL: configurationURL,
      stateURL: paths.stateFile
    )
  }

  private func resolvePath(_ path: String, relativeTo directory: URL) -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    if (expanded as NSString).isAbsolutePath {
      return URL(fileURLWithPath: expanded).standardizedFileURL
    }
    return
      directory
      .appendingPathComponent(expanded)
      .standardizedFileURL
  }

  private func launchSort(_ key: SortConfiguration.Key) -> LaunchSort {
    switch key {
    case .name:
      .name
    case .modified:
      .modified
    case .size:
      .size
    }
  }

  private func defaultSortDirection(
    _ sort: LaunchSort
  ) -> SortConfiguration.Direction {
    switch sort {
    case .name:
      .ascending
    case .modified, .size:
      .descending
    }
  }
}

extension LaunchInputResolver where Inspector == LocalLaunchPathInspector {
  public init() {
    self.init(inspector: LocalLaunchPathInspector())
  }

  public func resolveFromCurrentDirectory(
    _ options: LaunchOptions,
    currentDirectoryURL: URL = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath,
      isDirectory: true
    )
  ) throws -> ResolvedLaunchInput {
    try resolve(options, currentDirectoryURL: currentDirectoryURL)
  }

  public func resolveConfiguredFromCurrentDirectory(
    _ options: LaunchOptions,
    currentDirectoryURL: URL = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath,
      isDirectory: true
    ),
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> ResolvedLaunchInput {
    try resolveConfigured(
      options,
      currentDirectoryURL: currentDirectoryURL,
      environment: environment,
      homeDirectory: homeDirectory
    )
  }
}

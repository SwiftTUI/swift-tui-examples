import Foundation
import Testing

@testable import Sextant

@Suite("CLI launch options")
struct LaunchOptionsTests {
  @Test("The complete public CLI parses into typed launch options")
  func parsesCompleteArguments() throws {
    let options = try LaunchOptions.parse([
      "--hidden",
      "--sort", "modified",
      "--preview", "built-in",
      "--no-watch",
      "--config", "./sextant.json",
      "./fixture",
    ])

    #expect(options.path == "./fixture")
    #expect(options.hidden)
    #expect(options.sort == .modified)
    #expect(options.preview == .builtIn)
    #expect(options.noWatch)
    #expect(options.config == "./sextant.json")
  }

  @Test(
    "Every documented sort and preview spelling parses",
    arguments: [
      ("name", "auto", LaunchSort.name, LaunchPreviewMode.auto),
      ("modified", "built-in", .modified, .builtIn),
      ("size", "external", .size, .external),
      ("name", "off", .name, .off),
    ]
  )
  func parsesEnumeratedValues(
    sort: String,
    preview: String,
    expectedSort: LaunchSort,
    expectedPreview: LaunchPreviewMode
  ) throws {
    let options = try LaunchOptions.parse([
      "--sort", sort,
      "--preview", preview,
    ])
    #expect(options.sort == expectedSort)
    #expect(options.preview == expectedPreview)
  }

  @Test("No path resolves to the current directory")
  func resolvesCurrentDirectory() throws {
    let cwd = URL(fileURLWithPath: "/work/project", isDirectory: true)
    let resolver = LaunchInputResolver(
      inspector: StubLaunchPathInspector(kind: .directory)
    )

    let launch = try resolver.resolve(
      LaunchOptions.parse([]),
      currentDirectoryURL: cwd
    )

    #expect(launch.rootDirectoryURL == cwd.standardizedFileURL)
    #expect(launch.selectedFileURL == nil)
    #expect(launch.watchesFileSystem)
    #expect(launch.previewMode == .auto)
  }

  @Test("A file opens its parent and preserves the file selection")
  func resolvesFileToParentAndSelection() throws {
    var options = try LaunchOptions.parse([])
    options.path = "./fixtures/readme.txt"
    options.hidden = true
    options.sort = .size
    options.preview = .external
    options.noWatch = true
    options.config = "../config/sextant.json"
    let cwd = URL(fileURLWithPath: "/work/project", isDirectory: true)
    let resolver = LaunchInputResolver(
      inspector: StubLaunchPathInspector(kind: .file)
    )

    let launch = try resolver.resolve(options, currentDirectoryURL: cwd)

    #expect(launch.rootDirectoryURL.path == "/work/project/fixtures")
    #expect(launch.selectedFileURL?.path == "/work/project/fixtures/readme.txt")
    #expect(launch.showsHiddenFiles)
    #expect(launch.sort == .size)
    #expect(launch.previewMode == .external)
    #expect(!launch.watchesFileSystem)
    #expect(launch.configurationURL?.path == "/work/config/sextant.json")
  }

  @Test(
    "Invalid targets fail before launch with a typed diagnostic",
    arguments: [
      (LaunchPathKind.missing, "path does not exist"),
      (.unreadable, "path is not readable"),
      (.unsupported, "unsupported file type"),
    ]
  )
  func rejectsInvalidTarget(kind: LaunchPathKind, diagnostic: String) {
    var options = try! LaunchOptions.parse([])
    options.path = "bad-target"
    let resolver = LaunchInputResolver(
      inspector: StubLaunchPathInspector(kind: kind)
    )

    do {
      _ = try resolver.resolve(
        options,
        currentDirectoryURL: URL(fileURLWithPath: "/work", isDirectory: true)
      )
      Issue.record("Expected invalid launch target to be rejected")
    } catch let error as LaunchInputFailure {
      #expect(error.localizedDescription.contains(diagnostic))
      #expect(error.localizedDescription.contains("/work/bad-target"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("Standardization does not resolve symlink components")
  func standardizesWithoutResolvingSymlinks() throws {
    var options = try LaunchOptions.parse([])
    options.path = "./linked/../linked/file.txt"
    let resolver = LaunchInputResolver(
      inspector: StubLaunchPathInspector(kind: .file)
    )

    let launch = try resolver.resolve(
      options,
      currentDirectoryURL: URL(fileURLWithPath: "/work", isDirectory: true)
    )

    #expect(launch.selectedFileURL?.path == "/work/linked/file.txt")
  }

  @Test("CLI flags override configuration while configuration overrides defaults")
  func configurationPrecedence() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "sextant-launch-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let configURL = temporaryDirectory.appendingPathComponent("config.json")
    try JSONFileStore<SextantConfiguration>(url: configURL).save(
      SextantConfiguration(
        showsHiddenFiles: true,
        sort: SortConfiguration(
          key: .modified,
          direction: .ascending,
          directoriesFirst: false
        ),
        watchesFileSystem: false
      )
    )
    let resolver = LaunchInputResolver(
      inspector: StubLaunchPathInspector(kind: .directory)
    )
    var configuredOptions = try LaunchOptions.parse([])
    configuredOptions.config = configURL.path

    let configured = try resolver.resolveConfigured(
      configuredOptions,
      currentDirectoryURL: temporaryDirectory,
      environment: [:],
      homeDirectory: temporaryDirectory
    )
    #expect(configured.showsHiddenFiles)
    #expect(configured.sort == .modified)
    #expect(configured.sortDirection == .ascending)
    #expect(!configured.watchesFileSystem)
    #expect(!configured.configuration.sort.directoriesFirst)

    var overriddenOptions = configuredOptions
    overriddenOptions.sort = .size
    overriddenOptions.noWatch = true
    let overridden = try resolver.resolveConfigured(
      overriddenOptions,
      currentDirectoryURL: temporaryDirectory,
      environment: [:],
      homeDirectory: temporaryDirectory
    )
    #expect(overridden.sort == .size)
    #expect(overridden.sortDirection == .descending)
    #expect(!overridden.watchesFileSystem)
  }

  @Test("a malformed configuration fails before terminal startup")
  func malformedConfiguration() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "sextant-malformed-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    let configURL = temporaryDirectory.appendingPathComponent("config.json")
    try Data("{not-json".utf8).write(to: configURL)
    var options = try LaunchOptions.parse([])
    options.config = configURL.path
    let resolver = LaunchInputResolver(
      inspector: StubLaunchPathInspector(kind: .directory)
    )

    #expect(throws: DecodingError.self) {
      _ = try resolver.resolveConfigured(
        options,
        currentDirectoryURL: temporaryDirectory,
        environment: [:],
        homeDirectory: temporaryDirectory
      )
    }
  }

  @Test("an ineffective quit override fails before terminal startup")
  func rejectsQuitOverrideBeforeStartup() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "sextant-quit-override-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let configURL = temporaryDirectory.appendingPathComponent("config.json")
    try JSONFileStore<SextantConfiguration>(url: configURL).save(
      SextantConfiguration(
        keyOverrides: ["application.quit": "x"]
      )
    )
    var options = try LaunchOptions.parse([])
    options.config = configURL.path
    let resolver = LaunchInputResolver(
      inspector: StubLaunchPathInspector(kind: .directory)
    )

    #expect(
      throws: ConfigurationFailure.runtimeOwnedKeyOverride("application.quit")
    ) {
      _ = try resolver.resolveConfigured(
        options,
        currentDirectoryURL: temporaryDirectory,
        environment: [:],
        homeDirectory: temporaryDirectory
      )
    }
  }
}

private struct StubLaunchPathInspector: LaunchPathInspecting {
  var kind: LaunchPathKind

  func kind(of _: URL) -> LaunchPathKind {
    kind
  }
}

import Foundation
import SwiftTUI
import Testing

@testable import Sextant

@Suite("Configuration and handoff")
struct ConfigurationAndHandoffTests {
  @Test("XDG paths and fallbacks use the Sextant namespace")
  func paths() {
    let home = URL(fileURLWithPath: "/Users/test")
    #expect(
      SextantPaths.resolve(environment: [:], homeDirectory: home)
        == SextantPaths(
          configurationFile: URL(
            fileURLWithPath: "/Users/test/.config/sextant/config.json"
          ),
          stateFile: URL(
            fileURLWithPath: "/Users/test/.local/state/sextant/state.json"
          )
        )
    )
    #expect(
      SextantPaths.resolve(
        environment: [
          "XDG_CONFIG_HOME": "/config",
          "XDG_STATE_HOME": "/state",
        ],
        homeDirectory: home
      )
        == SextantPaths(
          configurationFile: URL(
            fileURLWithPath: "/config/sextant/config.json"
          ),
          stateFile: URL(fileURLWithPath: "/state/sextant/state.json")
        )
    )
  }

  @Test("unknown JSON fields are tolerated and writes round-trip")
  func jsonStore() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.json")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let source = """
      {
        "version": 1,
        "showsHiddenFiles": true,
        "sort": {
          "key": "name",
          "direction": "ascending",
          "directoriesFirst": true
        },
        "watchesFileSystem": true,
        "keyOverrides": {},
        "colors": {},
        "previewAdapters": [],
        "futureField": 42
      }
      """
    try Data(source.utf8).write(to: url)
    let store = JSONFileStore<SextantConfiguration>(url: url)
    let loaded = try store.load(default: SextantConfiguration())
    #expect(loaded.showsHiddenFiles)
    try store.save(loaded)
    #expect(try store.load(default: SextantConfiguration()) == loaded)
  }

  @Test("configuration rejects duplicate chords and shell-like adapters")
  func validation() {
    var duplicate = SextantConfiguration(
      keyOverrides: [
        "navigation.up": "x",
        "navigation.down": "x",
      ]
    )
    #expect(throws: ConfigurationFailure.self) {
      _ = try duplicate.validated()
    }

    duplicate.keyOverrides = [:]
    duplicate.previewAdapters = [
      ExternalPreviewConfiguration(
        id: "unsafe",
        displayName: "Unsafe",
        executable: "tool",
        arguments: ["$(echo {path})"]
      )
    ]
    #expect(throws: ConfigurationFailure.self) {
      _ = try duplicate.validated()
    }
  }

  @Test("preview path placeholders must be standalone argv elements")
  func standalonePreviewPathArgument() {
    let embeddedPath = SextantConfiguration(
      previewAdapters: [
        ExternalPreviewConfiguration(
          id: "embedded-path",
          displayName: "Embedded Path",
          executable: "viewer",
          arguments: ["--input={path}"]
        )
      ]
    )

    #expect(
      throws: ConfigurationFailure.previewAdapterMissingPath("embedded-path")
    ) {
      _ = try embeddedPath.validated()
    }
  }

  @Test("preview adapters reject interpreter source execution")
  func interpreterSourcePreviewAdapters() {
    for adapter in [
      ExternalPreviewConfiguration(
        id: "shell-source",
        displayName: "Shell Source",
        executable: "/bin/sh",
        arguments: ["-c", "cat -- \"$1\"", "sextant-preview", "{path}"]
      ),
      ExternalPreviewConfiguration(
        id: "env-shell-source",
        displayName: "Environment Shell Source",
        executable: "/usr/bin/env",
        arguments: ["-i", "bash", "-lc", "cat -- \"$1\"", "sextant-preview", "{path}"]
      ),
    ] {
      #expect(
        throws: ConfigurationFailure.previewAdapterContainsShellSource(adapter.id)
      ) {
        _ = try SextantConfiguration(previewAdapters: [adapter]).validated()
      }
    }
  }

  @Test("configuration validates effective bindings including defaults")
  func validatesEffectiveBindings() throws {
    let configuration = SextantConfiguration(
      keyOverrides: ["navigation.up": "Ctrl-U"]
    )
    #expect(try configuration.validated() == configuration)

    let collidesWithDefault = SextantConfiguration(
      keyOverrides: ["navigation.up": "j"]
    )
    #expect(throws: ConfigurationFailure.self) {
      _ = try collidesWithDefault.validated()
    }

    let unsupportedModifier = SextantConfiguration(
      keyOverrides: ["view.palette": "Command-P"]
    )
    #expect(throws: ConfigurationFailure.self) {
      _ = try unsupportedModifier.validated()
    }
  }

  @Test("runtime-owned quit keys cannot be overridden by configuration")
  func rejectsQuitOverride() {
    let configuration = SextantConfiguration(
      keyOverrides: ["application.quit": "x"]
    )

    do {
      _ = try configuration.validated()
      Issue.record("expected the ineffective quit override to be rejected")
    } catch let failure as ConfigurationFailure {
      #expect(
        failure.localizedDescription
          == "key override for 'application.quit' is unsupported because the terminal runtime owns application exit keys"
      )
    } catch {
      Issue.record("unexpected error: \(error)")
    }
  }

  @Test("configured colors are parsed or rejected at startup")
  func configuredColors() throws {
    let configuration = SextantConfiguration(
      colors: ColorConfiguration(accent: "#123456", muted: "#ABC")
    )
    let validated = try configuration.validated()
    let expectedAccent = try Color(hex: "#123456")
    let expectedMuted = try Color(hex: "#ABC")
    #expect(validated.colors.accentColor == expectedAccent)
    #expect(validated.colors.mutedColor == expectedMuted)

    #expect(throws: ConfigurationFailure.self) {
      _ = try SextantConfiguration(
        colors: ColorConfiguration(accent: "not-a-color")
      ).validated()
    }
  }

  @Test("sort configuration preserves direction and directory grouping")
  func sortDirection() {
    let descending = SortConfiguration(
      key: .name,
      direction: .descending,
      directoriesFirst: false
    )
    #expect(descending.directorySort.key == .name)
    #expect(descending.directorySort.direction == .descending)
    #expect(!descending.directoriesFirst)
  }

  @MainActor
  @Test("versioned preview content rules map into runtime adapter policy")
  func previewAdapterRules() throws {
    let configured = ExternalPreviewConfiguration(
      id: "binary-small",
      displayName: "Binary Small",
      executable: "viewer",
      arguments: ["--", "{path}"],
      fileExtensions: ["bin"],
      priority: 42,
      isInteractive: true,
      contentKinds: [.binary],
      maximumByteCount: 1_024
    )
    _ = try SextantConfiguration(
      previewAdapters: [configured]
    ).validated()

    let adapter = SextantRootView.previewAdapter(configured)
    #expect(adapter.contentKinds == [.binary])
    #expect(adapter.maximumByteCount == 1_024)
    #expect(adapter.fileExtensions == ["bin"])
    #expect(
      adapter.arguments(URL(fileURLWithPath: "/tmp/a.bin")) == [
        "--", "/tmp/a.bin",
      ])
  }

  @Test("legacy adapter JSON receives version-one content defaults")
  func legacyPreviewAdapterDefaults() throws {
    let source = """
      {
        "id": "legacy",
        "displayName": "Legacy",
        "executable": "viewer",
        "arguments": ["--", "{path}"]
      }
      """
    let adapter = try JSONDecoder().decode(
      ExternalPreviewConfiguration.self,
      from: Data(source.utf8)
    )

    #expect(adapter.rulesVersion == 1)
    #expect(adapter.contentKinds == [.anyFile])
    #expect(adapter.maximumByteCount == nil)
    #expect(
      try SextantConfiguration(previewAdapters: [adapter]).validated()
        .previewAdapters == [adapter]
    )
  }

  @MainActor
  @Test("legacy fallback policy cannot suppress the built-in preview")
  func legacyFallbackPolicyIsIgnored() throws {
    let source = """
      {
        "id": "legacy-strict",
        "displayName": "Legacy Strict",
        "executable": "viewer",
        "arguments": ["--", "{path}"],
        "fallbackPolicy": "unavailable"
      }
      """
    let configured = try JSONDecoder().decode(
      ExternalPreviewConfiguration.self,
      from: Data(source.utf8)
    )

    let adapter = SextantRootView.previewAdapter(configured)
    let launch = PreviewResolver(adapters: [adapter]).resolve(
      url: URL(fileURLWithPath: "/tmp/value.txt"),
      classification: .text(.utf8),
      byteCount: 5,
      availableExecutables: ["viewer": "/bin/viewer"]
    )
    guard case .external = launch else {
      Issue.record("expected the configured adapter to launch")
      return
    }
  }

  @Test("preview content rules reject unknown versions and unsafe bounds")
  func invalidPreviewAdapterRules() {
    #expect(throws: ConfigurationFailure.self) {
      _ = try SextantConfiguration(
        previewAdapters: [
          ExternalPreviewConfiguration(
            id: "future",
            displayName: "Future",
            executable: "viewer",
            arguments: ["{path}"],
            rulesVersion: 2
          )
        ]
      ).validated()
    }
    #expect(throws: ConfigurationFailure.self) {
      _ = try SextantConfiguration(
        previewAdapters: [
          ExternalPreviewConfiguration(
            id: "unbounded",
            displayName: "Unbounded",
            executable: "viewer",
            arguments: ["{path}"],
            contentKinds: [],
            maximumByteCount: 0
          )
        ]
      ).validated()
    }
  }

  @Test(
    "POSIX lexer handles quoting without executing source",
    arguments: [
      ("code --wait", ["code", "--wait"]),
      ("'Visual Studio Code' --wait", ["Visual Studio Code", "--wait"]),
      ("editor \"two words\" escaped\\ value", ["editor", "two words", "escaped value"]),
      ("editor ''", ["editor", ""]),
    ])
  func lexer(source: String, expected: [String]) throws {
    #expect(try POSIXWordLexer().parse(source) == expected)
  }

  @Test("POSIX lexer reports malformed input")
  func malformedLexer() {
    #expect(throws: POSIXWordLexer.Failure.unterminatedSingleQuote) {
      _ = try POSIXWordLexer().parse("editor '")
    }
    #expect(throws: POSIXWordLexer.Failure.unterminatedDoubleQuote) {
      _ = try POSIXWordLexer().parse("editor \"")
    }
    #expect(throws: POSIXWordLexer.Failure.danglingEscape) {
      _ = try POSIXWordLexer().parse("editor \\")
    }
  }

  @Test("VISUAL takes precedence over EDITOR and configured fallback")
  func editorPrecedence() {
    let resolver = EditorCommandResolver()
    #expect(
      resolver.resolve(
        environment: [
          "VISUAL": "visual --wait",
          "EDITOR": "editor",
        ],
        configuredFallback: ["fallback"]
      ) == .success(["visual", "--wait"])
    )
  }

  @Test("live handoff resolves PATH names and preserves absolute paths and argv")
  func liveHandoffResolvesBareEditor() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("sextant-handoff-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    let decoyDirectory = directory.appendingPathComponent("decoy", isDirectory: true)
    let executableDirectory = directory.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(
      at: decoyDirectory.appendingPathComponent("fixture-editor", isDirectory: true),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: executableDirectory,
      withIntermediateDirectories: false
    )
    let executable = executableDirectory.appendingPathComponent("fixture-editor")
    let output = directory.appendingPathComponent("argv.txt")
    let source = """
      #!/bin/sh
      printf '%s\\n' "$@" > '\(output.path)'
      """
    try Data(source.utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )
    let file = directory.appendingPathComponent("name with spaces.txt")
    try Data().write(to: file)
    let client = HandoffClient.live(
      clipboard: { _ in true },
      environment: [
        "PATH": "\(decoyDirectory.path):\(executableDirectory.path)"
      ],
      editorStandardIO: .discarded
    )

    let result = await client.edit(
      ["fixture-editor", "--wait", "two words"],
      file
    )

    guard case .success = result else {
      Issue.record("bare editor launch failed: \(result)")
      return
    }
    let arguments = try String(contentsOf: output, encoding: .utf8)
      .split(separator: "\n", omittingEmptySubsequences: false)
      .dropLast()
      .map(String.init)
    #expect(arguments == ["--wait", "two words", "--", file.path])

    try FileManager.default.removeItem(at: output)
    let absoluteClient = HandoffClient.live(
      clipboard: { _ in true },
      environment: ["PATH": "/definitely/not-the-editor-directory"],
      editorStandardIO: .discarded
    )
    let absoluteResult = await absoluteClient.edit(
      [executable.path, "--absolute"],
      file
    )
    guard case .success = absoluteResult else {
      Issue.record("absolute editor launch failed: \(absoluteResult)")
      return
    }
    let absoluteArguments = try String(contentsOf: output, encoding: .utf8)
      .split(separator: "\n", omittingEmptySubsequences: false)
      .dropLast()
      .map(String.init)
    #expect(absoluteArguments == ["--absolute", "--", file.path])
  }
}

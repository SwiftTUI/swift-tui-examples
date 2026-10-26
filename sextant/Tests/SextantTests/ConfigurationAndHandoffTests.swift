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

  /// Each template runs inline program text through a common interpreter,
  /// directly, after a wrapper, or under a versioned name (README:
  /// "External templates ... cannot execute inline interpreter source").
  @Test(
    "preview adapters reject inline source for common interpreters and wrappers",
    arguments: inlineSourceTemplates
  )
  func inlineInterpreterSourcePreviewAdapters(
    executable: String,
    arguments: [String]
  ) {
    let adapter = ExternalPreviewConfiguration(
      id: executable,
      displayName: "Inline",
      executable: executable,
      arguments: arguments
    )
    #expect(
      throws: ConfigurationFailure.previewAdapterContainsShellSource(adapter.id)
    ) {
      _ = try SextantConfiguration(previewAdapters: [adapter]).validated()
    }
  }

  private static let inlineSourceTemplates: [(String, [String])] = [
    ("perl", ["-ne", "print", "{path}"]),
    ("/usr/bin/perl5.36", ["-MJSON::PP", "-E", "say 1", "{path}"]),
    ("ruby", ["-e", "puts File.read(ARGV[0])", "{path}"]),
    ("node", ["--eval=console.log(1)", "{path}"]),
    ("nodejs", ["-pe", "1", "{path}"]),
    ("bun", ["-p", "1", "{path}"]),
    ("deno", ["eval", "console.log(1)", "{path}"]),
    ("php", ["-d", "display_errors=1", "-r", "readfile($argv[1]);", "{path}"]),
    ("lua5.4", ["-e", "print(1)", "{path}"]),
    ("luajit", ["-eprint(1)", "{path}"]),
    ("osascript", ["-l", "JavaScript", "-e", "1", "{path}"]),
    ("pwsh", ["-NoProfile", "-Command", "Get-Content", "{path}"]),
    ("powershell", ["-ec", "ZQBjAGgAbwA=", "{path}"]),
    ("fish", ["-C", "cat $argv", "{path}"]),
    ("zsh", ["--command=cat", "{path}"]),
    ("timeout", ["5", "python3.12", "-Ic", "print(1)", "{path}"]),
    ("xcrun", ["python3", "-c", "print(1)", "{path}"]),
    ("busybox", ["sh", "-c", "cat \"$1\"", "sh", "{path}"]),
    ("/usr/bin/env", ["PYTHONSAFEPATH=1", "pypy3", "-c", "print(1)", "{path}"]),
  ]

  /// Templates that name an interpreter without passing it program text, or
  /// that use `-c`/`-e` as some other tool's option, stay valid.
  @Test(
    "preview adapters without inline interpreter source stay valid",
    arguments: plainTemplates
  )
  func previewAdaptersWithoutInlineSource(executable: String, arguments: [String]) throws {
    _ = try SextantConfiguration(
      previewAdapters: [
        ExternalPreviewConfiguration(
          id: "plain",
          displayName: "Plain",
          executable: executable,
          arguments: arguments
        )
      ]
    ).validated()
  }

  private static let plainTemplates: [(String, [String])] = [
    ("viewer", ["--", "{path}"]),
    ("python3", ["-m", "json.tool", "{path}"]),
    ("python3", ["-Xpycache_prefix=/tmp/c", "-Wdefault", "tool.py", "{path}"]),
    ("head", ["-c", "4096", "{path}"]),
    ("xxd", ["-c", "16", "{path}"]),
    ("bat", ["-l", "sh", "--color=always", "{path}"]),
    ("perl", ["-MJSON::PP", "-i.bak", "tool.pl", "{path}"]),
    ("php", ["-d", "error_reporting=E_ALL", "-derror_log=/dev/null", "tool.php", "{path}"]),
    ("pwsh", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "tool.ps1", "{path}"]),
    ("deno", ["run", "--allow-read", "tool.ts", "{path}"]),
    ("lua", ["-lsocket", "tool.lua", "{path}"]),
    ("nice", ["glow", "-s", "dark", "{path}"]),
  ]

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

  /// POSIX XCU 2.2.1 and 2.2.3: inside double quotes a backslash escapes only
  /// `$`, backquote, `"`, `\` and newline; backslash-newline is a line
  /// continuation in both contexts; words split only at space, tab and newline.
  @Test(
    "POSIX lexer applies the shell's backslash and blank rules",
    arguments: backslashAndBlankCases
  )
  func posixBackslashRules(source: String, expected: [String]) throws {
    let words = try POSIXWordLexer().parse(source)
    #expect(words.map { Array($0.unicodeScalars) } == expected.map { Array($0.unicodeScalars) })
  }

  private static let backslashAndBlankCases: [(String, [String])] = [
    (
      "\"\\$x\" \"\\`\" \"a\\\\b\" \"a\\b\" \"line\\\ncont\"",
      ["$x", "`", "a\\b", "a\\b", "linecont"]
    ),
    ("a \\\n b", ["a", "b"]),
    ("co\\\nde --wait", ["code", "--wait"]),
    ("a\tb\nc", ["a", "b", "c"]),
    ("'a\\b' 'c\\\nd'", ["a\\b", "c\\\nd"]),
    ("e\\\u{301}", ["e\u{301}"]),
    ("\u{A0}x\u{2003}y\u{3000}", ["\u{A0}x\u{2003}y\u{3000}"]),
  ]

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

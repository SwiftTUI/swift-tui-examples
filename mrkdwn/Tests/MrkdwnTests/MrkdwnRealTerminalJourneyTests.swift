@preconcurrency @unsafe import Dispatch
import Foundation
@_spi(Runners) @_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import Mrkdwn

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

private let mrkdwnViewerPTYTestsEnabled =
  ProcessInfo.processInfo.environment["MRKDWN_REAL_PTY_TESTS"] != nil
private let mrkdwnViewerPTYTestGateComment: Comment =
  "Production-async PTY test; set MRKDWN_REAL_PTY_TESTS=1 to run."

@MainActor
@Suite(.serialized)
struct MrkdwnRealTerminalJourneyTests {
  @Test("fallback executable discovery requires one regular non-symlink product")
  func executableDiscoveryContract() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mrkdwn-product-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("mrkdwn")
    try Data().write(to: executable)
    #expect(unsafe chmod(executable.path, 0o700) == 0)
    let symlink = directory.appendingPathComponent("mrkdwn-link")
    try FileManager.default.createSymbolicLink(
      at: symlink,
      withDestinationURL: executable
    )
    #expect(
      try uniqueRegularExecutable(from: [symlink, executable]) == executable
    )
    #expect(throws: PTYFixtureFailure.self) {
      try uniqueRegularExecutable(from: [symlink])
    }

    let second = directory.appendingPathComponent("mrkdwn-second")
    try Data().write(to: second)
    #expect(unsafe chmod(second.path, 0o700) == 0)
    #expect(throws: PTYFixtureFailure.self) {
      try uniqueRegularExecutable(from: [executable, second])
    }
    #expect(
      try preferredRegularExecutable(
        contextualCandidates: [executable],
        fallbackCandidates: [second]
      ) == executable
    )

    let nestedBundle =
      directory
      .appendingPathComponent("Debug")
      .appendingPathComponent("Tests.xctest/Contents/Resources/Fixtures.bundle")
    #expect(
      enclosingDebugProduct(for: nestedBundle)
        == directory.appendingPathComponent("Debug/mrkdwn")
    )
  }

  @Test(
    "rebuilt executable reports a platform link-opener failure",
    .enabled(if: mrkdwnViewerPTYTestsEnabled, mrkdwnViewerPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func externalLinkFailureJourney() async throws {
    let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("mrkdwn-link-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = directory.appendingPathComponent("link.md")
    try Data(
      """
      # Link failure

      [Missing attachment](missing.bin)
      """.utf8
    ).write(to: document)

    let size = CellSize(width: 90, height: 24)
    let pair = try RealTerminalPTYPair.open(size: size)
    defer { pair.close() }
    let process = try launchMrkdwn(
      arguments: [document.path, "--no-config", "--no-watch"],
      workingDirectory: directory,
      terminal: pair
    )
    do {
      var screen = ANSIVisibleScreen(size: size)
      let initial = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains("Link failure") && $0.contains("Missing attachment") }
      let lines = initial.split(separator: "\n", omittingEmptySubsequences: false)
      let row = try #require(
        lines.firstIndex(where: { $0.contains("Missing attachment") })
      )
      let line = String(lines[row])
      let range = try #require(line.range(of: "Missing attachment"))
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      let click =
        "\u{1B}[<0;\(column + 1);\(row + 1)M"
        + "\u{1B}[<0;\(column + 1);\(row + 1)m"
      try writeAllBytes(Array(click.utf8), to: pair.master)
      let failed = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains("Could not open") }
      #expect(failed.contains("Link failure"))

      let shutdownDrain = MrkdwnPTYOutputDrain(fileDescriptor: pair.master)
      try writeAllBytes(Array("q".utf8), to: pair.master)
      let status = try await waitForExit(process, timeout: .seconds(10))
      await shutdownDrain.cancel()
      #expect(status == 0)
    } catch {
      // A silent journey has two very different causes — a viewer that never
      // painted and one that already died. Record which, so a CI-only failure
      // distinguishes a startup hang from a startup crash.
      let wasRunning = process.isRunning
      if wasRunning { process.terminate() }
      pair.closeMaster()
      _ = try? await waitForExit(process, timeout: .seconds(5))
      if wasRunning {
        Issue.record("viewer was still running at the failure; terminated for cleanup")
      } else {
        let reason =
          process.terminationReason == .uncaughtSignal ? "uncaught signal" : "exit"
        Issue.record(
          "viewer had already died before the failure: \(reason) status \(process.terminationStatus)"
        )
      }
      throw error
    }
  }

  @Test(
    "rebuilt executable reaches nested Mermaid blocks with keyboard commands",
    .enabled(if: mrkdwnViewerPTYTestsEnabled, mrkdwnViewerPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func focusedNestedMermaidJourney() async throws {
    let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("mrkdwn-focus-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = directory.appendingPathComponent("focus.md")
    let source =
      """
      # Diagrams

      ```mermaid
      flowchart LR
      FIRST --> A
      style FIRST fill:#010101
      ```

      > ```mermaid
      > flowchart LR
      > SECOND --> B
      > style SECOND fill:#020202
      > ```
      """
    try Data(source.utf8).write(to: document)
    let compiled = MarkdownCompiler().compile(source: source, sourceURL: document)
    let mermaidIDs = MarkdownBlockLayout.flattened(
      compiled.blocks,
      offeredWidth: 80
    ).compactMap { descriptor -> BlockID? in
      if case .mermaid(let id, _, _) = descriptor.block { return id }
      return nil
    }
    #expect(Set(mermaidIDs).count == 2)
    let size = CellSize(width: 100, height: 80)
    let pair = try RealTerminalPTYPair.open(size: size)
    defer { pair.close() }
    let process = try launchMrkdwn(
      arguments: [document.path, "--no-config", "--no-watch"],
      workingDirectory: directory,
      terminal: pair
    )
    do {
      var screen = ANSIVisibleScreen(size: size)
      let initial = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("FIRST") && $0.contains("SECOND") && $0.contains("q quit")
      }
      #expect(!initial.contains("style FIRST fill:#010101"))
      #expect(!initial.contains("style SECOND fill:#020202"))
      // Traverse document ScrollView → first Mermaid, then exercise the
      // focused lowercase command. The surrounding Panel is a command scope,
      // not a focus stop.
      try writeAllBytes([0x09, 0x09], to: pair.master)
      try await Task.sleep(for: .milliseconds(100))
      try writeAllBytes(Array("m".utf8), to: pair.master)
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains("style FIRST fill:#010101") }

      // The newly revealed source ScrollView is the next focus stop. Alt-M
      // must dispatch from that descendant through the app-global Panel
      // command scope.
      try writeAllBytes([0x09], to: pair.master)
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains("style FIRST fill:#010101") }
      try writeAllBytes(Array("\u{1B}[109;3u".utf8), to: pair.master)
      try await Task.sleep(for: .milliseconds(200))
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains("style SECOND fill:#020202") }

      // Once every authored block has been revealed, Alt-M is a stable no-op.
      // Exercise that terminal route once more; the model test owns the exact
      // retained-set assertion while this rebuilt process proves the command
      // remains safe at the terminal boundary.
      try writeAllBytes(Array("\u{1B}[109;3u".utf8), to: pair.master)
      try await Task.sleep(for: .milliseconds(100))

      let shutdownDrain = MrkdwnPTYOutputDrain(fileDescriptor: pair.master)
      try writeAllBytes(Array("q".utf8), to: pair.master)
      let status = try await waitForExit(process, timeout: .seconds(10))
      await shutdownDrain.cancel()
      #expect(status == 0)
    } catch {
      // A silent journey has two very different causes — a viewer that never
      // painted and one that already died. Record which, so a CI-only failure
      // distinguishes a startup hang from a startup crash.
      let wasRunning = process.isRunning
      if wasRunning { process.terminate() }
      pair.closeMaster()
      _ = try? await waitForExit(process, timeout: .seconds(5))
      if wasRunning {
        Issue.record("viewer was still running at the failure; terminated for cleanup")
      } else {
        let reason =
          process.terminationReason == .uncaughtSignal ? "uncaught signal" : "exit"
        Issue.record(
          "viewer had already died before the failure: \(reason) status \(process.terminationStatus)"
        )
      }
      throw error
    }
  }

  @Test(
    "rebuilt executable covers navigation, search, Mermaid, reload, resize, and quit",
    .enabled(if: mrkdwnViewerPTYTestsEnabled, mrkdwnViewerPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func rebuiltExecutableJourney() async throws {
    let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("mrkdwn-executable-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = directory.appendingPathComponent("main.md")
    let linked = directory.appendingPathComponent("linked.md")
    let theme = directory.appendingPathComponent("theme.toml")
    try Data(
      """
      # Intro

      [Open linked document](linked.md)

      qwerty is visible and searchable.

      ## Diagram

      > ```mermaid
      > flowchart LR
      > A --> B
      > ```
      """.utf8
    ).write(to: document)
    try Data("# Linked document\n\nHistory target.".utf8).write(to: linked)
    try Data(ViewerTheme.defaultTOML.utf8).write(to: theme)

    let initialSize = CellSize(width: 90, height: 24)
    let pair = try RealTerminalPTYPair.open(size: initialSize)
    defer { pair.close() }
    let process = try launchMrkdwn(
      arguments: [
        document.path,
        "--config", theme.path,
        "--watch",
      ],
      workingDirectory: directory,
      terminal: pair
    )

    do {
      var screen = ANSIVisibleScreen(size: initialSize)
      let initial = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("mrkdwn") && $0.contains("Intro")
          && $0.contains("qwerty is visible") && $0.contains("q quit")
      }
      #expect(initial.contains("q quit"))

      // The first Tab focuses the first authored link; Return follows it
      // inside the same executable and `b` traverses the app-owned history.
      try writeAllBytes([0x09, 0x0D], to: pair.master)
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains("Linked document") && $0.contains("History target") }
      // The activated link no longer exists in the new document. Tab
      // re-establishes traversal at the root before the history command.
      try writeAllBytes([0x09], to: pair.master)
      try await Task.sleep(for: .milliseconds(100))
      try writeAllBytes(Array("b".utf8), to: pair.master)
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains("Intro") && $0.contains("qwerty is visible") }

      // Navigation replaces the focused link subtree and leaves no focused
      // leaf. The root-sweep path owns document-level commands in that state.
      try writeAllBytes(Array("/".utf8), to: pair.master)
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains("Search") && $0.contains("Type to search") }
      try writeAllBytes(Array("q".utf8), to: pair.master)
      let searched = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("Search") && $0.contains("/q")
          && $0.contains("matches") && !$0.contains("Searching")
      }
      #expect(searched.contains("matches"))
      try writeAllBytes([0x0D], to: pair.master)
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("qwerty is visible") && !$0.contains("Type to search")
      }

      // `m` resolves the first nested Mermaid block when no diagram owns
      // focus, proving recursive identity and offered-width plumbing.
      try writeAllBytes(Array("m".utf8), to: pair.master)
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains(" flowchart LR") }

      try Data(
        """
        # Intro

        watcher replacement reached the rebuilt executable.

        ## Diagram

        > ```mermaid
        > flowchart LR
        > A --> B
        > ```
        """.utf8
      ).write(to: document, options: .atomic)
      try await Task.sleep(for: .milliseconds(300))
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("watcher replacement")
          && $0.contains("reached the rebuilt")
      }

      // Atomic replacement can briefly rearm the directory source. Let the
      // independent theme watcher settle before exercising its failure lane.
      try await Task.sleep(for: .milliseconds(250))
      try Data("version = 2\n".utf8).write(to: theme, options: .atomic)
      try await Task.sleep(for: .milliseconds(300))
      let failedTheme = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains("/tmp/mrkdwn-executable-") }
      #expect(failedTheme.contains("watcher replacement"))
      #expect(failedTheme.contains("reached the rebuilt"))
      try Data(ViewerTheme.defaultTOML.utf8).write(to: theme, options: .atomic)

      let compactSize = CellSize(width: 60, height: 16)
      try resize(fileDescriptor: pair.slave, to: compactSize)
      guard kill(process.processIdentifier, SIGWINCH) == 0 else {
        throw PTYFixtureFailure.signal(errno)
      }
      screen = ANSIVisibleScreen(size: compactSize)
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("mrkdwn") && $0.contains("watcher")
          && $0.contains("replacement") && $0.contains("executable")
          && $0.contains("q quit")
      }

      let shutdownDrain = MrkdwnPTYOutputDrain(fileDescriptor: pair.master)
      try writeAllBytes(Array("q".utf8), to: pair.master)
      let status = try await waitForExit(process, timeout: .seconds(10))
      await shutdownDrain.cancel()
      #expect(status == 0)
    } catch {
      // A silent journey has two very different causes — a viewer that never
      // painted and one that already died. Record which, so a CI-only failure
      // distinguishes a startup hang from a startup crash.
      let wasRunning = process.isRunning
      if wasRunning { process.terminate() }
      pair.closeMaster()
      _ = try? await waitForExit(process, timeout: .seconds(5))
      if wasRunning {
        Issue.record("viewer was still running at the failure; terminated for cleanup")
      } else {
        let reason =
          process.terminationReason == .uncaughtSignal ? "uncaught signal" : "exit"
        Issue.record(
          "viewer had already died before the failure: \(reason) status \(process.terminationStatus)"
        )
      }
      throw error
    }
  }

  @Test(
    "rebuilt executable reads stdin once, rebinds fd zero to the PTY, and quits",
    .enabled(if: mrkdwnViewerPTYTestsEnabled, mrkdwnViewerPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func stdinReadThenPTYJourney() async throws {
    let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
    let size = CellSize(width: 90, height: 24)
    let pair = try RealTerminalPTYPair.open(size: size)
    defer { pair.close() }
    let documentPipe = Pipe()
    let process = try launchMrkdwn(
      arguments: ["-", "--no-config"],
      workingDirectory: directory,
      terminal: pair,
      standardInput: documentPipe
    )
    documentPipe.fileHandleForWriting.write(
      Data("# Piped document\n\ninteractive handoff reached".utf8)
    )
    try documentPipe.fileHandleForWriting.close()

    do {
      var screen = ANSIVisibleScreen(size: size)
      let visible = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("Piped document") && $0.contains("interactive handoff reached")
          && $0.contains("q quit")
      }
      #expect(visible.contains("q quit"))

      let shutdownDrain = MrkdwnPTYOutputDrain(fileDescriptor: pair.master)
      try writeAllBytes(Array("q".utf8), to: pair.master)
      let status = try await waitForExit(process, timeout: .seconds(10))
      await shutdownDrain.cancel()
      #expect(status == 0)
    } catch {
      // A silent journey has two very different causes — a viewer that never
      // painted and one that already died. Record which, so a CI-only failure
      // distinguishes a startup hang from a startup crash.
      let wasRunning = process.isRunning
      if wasRunning { process.terminate() }
      pair.closeMaster()
      _ = try? await waitForExit(process, timeout: .seconds(5))
      if wasRunning {
        Issue.record("viewer was still running at the failure; terminated for cleanup")
      } else {
        let reason =
          process.terminationReason == .uncaughtSignal ? "uncaught signal" : "exit"
        Issue.record(
          "viewer had already died before the failure: \(reason) status \(process.terminationStatus)"
        )
      }
      throw error
    }
  }

  @Test(
    "rebuilt executable reads stdin, acquires its controlling PTY, and quits",
    .enabled(if: mrkdwnViewerPTYTestsEnabled, mrkdwnViewerPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func controllingTerminalStdinJourney() async throws {
    let size = CellSize(width: 90, height: 24)
    let documentPipe = Pipe()
    let process = try launchMrkdwnWithControllingTerminal(
      executable: mrkdwnExecutableURL(),
      size: size,
      standardInput: documentPipe
    )
    defer { _ = close(process.master) }
    documentPipe.fileHandleForWriting.write(
      Data("# Controlling terminal\n\nstdin ownership survived".utf8)
    )
    try documentPipe.fileHandleForWriting.close()

    do {
      var screen = ANSIVisibleScreen(size: size)
      let visible = try await waitForANSIVisibleScreen(
        on: process.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("Controlling terminal") && $0.contains("stdin ownership survived")
          && $0.contains("q quit")
      }
      #expect(visible.contains("q quit"))

      let shutdownDrain = MrkdwnPTYOutputDrain(fileDescriptor: process.master)
      try writeAllBytes(Array("q".utf8), to: process.master)
      let status = try await waitForExit(process.processIdentifier, timeout: .seconds(10))
      await shutdownDrain.cancel()
      #expect(processExitedSuccessfully(status))
    } catch {
      _ = kill(-process.processIdentifier, SIGTERM)
      _ = kill(process.processIdentifier, SIGTERM)
      _ = try? await waitForExit(process.processIdentifier, timeout: .seconds(5))
      throw error
    }
  }

  @Test(
    "invalid path and explicit config fail before alternate-screen takeover",
    .enabled(if: mrkdwnViewerPTYTestsEnabled, mrkdwnViewerPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func preflightFailuresStayOutsideAlternateScreen() async throws {
    let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("mrkdwn-preflight-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let validDocument = directory.appendingPathComponent("valid.md")
    let invalidTheme = directory.appendingPathComponent("invalid-theme.toml")
    try Data("# Valid".utf8).write(to: validDocument)
    try Data("version = 2\n".utf8).write(to: invalidTheme)

    for arguments in [
      [directory.appendingPathComponent("missing.md").path],
      [validDocument.path, "--config", invalidTheme.path],
    ] {
      let pair = try RealTerminalPTYPair.open(size: CellSize(width: 80, height: 24))
      let process = try launchMrkdwn(
        arguments: arguments,
        workingDirectory: directory,
        terminal: pair
      )
      let capture = try await captureUntilExit(
        process,
        fileDescriptor: pair.master,
        timeout: .seconds(10)
      )
      pair.close()
      #expect(capture.status != 0)
      #expect(!capture.bytes.containsSubsequence(Array("\u{1B}[?1049h".utf8)))
      #expect(!capture.bytes.containsSubsequence(Array("\u{1B}[?1049l".utf8)))
      let output = String(decoding: capture.bytes, as: UTF8.self)
      #expect(output.contains("missing.md") || output.contains("unsupported theme version 2"))
    }
  }

  @Test(
    "rebuilt executable paints content, authors q in search, and quits",
    .enabled(if: mrkdwnViewerPTYTestsEnabled, mrkdwnViewerPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func searchAndQuitJourney() async throws {
    let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("mrkdwn-search-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = directory.appendingPathComponent("search.md")
    try Data(
      """
      # Intro

      qwerty is visible and searchable.
      """.utf8
    ).write(to: document)

    let size = CellSize(width: 90, height: 24)
    let pair = try RealTerminalPTYPair.open(size: size)
    defer { pair.close() }
    let process = try launchMrkdwn(
      arguments: [document.path, "--no-config", "--no-watch"],
      workingDirectory: directory,
      terminal: pair
    )

    do {
      var screen = ANSIVisibleScreen(size: size)
      let initial = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("mrkdwn") && $0.contains("Intro")
          && $0.contains("qwerty is visible") && $0.contains("q quit")
      }
      #expect(initial.contains("q quit"))

      try writeAllBytes(Array("/".utf8), to: pair.master)
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains("Search") && $0.contains("Type to search") }
      try writeAllBytes(Array("q".utf8), to: pair.master)
      let searched = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("Search") && $0.contains("/q")
          && $0.contains("matches") && !$0.contains("Searching")
      }
      #expect(searched.contains("matches"))

      try writeAllBytes([0x1B], to: pair.master)
      _ = try await waitForANSIVisibleScreen(
        on: pair.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("qwerty is visible") && !$0.contains("Type to search")
      }
      let shutdownDrain = MrkdwnPTYOutputDrain(fileDescriptor: pair.master)
      try writeAllBytes(Array("q".utf8), to: pair.master)
      let status = try await waitForExit(process, timeout: .seconds(10))
      await shutdownDrain.cancel()
      #expect(status == 0)
    } catch {
      // A silent journey has two very different causes — a viewer that never
      // painted and one that already died. Record which, so a CI-only failure
      // distinguishes a startup hang from a startup crash.
      let wasRunning = process.isRunning
      if wasRunning { process.terminate() }
      pair.closeMaster()
      _ = try? await waitForExit(process, timeout: .seconds(5))
      if wasRunning {
        Issue.record("viewer was still running at the failure; terminated for cleanup")
      } else {
        let reason =
          process.terminationReason == .uncaughtSignal ? "uncaught signal" : "exit"
        Issue.record(
          "viewer had already died before the failure: \(reason) status \(process.terminationStatus)"
        )
      }
      throw error
    }
  }
}

private enum PTYFixtureFailure: Error {
  case unavailable
  case timedOut
  case executableNotFound(String)
  case ambiguousExecutables([String])
  case processTimedOut
  case resize(Int32)
  case signal(Int32)
}

@MainActor
private func launchMrkdwn(
  arguments: [String],
  workingDirectory: URL,
  terminal: RealTerminalPTYPair,
  standardInput: Any? = nil
) throws -> Process {
  let executable = try mrkdwnExecutableURL()
  let process = Process()
  process.executableURL = executable
  process.arguments = arguments
  process.currentDirectoryURL = workingDirectory
  var environment = ProcessInfo.processInfo.environment
  environment["TERM"] = "xterm-256color"
  process.environment = environment
  let terminalHandle = FileHandle(
    fileDescriptor: terminal.slave,
    closeOnDealloc: false
  )
  process.standardInput = standardInput ?? terminalHandle
  process.standardOutput = terminalHandle
  process.standardError = terminalHandle
  try process.run()
  return process
}

private struct ControllingTerminalProcess {
  var processIdentifier: pid_t
  var master: Int32
}

private func launchMrkdwnWithControllingTerminal(
  executable: URL,
  size: CellSize,
  standardInput: Pipe
) throws -> ControllingTerminalProcess {
  #if canImport(Darwin) || canImport(Glibc)
    guard
      var argumentPointers = unsafe makeCStringArray([
        executable.path,
        "-",
        "--no-config",
      ])
    else {
      throw PTYFixtureFailure.unavailable
    }
    defer { unsafe releaseCStringArray(argumentPointers) }

    var master: Int32 = -1
    var windowSize = winsize(
      ws_row: UInt16(max(1, size.height)),
      ws_col: UInt16(max(1, size.width)),
      ws_xpixel: 0,
      ws_ypixel: 0
    )
    let documentReader = standardInput.fileHandleForReading.fileDescriptor
    let documentWriter = standardInput.fileHandleForWriting.fileDescriptor
    let processIdentifier = argumentPointers.withUnsafeMutableBufferPointer {
      argumentBuffer -> pid_t in
      let child = unsafe forkpty(&master, nil, nil, &windowSize)
      guard child == 0 else { return child }
      guard dup2(documentReader, STDIN_FILENO) >= 0 else { _exit(97) }
      if documentReader != STDIN_FILENO {
        _ = close(documentReader)
      }
      _ = close(documentWriter)
      unsafe execv(argumentBuffer[0]!, argumentBuffer.baseAddress!)
      _exit(98)
    }
    guard processIdentifier > 0 else {
      throw RealTerminalJourneyError.operationFailed(
        operation: "forkpty",
        errno: errno
      )
    }
    try standardInput.fileHandleForReading.close()

    let currentFlags = fcntl(master, F_GETFL)
    guard currentFlags >= 0, fcntl(master, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
      let errorNumber = errno
      _ = kill(-processIdentifier, SIGTERM)
      _ = kill(processIdentifier, SIGTERM)
      _ = close(master)
      throw RealTerminalJourneyError.operationFailed(
        operation: "fcntl",
        errno: errorNumber
      )
    }
    return ControllingTerminalProcess(
      processIdentifier: processIdentifier,
      master: master
    )
  #else
    throw PTYFixtureFailure.unavailable
  #endif
}

private func makeCStringArray(
  _ strings: [String]
) -> [UnsafeMutablePointer<CChar>?]? {
  var result: [UnsafeMutablePointer<CChar>?] = unsafe []
  unsafe result.reserveCapacity(strings.count + 1)
  for string in strings {
    guard let pointer = unsafe strdup(string) else {
      unsafe releaseCStringArray(result)
      return nil
    }
    unsafe result.append(pointer)
  }
  unsafe result.append(nil)
  return unsafe result
}

private func releaseCStringArray(
  _ pointers: [UnsafeMutablePointer<CChar>?]
) {
  var index = 0
  while index < (unsafe pointers.count) {
    let pointer = unsafe pointers[index]
    unsafe free(pointer)
    index += 1
  }
}

private func processExitedSuccessfully(_ status: Int32) -> Bool {
  status & 0x7F == 0 && (status >> 8) & 0xFF == 0
}

private func waitForExit(
  _ processIdentifier: pid_t,
  timeout: Duration
) async throws -> Int32 {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  while clock.now < deadline {
    var status: Int32 = 0
    let result = unsafe waitpid(processIdentifier, &status, WNOHANG)
    if result == processIdentifier {
      return status
    }
    if result < 0, errno != EINTR {
      throw RealTerminalJourneyError.operationFailed(
        operation: "waitpid",
        errno: errno
      )
    }
    try await Task.sleep(for: .milliseconds(10))
  }
  throw PTYFixtureFailure.processTimedOut
}

private func mrkdwnExecutableURL() throws -> URL {
  let bundleURL = Bundle.module.bundleURL
  let colocated =
    bundleURL
    .deletingLastPathComponent()
    .appendingPathComponent("mrkdwn")
  let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let buildRoot = packageRoot.appendingPathComponent(".build", isDirectory: true)
  var contextualCandidates = [colocated]
  if let enclosingProduct = enclosingDebugProduct(for: bundleURL) {
    contextualCandidates.append(enclosingProduct)
  }
  var fallbackCandidates = [
    buildRoot.appendingPathComponent("out/Products/Debug/mrkdwn")
  ]
  let platformDirectories =
    (try? FileManager.default.contentsOfDirectory(
      at: buildRoot,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )) ?? []
  fallbackCandidates.append(
    contentsOf: platformDirectories.map {
      $0.appendingPathComponent("debug/mrkdwn")
    }
  )
  return try preferredRegularExecutable(
    contextualCandidates: contextualCandidates,
    fallbackCandidates: fallbackCandidates
  )
}

private func enclosingDebugProduct(for bundleURL: URL) -> URL? {
  var ancestor = bundleURL.deletingLastPathComponent()
  for _ in 0..<8 {
    if ancestor.lastPathComponent == "debug"
      || ancestor.lastPathComponent == "Debug"
    {
      return ancestor.appendingPathComponent("mrkdwn")
    }
    let parent = ancestor.deletingLastPathComponent()
    guard parent != ancestor else { return nil }
    ancestor = parent
  }
  return nil
}

private func preferredRegularExecutable(
  contextualCandidates: [URL],
  fallbackCandidates: [URL]
) throws -> URL {
  let contextualExecutables = contextualCandidates.filter(isRegularExecutableFile)
  if !contextualExecutables.isEmpty {
    return try uniqueRegularExecutable(from: contextualExecutables)
  }
  return try uniqueRegularExecutable(from: fallbackCandidates)
}

private func uniqueRegularExecutable(from candidates: [URL]) throws -> URL {
  var uniqueCandidates: [String: URL] = [:]
  for candidate in candidates {
    uniqueCandidates[candidate.standardizedFileURL.path] = candidate
  }
  let executables = uniqueCandidates.values
    .filter(isRegularExecutableFile)
    .sorted { $0.path < $1.path }
  switch executables.count {
  case 1:
    return executables[0]
  case 0:
    throw PTYFixtureFailure.executableNotFound(
      uniqueCandidates.keys.sorted().joined(separator: ", ")
    )
  default:
    throw PTYFixtureFailure.ambiguousExecutables(executables.map(\.path))
  }
}

private func isRegularExecutableFile(_ url: URL) -> Bool {
  var metadata = stat()
  let status = unsafe url.path.withCString {
    unsafe lstat($0, &metadata)
  }
  guard status == 0, metadata.st_mode & S_IFMT == S_IFREG else {
    return false
  }
  return FileManager.default.isExecutableFile(atPath: url.path)
}

@MainActor
private func waitForExit(
  _ process: Process,
  timeout: Duration
) async throws -> Int32 {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  while process.isRunning, clock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  guard !process.isRunning else { throw PTYFixtureFailure.processTimedOut }
  return process.terminationStatus
}

@MainActor
private func captureUntilExit(
  _ process: Process,
  fileDescriptor: Int32,
  timeout: Duration
) async throws -> (status: Int32, bytes: [UInt8]) {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  var bytes: [UInt8] = []
  while process.isRunning, clock.now < deadline {
    bytes.append(contentsOf: try readAvailableBytes(from: fileDescriptor))
    try await Task.sleep(for: .milliseconds(10))
  }
  guard !process.isRunning else {
    process.terminate()
    throw PTYFixtureFailure.processTimedOut
  }
  for _ in 0..<10 {
    let next = try readAvailableBytes(from: fileDescriptor)
    bytes.append(contentsOf: next)
    if next.isEmpty { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  return (process.terminationStatus, bytes)
}

private func readAvailableBytes(from fileDescriptor: Int32) throws -> [UInt8] {
  var result: [UInt8] = []
  var buffer = [UInt8](repeating: 0, count: 4_096)
  while true {
    let count = unsafe buffer.withUnsafeMutableBytes {
      unsafe read(fileDescriptor, $0.baseAddress, $0.count)
    }
    if count > 0 {
      result.append(contentsOf: buffer.prefix(count))
      continue
    }
    if count == 0 { return result }
    if errno == EINTR { continue }
    if errno == EAGAIN || errno == EWOULDBLOCK { return result }
    throw RealTerminalJourneyError.operationFailed(
      operation: "read",
      errno: errno
    )
  }
}

private func resize(fileDescriptor: Int32, to size: CellSize) throws {
  #if canImport(Darwin) || canImport(Glibc)
    var windowSize = winsize(
      ws_row: UInt16(max(1, size.height)),
      ws_col: UInt16(max(1, size.width)),
      ws_xpixel: 0,
      ws_ypixel: 0
    )
    guard unsafe ioctl(fileDescriptor, UInt(TIOCSWINSZ), &windowSize) == 0 else {
      throw PTYFixtureFailure.resize(errno)
    }
  #else
    throw PTYFixtureFailure.unavailable
  #endif
}

extension [UInt8] {
  fileprivate func containsSubsequence(_ needle: [UInt8]) -> Bool {
    guard !needle.isEmpty, count >= needle.count else { return false }
    return indices.dropLast(needle.count - 1).contains { start in
      Array(self[start..<(start + needle.count)]) == needle
    }
  }
}

private final class MrkdwnPTYOutputDrain: Sendable {
  private struct State {
    var cancelled = false
    var cancellationWaiter: CheckedContinuation<Void, Never>?
  }

  private let source: any DispatchSourceRead
  private let state = Mutex(State())

  init(fileDescriptor: Int32) {
    let queue = DispatchQueue(label: "MrkdwnTests.PTYOutputDrain")
    let source = DispatchSource.makeReadSource(
      fileDescriptor: fileDescriptor,
      queue: queue
    )
    self.source = source
    source.setEventHandler {
      var buffer = [UInt8](repeating: 0, count: 4_096)
      while true {
        let count = unsafe buffer.withUnsafeMutableBytes {
          unsafe read(fileDescriptor, $0.baseAddress, $0.count)
        }
        if count > 0 { continue }
        if count < 0, errno == EINTR { continue }
        return
      }
    }
    source.setCancelHandler { [weak self] in
      self?.didCancel()
    }
    source.resume()
  }

  func cancel() async {
    source.cancel()
    await withCheckedContinuation { continuation in
      state.withLock {
        if $0.cancelled {
          continuation.resume()
        } else {
          $0.cancellationWaiter = continuation
        }
      }
    }
  }

  private func didCancel() {
    let waiter = state.withLock {
      $0.cancelled = true
      let waiter = $0.cancellationWaiter
      $0.cancellationWaiter = nil
      return waiter
    }
    waiter?.resume()
  }
}

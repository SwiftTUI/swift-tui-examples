@preconcurrency @unsafe import Dispatch
import Foundation
@_spi(Runners) @_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import CSVUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

private let csvuiPTYTestsEnabled =
  ProcessInfo.processInfo.environment["CSVUI_REAL_PTY_TESTS"] != nil
private let csvuiLatencyPTYTestsEnabled =
  csvuiPTYTestsEnabled
  || ProcessInfo.processInfo.environment["CSVUI_LATENCY_PTY_TESTS"] != nil
private let csvuiPTYTestGateComment: Comment =
  "Production-async PTY test; set CSVUI_REAL_PTY_TESTS=1 to run."

@MainActor
@Suite(.serialized)
struct CSVUIRealTerminalJourneyTests {
  @Test(
    "settled generated 100x40 document responds to cursor actions within the regression ceiling",
    .enabled(
      if: csvuiLatencyPTYTestsEnabled,
      "Performance guard; set CSVUI_REAL_PTY_TESTS=1 to run the full PTY gate."
    ),
    .timeLimit(.minutes(1))
  )
  func generatedCursorLatencyGuard() async throws {
    let directory = try makeCSVUITemporaryDirectory("latency")
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = directory.appendingPathComponent("generated.tsv")
    let header = (0..<12).map { "c\($0)" }.joined(separator: "\t")
    let rows = (0..<240).map { row in
      (0..<12).map { column in "r\(row)c\(column)" }.joined(separator: "\t")
    }
    try Data(([header] + rows).joined(separator: "\n").utf8).write(to: document)

    try await withCSVUITerminalSession(
      arguments: [document.path, "--no-config", "--no-watch"],
      workingDirectory: directory,
      size: CellSize(width: 100, height: 40)
    ) { session in
      _ = try await session.wait("settled generated grid") {
        $0.contains("A1 · c0 · r0c0") && $0.contains("r36c0")
      }

      let firstStarted = ContinuousClock.now
      try session.send("l")
      _ = try await session.wait("one generated cursor action", timeout: .seconds(10)) {
        $0.contains("B1 · c1 · r0c1")
      }
      let firstElapsed = firstStarted.duration(to: .now)
      #expect(
        firstElapsed < .seconds(2),
        "first cursor action exceeded the generous regression ceiling: \(firstElapsed)"
      )

      let secondStarted = ContinuousClock.now
      try session.send("l")
      _ = try await session.wait("second generated cursor action", timeout: .seconds(10)) {
        $0.contains("C1 · c2 · r0c2")
      }
      let secondElapsed = secondStarted.duration(to: .now)
      #expect(
        secondElapsed < .seconds(2),
        "second cursor action exceeded the generous regression ceiling: \(secondElapsed)"
      )
      #expect(try await session.finish(sending: Array("q".utf8)) == 0)
    }
  }

  @Test(
    "rebuilt executable edits a cell and guards dirty quit",
    .enabled(if: csvuiPTYTestsEnabled, csvuiPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func editAndDirtyQuitJourney() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("csvui-pty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let document = directory.appendingPathComponent("people.csv")
    try Data(
      """
      name,city
      Alice,Seattle
      Bob,Portland

      """.utf8
    ).write(to: document)

    let size = CellSize(width: 100, height: 28)
    let terminal = try RealTerminalPTYPair.open(size: size)
    defer { terminal.close() }
    let process = try launchCSVUI(
      arguments: [document.path, "--no-config", "--no-watch"],
      workingDirectory: directory,
      terminal: terminal
    )

    do {
      var screen = ANSIVisibleScreen(size: size)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) { $0.contains("Alice") && $0.contains("Seattle") }

      // SGR wheel-down/up over the virtualized grid uses the app-owned wheel
      // route without materializing offscreen rows.
      try writeAllBytes(Array("\u{1B}[<65;10;4M".utf8), to: terminal.master)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) { $0.contains("A2 · name · Bob") }
      try writeAllBytes(Array("\u{1B}[<64;10;4M".utf8), to: terminal.master)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) { $0.contains("A1 · name · Alice") }

      try writeAllBytes(Array("e".utf8), to: terminal.master)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) { $0.contains("Edit name") && $0.contains("Save  Ctrl-S") }

      // `q` is an application quit command only in browse mode. A focused
      // TextEditor must receive it as ordinary text and keep the app alive.
      try writeAllBytes(Array("q".utf8), to: terminal.master)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) { $0.contains("qAlice") || $0.contains("Aliceq") }
      #expect(process.isRunning)

      // Tab reaches the focusable Save button and Return activates it.
      try writeAllBytes([0x09, 0x0D], to: terminal.master)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) {
        !$0.contains("Edit name") && ($0.contains("qAlice") || $0.contains("Aliceq"))
      }

      try writeAllBytes(Array("e".utf8), to: terminal.master)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) { $0.contains("Edit name") && $0.contains("Save  Ctrl-S") }
      try writeAllBytes(Array("discard-me".utf8), to: terminal.master)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) { $0.contains("discard-me") }
      // Shift-Tab wraps backward from the editor to Cancel; Return dismisses
      // the overlay without committing the local editor value.
      try writeAllBytes([0x1B, 0x5B, 0x5A, 0x0D], to: terminal.master)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) {
        !$0.contains("Edit name") && !$0.contains("discard-me")
          && ($0.contains("qAlice") || $0.contains("Aliceq"))
      }

      try writeAllBytes(Array("q".utf8), to: terminal.master)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) { $0.contains("Save changes before quitting?") }

      try writeAllBytes([0x1B], to: terminal.master)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) { !$0.contains("Save changes before quitting?") && $0.contains("Seattle") }
      #expect(process.isRunning)

      try writeAllBytes(Array("q".utf8), to: terminal.master)
      _ = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) { $0.contains("Save changes before quitting?") }
      let shutdownDrain = CSVUIPTYOutputDrain(fileDescriptor: terminal.master)
      try writeAllBytes(Array("D".utf8), to: terminal.master)
      let status: Int32
      do {
        status = try await waitForExit(process, timeout: .seconds(10))
      } catch {
        await shutdownDrain.cancel()
        throw error
      }
      await shutdownDrain.cancel()
      #expect(status == 0)
    } catch {
      let wasRunning = process.isRunning
      if wasRunning { process.terminate() }
      terminal.closeMaster()
      _ = try? await waitForExit(process, timeout: .seconds(5))
      if wasRunning {
        Issue.record("csvui was still running at the failure; terminated for cleanup")
      } else {
        Issue.record("csvui exited early with status \(process.terminationStatus)")
      }
      throw error
    }
  }

  @Test(
    "rebuilt executable navigates the virtual grid and opens row detail",
    .enabled(if: csvuiPTYTestsEnabled, csvuiPTYTestGateComment),
    .timeLimit(.minutes(2))
  )
  func viewerNavigationJourney() async throws {
    let directory = try makeCSVUITemporaryDirectory("viewer")
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = directory.appendingPathComponent("wide.csv")
    let rows = (0..<50).map { "r\($0)a,r\($0)b,r\($0)c,r\($0)d,r\($0)e" }
    try Data((["c1,c2,c3,c4,c5"] + rows).joined(separator: "\n").utf8).write(to: document)

    try await withCSVUITerminalSession(
      arguments: [document.path, "--no-config", "--no-watch"],
      workingDirectory: directory
    ) { session in
      _ = try await session.wait("initial viewer") { $0.contains("A1 · c1 · r0a") }
      try session.send(bytes: [0x1B, 0x5B, 0x36, 0x7E])  // Page Down
      _ = try await session.wait("page down") { $0.contains("A26 · c1 · r25a") }
      try session.send("$")
      _ = try await session.wait("last column") { $0.contains("E26 · c5 · r25e") }
      try session.send(bytes: [0x0D])
      _ = try await session.wait("row detail") { $0.contains("Row 26") && $0.contains("r25e") }
      try session.send(bytes: [0x1B])
      _ = try await session.wait("dismiss row detail") {
        !$0.contains("Row 26") && $0.contains("E26 · c5 · r25e")
      }
      try session.send("z]")
      try await Task.sleep(for: .milliseconds(100))
      try session.send("y")
      _ = try await session.wait("copy") {
        $0.contains("copied cell") || $0.contains("clipboard unavailable")
      }
      #expect(try await session.finish(sending: Array("q".utf8)) == 0)
    }
  }

  @Test(
    "rebuilt executable searches, filters, sorts, and resets projections",
    .enabled(if: csvuiPTYTestsEnabled, csvuiPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func projectionJourney() async throws {
    let directory = try makeCSVUITemporaryDirectory("projection")
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = directory.appendingPathComponent("places.csv")
    try Data(
      """
      id,name,city
      1,Alice,Seattle
      2,Bob,Portland
      3,Alice,Austin
      4,Cara,Seattle

      """.utf8
    ).write(to: document)

    try await withCSVUITerminalSession(
      arguments: [document.path, "--no-config", "--no-watch"],
      workingDirectory: directory
    ) { session in
      _ = try await session.wait { $0.contains("Alice") && $0.contains("Seattle") }
      try session.send("/Seattle")
      try session.send(bytes: [0x0D])
      _ = try await session.wait { $0.contains("MATCH 2") && $0.contains("C1 · city · Seattle") }
      try session.send("n")
      _ = try await session.wait { $0.contains("C4 · city · Seattle") }
      try session.send("NfPortland")
      try session.send(bytes: [0x0D])
      _ = try await session.wait { $0.contains("FILTER 1/4") && $0.contains("Portland") }
      try session.send("s")
      _ = try await session.wait { $0.contains("SORT city ↑") }
      try session.send("r")
      _ = try await session.wait {
        $0.contains("Alice") && !$0.contains("FILTER ") && !$0.contains("SORT city")
          && !$0.contains("MATCH ")
      }
      #expect(try await session.finish(sending: Array("q".utf8)) == 0)
    }
  }

  @Test(
    "multiline edit survives undo redo and dirty-quit Save",
    .enabled(if: csvuiPTYTestsEnabled, csvuiPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func multilineSaveJourney() async throws {
    let directory = try makeCSVUITemporaryDirectory("save")
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = directory.appendingPathComponent("notes.csv")
    try Data("note,other\n,x\n".utf8).write(to: document)

    try await withCSVUITerminalSession(
      arguments: [document.path, "--no-config", "--no-watch"],
      workingDirectory: directory
    ) { session in
      _ = try await session.wait("initial multiline grid") { $0.contains("A1 · note ·") }
      try session.send("e")
      _ = try await session.wait("multiline editor") {
        $0.contains("Edit note") && $0.contains("Save  Ctrl-S")
      }
      try session.send("Line1")
      try session.send(bytes: [0x0D])
      try session.send("Line2")
      _ = try await session.wait("multiline editor accepted input") {
        $0.contains("Line1") && $0.contains("Line2")
      }
      try session.send(bytes: [0x13])
      _ = try await session.wait("committed multiline value") { $0.contains("Line1↵Line2") }
      try session.send("u")
      try session.send(bytes: [0x12])  // Ctrl-R
      _ = try await session.wait("redone multiline value") { $0.contains("Line1↵Line2") }
      try session.send("q")
      _ = try await session.wait("multiline dirty quit") {
        $0.contains("Save changes before quitting?")
      }
      #expect(try await session.finish(sending: Array("S".utf8)) == 0)
    }

    #expect(try Data(contentsOf: document) == Data("note,other\n\"Line1\nLine2\",x\n".utf8))
    try await withCSVUITerminalSession(
      arguments: [document.path, "--no-config", "--no-watch"],
      workingDirectory: directory
    ) { session in
      _ = try await session.wait("reopened multiline value") {
        $0.contains("Line1↵Line2") && $0.contains("A1 · note ·")
      }
      #expect(try await session.finish(sending: Array("q".utf8)) == 0)
    }
  }

  @Test(
    "source and theme watchers retain last-good state and report dirty conflict",
    .enabled(if: csvuiPTYTestsEnabled, csvuiPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func watcherAndConflictJourney() async throws {
    let directory = try makeCSVUITemporaryDirectory("watchers")
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = directory.appendingPathComponent("watched.csv")
    let theme = directory.appendingPathComponent("theme.toml")
    try Data("name,city\nAlice,Seattle\n".utf8).write(to: document)
    try Data(CSVTheme.defaultTOML.utf8).write(to: theme)

    try await withCSVUITerminalSession(
      arguments: [document.path, "--config", theme.path, "--watch"],
      workingDirectory: directory,
      size: CellSize(width: 180, height: 40)
    ) { session in
      _ = try await session.wait { $0.contains("Alice") && $0.contains("Seattle") }
      try Data("name,city\nBob,Portland\n".utf8).write(to: document, options: .atomic)
      _ = try await session.wait { $0.contains("Bob") && $0.contains("Portland") }

      try Data("name,city\n\"broken".utf8).write(to: document, options: .atomic)
      _ = try await session.wait {
        $0.contains("unclosed quoted field") && $0.contains("Portland")
      }
      try Data("name,city\nCara,Austin\n".utf8).write(to: document, options: .atomic)
      _ = try await session.wait { $0.contains("Cara") && $0.contains("Austin") }

      try Data("version = 2\n".utf8).write(to: theme, options: .atomic)
      _ = try await session.wait {
        $0.contains("unsupported theme version 2") && $0.contains("Cara")
      }
      try Data(CSVTheme.defaultTOML.utf8).write(to: theme, options: .atomic)
      try await Task.sleep(for: .milliseconds(300))

      try session.send("e")
      _ = try await session.wait { $0.contains("Edit name") && $0.contains("Save  Ctrl-S") }
      try session.send("q")
      _ = try await session.wait("watcher editor accepted input") {
        $0.contains("qCara") || $0.contains("Caraq")
      }
      try session.send(bytes: [0x13])
      _ = try await session.wait { $0.contains("qCara") || $0.contains("Caraq") }
      try Data("name,city\nDana,Denver\n".utf8).write(to: document, options: .atomic)
      _ = try await session.wait { $0.contains("EXTERNAL CHANGE") }
      try session.send("q")
      _ = try await session.wait { $0.contains("Save changes before quitting?") }
      #expect(try await session.finish(sending: Array("D".utf8)) == 0)
    }
  }

  @Test(
    "stdin hands interaction to the PTY and Save As publishes a new file",
    .enabled(if: csvuiPTYTestsEnabled, csvuiPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func standardInputSaveAsJourney() async throws {
    let directory = try makeCSVUITemporaryDirectory("stdin")
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("standard-input.csv")
    try Data("note,other\n,x\n".utf8).write(to: input)
    let standardInput = try FileHandle(forReadingFrom: input)
    defer { try? standardInput.close() }

    try await withCSVUITerminalSession(
      arguments: ["-", "--no-config"],
      workingDirectory: directory,
      standardInput: standardInput
    ) { session in
      _ = try await session.wait { $0.contains("A1 · note ·") }
      try session.send("e")
      _ = try await session.wait { $0.contains("Edit note") && $0.contains("Save  Ctrl-S") }
      try session.send("stdin-value")
      _ = try await session.wait("stdin editor accepted input") { $0.contains("stdin-value") }
      try session.send(bytes: [0x13])
      _ = try await session.wait { $0.contains("stdin-value") }
      try session.send(bytes: [0x13])
      _ = try await session.wait { $0.contains("Save As") && $0.contains("stdin▏") }
      try session.send(bytes: Array(repeating: 0x7F, count: 5))
      try session.send("stdin-saved.csv")
      try session.send(bytes: [0x0D])
      _ = try await session.wait { $0.contains("saved stdin-saved.csv") }
      #expect(try await session.finish(sending: Array("q".utf8)) == 0)
    }

    let saved = directory.appendingPathComponent("stdin-saved.csv")
    #expect(try Data(contentsOf: saved) == Data("note,other\nstdin-value,x\n".utf8))
  }

  @Test(
    "read-only symlink source survives full compact and below-floor resize",
    .enabled(if: csvuiPTYTestsEnabled, csvuiPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func readOnlyResizeJourney() async throws {
    let directory = try makeCSVUITemporaryDirectory("resize")
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = directory.appendingPathComponent("source.csv")
    let link = directory.appendingPathComponent("linked.csv")
    try Data("name,city\nAlice,Seattle\n".utf8).write(to: document)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: document)

    try await withCSVUITerminalSession(
      arguments: [link.path, "--read-only", "--no-config", "--no-watch"],
      workingDirectory: directory
    ) { session in
      _ = try await session.wait { $0.contains("Alice") && $0.contains("READ ONLY") }
      try session.send("e")
      _ = try await session.wait {
        $0.contains("read-only mode") && !$0.contains("Edit name")
      }
      try session.resize(to: CellSize(width: 60, height: 16))
      _ = try await session.wait { $0.contains("Alice") && $0.contains("READ ONLY") }
      try session.resize(to: CellSize(width: 30, height: 8))
      _ = try await session.wait {
        $0.contains("terminal too small (need") && $0.contains("40×10)")
      }
      try session.resize(to: CellSize(width: 100, height: 28))
      _ = try await session.wait { $0.contains("Alice") && $0.contains("READ ONLY") }
      #expect(try await session.finish(sending: Array("q".utf8)) == 0)
    }
  }

  @Test(
    "terminal input lease restores descriptor zero",
    .enabled(if: csvuiPTYTestsEnabled, csvuiPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func terminalInputLeaseRestoration() throws {
    var before = stat()
    try #require(unsafe fstat(STDIN_FILENO, &before) == 0)
    let pair = try RealTerminalPTYPair.open(size: CellSize(width: 80, height: 24))
    defer { pair.close() }
    let lease = try CSVTerminalInputLease()
    defer { try? lease.restore() }
    #expect(lease.preservedStandardInputIsCloseOnExec)
    try lease.activate(fileDescriptor: pair.slave)
    #expect(isatty(STDIN_FILENO) == 1)
    try lease.restore()

    var after = stat()
    #expect(unsafe fstat(STDIN_FILENO, &after) == 0)
    #expect(before.st_dev == after.st_dev)
    #expect(before.st_ino == after.st_ino)
    #expect(before.st_rdev == after.st_rdev)
  }
}

@MainActor
private final class CSVUITerminalSession {
  let terminal: RealTerminalPTYPair
  let process: Process
  private(set) var screen: ANSIVisibleScreen

  init(terminal: RealTerminalPTYPair, process: Process, size: CellSize) {
    self.terminal = terminal
    self.process = process
    screen = ANSIVisibleScreen(size: size)
  }

  func wait(
    _ label: String = "screen condition",
    timeout: DispatchTimeInterval = .seconds(15),
    until predicate: @escaping (String) -> Bool
  ) async throws -> String {
    var currentScreen = screen
    do {
      let rendered = try await waitForANSIVisibleScreen(
        on: terminal.master,
        screen: &currentScreen,
        deadline: .now() + timeout,
        condition: predicate
      )
      screen = currentScreen
      return rendered
    } catch {
      Issue.record("\(label) wait failed: \(error)")
      throw error
    }
  }

  func send(_ text: String) throws {
    try send(bytes: Array(text.utf8))
  }

  func send(bytes: [UInt8]) throws {
    try writeAllBytes(bytes, to: terminal.master)
  }

  func resize(to size: CellSize) throws {
    var windowSize = winsize(
      ws_row: UInt16(max(1, size.height)),
      ws_col: UInt16(max(1, size.width)),
      ws_xpixel: 0,
      ws_ypixel: 0
    )
    guard unsafe ioctl(terminal.slave, UInt(TIOCSWINSZ), &windowSize) == 0 else {
      throw CSVUIPTYFixtureFailure.resize(errno)
    }
    guard kill(process.processIdentifier, SIGWINCH) == 0 else {
      throw CSVUIPTYFixtureFailure.signal(errno)
    }
    screen = ANSIVisibleScreen(size: size)
  }

  func finish(sending bytes: [UInt8]) async throws -> Int32 {
    let drain = CSVUIPTYOutputDrain(fileDescriptor: terminal.master)
    do {
      try send(bytes: bytes)
      let status = try await waitForExit(process, timeout: .seconds(10))
      await drain.cancel()
      return status
    } catch {
      await drain.cancel()
      throw error
    }
  }

  func cleanupAfterFailure() async {
    let wasRunning = process.isRunning
    if wasRunning { process.terminate() }
    terminal.closeMaster()
    _ = try? await waitForExit(process, timeout: .seconds(5))
    if wasRunning {
      Issue.record("csvui was still running at the failure; terminated for cleanup")
    } else {
      Issue.record("csvui exited early with status \(process.terminationStatus)")
    }
  }
}

@MainActor
private func withCSVUITerminalSession(
  arguments: [String],
  workingDirectory: URL,
  size: CellSize = CellSize(width: 100, height: 28),
  standardInput: Any? = nil,
  operation: @escaping @MainActor (CSVUITerminalSession) async throws -> Void
) async throws {
  let terminal = try RealTerminalPTYPair.open(size: size)
  defer { terminal.close() }
  let process = try launchCSVUI(
    arguments: arguments,
    workingDirectory: workingDirectory,
    terminal: terminal,
    standardInput: standardInput
  )
  let session = CSVUITerminalSession(terminal: terminal, process: process, size: size)
  do {
    try await operation(session)
    if process.isRunning {
      Issue.record("csvui journey returned before the process exited")
      await session.cleanupAfterFailure()
    }
  } catch {
    await session.cleanupAfterFailure()
    throw error
  }
}

private func makeCSVUITemporaryDirectory(_ label: String) throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("csvui-\(label)-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

private enum CSVUIPTYFixtureFailure: Error {
  case executableNotFound([String])
  case processTimedOut
  case resize(Int32)
  case signal(Int32)
}

@MainActor
private func launchCSVUI(
  arguments: [String],
  workingDirectory: URL,
  terminal: RealTerminalPTYPair,
  standardInput: Any? = nil
) throws -> Process {
  let process = Process()
  process.executableURL = try csvuiExecutableURL()
  process.arguments = arguments
  process.currentDirectoryURL = workingDirectory
  var environment = ProcessInfo.processInfo.environment
  environment["TERM"] = "xterm-256color"
  // Bazel intentionally provides a minimal test environment. Pin the child
  // terminal profile so assertions exercise the same Unicode presentation as
  // an ordinary interactive launch instead of framework ASCII fallbacks.
  environment["LANG"] = "en_US.UTF-8"
  environment["LC_ALL"] = "en_US.UTF-8"
  process.environment = environment
  let terminalHandle = FileHandle(fileDescriptor: terminal.slave, closeOnDealloc: false)
  process.standardInput = standardInput ?? terminalHandle
  process.standardOutput = terminalHandle
  process.standardError = terminalHandle
  try process.run()
  return process
}

private func csvuiExecutableURL() throws -> URL {
  let bundleURL = Bundle.module.bundleURL
  let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let buildRoot = packageRoot.appendingPathComponent(".build", isDirectory: true)
  let preferredCandidates = [
    buildRoot.appendingPathComponent("out/Products/Debug/csvui"),
    bundleURL.deletingLastPathComponent().appendingPathComponent("csvui"),
  ]
  if let executable = preferredCandidates.first(where: isRegularExecutable) {
    return executable
  }
  let platformDirectories =
    (try? FileManager.default.contentsOfDirectory(
      at: buildRoot,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )) ?? []
  let fallbackCandidates = platformDirectories.map { $0.appendingPathComponent("debug/csvui") }

  var unique: [String: URL] = [:]
  for candidate in fallbackCandidates where isRegularExecutable(candidate) {
    unique[candidate.standardizedFileURL.path] = candidate
  }
  guard let executable = unique.values.sorted(by: { $0.path < $1.path }).first else {
    throw CSVUIPTYFixtureFailure.executableNotFound(
      (preferredCandidates + fallbackCandidates).map(\.path)
    )
  }
  return executable
}

private func isRegularExecutable(_ url: URL) -> Bool {
  var metadata = stat()
  let status = unsafe url.path.withCString { unsafe lstat($0, &metadata) }
  return status == 0 && metadata.st_mode & S_IFMT == S_IFREG
    && FileManager.default.isExecutableFile(atPath: url.path)
}

@MainActor
private func waitForExit(_ process: Process, timeout: Duration) async throws -> Int32 {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  while process.isRunning, clock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  guard !process.isRunning else { throw CSVUIPTYFixtureFailure.processTimedOut }
  return process.terminationStatus
}

private final class CSVUIPTYOutputDrain: Sendable {
  private struct State {
    var cancelled = false
    var waiter: CheckedContinuation<Void, Never>?
  }

  private let source: any DispatchSourceRead
  private let state = Mutex(State())

  init(fileDescriptor: Int32) {
    let source = DispatchSource.makeReadSource(
      fileDescriptor: fileDescriptor,
      queue: DispatchQueue(label: "CSVUITests.PTYOutputDrain")
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
    source.setCancelHandler { [weak self] in self?.didCancel() }
    source.resume()
  }

  func cancel() async {
    source.cancel()
    await withCheckedContinuation { continuation in
      state.withLock {
        if $0.cancelled {
          continuation.resume()
        } else {
          $0.waiter = continuation
        }
      }
    }
  }

  private func didCancel() {
    let waiter = state.withLock {
      $0.cancelled = true
      let waiter = $0.waiter
      $0.waiter = nil
      return waiter
    }
    waiter?.resume()
  }
}

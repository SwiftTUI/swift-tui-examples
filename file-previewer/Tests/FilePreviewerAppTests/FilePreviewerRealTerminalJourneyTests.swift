import Dispatch
import Foundation
@_spi(Runners) @_spi(Testing) import SwiftTUI
import SwiftTUITerminal
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import FilePreviewerApp

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite(.serialized)
struct FilePreviewerRealTerminalJourneyTests {
  @Test("preview focus routes child arrows, consumes Escape, resizes, and shuts down")
  func previewFocusRoutesKeysAndShutsDown() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let firstFile = root.appendingPathComponent("first.txt")
    let secondFile = root.appendingPathComponent("second.txt")
    try Data("first fixture\n".utf8).write(to: firstFile)
    try Data("second fixture\n".utf8).write(to: secondFile)

    let initialSize = CellSize(width: 100, height: 28)
    let resizedSize = CellSize(width: 90, height: 24)
    let pty = try RealTerminalPTYPair.open(size: initialSize)
    defer { pty.close() }

    let host = TerminalHost(
      inputFileDescriptor: pty.slave,
      outputFileDescriptor: pty.slave,
      fallbackSize: initialSize,
      capabilityProfile: .previewUnicode
    )
    let inputReader = InputReader(fileDescriptor: pty.slave)
    let signalReader = InProcessSignalReader()
    let capture = PreviewSessionCapture()
    let previewSessions = PreviewSessionSlot<TerminalProcessSession>.terminalProcesses()
    let entryCache = DirectoryEntryCache()
    let registry = PreviewerRegistry(
      byExtension: [:],
      fallback: PreviewCommand(executable: "/bin/cat", arguments: { _ in ["-v"] })
    )
    let rootIdentity = Identity(components: ["file-previewer.real-terminal"])

    let runTask = Task {
      do {
        let result = try await Self.runHarness(
          presentationSurface: host,
          terminalInputReader: inputReader,
          signalReader: signalReader,
          terminalSize: initialSize,
          rootIdentity: rootIdentity
        ) {
          ColumnBrowser(
            path: [root],
            registry: registry,
            entryCache: entryCache,
            previewSessions: previewSessions,
            onPreviewSessionCreated: { capture.sessions.append($0) }
          )
        }
        await previewSessions.shutdown()
        capture.isShutdownComplete = true
        return result
      } catch {
        await previewSessions.shutdown()
        capture.isShutdownComplete = true
        throw error
      }
    }

    var screen = ANSIVisibleScreen(size: initialSize)
    let initialScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { rendered in
      rendered.contains("first.txt")
        && rendered.contains("second.txt")
        && rendered.contains("BROWSER")
    }
    #expect(initialScreen.contains("first.txt"))

    // Select the first file without leaving browser focus.
    try writeAllBytes([0x1B, 0x5B, 0x42], to: pty.master)
    let firstSelectionScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { rendered in
      rendered.contains("BROWSER")
        && rendered.components(separatedBy: "first.txt").count >= 2
    }
    #expect(!firstSelectionScreen.contains("^[[B"))
    _ = try await Self.waitForCapturedSession(
      capture,
      count: 1,
      deadline: ContinuousClock().now + .seconds(5)
    )

    // Right enters preview from the browser.
    try writeAllBytes([0x1B, 0x5B, 0x43], to: pty.master)
    let previewScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { $0.contains("PREVIEW") }
    #expect(previewScreen.contains("first.txt"))

    let resizedPreviewSession = try #require(capture.sessions.last)
    let childSizeBeforeResize = try await Self.waitForLayoutSize(
      of: resizedPreviewSession,
      differentFrom: CellSize(width: 80, height: 40),
      deadline: ContinuousClock().now + .seconds(5)
    )

    try Self.resize(fileDescriptor: pty.slave, to: resizedSize)
    signalReader.send("SIGWINCH")
    #expect(host.surfaceSize == resizedSize)
    screen = ANSIVisibleScreen(size: resizedSize)
    let resizedScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { rendered in
      rendered.contains("PREVIEW") && rendered.contains("first.txt")
    }
    #expect(resizedScreen.contains("PREVIEW"))
    let childSizeAfterResize = try await Self.waitForLayoutSize(
      of: resizedPreviewSession,
      differentFrom: childSizeBeforeResize,
      deadline: ContinuousClock().now + .seconds(5)
    )
    #expect(childSizeAfterResize != childSizeBeforeResize)

    // A real Down sequence and Return must reach the nested `cat -v` child.
    // `cat -v` renders the child's received Escape byte as the visible `^[`.
    try writeAllBytes([0x1B, 0x5B, 0x42, 0x0D], to: pty.master)
    let childScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { $0.contains("^[[B") }
    #expect(childScreen.contains("PREVIEW"))

    try writeAllBytes([0x1B], to: pty.master)
    let returnedScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { $0.contains("BROWSER") }
    #expect(returnedScreen.contains("first.txt"))

    // Because Escape returned to the browser without resetting its selection,
    // another Down advances from first.txt to second.txt.
    try writeAllBytes([0x1B, 0x5B, 0x42], to: pty.master)
    let secondSelectionScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { rendered in
      rendered.contains("BROWSER")
        && rendered.components(separatedBy: "second.txt").count >= 2
    }
    #expect(secondSelectionScreen.contains("second.txt"))
    _ = try await Self.waitForCapturedSession(
      capture,
      count: 2,
      deadline: ContinuousClock().now + .seconds(5)
    )

    // Tab is the second supported browser-to-preview transition.
    try writeAllBytes([0x09], to: pty.master)
    _ = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { $0.contains("PREVIEW") && $0.contains("second.txt") }

    // A distinct child arrow proves Tab landed on the embedded terminal.
    try writeAllBytes([0x1B, 0x5B, 0x41, 0x0D], to: pty.master)
    _ = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { $0.contains("^[[A") }

    try writeAllBytes([0x1B], to: pty.master)
    let secondReturnScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { $0.contains("BROWSER") && $0.contains("second.txt") }
    #expect(secondReturnScreen.contains("second.txt"))

    let screenBeforeShutdown = screen
    let shutdownDrainTask = Task.detached {
      var shutdownScreen = screenBeforeShutdown
      return try await waitForANSIVisibleScreen(
        on: pty.master,
        screen: &shutdownScreen,
        deadline: .now() + .seconds(5)
      ) { rendered in
        !rendered.contains("BROWSER")
      }
    }
    // Keep draining on a non-main executor while TerminalHost restores PTY
    // attributes; Darwin's tcsetattr(TCSAFLUSH) waits for pending output.
    // One Ctrl-D exits; the runner-owned post-run shutdown then drains the
    // child session before returning.
    try writeAllBytes([0x04], to: pty.master)
    do {
      try await Self.waitForShutdown(
        capture,
        deadline: ContinuousClock().now + .seconds(5)
      )
    } catch {
      runTask.cancel()
      throw error
    }
    _ = try await runTask.value
    _ = try await shutdownDrainTask.value
    for session in capture.sessions {
      try await Self.waitForExit(
        of: session,
        deadline: ContinuousClock().now + .seconds(5)
      )
    }
    #expect(capture.isShutdownComplete)
  }

  private static func runHarness<V: View>(
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    signalReader: any SignalReading,
    terminalSize: CellSize,
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var environment = EnvironmentValues()
    environment.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      environmentValues: environment,
      viewBuilder: { _, _ in viewBuilder() }
    )
    runLoop.renderMode = .async
    return try await runLoop.run()
  }

  private static func resize(fileDescriptor: Int32, to size: CellSize) throws {
    #if canImport(Darwin) || canImport(Glibc)
      var windowSize = winsize(
        ws_row: UInt16(max(1, size.height)),
        ws_col: UInt16(max(1, size.width)),
        ws_xpixel: 0,
        ws_ypixel: 0
      )
      guard unsafe ioctl(fileDescriptor, UInt(TIOCSWINSZ), &windowSize) == 0 else {
        throw JourneyFailure.resize(errno)
      }
    #else
      throw JourneyFailure.unsupportedPlatform
    #endif
  }

  private static func waitForExit(
    of session: TerminalProcessSession,
    deadline: ContinuousClock.Instant
  ) async throws {
    let clock = ContinuousClock()
    while clock.now < deadline {
      if case .exited = await session.currentLifecycle() {
        return
      }
      await Task.yield()
    }
    throw JourneyFailure.previewDidNotExit
  }

  private static func waitForLayoutSize(
    of session: TerminalProcessSession,
    differentFrom previous: CellSize,
    deadline: ContinuousClock.Instant
  ) async throws -> CellSize {
    let clock = ContinuousClock()
    while clock.now < deadline {
      let size = session.cachedSnapshot.size
      if size != previous {
        return size
      }
      await Task.yield()
    }
    throw JourneyFailure.previewDidNotResize
  }

  private static func waitForCapturedSession(
    _ capture: PreviewSessionCapture,
    count: Int,
    deadline: ContinuousClock.Instant
  ) async throws -> TerminalProcessSession {
    let clock = ContinuousClock()
    while clock.now < deadline {
      if capture.sessions.count >= count, let session = capture.sessions.last {
        return session
      }
      await Task.yield()
    }
    throw JourneyFailure.previewDidNotStart
  }

  private static func waitForShutdown(
    _ capture: PreviewSessionCapture,
    deadline: ContinuousClock.Instant
  ) async throws {
    let clock = ContinuousClock()
    while clock.now < deadline {
      if capture.isShutdownComplete {
        return
      }
      await Task.yield()
    }
    throw JourneyFailure.runDidNotExit
  }
}

@MainActor
private final class PreviewSessionCapture {
  var sessions: [TerminalProcessSession] = []
  var isShutdownComplete = false
}

private enum JourneyFailure: Error {
  case unsupportedPlatform
  case resize(Int32)
  case previewDidNotExit
  case previewDidNotStart
  case previewDidNotResize
  case runDidNotExit
}

private func temporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("file-previewer-pty-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

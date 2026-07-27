import Dispatch
import Foundation
@_spi(Runners) @_spi(Testing) import SwiftTUI
import SwiftTUITerminal
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import Sextant

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite(.serialized)
struct SextantRealTerminalJourneyTests {
  @Test(
    "interactive editor receives a cooked terminal and Sextant reclaims it",
    .enabled(if: sextantRealPTYTestsEnabled, sextantRealPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func interactiveEditorHandoffAndRestore() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("editable.txt")
    try Data("fixture\n".utf8).write(to: file)

    let size = CellSize(width: 90, height: 24)
    let pty = try RealTerminalPTYPair.open(size: size)
    defer { pty.close() }

    let handoffClient = HandoffClient(
      open: { _ in .success(()) },
      edit: { command, url in
        guard let executable = command.first else {
          return .failure(.invalidEditor("The editor command is empty."))
        }
        let result = await runHandoffProcess(
          executable,
          arguments: Array(command.dropFirst()) + ["--", url.path],
          standardIO: .fileDescriptor(pty.slave)
        )
        return result
      },
      reveal: { _ in .success(()) },
      copy: { _ in .success(()) }
    )
    let fileSystem = LocalFileSystemClient()
    let directoryStore = DirectoryStore(client: fileSystem)
    let rootID = DirectoryID(identity: .pathFallback(for: root))
    let model = BrowserModel(
      root: root,
      rootID: rootID,
      policy: DirectoryPolicy(),
      dependencies: BrowserModelDependencies(
        loadDirectory: { request in
          await directoryStore.load(request)
        },
        performHandoff: { request in
          let result = await handoffClient.performWithRuntimeHandoff(request)
          return result
        },
        resolveEditor: {
          .success([
            "/bin/sh",
            "-c",
            """
            if /bin/stty -a | /usr/bin/grep -q -- '-icanon'; then
              printf '\\r\\nSEXTANT_EDITOR_RAW\\r\\n'
              exit 64
            fi
            printf '\\r\\nSEXTANT_EDITOR_COOKED\\r\\n'
            IFS= read -r line
            printf 'SEXTANT_EDITOR_INPUT:%s\\r\\n' "$line"
            """,
            "sextant-editor",
          ])
        },
        shutdown: {
          await directoryStore.cancelAll()
        }
      )
    )
    let host = TerminalHost(
      inputFileDescriptor: pty.slave,
      outputFileDescriptor: pty.slave,
      fallbackSize: size,
      capabilityProfile: .previewUnicode
    )
    let runTask = Task {
      do {
        let result = try await Self.runHarness(
          presentationSurface: host,
          terminalInputReader: InputReader(fileDescriptor: pty.slave),
          signalReader: InProcessSignalReader(),
          terminalSize: size,
          rootIdentity: Identity(components: ["sextant.editor-handoff"])
        ) {
          ColumnBrowser(model: model)
        }
        await model.shutdown()
        return result
      } catch {
        await model.shutdown()
        throw error
      }
    }

    do {
      var screen = ANSIVisibleScreen(size: size)
      _ = try await waitForANSIVisibleScreen(
        on: pty.master,
        screen: &screen,
        deadline: .now() + .seconds(15)
      ) {
        $0.contains("BROWSER") && $0.contains("editable.txt")
      }
      let screenBeforeEditor = screen
      let editorDrainTask = Task.detached {
        var editorScreen = screenBeforeEditor
        let rendered = try await waitForANSIVisibleScreen(
          on: pty.master,
          screen: &editorScreen,
          deadline: .now() + .seconds(15)
        ) {
          $0.contains("SEXTANT_EDITOR_COOKED")
            || $0.contains("SEXTANT_EDITOR_RAW")
        }
        return DetachedVisibleScreenResult(rendered: rendered, screen: editorScreen)
      }
      try writeAllBytes(Array("e".utf8), to: pty.master)
      let editorResult = try await editorDrainTask.value
      let editorScreen = editorResult.rendered
      screen = editorResult.screen
      #expect(editorScreen.contains("SEXTANT_EDITOR_COOKED"))
      #expect(!editorScreen.contains("SEXTANT_EDITOR_RAW"))

      let screenBeforeRestore = screen
      let restoreDrainTask = Task.detached {
        var restoredScreen = screenBeforeRestore
        let rendered = try await waitForANSIVisibleScreen(
          on: pty.master,
          screen: &restoredScreen,
          deadline: .now() + .seconds(15)
        ) {
          $0.contains("editable.txt")
            && $0.contains("Opened editable.txt")
        }
        return DetachedVisibleScreenResult(rendered: rendered, screen: restoredScreen)
      }
      try writeAllBytes(Array("accepted\n".utf8), to: pty.master)
      let restoreResult = try await restoreDrainTask.value
      screen = restoreResult.screen
      try await Self.waitForModel(
        deadline: ContinuousClock().now + .seconds(5)
      ) {
        model.state.status == .message("Opened editable.txt in the editor.")
      }
      let shutdownDrain = PTYOutputDrain(fileDescriptor: pty.master)
      try writeAllBytes([0x04], to: pty.master)
      _ = try await runTask.value
      await shutdownDrain.cancel()
    } catch {
      runTask.cancel()
      pty.closeMaster()
      _ = try? await runTask.value
      throw error
    }
  }

  @Test(
    "real preview focus, replacement, resize, host Escape, and shutdown",
    .enabled(if: sextantRealPTYTestsEnabled, sextantRealPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func previewFocusReplacementResizeAndShutdown() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let firstFile = root.appendingPathComponent("first.txt")
    let secondFile = root.appendingPathComponent("second.txt")
    try Data("first fixture\n".utf8).write(to: firstFile)
    try Data("second fixture\n".utf8).write(to: secondFile)

    let capture = PreviewSessionCapture()
    let previewHub = JourneyPreviewEventHub()
    let processClient = PreviewProcessClient { launch in
      let session = TerminalProcessSession(
        command: launch.executable,
        arguments: launch.arguments,
        initialSize: CellSize(width: 80, height: 40)
      )
      await capture.append(session)
      return PreviewSessionHandle(
        terminal: session,
        start: { try await session.start() },
        terminate: { await session.terminate(signal: $0) },
        lifecycle: { await session.currentLifecycle() }
      )
    }
    let coordinator = PreviewCoordinator(
      processClient: processClient,
      eventSink: { event in
        await previewHub.receive(event)
      }
    )
    let fileSystem = LocalFileSystemClient()
    let directoryStore = DirectoryStore(client: fileSystem)
    let rootID = DirectoryID(identity: .pathFallback(for: root))
    let model = BrowserModel(
      root: root,
      rootID: rootID,
      policy: DirectoryPolicy(),
      dependencies: BrowserModelDependencies(
        loadDirectory: { request in
          await directoryStore.load(request)
        },
        previewEvents: { item, _, generation in
          let fallback = Self.fallback(for: item)
          let stream = await previewHub.stream(
            item: item,
            generation: generation,
            fallback: fallback
          )
          await coordinator.select(
            generation: generation.rawValue,
            launch: PreviewLaunch(
              adapterID: PreviewAdapterID("journey-cat"),
              adapterName: "Journey cat",
              executable: "/bin/cat",
              arguments: ["-v"],
              isInteractive: true
            ),
            fallback: fallback
          )
          return stream
        },
        cancelPreview: {
          await coordinator.shutdown()
        },
        shutdown: {
          await coordinator.shutdown()
          await directoryStore.cancelAll()
        }
      )
    )

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
    let rootIdentity = Identity(components: ["sextant.real-terminal"])

    let runTask = Task {
      do {
        let result = try await Self.runHarness(
          presentationSurface: host,
          terminalInputReader: inputReader,
          signalReader: signalReader,
          terminalSize: initialSize,
          rootIdentity: rootIdentity
        ) {
          ColumnBrowser(model: model)
        }
        await model.shutdown()
        await capture.markShutdownComplete()
        return result
      } catch {
        await model.shutdown()
        await capture.markShutdownComplete()
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
    #expect(initialScreen.contains("Preview"))
    try await Self.waitForModel(
      deadline: ContinuousClock().now + .seconds(5)
    ) {
      model.state.selectedItem?.url == firstFile.standardizedFileURL
    }
    let initialSelectedID = try #require(model.state.activeDirectory?.selectedItemID)

    // Right focuses the preview for the initially selected file.
    try writeAllBytes([0x1B, 0x5B, 0x43], to: pty.master)
    let previewScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) {
      $0.contains("PREVIEW")
        && $0.contains("first.txt")
        && $0.contains("Journey cat · ready")
    }
    let firstSession = try await capture.waitForSession(
      count: 1,
      deadline: ContinuousClock().now + .seconds(5)
    )
    let childSizeBeforeResize = try await Self.waitForLayoutSize(
      of: firstSession,
      differentFrom: CellSize(width: 80, height: 40),
      deadline: ContinuousClock().now + .seconds(5)
    )

    // A real child arrow sequence must reach the nested terminal.
    try writeAllBytes([0x1B, 0x5B, 0x42, 0x0D], to: pty.master)
    let childScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { $0.contains("^[[B") }
    #expect(childScreen.contains("PREVIEW"))

    // Resize the real outer PTY, deliver SIGWINCH, and require both a changed
    // visible render and changed embedded-child layout geometry.
    try Self.resize(fileDescriptor: pty.slave, to: resizedSize)
    signalReader.send("SIGWINCH")
    screen = ANSIVisibleScreen(size: resizedSize)
    let resizedScreen = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) {
      $0.contains("PREVIEW")
        && $0.contains("first.txt")
        && $0.contains("Journey cat")
    }
    let childSizeAfterResize = try await Self.waitForLayoutSize(
      of: firstSession,
      differentFrom: childSizeBeforeResize,
      deadline: ContinuousClock().now + .seconds(5)
    )
    #expect(host.surfaceSize == resizedSize)
    #expect(childSizeAfterResize != childSizeBeforeResize)
    #expect(resizedScreen != previewScreen)

    // Host Escape must not reach the child and must preserve the browser row.
    try writeAllBytes([0x1B], to: pty.master)
    _ = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { $0.contains("BROWSER") && $0.contains("first.txt") }
    try await Self.waitForModel(
      deadline: ContinuousClock().now + .seconds(5)
    ) {
      model.state.focus == .browser(rootID)
    }
    #expect(model.state.activeDirectory?.selectedItemID == initialSelectedID)

    // Down replaces the preview while browser focus remains active.
    try writeAllBytes([0x1B, 0x5B, 0x42], to: pty.master)
    _ = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { rendered in
      rendered.contains("BROWSER")
        && rendered.components(separatedBy: "second.txt").count >= 2
    }
    try await Self.waitForModel(
      deadline: ContinuousClock().now + .seconds(5)
    ) {
      model.state.selectedItem?.url == secondFile.standardizedFileURL
    }
    let secondSession = try await capture.waitForSession(
      count: 2,
      deadline: ContinuousClock().now + .seconds(5)
    )
    try await Self.waitForExit(
      of: firstSession,
      deadline: ContinuousClock().now + .seconds(5)
    )

    // Tab is the second browser-to-preview transition.
    try writeAllBytes([0x09], to: pty.master)
    _ = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) {
      $0.contains("PREVIEW")
        && $0.contains("second.txt")
        && $0.contains("Journey cat · ready")
    }
    try writeAllBytes([0x1B, 0x5B, 0x41, 0x0D], to: pty.master)
    _ = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { $0.contains("^[[A") }

    try writeAllBytes([0x1B], to: pty.master)
    _ = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(15)
    ) { $0.contains("BROWSER") && $0.contains("second.txt") }
    #expect(model.state.selectedItem?.url == secondFile.standardizedFileURL)

    let shutdownDrain = PTYOutputDrain(fileDescriptor: pty.master)
    try writeAllBytes([0x04], to: pty.master)
    do {
      try await capture.waitForShutdown(
        deadline: ContinuousClock().now + .seconds(5)
      )
    } catch {
      runTask.cancel()
      throw error
    }
    _ = try await runTask.value
    await shutdownDrain.cancel()

    let sessions = await capture.allSessions()
    #expect(sessions.count == 2)
    for session in sessions {
      try await Self.waitForExit(
        of: session,
        deadline: ContinuousClock().now + .seconds(5)
      )
    }
    if case .exited = await secondSession.currentLifecycle() {
      // Expected: runner-owned BrowserModel shutdown drains the last child.
    } else {
      Issue.record("The current preview child remained alive after shutdown.")
    }
    #expect(await capture.isShutdownComplete())
  }

  nonisolated private static func fallback(for item: BrowserItem) -> BuiltInPreview {
    BuiltInPreview(
      metadata: PreviewMetadata(
        displayName: item.name,
        path: item.url.path,
        kind: "File",
        size: item.listingMetadata.byteCount,
        modificationDate: item.listingMetadata.modificationDate
      ),
      body: .metadataOnly
    )
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

  private static func waitForModel(
    deadline: ContinuousClock.Instant,
    condition: @MainActor () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    while clock.now < deadline {
      if condition() {
        return
      }
      await Task.yield()
    }
    throw JourneyFailure.modelDidNotReachExpectedState
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
}

private actor JourneyPreviewEventHub {
  private struct Entry {
    var item: BrowserItem
    var generation: PreviewGeneration
    var fallback: BuiltInPreview
    var handle: PreviewSessionHandle?
    var adapterName = "Journey cat"
    var continuation: AsyncStream<PreviewModelEvent>.Continuation
  }

  private var entries: [UInt64: Entry] = [:]

  func stream(
    item: BrowserItem,
    generation: PreviewGeneration,
    fallback: BuiltInPreview
  ) -> AsyncStream<PreviewModelEvent> {
    AsyncStream { continuation in
      entries[generation.rawValue] = Entry(
        item: item,
        generation: generation,
        fallback: fallback,
        continuation: continuation
      )
    }
  }

  func receive(_ event: PreviewCoordinatorEvent) {
    let rawGeneration: UInt64
    switch event {
    case .builtIn(let generation, _),
      .starting(let generation, _, _, _),
      .ready(let generation, _),
      .slow(let generation, _),
      .exited(let generation, _, _),
      .failed(let generation, _, _):
      rawGeneration = generation
    }
    guard var entry = entries[rawGeneration] else {
      return
    }

    switch event {
    case .builtIn(_, let preview):
      entry.continuation.yield(
        .builtIn(
          item: entry.item,
          generation: entry.generation,
          preview: preview
        )
      )
      entry.continuation.finish()
      entries[rawGeneration] = nil

    case .starting(_, let launch, let handle, let fallback):
      entry.handle = handle
      entry.adapterName = launch.adapterName
      entry.fallback = fallback
      entry.continuation.yield(
        .external(
          ExternalPreviewState(
            item: entry.item,
            generation: entry.generation,
            adapterName: launch.adapterName,
            status: .starting,
            handle: handle,
            fallback: fallback
          )
        )
      )
      entries[rawGeneration] = entry

    case .ready(_, let handleID):
      guard let handle = entry.handle, handle.id == handleID else {
        return
      }
      entry.continuation.yield(
        .external(
          ExternalPreviewState(
            item: entry.item,
            generation: entry.generation,
            adapterName: entry.adapterName,
            status: .ready,
            handle: handle,
            fallback: entry.fallback
          )
        )
      )
      entries[rawGeneration] = entry

    case .slow(_, let handleID):
      guard let handle = entry.handle, handle.id == handleID else {
        return
      }
      entry.continuation.yield(
        .external(
          ExternalPreviewState(
            item: entry.item,
            generation: entry.generation,
            adapterName: entry.adapterName,
            status: .slow,
            handle: handle,
            fallback: entry.fallback
          )
        )
      )
      entries[rawGeneration] = entry

    case .exited(_, let handleID, let reason):
      guard let handle = entry.handle, handle.id == handleID else {
        return
      }
      entry.continuation.yield(
        .external(
          ExternalPreviewState(
            item: entry.item,
            generation: entry.generation,
            adapterName: entry.adapterName,
            status: .exited(reason),
            handle: handle,
            fallback: entry.fallback
          )
        )
      )
      entry.continuation.finish()
      entries[rawGeneration] = nil

    case .failed(_, let failure, let fallback):
      let previewFailure: PreviewFailure =
        switch failure {
        case .missingExecutable:
          .unreadable("Missing preview executable")
        case .startup(let message):
          .unreadable(message)
        }
      entry.continuation.yield(
        .failed(
          item: entry.item,
          generation: entry.generation,
          adapter: entry.adapterName,
          failure: previewFailure,
          fallback: fallback
        )
      )
      entry.continuation.finish()
      entries[rawGeneration] = nil
    }
  }
}

private actor PreviewSessionCapture {
  private var sessions: [TerminalProcessSession] = []
  private var shutdownComplete = false

  func append(_ session: TerminalProcessSession) {
    sessions.append(session)
  }

  func allSessions() -> [TerminalProcessSession] {
    sessions
  }

  func markShutdownComplete() {
    shutdownComplete = true
  }

  func isShutdownComplete() -> Bool {
    shutdownComplete
  }

  func waitForSession(
    count: Int,
    deadline: ContinuousClock.Instant
  ) async throws -> TerminalProcessSession {
    let clock = ContinuousClock()
    while sessions.count < count, clock.now < deadline {
      await Task.yield()
    }
    guard sessions.count >= count else {
      throw JourneyFailure.previewDidNotStart
    }
    return sessions[count - 1]
  }

  func waitForShutdown(
    deadline: ContinuousClock.Instant
  ) async throws {
    let clock = ContinuousClock()
    while !shutdownComplete, clock.now < deadline {
      await Task.yield()
    }
    guard shutdownComplete else {
      throw JourneyFailure.runDidNotExit
    }
  }
}

private enum JourneyFailure: Error {
  case unsupportedPlatform
  case resize(Int32)
  case modelDidNotReachExpectedState
  case previewDidNotExit
  case previewDidNotStart
  case previewDidNotResize
  case runDidNotExit
}

private struct DetachedVisibleScreenResult: Sendable {
  var rendered: String
  var screen: ANSIVisibleScreen
}

private final class PTYOutputDrain: @unchecked Sendable {
  private let source: any DispatchSourceRead
  private let lock = NSLock()
  private var cancelled = false
  private var cancellationWaiter: CheckedContinuation<Void, Never>?

  init(fileDescriptor: Int32) {
    let queue = DispatchQueue(label: "SextantTests.PTYOutputDrain")
    let source = DispatchSource.makeReadSource(
      fileDescriptor: fileDescriptor,
      queue: queue
    )
    self.source = source
    source.setEventHandler {
      var buffer = Array(repeating: UInt8(0), count: 4_096)
      while true {
        let count = unsafe read(fileDescriptor, &buffer, buffer.count)
        if count > 0 {
          continue
        }
        if count < 0, errno == EINTR {
          continue
        }
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
      lock.lock()
      if cancelled {
        lock.unlock()
        continuation.resume()
      } else {
        cancellationWaiter = continuation
        lock.unlock()
      }
    }
  }

  private func didCancel() {
    lock.lock()
    cancelled = true
    let waiter = cancellationWaiter
    cancellationWaiter = nil
    lock.unlock()
    waiter?.resume()
  }
}

private func temporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("sextant-pty-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

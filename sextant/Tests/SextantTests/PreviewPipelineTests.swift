import Foundation
import SwiftTUI
import SwiftTUITerminal
import Synchronization
import Testing

@testable import Sextant

@Suite("Preview pipeline", .serialized)
struct PreviewPipelineTests {
  @Test("superseded work cannot publish after an awaited metadata read")
  func supersededMetadataRead() async throws {
    let fileSystem = SuspendedMetadataFileSystemClient()
    let pipeline = makePipeline(fileSystem: fileSystem)
    let first = item(path: "/fixture/first")
    let second = item(path: "/fixture/second")

    let firstRequest = Task {
      await pipeline.events(
        for: first,
        generation: PreviewGeneration(rawValue: 1)
      )
    }
    try await fileSystem.waitForPendingMetadata(count: 1)

    let secondRequest = Task {
      await pipeline.events(
        for: second,
        generation: PreviewGeneration(rawValue: 2)
      )
    }
    try await fileSystem.waitForPendingMetadata(count: 2)

    await fileSystem.resumeMetadata(
      at: second.url,
      with: .success(second.listingMetadata)
    )
    let secondStream = await secondRequest.value
    let secondEvent = await firstEvent(in: secondStream)
    guard case .builtIn(_, let generation, _) = secondEvent else {
      Issue.record("expected current built-in preview")
      return
    }
    #expect(generation == PreviewGeneration(rawValue: 2))

    await fileSystem.resumeMetadata(
      at: first.url,
      with: .success(first.listingMetadata)
    )
    let firstStream = await firstRequest.value
    #expect(await events(in: firstStream).isEmpty)
    await pipeline.shutdown()
  }

  @Test("cancelled work cannot publish after an awaited metadata read")
  func cancelledMetadataRead() async throws {
    let fileSystem = SuspendedMetadataFileSystemClient()
    let pipeline = makePipeline(fileSystem: fileSystem)
    let selected = item(path: "/fixture/cancelled")

    let request = Task {
      await pipeline.events(
        for: selected,
        generation: PreviewGeneration(rawValue: 1)
      )
    }
    try await fileSystem.waitForPendingMetadata(count: 1)
    await pipeline.cancelCurrent()
    await fileSystem.resumeMetadata(
      at: selected.url,
      with: .success(selected.listingMetadata)
    )

    let stream = await request.value
    #expect(await events(in: stream).isEmpty)
    await pipeline.shutdown()
  }

  @Test("directory snapshots are forwarded to the built-in previewer")
  func directorySnapshotForwarding() async {
    let fileSystem = InMemoryFileSystemClient()
    let pipeline = makePipeline(fileSystem: fileSystem)
    let directory = item(path: "/fixture/directory")
    await fileSystem.setMetadata(
      .success(directory.listingMetadata),
      at: directory.url
    )
    let child = BrowserItem(
      id: BrowserItemID(identity: .path("/fixture/directory/child.txt")),
      directoryID: directory.targetDirectoryID!,
      name: "child.txt",
      url: directory.url.appendingPathComponent("child.txt"),
      kind: .file,
      listingMetadata: ItemMetadata(
        identity: .path("/fixture/directory/child.txt"),
        byteCount: 42,
        isReadable: true
      )
    )
    let snapshot = DirectorySnapshot(
      request: DirectoryRequest(
        id: DirectoryRequestID(rawValue: 1),
        directoryID: directory.targetDirectoryID!,
        url: directory.url
      ),
      items: [child]
    )

    let stream = await pipeline.events(
      for: directory,
      generation: PreviewGeneration(rawValue: 1),
      directorySnapshot: snapshot
    )
    let event = await firstEvent(in: stream)
    guard case .builtIn(_, _, let preview) = event else {
      Issue.record("expected a built-in directory preview")
      return
    }
    #expect(
      preview.body
        == .directorySummary(
          DirectorySummary(
            itemCount: 1,
            directoryCount: 0,
            fileCount: 1,
            specialCount: 0,
            totalKnownBytes: 42,
            entryNames: ["child.txt"],
            hiddenEntryCount: 0
          )
        )
    )
    await pipeline.shutdown()
  }

  @Test("automatic falls back while explicit external reports a missing tool")
  func automaticVersusExplicitMissingExecutable() async {
    let fileSystem = InMemoryFileSystemClient()
    let selected = fileItem(path: "/fixture/readme.txt")
    await fileSystem.setFile(
      Data("fixture".utf8),
      metadata: selected.listingMetadata,
      at: selected.url
    )
    let adapter = PreviewAdapterDescription(
      id: PreviewAdapterID("missing"),
      displayName: "Missing previewer",
      contentKinds: [.text],
      executable: "missing-preview-tool",
      isInteractive: false,
      priority: 1,
      arguments: { [$0.path] }
    )
    let resolver = PreviewResolver(adapters: [adapter])

    let automatic = makePipeline(
      fileSystem: fileSystem,
      resolver: resolver,
      mode: .automatic
    )
    let automaticStream = await automatic.events(
      for: selected,
      generation: PreviewGeneration(rawValue: 1)
    )
    guard case .builtIn = await firstEvent(in: automaticStream) else {
      Issue.record("automatic mode should retain the built-in preview")
      return
    }
    await automatic.shutdown()

    let external = makePipeline(
      fileSystem: fileSystem,
      resolver: resolver,
      mode: .external
    )
    let externalStream = await external.events(
      for: selected,
      generation: PreviewGeneration(rawValue: 1)
    )
    guard
      case .failed(
        _,
        _,
        let adapterName,
        let failure,
        let fallback
      ) = await firstEvent(in: externalStream)
    else {
      Issue.record("external mode should expose its unavailable executable")
      return
    }
    #expect(adapterName == "Missing previewer")
    #expect(failure == .missingExecutable("missing-preview-tool"))
    #expect(fallback != nil)
    await external.shutdown()
  }

  @Test(
    arguments: [
      (TerminalExitReason.normal(code: 7), PreviewFailure.externalExit(7)),
      (TerminalExitReason.signal(9), PreviewFailure.externalSignal(9)),
    ]
  )
  func unsuccessfulExternalExitRetainsFallback(
    reason: TerminalExitReason,
    expectedFailure: PreviewFailure
  ) async {
    let fileSystem = InMemoryFileSystemClient()
    let selected = fileItem(path: "/fixture/value.txt")
    await fileSystem.setFile(
      Data("fixture".utf8),
      metadata: selected.listingMetadata,
      at: selected.url
    )
    let adapter = PreviewAdapterDescription(
      id: PreviewAdapterID("scripted"),
      displayName: "Scripted previewer",
      contentKinds: [.text],
      executable: "scripted",
      isInteractive: false,
      priority: 1,
      arguments: { [$0.path] }
    )
    let pipeline = makePipeline(
      fileSystem: fileSystem,
      resolver: PreviewResolver(adapters: [adapter]),
      executableCache: PreviewExecutableCache(path: "") { _, _ in
        "/fixture/scripted"
      },
      mode: .external,
      processClient: exitedProcessClient(reason: reason)
    )

    let stream = await pipeline.events(
      for: selected,
      generation: PreviewGeneration(rawValue: 1)
    )
    let recorded = await events(in: stream)
    guard let last = recorded.last else {
      Issue.record("expected external preview events")
      return
    }
    guard
      case .failed(
        _,
        _,
        let adapterName,
        let failure,
        let fallback
      ) = last
    else {
      Issue.record("expected an external exit failure")
      return
    }
    #expect(adapterName == "Scripted previewer")
    #expect(failure == expectedFailure)
    #expect(fallback != nil)
    await pipeline.shutdown()
  }

  @Test("external adapter failures always retain the built-in fallback")
  func externalAdapterFailuresRetainFallback() async {
    let fileSystem = InMemoryFileSystemClient()
    let selected = fileItem(path: "/fixture/value.txt")
    await fileSystem.setFile(
      Data("fixture".utf8),
      metadata: selected.listingMetadata,
      at: selected.url
    )
    let adapter = PreviewAdapterDescription(
      id: PreviewAdapterID("strict"),
      displayName: "Strict previewer",
      contentKinds: [.text],
      executable: "strict",
      isInteractive: false,
      priority: 1,
      arguments: { [$0.path] }
    )

    let missingPipeline = makePipeline(
      fileSystem: fileSystem,
      resolver: PreviewResolver(adapters: [adapter]),
      mode: .external
    )
    let missingStream = await missingPipeline.events(
      for: selected,
      generation: PreviewGeneration(rawValue: 1)
    )
    guard
      case .failed(_, _, _, .missingExecutable("strict"), let missingFallback) =
        await firstEvent(in: missingStream)
    else {
      Issue.record("expected a visible missing-executable failure")
      return
    }
    #expect(missingFallback != nil)
    await missingPipeline.shutdown()

    let failedPipeline = makePipeline(
      fileSystem: fileSystem,
      resolver: PreviewResolver(adapters: [adapter]),
      executableCache: PreviewExecutableCache(path: "") { _, _ in
        "/fixture/strict"
      },
      mode: .external,
      processClient: exitedProcessClient(reason: .normal(code: 7))
    )
    let failedStream = await failedPipeline.events(
      for: selected,
      generation: PreviewGeneration(rawValue: 1)
    )
    let recorded = await events(in: failedStream)
    guard let last = recorded.last else {
      Issue.record("expected external preview events")
      return
    }
    guard
      case .failed(_, _, _, .externalExit(7), let failedFallback) =
        last
    else {
      Issue.record("expected the external failure")
      return
    }
    #expect(failedFallback != nil)
    await failedPipeline.shutdown()
  }

  @Test("a replacement selection leaves the live preview up until the debounce closes")
  func replacementWaitsForTheDebounce() async throws {
    let fileSystem = InMemoryFileSystemClient()
    let first = fileItem(path: "/fixture/value.txt")
    let second = fileItem(path: "/fixture/other.txt")
    for item in [first, second] {
      await fileSystem.setFile(
        Data("fixture".utf8),
        metadata: item.listingMetadata,
        at: item.url
      )
    }
    let adapter = PreviewAdapterDescription(
      id: PreviewAdapterID("scripted"),
      displayName: "Scripted previewer",
      contentKinds: [.text],
      executable: "scripted",
      isInteractive: false,
      priority: 1,
      arguments: { [$0.path] }
    )
    let clock = ManualPipelineClock()
    let sessions = PipelineSessionRecorder()
    let pipeline = makePipeline(
      fileSystem: fileSystem,
      resolver: PreviewResolver(adapters: [adapter]),
      executableCache: PreviewExecutableCache(path: "") { _, _ in
        "/fixture/scripted"
      },
      mode: .external,
      clock: PreviewClock { try await clock.sleep($0) },
      processClient: sessions.processClient()
    )

    _ = await pipeline.events(
      for: first,
      generation: PreviewGeneration(rawValue: 1)
    )
    try await clock.waitForWaiters(count: 1)
    await clock.advanceAll()
    try await sessions.waitForSessions(count: 1)

    // The replacement arms its own debounce window. Until that window closes
    // the coordinator owns the teardown, so the visible child must still be
    // running — a pre-emptive cancel here is what made arrowing through a
    // directory blank the preview on every keystroke.
    _ = await pipeline.events(
      for: second,
      generation: PreviewGeneration(rawValue: 2)
    )
    try await clock.waitForWaiters(count: 1)

    #expect(await sessions.terminationSignals.isEmpty)
    #expect(await sessions.sessionCount == 1)

    await pipeline.shutdown()
  }

  private func makePipeline(
    fileSystem: any FileSystemClient,
    resolver: PreviewResolver = PreviewResolver(),
    executableCache: PreviewExecutableCache? = nil,
    mode: PreviewPipelineMode = .builtIn,
    clock: PreviewClock = .continuous,
    processClient: PreviewProcessClient = .live
  ) -> PreviewPipeline {
    PreviewPipeline(
      fileSystem: fileSystem,
      resolver: resolver,
      executableCache: executableCache
        ?? PreviewExecutableCache(path: "") { _, _ in nil },
      mode: mode,
      clock: clock,
      processClient: processClient
    )
  }

  private func item(path: String) -> BrowserItem {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    let identity = FileSystemIdentity.path(path)
    let directoryID = DirectoryID(identity: identity)
    return BrowserItem(
      id: BrowserItemID(identity: identity),
      directoryID: DirectoryID(identity: .path("/fixture")),
      targetDirectoryID: directoryID,
      name: url.lastPathComponent,
      url: url,
      kind: .directory,
      listingMetadata: ItemMetadata(
        identity: identity,
        isReadable: true,
        isExecutable: true
      )
    )
  }

  private func fileItem(path: String) -> BrowserItem {
    let url = URL(fileURLWithPath: path)
    let identity = FileSystemIdentity.path(path)
    return BrowserItem(
      id: BrowserItemID(identity: identity),
      directoryID: DirectoryID(
        identity: .path(url.deletingLastPathComponent().path)
      ),
      name: url.lastPathComponent,
      url: url,
      kind: .file,
      listingMetadata: ItemMetadata(
        identity: identity,
        byteCount: 7,
        isReadable: true
      )
    )
  }

  private func exitedProcessClient(
    reason: TerminalExitReason
  ) -> PreviewProcessClient {
    PreviewProcessClient { _ in
      let terminal = PipelineTerminalSession()
      return PreviewSessionHandle(
        terminal: terminal,
        start: {
          terminal.setLifecycle(.exited(reason: reason))
        },
        terminate: { signal in
          terminal.setLifecycle(.exited(reason: .signal(signal)))
        },
        lifecycle: {
          terminal.cachedLifecycle
        }
      )
    }
  }

  private func firstEvent(
    in stream: AsyncStream<PreviewModelEvent>
  ) async -> PreviewModelEvent? {
    for await event in stream {
      return event
    }
    return nil
  }

  private func events(
    in stream: AsyncStream<PreviewModelEvent>
  ) async -> [PreviewModelEvent] {
    var result: [PreviewModelEvent] = []
    for await event in stream {
      result.append(event)
    }
    return result
  }
}

private final class PipelineTerminalSession: TerminalSession, @unchecked Sendable {
  private let lifecycleStorage = Mutex<TerminalLifecycle>(.notStarted)

  var cachedSnapshot: ForeignGrid { .empty }
  var cachedLifecycle: TerminalLifecycle {
    lifecycleStorage.withLock { $0 }
  }

  func setLifecycle(_ lifecycle: TerminalLifecycle) {
    lifecycleStorage.withLock { $0 = lifecycle }
  }

  func start() async throws {}
  func snapshot() async -> ForeignGrid { .empty }
  func currentTitle() async -> String? { nil }
  func currentWorkingDirectory() async -> String? { nil }
  func currentLifecycle() async -> TerminalLifecycle { cachedLifecycle }
  func send(key _: TerminalEmulatorKey) async {}
  func send(paste _: String) async {}
  func send(mouse _: TerminalEmulatorMouse) async {}
  func resize(_: CellSize) async throws {}
  func events() -> AsyncStream<TerminalEmulatorEvent> {
    AsyncStream { $0.finish() }
  }
}

private actor SuspendedMetadataFileSystemClient: FileSystemClient {
  private var metadataContinuations:
    [String: CheckedContinuation<Result<ItemMetadata, FileSystemFailure>, Never>] = [:]

  func readDirectory(
    _ request: DirectoryRequest
  ) async -> Result<DirectorySnapshot, FileSystemFailure> {
    .failure(.notFound(path: request.url.path))
  }

  func metadata(
    at url: URL,
    followingSymbolicLinks _: Bool
  ) async -> Result<ItemMetadata, FileSystemFailure> {
    await withCheckedContinuation { continuation in
      metadataContinuations[url.standardizedFileURL.path] = continuation
    }
  }

  func readPrefix(
    at url: URL,
    maximumBytes _: Int
  ) async -> Result<FilePrefix, FileSystemFailure> {
    .failure(.notFound(path: url.path))
  }

  func resumeMetadata(
    at url: URL,
    with result: Result<ItemMetadata, FileSystemFailure>
  ) {
    metadataContinuations.removeValue(
      forKey: url.standardizedFileURL.path
    )?.resume(returning: result)
  }

  func waitForPendingMetadata(count: Int) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(2)
    while metadataContinuations.count < count, clock.now < deadline {
      await Task.yield()
    }
    guard metadataContinuations.count >= count else {
      throw PreviewPipelineTestFailure.timedOut
    }
  }
}

private enum PreviewPipelineTestFailure: Error {
  case timedOut
}

private actor ManualPipelineClock {
  private struct Waiter {
    var duration: Duration
    var continuation: CheckedContinuation<Void, any Error>
  }

  private var waiters: [UUID: Waiter] = [:]

  func sleep(_ duration: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          waiters[id] = Waiter(duration: duration, continuation: continuation)
        }
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }

  func advanceAll() {
    let current = waiters.values
    waiters.removeAll()
    for waiter in current {
      waiter.continuation.resume()
    }
  }

  func waitForWaiters(count: Int) async throws {
    let deadline = ContinuousClock().now + .seconds(2)
    while waiters.count < count, ContinuousClock().now < deadline {
      await Task.yield()
    }
    guard waiters.count >= count else {
      throw PreviewPipelineTestFailure.timedOut
    }
  }

  private func cancel(_ id: UUID) {
    waiters.removeValue(forKey: id)?.continuation.resume(
      throwing: CancellationError()
    )
  }
}

private actor PipelineSessionRecorder {
  private var sessions: [PipelineTerminalSession] = []
  private(set) var terminationSignals: [Int32] = []

  var sessionCount: Int { sessions.count }

  nonisolated func processClient() -> PreviewProcessClient {
    PreviewProcessClient { _ in
      let terminal = PipelineTerminalSession()
      await self.record(terminal)
      return PreviewSessionHandle(
        terminal: terminal,
        start: {
          terminal.setLifecycle(.running)
        },
        terminate: { signal in
          await self.record(signal: signal)
          terminal.setLifecycle(.exited(reason: .signal(signal)))
        },
        lifecycle: {
          terminal.cachedLifecycle
        }
      )
    }
  }

  func waitForSessions(count: Int) async throws {
    let deadline = ContinuousClock().now + .seconds(2)
    while sessions.count < count, ContinuousClock().now < deadline {
      await Task.yield()
    }
    guard sessions.count >= count else {
      throw PreviewPipelineTestFailure.timedOut
    }
  }

  private func record(_ session: PipelineTerminalSession) {
    sessions.append(session)
  }

  private func record(signal: Int32) {
    terminationSignals.append(signal)
  }
}

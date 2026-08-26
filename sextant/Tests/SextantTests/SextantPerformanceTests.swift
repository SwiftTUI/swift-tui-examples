import Foundation
import SwiftTUI
import SwiftTUITerminal
import Synchronization
import Testing

@testable import Sextant

@MainActor
@Suite("Sextant performance", .serialized)
struct SextantPerformanceTests {
  @Test(
    "10,000-entry selection and filtering stay within interaction budgets",
    .timeLimit(.minutes(1))
  )
  func largeDirectoryInteractionBudgets() async throws {
    let root = URL(fileURLWithPath: "/performance", isDirectory: true)
    let rootID = DirectoryID(identity: .path(root.path))
    let fileSystem = InMemoryFileSystemClient()
    await fileSystem.setDirectory(
      (0..<10_000).map { index in
        let digits = String(index)
        return InMemoryFileSystemEntry(
          name:
            "item-"
            + String(repeating: "0", count: max(0, 5 - digits.count))
            + digits
            + ".txt",
          kind: .file,
          identity: .inode(device: 9, inode: UInt64(index + 1))
        )
      },
      at: root
    )
    let store = DirectoryStore(client: fileSystem)
    let model = BrowserModel(
      root: root,
      rootID: rootID,
      policy: DirectoryPolicy(),
      dependencies: BrowserModelDependencies(
        loadDirectory: { request in
          await store.load(request)
        }
      )
    )
    model.send(.start)
    try await waitForCondition {
      model.state.activeDirectory?.directory.snapshot?.items.count == 10_000
    }

    let clock = ContinuousClock()
    let renderer = DefaultRenderer()
    let renderIdentity = Identity(components: ["Performance", "LargeDirectory"])
    let proposal = ProposedSize(width: 100, height: 30)
    var selectionDurations: [Duration] = []
    selectionDurations.reserveCapacity(100)
    for _ in 0..<100 {
      let start = clock.now
      model.send(.moveSelection(.offset(1)))
      let frame = try renderActiveDirectory(
        model: model,
        renderer: renderer,
        identity: renderIdentity,
        proposal: proposal
      )
      #expect(!frame.rasterSurface.lines.isEmpty)
      selectionDurations.append(start.duration(to: clock.now))
    }
    let selectionP95 = percentile95(selectionDurations)

    let filterStart = clock.now
    model.send(.showFilter)
    model.send(.setFilter("item-09999"))
    let filteredFrame = try renderActiveDirectory(
      model: model,
      renderer: renderer,
      identity: renderIdentity,
      proposal: proposal
    )
    let filterDuration = filterStart.duration(to: clock.now)
    print(
      "SEXTANT_PERF selection_p95_ms=\(milliseconds(selectionP95)) "
        + "filter_ms=\(milliseconds(filterDuration)) entries=10000 moves=100"
    )

    if sextantWallClockBudgetsEnabled {
      #expect(selectionP95 < .milliseconds(50))
      #expect(filterDuration < .milliseconds(50))
    }
    #expect(model.state.selectedItem?.name == "item-09999.txt")
    #expect(
      filteredFrame.rasterSurface.lines
        .joined(separator: "\n")
        .contains("item-09999.txt")
    )
    await model.shutdown()
  }

  @Test(
    "benchmark records chrome, directory, preview launch, and replacement latency",
    .timeLimit(.minutes(1))
  )
  func endToEndLatencySlices() async throws {
    let clock = ContinuousClock()
    let root = URL(fileURLWithPath: "/benchmark", isDirectory: true)
    let rootID = DirectoryID(identity: .path(root.path))
    let model = BrowserModel(
      root: root,
      rootID: rootID,
      policy: DirectoryPolicy(),
      dependencies: BrowserModelDependencies(
        loadDirectory: { _ in .failure(.cancelled) }
      )
    )
    let renderer = DefaultRenderer()
    let chromeStart = clock.now
    _ = renderer.render(
      ColumnBrowser(model: model),
      context: .init(identity: Identity(components: ["Benchmark"])),
      proposal: .init(width: 100, height: 30)
    )
    let chromeDuration = chromeStart.duration(to: clock.now)

    let fileSystem = InMemoryFileSystemClient()
    await fileSystem.setDirectory(
      makeEntries(count: 10_000),
      at: root
    )
    let store = DirectoryStore(client: fileSystem)
    let request = DirectoryRequest(
      id: DirectoryRequestID(rawValue: 1),
      directoryID: rootID,
      url: root
    )
    let directoryStart = clock.now
    _ = await store.load(request)
    let directoryDuration = directoryStart.duration(to: clock.now)

    let previewFactory = BenchmarkPreviewFactory()
    let recorder = BenchmarkPreviewRecorder()
    let coordinator = PreviewCoordinator(
      processClient: PreviewProcessClient { launch in
        await previewFactory.make(launch)
      },
      eventSink: { event in
        await recorder.record(event)
      }
    )
    let fallback = BuiltInPreview(
      metadata: PreviewMetadata(
        displayName: "benchmark",
        path: "/benchmark",
        kind: "File"
      ),
      body: .metadataOnly
    )
    let firstLaunchStart = clock.now
    await coordinator.select(
      generation: 1,
      launch: benchmarkLaunch("first"),
      fallback: fallback
    )
    try await waitForAsyncCondition {
      await recorder.readyCount == 1
    }
    let launchDuration = firstLaunchStart.duration(to: clock.now)

    let replacementStart = clock.now
    await coordinator.select(
      generation: 2,
      launch: benchmarkLaunch("second"),
      fallback: fallback
    )
    try await waitForAsyncCondition {
      await previewFactory.terminationCount == 1
    }
    let terminationDuration = replacementStart.duration(to: clock.now)
    try await waitForAsyncCondition {
      await recorder.readyCount == 2
    }
    await coordinator.shutdown()

    print(
      "SEXTANT_PERF chrome_ms=\(milliseconds(chromeDuration)) "
        + "directory_10000_ms=\(milliseconds(directoryDuration)) "
        + "preview_launch_ms=\(milliseconds(launchDuration)) "
        + "replacement_termination_ms=\(milliseconds(terminationDuration))"
    )
    if sextantWallClockBudgetsEnabled {
      #expect(chromeDuration < .milliseconds(50))
      #expect(directoryDuration < .milliseconds(250))
      #expect(launchDuration < .milliseconds(250))
      #expect(terminationDuration < .milliseconds(900))
    }
  }

  private func percentile95(_ values: [Duration]) -> Duration {
    let sorted = values.sorted()
    let index = min(
      sorted.count - 1,
      Int((Double(sorted.count) * 0.95).rounded(.up)) - 1
    )
    return sorted[max(0, index)]
  }

  private func renderActiveDirectory(
    model: BrowserModel,
    renderer: DefaultRenderer,
    identity: Identity,
    proposal: ProposedSize
  ) throws -> RenderSnapshot {
    let directory = try #require(model.state.activeDirectory)
    let snapshot = try #require(directory.directory.snapshot)
    let query = model.state.filter.query
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let items =
      query.isEmpty
      ? snapshot.items
      : snapshot.items.filter { $0.name.lowercased().contains(query) }
    return renderer.render(
      FileColumn(
        directory: directory.url,
        entries: items,
        selection: directory.selectedItemID,
        isActive: true
      ),
      context: .init(identity: identity),
      proposal: proposal
    )
  }

  private func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }

  private func waitForCondition(
    _ condition: @MainActor () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(5)
    while !condition() {
      guard clock.now < deadline else {
        throw PerformanceFailure.timeout
      }
      try await clock.sleep(for: .milliseconds(10))
    }
  }

  private func waitForAsyncCondition(
    _ condition: @escaping @Sendable () async -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(5)
    while !(await condition()) {
      guard clock.now < deadline else {
        throw PerformanceFailure.timeout
      }
      try await clock.sleep(for: .milliseconds(5))
    }
  }

  private func makeEntries(count: Int) -> [InMemoryFileSystemEntry] {
    (0..<count).map { index in
      let digits = String(index)
      return InMemoryFileSystemEntry(
        name:
          "item-"
          + String(repeating: "0", count: max(0, 5 - digits.count))
          + digits
          + ".txt",
        kind: .file,
        identity: .inode(device: 10, inode: UInt64(index + 1))
      )
    }
  }

  private func benchmarkLaunch(_ name: String) -> PreviewLaunch {
    PreviewLaunch(
      adapterID: PreviewAdapterID(name),
      adapterName: name,
      executable: "/bin/\(name)",
      arguments: [],
      isInteractive: false
    )
  }
}

private enum PerformanceFailure: Error {
  case timeout
}

private actor BenchmarkPreviewRecorder {
  private(set) var readyCount = 0

  func record(_ event: PreviewCoordinatorEvent) {
    if case .ready = event {
      readyCount += 1
    }
  }
}

private actor BenchmarkPreviewFactory {
  private(set) var terminationCount = 0

  func make(_ launch: PreviewLaunch) -> PreviewSessionHandle {
    _ = launch
    let state = BenchmarkTerminalState()
    let terminal = BenchmarkTerminalSession(state: state)
    return PreviewSessionHandle(
      terminal: terminal,
      start: {
        await state.set(.running)
        terminal.markOutput()
      },
      terminate: { signal in
        await self.recordTermination()
        await state.set(.exited(reason: .signal(signal)))
      },
      lifecycle: {
        await state.lifecycle
      }
    )
  }

  private func recordTermination() {
    terminationCount += 1
  }
}

private actor BenchmarkTerminalState {
  private(set) var lifecycle: TerminalLifecycle = .notStarted

  func set(_ lifecycle: TerminalLifecycle) {
    self.lifecycle = lifecycle
  }
}

private final class BenchmarkTerminalSession: TerminalSession, @unchecked Sendable {
  private let state: BenchmarkTerminalState
  private let snapshotStorage = Mutex<ForeignGrid>(.empty)

  init(state: BenchmarkTerminalState) {
    self.state = state
  }

  var cachedSnapshot: ForeignGrid {
    snapshotStorage.withLock { $0 }
  }
  func markOutput() {
    snapshotStorage.withLock {
      $0 = ForeignGrid(
        size: CellSize(width: 1, height: 1),
        cells: [[RasterCell(character: "x")]]
      )
    }
  }
  func start() async throws {}
  func snapshot() async -> ForeignGrid { cachedSnapshot }
  func currentTitle() async -> String? { nil }
  func currentWorkingDirectory() async -> String? { nil }
  func currentLifecycle() async -> TerminalLifecycle { await state.lifecycle }
  func send(key: TerminalEmulatorKey) async {}
  func send(paste: String) async {}
  func send(mouse: TerminalEmulatorMouse) async {}
  func resize(_ size: CellSize) async throws {}
  func events() -> AsyncStream<TerminalEmulatorEvent> {
    AsyncStream { $0.finish() }
  }
}

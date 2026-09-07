import Foundation
import Synchronization
import Testing

@testable import CSVUI

@Suite(.serialized)
@MainActor
struct CSVBackgroundWorkTests {
  @Test("an already cancelled caller never starts background work")
  func alreadyCancelled() async {
    let executed = Mutex(false)
    let task = Task {
      await runCSVBackgroundWork { executed.withLock { $0 = true } }
    }
    task.cancel()
    let result = await task.value
    if case .success = result { Issue.record("cancelled work succeeded") }
    #expect(!executed.withLock { $0 })
  }

  @Test("a worker that returns after cancellation cannot publish stale search results")
  func stalePublication() async throws {
    let model = try makeModel()
    let probe = CSVWorkerProbe()
    defer { probe.release() }
    var operations = CSVProjectionOperations()
    operations.search = { _, _, _, query in
      if query == "old" { try? await probe.wait() }
      return .init(
        matches: [
          .init(
            address: .init(
              row: RowID(sourceIndex: query == "old" ? 0 : 1), column: ColumnID(0)
            ))
        ], isTruncated: false)
    }
    model.installProjectionOperationsForTesting(operations)
    submit("old", filter: false, to: model)
    for await _ in probe.started { break }
    submit("current", filter: false, to: model)
    await model.waitForIdle()
    #expect(model.state.searchMatches.first?.address.row == RowID(sourceIndex: 1))
    await model.shutdown()
  }

  @Test(
    "superseding search and filter cancels their detached row workers", arguments: [false, true])
  func supersession(filter: Bool) async throws {
    let model = try makeModel()
    let probe = CSVWorkerProbe()
    defer { probe.release() }
    var operations = CSVProjectionOperations()
    if filter {
      operations.filter = { _, rows, _, spec in
        if spec.query == "old" { try await probe.wait() }
        return rows
      }
    } else {
      operations.search = { _, _, _, query in
        if query == "old" { try await probe.wait() }
        return CSVSearchResultSet(matches: [], isTruncated: false)
      }
    }
    model.installProjectionOperationsForTesting(operations)
    submit("old", filter: filter, to: model)
    for await _ in probe.started { break }
    submit("current", filter: filter, to: model)
    await model.waitForIdle()
    #expect(probe.wasCancelled)
    #expect(model.state.diagnostic?.severity != .error)
    await model.shutdown()
  }

  @Test("shutdown cancels an active detached projection worker")
  func shutdown() async throws {
    let model = try makeModel()
    let probe = CSVWorkerProbe()
    defer { probe.release() }
    var operations = CSVProjectionOperations()
    operations.filter = { _, rows, _, _ in
      try await probe.wait()
      return rows
    }
    model.installProjectionOperationsForTesting(operations)
    submit("old", filter: true, to: model)
    for await _ in probe.started { break }
    let shutdown = Task { await model.shutdown() }
    // Cancellation is acknowledged by the worker, not inferred from elapsed time.
    for await _ in probe.cancelled { break }
    await shutdown.value
    #expect(probe.wasCancelled)
  }

  private func submit(_ query: String, filter: Bool, to model: CSVModel) {
    model.send(filter ? .beginFilterAll : .beginFind)
    model.send(.updatePrompt(query))
    model.send(.submitPrompt)
  }

  private func makeModel() throws -> CSVModel {
    CSVModel(
      document: try CSVDocument.parse(
        source: CSVSourceSnapshot(
          origin: .standardInput, displayName: "test.csv", bytes: Data("name\na\nb\n".utf8)
        ), delimiter: .comma, hasHeaders: true
      ))
  }
}

private final class CSVWorkerProbe: Sendable {
  private struct State {
    var continuation: CheckedContinuation<Void, any Error>?
    var cancelled = false
  }
  private let state = Mutex(State())
  let started: AsyncStream<Void>
  let cancelled: AsyncStream<Void>
  private let startSignal: AsyncStream<Void>.Continuation
  private let cancelSignal: AsyncStream<Void>.Continuation

  init() {
    (started, startSignal) = AsyncStream.makeStream()
    (cancelled, cancelSignal) = AsyncStream.makeStream()
  }

  var wasCancelled: Bool { state.withLock { $0.cancelled } }

  func wait() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let cancelled = state.withLock {
          if $0.cancelled { return true }
          $0.continuation = continuation
          return false
        }
        if cancelled { continuation.resume(throwing: CancellationError()) }
        startSignal.yield()
        startSignal.finish()
      }
    } onCancel: {
      let continuation = self.state.withLock { state in
        state.cancelled = true
        defer { state.continuation = nil }
        return state.continuation
      }
      continuation?.resume(throwing: CancellationError())
      self.cancelSignal.yield()
      self.cancelSignal.finish()
    }
  }

  func release() {
    state.withLock {
      $0.continuation?.resume()
      $0.continuation = nil
    }
  }
}

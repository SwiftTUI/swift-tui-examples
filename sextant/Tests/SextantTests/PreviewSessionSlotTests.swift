import Synchronization
import Testing

@testable import Sextant

@MainActor
struct PreviewSessionSlotTests {
  @Test("replace terminates the previous session")
  func replaceTerminatesPreviousSession() async {
    let first = FakePreviewSession()
    let second = FakePreviewSession()
    let slot = PreviewSessionSlot<FakePreviewSession> { session in
      session.terminate()
    }

    await slot.replace(with: first)
    await slot.replace(with: second)
    await slot.waitForPendingTerminations()

    #expect(slot.current === second)
    #expect(first.terminationCount == 1)
    #expect(second.terminationCount == 0)
  }

  @Test("replacing with the same session is a no-op")
  func replacingWithSameSessionDoesNotTerminate() async {
    let session = FakePreviewSession()
    let slot = PreviewSessionSlot<FakePreviewSession> { session in
      session.terminate()
    }

    await slot.replace(with: session)
    await slot.replace(with: session)

    #expect(slot.current === session)
    #expect(session.terminationCount == 0)
  }

  @Test("clear terminates the current session once")
  func clearTerminatesCurrentSessionOnce() async {
    let session = FakePreviewSession()
    let slot = PreviewSessionSlot<FakePreviewSession> { session in
      session.terminate()
    }

    await slot.replace(with: session)
    await slot.clear()
    await slot.clear()
    await slot.waitForPendingTerminations()

    #expect(slot.current == nil)
    #expect(session.terminationCount == 1)
  }

  @Test("deinit terminates the current session")
  func deinitTerminatesCurrentSession() async {
    let session = FakePreviewSession()

    do {
      let slot = PreviewSessionSlot<FakePreviewSession> { session in
        session.terminate()
      }
      await slot.replace(with: session)
    }
    await waitForTermination(of: session)

    #expect(session.terminationCount == 1)
  }

  @Test("shutdown awaits current and pending terminations")
  func shutdownAwaitsCurrentAndPendingTerminations() async {
    let first = FakePreviewSession()
    let second = FakePreviewSession()
    let slot = PreviewSessionSlot<FakePreviewSession> { session in
      await Task.yield()
      session.terminate()
    }

    await slot.replace(with: first)
    await slot.replace(with: second)
    await slot.shutdown()

    #expect(slot.current == nil)
    #expect(first.terminationCount == 1)
    #expect(second.terminationCount == 1)
  }

  @Test("shutdown rejects and drains replacements without overlapping terminations")
  func shutdownRejectsAndDrainsReplacements() async throws {
    let first = FakePreviewSession()
    let replacement = FakePreviewSession()
    let gate = TerminationGate()
    let slot = PreviewSessionSlot<FakePreviewSession> { session in
      await gate.terminate(session)
    }

    #expect(await slot.replace(with: first))
    let shutdown = Task { @MainActor in
      await slot.shutdown()
    }
    try await gate.waitForStarts(
      1,
      deadline: ContinuousClock().now + .seconds(1)
    )

    let rejectedReplacement = Task { @MainActor in
      await slot.replace(with: replacement)
    }
    await Task.yield()
    #expect(slot.current == nil)
    #expect(await gate.maximumConcurrentTerminations == 1)

    await gate.releaseNext()
    try await gate.waitForStarts(
      2,
      deadline: ContinuousClock().now + .seconds(1)
    )
    #expect(await gate.maximumConcurrentTerminations == 1)
    await gate.releaseNext()
    #expect(!(await rejectedReplacement.value))
    await shutdown.value

    #expect(slot.current == nil)
    #expect(first.terminationCount == 1)
    #expect(replacement.terminationCount == 1)
    #expect(await gate.maximumConcurrentTerminations == 1)

    let afterShutdown = FakePreviewSession()
    await gate.releaseNext()
    #expect(!(await slot.replace(with: afterShutdown)))
    #expect(slot.current == nil)
    #expect(afterShutdown.terminationCount == 1)
  }
}

private func waitForTermination(of session: FakePreviewSession) async {
  let clock = ContinuousClock()
  let deadline = clock.now + .seconds(1)
  while clock.now < deadline, session.terminationCount == 0 {
    await Task.yield()
  }
}

private final class FakePreviewSession: Sendable {
  private let state = Mutex(0)

  var terminationCount: Int {
    state.withLock { $0 }
  }

  func terminate() {
    state.withLock {
      $0 += 1
    }
  }
}

private actor TerminationGate {
  private var starts = 0
  private var activeTerminations = 0
  private var maximumActiveTerminations = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var permits = 0

  var maximumConcurrentTerminations: Int {
    maximumActiveTerminations
  }

  func terminate(_ session: FakePreviewSession) async {
    starts += 1
    activeTerminations += 1
    maximumActiveTerminations = max(maximumActiveTerminations, activeTerminations)
    await waitForPermit()
    session.terminate()
    activeTerminations -= 1
  }

  func waitForStarts(
    _ expected: Int,
    deadline: ContinuousClock.Instant
  ) async throws {
    let clock = ContinuousClock()
    while starts < expected, clock.now < deadline {
      await Task.yield()
    }
    guard starts >= expected else {
      throw TerminationGateError.timedOut(expectedStarts: expected)
    }
  }

  func releaseNext() {
    if waiters.isEmpty {
      permits += 1
    } else {
      waiters.removeFirst().resume()
    }
  }

  private func waitForPermit() async {
    if permits > 0 {
      permits -= 1
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }
}

private enum TerminationGateError: Error {
  case timedOut(expectedStarts: Int)
}

@testable import FilePreviewerApp
import Synchronization
import Testing

@MainActor
struct PreviewSessionSlotTests {
  @Test("replace terminates the previous session")
  func replaceTerminatesPreviousSession() {
    let first = FakePreviewSession()
    let second = FakePreviewSession()
    let slot = PreviewSessionSlot<FakePreviewSession> { session in
      session.terminate()
    }

    slot.replace(with: first)
    slot.replace(with: second)

    #expect(slot.current === second)
    #expect(first.terminationCount == 1)
    #expect(second.terminationCount == 0)
  }

  @Test("replacing with the same session is a no-op")
  func replacingWithSameSessionDoesNotTerminate() {
    let session = FakePreviewSession()
    let slot = PreviewSessionSlot<FakePreviewSession> { session in
      session.terminate()
    }

    slot.replace(with: session)
    slot.replace(with: session)

    #expect(slot.current === session)
    #expect(session.terminationCount == 0)
  }

  @Test("clear terminates the current session once")
  func clearTerminatesCurrentSessionOnce() {
    let session = FakePreviewSession()
    let slot = PreviewSessionSlot<FakePreviewSession> { session in
      session.terminate()
    }

    slot.replace(with: session)
    slot.clear()
    slot.clear()

    #expect(slot.current == nil)
    #expect(session.terminationCount == 1)
  }

  @Test("deinit terminates the current session")
  func deinitTerminatesCurrentSession() {
    let session = FakePreviewSession()

    do {
      let slot = PreviewSessionSlot<FakePreviewSession> { session in
        session.terminate()
      }
      slot.replace(with: session)
    }

    #expect(session.terminationCount == 1)
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

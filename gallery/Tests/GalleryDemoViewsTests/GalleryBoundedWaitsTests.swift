@_spi(Testing) import SwiftTUITestSupport
import Testing

/// Coverage for the wall-clock ceiling that bounds the gallery's runtime waits.
///
/// The ceiling is the guard that stops a stalled animation from hanging the org
/// examples gate until its job cap. A guard with no test is a guard nobody
/// notices the loss of, and this one is invisible when it works: a healthy run
/// never reaches it. `stalledWaitFailsInsteadOfHanging` is therefore the load
/// bearing case — delete the `Task.sleep` racer from `withGalleryWaitCeiling`
/// and it hangs forever rather than failing, which is exactly the regression it
/// exists to catch.
@Suite
struct GalleryBoundedWaitsTests {
  @Test("a wait that resolves returns its value and never reaches the ceiling")
  func resolvedWaitReturnsItsValue() async throws {
    let event = AsyncEvent()
    event.fire()

    let value = try await withGalleryWaitCeiling(
      "an event that already fired",
      nanoseconds: 30_000_000_000
    ) {
      await event.wait()
      return 42
    }

    #expect(value == 42)
  }

  @Test("a wait that never resolves fails at the ceiling instead of hanging")
  func stalledWaitFailsInsteadOfHanging() async throws {
    // Never fired: this models the animation that stops presenting, so the
    // waiter can never be resumed by the thing it is synchronising on.
    let stalled = AsyncEvent()
    let clock = ContinuousClock()
    let started = clock.now

    await #expect(throws: GalleryWaitCeilingExceeded.self) {
      try await withGalleryWaitCeiling(
        "a stalled animation",
        nanoseconds: 200_000_000
      ) {
        await stalled.wait()
      }
    }

    // Generous enough not to flake on a loaded runner, tight enough that a
    // missing ceiling (which would hang until the test harness gives up) fails.
    #expect(clock.now - started < .seconds(20))
  }

  @Test("the ceiling failure names the wait and reads as a stall, not slowness")
  func ceilingFailureCarriesADiagnostic() async {
    let failure = GalleryWaitCeilingExceeded(
      label: "the chasing-light animation to present three frames",
      nanoseconds: 180_000_000_000
    )

    #expect(failure.description.contains("chasing-light animation"))
    #expect(failure.description.contains("180s"))
    #expect(
      failure.description.contains("stalled animation, not a slow runner"),
      "the diagnostic must steer the reader away from blaming runner load"
    )
  }

  @Test("the ceiling cancels the operation it abandoned")
  func ceilingCancelsTheAbandonedOperation() async throws {
    // A stranded operation task would keep whatever the wait holds alive past
    // the test, so the group must observe the cancellation unwind before
    // `withGalleryWaitCeiling` returns.
    let observedCancellation = AsyncEvent()
    let stalled = AsyncEvent()

    await #expect(throws: GalleryWaitCeilingExceeded.self) {
      try await withGalleryWaitCeiling(
        "an operation that must be cancelled",
        nanoseconds: 200_000_000
      ) {
        await withTaskCancellationHandler {
          await stalled.wait()
        } onCancel: {
          observedCancellation.fire()
        }
      }
    }

    // Bounded so a regression fails rather than hanging this test in turn.
    try await withGalleryWaitCeiling(
      "the abandoned operation to observe cancellation",
      nanoseconds: 10_000_000_000
    ) {
      await observedCancellation.wait()
    }
  }

  @Test("the recorder hands a ceiling failure back to the test body")
  func recorderCarriesFailureToTheTestBody() async throws {
    let recorder = GalleryWaitFailureRecorder()

    // Nothing recorded: the test body proceeds to its real assertions.
    try await recorder.requireNoFailure()

    await recorder.record(
      GalleryWaitCeilingExceeded(label: "a stalled wait", nanoseconds: 1_000_000_000)
    )

    await #expect(throws: GalleryWaitCeilingExceeded.self) {
      try await recorder.requireNoFailure()
    }
  }
}

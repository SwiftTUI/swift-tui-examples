import Foundation

// A wall-clock ceiling for the gallery's runtime-driven waits.
//
// The poll-free test signals (`MainActorConditionSignal`, `AsyncEvent`) are
// deliberately unbounded: a waiter re-checks its predicate only when the host
// presents a frame, so a *starved* run loop slows a test down instead of
// failing it. That is the right trade for a loaded CI runner — but it means a
// genuinely stalled animation never presents again, the waiter parks forever,
// and the only backstop left is the CI job cap.
//
// That is not hypothetical. On 2026-08-19 the org's `examples vs framework
// HEAD` gate burned its full 1h15m cap three runs running, silent for 47
// minutes, because two gallery animation tests parked exactly this way. The
// failure reported as "job timed out" — nothing named the animation.
//
// These helpers keep the poll-free synchronisation and add only a last-resort
// ceiling, so a stall fails in minutes with a diagnostic that says which wait
// gave up.
//
// The framework's `withStageBudget` solves the same problem with a
// hardware-independent stage budget, and it is the better tool where it fits.
// It is not used here: its wall-clock backstop is a hardcoded 30s, and these
// tests healthily take 22.0s and 36.5s on the org gate's Linux runner, so that
// backstop would fire on a passing run and trade the hang for a flake. Raising
// it belongs in `swift-tui`, and this package builds against a *tagged*
// framework release — so the ceiling lives here until such a change ships.

/// The ceiling applied to every gallery runtime wait.
///
/// Sized against the slowest healthy observation (36.5s, `AnimationsTab` on the
/// org gate's Linux runner; 3.1s on a dev Mac) with room for a runner several
/// times slower still, while staying far below the gate's 75-minute job cap.
let galleryWaitCeilingNanoseconds: UInt64 = 180_000_000_000

/// Thrown when a gallery runtime wait exceeds its ceiling.
struct GalleryWaitCeilingExceeded: Error, CustomStringConvertible {
  let label: String
  let nanoseconds: UInt64

  var description: String {
    let seconds = Double(nanoseconds) / 1_000_000_000
    return """
      Waiting for \(label) exceeded its \(String(format: "%.0f", seconds))s ceiling. \
      The runtime stopped presenting frames, so the wait could never make \
      progress — this is a stalled animation, not a slow runner.
      """
  }
}

/// Runs `operation`, abandoning it with ``GalleryWaitCeilingExceeded`` if
/// `nanoseconds` elapse first.
///
/// `operation` must be cancellation-aware: when the ceiling wins the race the
/// operation task is cancelled, and the task group waits for it to unwind
/// before this returns. The poll-free signals satisfy this — both resume
/// promptly on cancellation precisely so they can be raced inside a group.
func withGalleryWaitCeiling<R: Sendable>(
  _ label: String,
  nanoseconds: UInt64 = galleryWaitCeilingNanoseconds,
  _ operation: @escaping @Sendable () async -> R
) async throws -> R {
  try await withThrowingTaskGroup(of: R.self) { group in
    group.addTask {
      await operation()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: nanoseconds)
      throw GalleryWaitCeilingExceeded(label: label, nanoseconds: nanoseconds)
    }
    defer { group.cancelAll() }
    guard let result = try await group.next() else {
      throw GalleryWaitCeilingExceeded(label: label, nanoseconds: nanoseconds)
    }
    return result
  }
}

/// Carries a ceiling failure out of an input stream's detached task so the test
/// body can fail on it.
///
/// A `TerminalInputReading` conformance produces events inside an
/// `AsyncStream` continuation task, which cannot throw. When a bounded wait
/// gives up there, all the stream can do is finish early — and a finished input
/// stream reads to the run loop as a clean shutdown. Without this hand-off a
/// stalled animation would surface as a puzzling assertion mismatch against a
/// truncated frame capture instead of the named ceiling failure.
actor GalleryWaitFailureRecorder {
  private var failure: GalleryWaitCeilingExceeded?

  func record(_ failure: GalleryWaitCeilingExceeded) {
    self.failure = failure
  }

  func requireNoFailure() throws {
    if let failure {
      throw failure
    }
  }
}

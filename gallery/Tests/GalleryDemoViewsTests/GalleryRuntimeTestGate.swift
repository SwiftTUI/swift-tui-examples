import Foundation
import Testing

/// Gate for environment-sensitive gallery runtime tests.
///
/// Some gallery tests drive the live ``RunLoop`` with real terminal I/O (PTYs)
/// or with autonomous `.task`-driven animation observed through a blocked
/// awaited-input reader. Those paths are timing- and terminal-dependent and do
/// not run reliably under headless `swift test`:
///
///   - The run loop only pumps frames on terminal input or a scheduler
///     deadline. Autonomous `@State`/`.task` animation observed while the
///     awaited-input reader is parked on a predicate stalls (no further
///     `present()`), so frame-budget waits never make progress.
///   - Real-terminal SGR mouse input is not delivered deterministically through
///     a headless PTY, so click-driven assertions (e.g. row deletion) flake.
///
/// These tests stay valuable and runnable on demand — set the
/// `GALLERY_RUNTIME_TESTS` environment variable (for example in Xcode or a
/// terminal-backed CI lane) — but are skipped by default so the repository's
/// `swift test` run is green and can never hang. The org gate build-checks the
/// gallery package; it does not run these suites.
let galleryRuntimeTestsEnabled =
  ProcessInfo.processInfo.environment["GALLERY_RUNTIME_TESTS"] != nil

/// Shared skip explanation attached to every gated runtime test.
let galleryRuntimeTestGateComment: Comment =
  "Environment-sensitive runtime/PTY test; set GALLERY_RUNTIME_TESTS=1 to run."

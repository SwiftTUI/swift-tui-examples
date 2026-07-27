import Foundation
import Testing

/// Gate for the resource-owning real-terminal integration journey.
///
/// Swift Testing executes independent suites concurrently in one process. The
/// journey owns a PTY, a production async run loop, and nested child processes,
/// so running it beside the deterministic unit and performance suites can
/// starve the terminal handshake. The native gate runs this suite in its own
/// process after the default suite has completed.
let sextantRealPTYTestsEnabled =
  ProcessInfo.processInfo.environment["SEXTANT_REAL_PTY_TESTS"] != nil

let sextantRealPTYTestGateComment: Comment =
  "Resource-owning PTY test; set SEXTANT_REAL_PTY_TESTS=1 to run."

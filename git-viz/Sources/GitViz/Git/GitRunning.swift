import Foundation
import Synchronization

/// The seam between *building* a git command line and *running* it.
///
/// `GitRepo` owns every `argv` array and every argv-to-parser pairing; this
/// protocol owns only the act of executing one. Splitting them here is what
/// lets a test assert the argv `GitRepo` actually issues — which is where the
/// interesting mistakes live, because the parsers are pure and already tested.
///
/// Two adapters ship: ``ProcessGitRunner`` spawns the real binary,
/// ``RecordedGitRunner`` replays output captured from a real repository by
/// `Scripts/record_git_fixtures.sh`.
protocol GitRunning: Sendable {
  /// Runs `git <argv>` with `workingDirectory` as the cwd and returns stdout
  /// decoded as UTF-8. Throws on launch failure, nonzero exit, or non-UTF-8
  /// output.
  func run(_ argv: [String], in workingDirectory: URL) throws -> String
}

/// Errors produced when a recorded run has nothing to replay.
enum RecordedGitError: Error, CustomStringConvertible, Sendable {
  case noRecording(argv: [String], known: [[String]])

  var description: String {
    switch self {
    case .noRecording(let argv, let known):
      let wanted = argv.joined(separator: " ")
      let available = known
        .map { "  git \($0.joined(separator: " "))" }
        .sorted()
        .joined(separator: "\n")
      return """
        No recording for `git \(wanted)`.

        Recorded argv:
        \(available.isEmpty ? "  (none)" : available)

        Recordings are keyed on the exact argv. If this fired because the argv \
        changed deliberately, re-run Scripts/record_git_fixtures.sh; if it \
        fired unexpectedly, the argv changed by accident.
        """
    }
  }
}

/// Replays git output captured ahead of time, keyed on the exact `argv`.
///
/// The exact-match rule is the point: an argv that no recording covers is a
/// loud failure rather than an empty string, so a flag that silently changes
/// meaning — dropping `-z`, or pairing `--reverse` with `--max-count` — fails
/// a test instead of degrading into a plausible-looking wrong chart.
final class RecordedGitRunner: GitRunning {
  private let recordings: [[String]: String]
  private let log = Mutex<[[String]]>([])

  init(_ recordings: [[String]: String]) {
    self.recordings = recordings
  }

  /// Every argv this runner was asked to run, in call order. Lets a test
  /// assert *which* commands a `GitRepo` method issues, not just what it
  /// returns.
  var issued: [[String]] {
    log.withLock { $0 }
  }

  func run(_ argv: [String], in workingDirectory: URL) throws -> String {
    log.withLock { $0.append(argv) }
    guard let output = recordings[argv] else {
      throw RecordedGitError.noRecording(argv: argv, known: Array(recordings.keys))
    }
    return output
  }
}

import Foundation
import Testing

@testable import GitViz

/// Tests for the argv `GitRepo` issues and the model it builds from the
/// output — the half of the pipeline that used to have no test surface,
/// because running git and interpreting git were welded together.
@Suite("GitRepo argv and pairing")
struct GitRepoTests {
  private static let repoPath = "/tmp/git-viz-test-repo"
  private static let oldest = "2020-01-01T09:00:00+00:00"
  private static let newest = "2026-07-28T09:00:00+00:00"

  /// Recordings for a two-commit repository.
  ///
  /// Note the two `--reverse` entries. Git applies `--max-count` *during* the
  /// walk and reverses afterwards, so `log --reverse --max-count 1` yields the
  /// NEWEST commit — that entry records real git behaviour, not a mistake.
  /// The entry without `--max-count` is what actually yields the oldest.
  private static func twoCommitRunner() -> RecordedGitRunner {
    RecordedGitRunner([
      ["rev-parse", "--show-toplevel"]: "\(repoPath)\n",
      ["rev-parse", "--abbrev-ref", "HEAD"]: "main\n",
      ["rev-list", "--count", "HEAD"]: "2\n",
      ["log", "--reverse", "--pretty=format:%aI", "--max-count", "1"]: newest,
      ["log", "--reverse", "--pretty=format:%aI"]: "\(oldest)\n\(newest)",
      ["log", "--pretty=format:%aI", "--max-count", "1"]: newest,
      ["shortlog", "-s", "-n", "-e", "HEAD"]: "     2\tAlice <alice@example.com>\n",
      ["tag", "--list"]: "v0.1.0\nv0.2.0\n",
    ])
  }

  @Test("info() reports the oldest commit as firstCommitDate, not the newest")
  func infoReportsOldestCommitAsFirst() throws {
    let repo = try GitRepo(
      workingDirectory: URL(fileURLWithPath: Self.repoPath),
      runner: Self.twoCommitRunner()
    )

    let info = try repo.info()

    #expect(info.firstCommitDate == GitParsers.parseISODate(Self.oldest))
    #expect(info.lastCommitDate == GitParsers.parseISODate(Self.newest))
    #expect(info.firstCommitDate != info.lastCommitDate)
  }

  @Test("first-commit lookup never pairs --reverse with --max-count")
  func firstCommitArgvDoesNotPairReverseWithMaxCount() throws {
    let runner = Self.twoCommitRunner()
    let repo = try GitRepo(
      workingDirectory: URL(fileURLWithPath: Self.repoPath),
      runner: runner
    )

    _ = try repo.info()

    let reverseCalls = runner.issued.filter { $0.contains("--reverse") }
    #expect(reverseCalls.count == 1)
    // The pairing git silently reinterprets. Asserted directly so a future
    // "optimization" that adds the bound fails here rather than in a chart.
    #expect(reverseCalls.allSatisfy { !$0.contains("--max-count") })
  }

  @Test("info() carries branch, counts and scanned share")
  func infoCarriesCountsAndShare() throws {
    let repo = try GitRepo(
      workingDirectory: URL(fileURLWithPath: Self.repoPath),
      runner: Self.twoCommitRunner()
    )

    let info = try repo.info(maxCommitsForScannedShare: 1)

    #expect(info.branch == "main")
    #expect(info.commitCount == 2)
    #expect(info.contributorCount == 1)
    #expect(info.tagCount == 2)
    #expect(info.scannedCommitShare == 0.5)
  }

  // MARK: - Opening a repository

  @Test("opening resolves the worktree root, so a subdirectory works")
  func openingResolvesWorktreeRoot() throws {
    let runner = RecordedGitRunner([
      ["rev-parse", "--show-toplevel"]: "\(Self.repoPath)\n"
    ])

    let repo = try GitRepo(
      workingDirectory: URL(fileURLWithPath: "\(Self.repoPath)/Sources/deep/nested"),
      runner: runner
    )

    #expect(repo.workingDirectory.path == Self.repoPath)
  }

  @Test("opening a non-repository throws notARepository")
  func openingNonRepositoryThrows() {
    // No recording for `rev-parse --show-toplevel` — the same shape as git
    // exiting nonzero outside a worktree.
    let runner = RecordedGitRunner([:])

    #expect(throws: GitRepoError.self) {
      try GitRepo(workingDirectory: URL(fileURLWithPath: "/not/a/repo"), runner: runner)
    }
  }

  // MARK: - argv the parsers depend on

  @Test("commits() issues -z, which the numstat parser depends on")
  func commitsIssuesNulSeparatedLog() throws {
    let runner = RecordedGitRunner([
      ["rev-parse", "--show-toplevel"]: "\(Self.repoPath)\n",
      [
        "log", "--no-color", "-z",
        "--pretty=format:\(GitParsers.recordSeparator)\(GitParsers.logFormat)",
        "--numstat",
      ]: "",
    ])
    let repo = try GitRepo(
      workingDirectory: URL(fileURLWithPath: Self.repoPath),
      runner: runner
    )

    _ = try repo.commits()

    let logCall = try #require(runner.issued.first { $0.first == "log" })
    // `parseLogWithNumstat` splits entries on NUL. Without -z the split
    // yields one blob and every commit past the first file silently
    // under-counts — a shape no parser test can catch on its own.
    #expect(logCall.contains("-z"))
    #expect(logCall.contains("--numstat"))
  }

  @Test("commits() appends bounds only when asked")
  func commitsAppendsBoundsOnlyWhenAsked() throws {
    let base = [
      "log", "--no-color", "-z",
      "--pretty=format:\(GitParsers.recordSeparator)\(GitParsers.logFormat)",
      "--numstat",
    ]
    let runner = RecordedGitRunner([
      ["rev-parse", "--show-toplevel"]: "\(Self.repoPath)\n",
      base: "",
      base + ["--since=2024-01-01", "--max-count=5"]: "",
    ])
    let repo = try GitRepo(
      workingDirectory: URL(fileURLWithPath: Self.repoPath),
      runner: runner
    )

    _ = try repo.commits()
    _ = try repo.commits(
      since: GitParsers.parseISODate("2024-01-01T00:00:00+00:00"),
      max: 5
    )

    let logCalls = runner.issued.filter { $0.first == "log" }
    #expect(logCalls.count == 2)
    #expect(logCalls[0].allSatisfy { !$0.hasPrefix("--since=") })
    #expect(logCalls[1].contains("--since=2024-01-01"))
    #expect(logCalls[1].contains("--max-count=5"))
  }

  @Test("an argv with no recording fails loudly rather than returning empty")
  func unrecordedArgvFailsLoudly() throws {
    let runner = RecordedGitRunner([
      ["rev-parse", "--show-toplevel"]: "\(Self.repoPath)\n"
    ])
    let repo = try GitRepo(
      workingDirectory: URL(fileURLWithPath: Self.repoPath),
      runner: runner
    )

    #expect(throws: RecordedGitError.self) {
      try repo.shortlog()
    }
  }
}

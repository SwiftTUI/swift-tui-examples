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
      ["branch", "--show-current"]: "main\n",
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
    #expect(!info.isDetached)
    #expect(info.headLabel == "branch main")
    #expect(info.commitCount == 2)
    #expect(info.contributorCount == 1)
    #expect(info.tagCount == 2)
    #expect(info.scannedCommitShare == 0.5)
  }

  @Test("info() says a detached HEAD is detached rather than naming a branch")
  func infoLabelsDetachedHead() throws {
    // `branch --show-current` prints an empty line when HEAD is detached.
    let detached = RecordedGitRunner([
      ["rev-parse", "--show-toplevel"]: "\(Self.repoPath)\n",
      ["branch", "--show-current"]: "\n",
    ])
    let info = try GitRepo(
      workingDirectory: URL(fileURLWithPath: Self.repoPath),
      runner: detached
    ).info()

    #expect(info.branch == nil)
    #expect(info.isDetached)
    #expect(info.headLabel == "detached HEAD")

    // When git cannot say at all, nothing is claimed either way.
    let unknown = RecordedGitRunner([
      ["rev-parse", "--show-toplevel"]: "\(Self.repoPath)\n"
    ])
    let unknownInfo = try GitRepo(
      workingDirectory: URL(fileURLWithPath: Self.repoPath),
      runner: unknown
    ).info()

    #expect(unknownInfo.branch == nil)
    #expect(!unknownInfo.isDetached)
    #expect(unknownInfo.headLabel == nil)
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

  @Test("opening keeps the toplevel verbatim, trailing space included")
  func openingKeepsTrailingSpaceInToplevel() throws {
    let runner = RecordedGitRunner([
      ["rev-parse", "--show-toplevel"]: "/tmp/trail \n"
    ])

    let repo = try GitRepo(workingDirectory: URL(fileURLWithPath: "/tmp/trail "), runner: runner)

    #expect(repo.workingDirectory.path == "/tmp/trail ")
  }

  @Test("opening a bare repository resolves its git directory")
  func openingBareRepositoryUsesGitDir() throws {
    // No recording for `--show-toplevel`: git refuses it without a worktree.
    let runner = RecordedGitRunner([
      ["rev-parse", "--is-bare-repository", "--absolute-git-dir"]: "true\n/srv/x.git\n"
    ])

    let repo = try GitRepo(
      workingDirectory: URL(fileURLWithPath: "/srv/x.git/refs"), runner: runner)

    #expect(repo.workingDirectory.path == "/srv/x.git")
    #expect(
      runner.issued == [
        ["rev-parse", "--show-toplevel"],
        ["rev-parse", "--is-bare-repository", "--absolute-git-dir"],
      ])
  }

  @Test("opening the inside of a worktree's .git directory is still refused")
  func openingInsideGitDirectoryIsStillRefused() {
    let runner = RecordedGitRunner([
      ["rev-parse", "--is-bare-repository", "--absolute-git-dir"]: "false\n/r/.git\n"
    ])

    #expect(throws: GitRepoError.self) {
      try GitRepo(workingDirectory: URL(fileURLWithPath: "/r/.git"), runner: runner)
    }
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
        "--pretty=format:\(GitParsers.logFormat)",
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

  @Test("fileChangeCounts() issues -z, so paths arrive verbatim rather than C-quoted")
  func fileChangeCountsIssuesNulSeparatedNameOnly() throws {
    let runner = RecordedGitRunner([
      ["rev-parse", "--show-toplevel"]: "\(Self.repoPath)\n",
      [
        "log", "--no-color", "-z", "--diff-filter=AMD", "--name-only", "--pretty=format:",
      ]: "\u{E9}.txt\0a\tb.txt\0",
    ])
    let repo = try GitRepo(
      workingDirectory: URL(fileURLWithPath: Self.repoPath),
      runner: runner
    )

    let tallies = try repo.fileChangeCounts()

    let logCall = try #require(runner.issued.first { $0.first == "log" })
    // Without -z, `core.quotePath` turns `é.txt` into `"\303\251.txt"`.
    #expect(logCall.contains("-z"))
    #expect(logCall.contains("--name-only"))
    #expect(
      Set(tallies)
        == [
          FileTally(path: "\u{E9}.txt", changeCount: 1),
          FileTally(path: "a\tb.txt", changeCount: 1),
        ]
    )
  }

  @Test("commits() appends bounds only when asked")
  func commitsAppendsBoundsOnlyWhenAsked() throws {
    let base = [
      "log", "--no-color", "-z",
      "--pretty=format:\(GitParsers.logFormat)",
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

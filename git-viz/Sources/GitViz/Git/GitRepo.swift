import Foundation

/// Errors specific to working with a `GitRepo` (separate from `GitProcessError`
/// which is concerned only with process-level failures).
enum GitRepoError: Error, CustomStringConvertible, Sendable {
  case notARepository(path: URL)

  var description: String {
    switch self {
    case .notARepository(let path):
      return "\(path.path) is not a git repository."
    }
  }
}

/// Public facade over the local git binary. Synchronous, throwing,
/// `Sendable`.
struct GitRepo: Sendable {
  /// The resolved worktree root — not necessarily the path the caller passed.
  /// For a bare repository, which has no worktree, its git directory.
  let workingDirectory: URL

  private let runner: any GitRunning

  /// Opens the repository containing `workingDirectory`.
  ///
  /// Validation asks git rather than probing the filesystem for `.git`. That
  /// matters for three reasons: a submodule's `.git` is a *file* rather than a
  /// directory, a linked worktree's is neither, and `git-viz` should work from
  /// any subdirectory the way every other git command does. `--show-toplevel`
  /// answers all three, and answers it through the seam, so a recorded run can
  /// answer it too.
  ///
  /// `--show-toplevel` needs a worktree, so a bare repository fails it. git's
  /// history commands still run there, so a bare repository opens at its git
  /// directory. Anything else that fails it — no repository, or the inside
  /// of a worktree's `.git` — is refused.
  init(workingDirectory: URL, runner: any GitRunning = ProcessGitRunner()) throws {
    // The path is printed verbatim plus one newline. Trimming whitespace
    // would turn `…/trail ` into a different directory.
    let toplevel =
      (try? runner.run(["rev-parse", "--show-toplevel"], in: workingDirectory))?
      .droppingOneTrailingNewline ?? ""
    let root: String
    if !toplevel.isEmpty {
      root = toplevel
    } else if let gitDirectory = Self.bareGitDirectory(of: workingDirectory, runner: runner) {
      root = gitDirectory
    } else {
      throw GitRepoError.notARepository(path: workingDirectory)
    }
    self.workingDirectory = URL(fileURLWithPath: root)
    self.runner = runner
  }

  /// The absolute git directory when `directory` is in a bare repository,
  /// or nil.
  private static func bareGitDirectory(of directory: URL, runner: any GitRunning) -> String? {
    guard
      let output = try? runner.run(
        ["rev-parse", "--is-bare-repository", "--absolute-git-dir"], in: directory)
    else { return nil }
    // `true` or `false`, a newline, then the path verbatim plus a newline.
    let lines = output.droppingOneTrailingNewline
    guard let newline = lines.firstIndex(of: "\n"), lines[..<newline] == "true" else {
      return nil
    }
    let gitDirectory = String(lines[lines.index(after: newline)...])
    return gitDirectory.isEmpty ? nil : gitDirectory
  }

  /// Runs repository IO and parsing outside the caller's actor.
  ///
  /// SwiftTUI command bodies render on the main actor, but `git` subprocesses
  /// and history parsing can block for large repositories. Keep that work
  /// behind this helper so commands prepare their data before hopping back to
  /// render.
  static func perform<T: Sendable>(
    workingDirectory: URL,
    priority: TaskPriority = .userInitiated,
    runner: any GitRunning = ProcessGitRunner(),
    _ operation: @Sendable @escaping (GitRepo) throws -> T
  ) async throws -> T {
    try await Task.detached(priority: priority) {
      let repo = try GitRepo(workingDirectory: workingDirectory, runner: runner)
      return try operation(repo)
    }.value
  }

  // MARK: - High-level summaries

  /// Repository-level summary used by `git-viz info`.
  func info(maxCommitsForScannedShare maxScan: Int? = nil) throws -> RepoInfo {
    // The branch HEAD names, an unborn one included; empty when HEAD is
    // detached. (`rev-parse --abbrev-ref HEAD` prints `HEAD` when detached
    // and fails on an unborn branch.)
    let currentBranch = (try? run(["branch", "--show-current"]))?.droppingOneTrailingNewline
    let commitCount =
      (try? GitParsers.parseInteger(run(["rev-list", "--count", "HEAD"]))) ?? 0
    // `--max-count` deliberately absent: git applies it *during* the walk and
    // applies `--reverse` to the result, so `log --reverse --max-count 1`
    // returns the NEWEST commit. Take the whole reversed list and read its
    // first line instead.
    let firstCommit =
      (try? run([
        "log", "--reverse", "--pretty=format:%aI",
      ]).trimmedLine).flatMap { GitParsers.parseISODate($0) }
    let lastCommit =
      (try? run([
        "log", "--pretty=format:%aI", "--max-count", "1",
      ]).trimmedLine).flatMap { GitParsers.parseISODate($0) }
    let contributorCount =
      (try? run(["shortlog", "-s", "-n", "-e", "HEAD"]).lineCount) ?? 0
    let tagCount =
      (try? run(["tag", "--list"]).lineCount) ?? 0

    let scanned: Int
    if let maxScan, maxScan > 0, commitCount > 0 {
      scanned = min(maxScan, commitCount)
    } else {
      scanned = commitCount
    }
    let share: Double
    if commitCount > 0 {
      share = Double(scanned) / Double(commitCount)
    } else {
      share = 1.0
    }

    return RepoInfo(
      path: workingDirectory,
      branch: currentBranch?.isEmpty == false ? currentBranch : nil,
      isDetached: currentBranch?.isEmpty == true,
      commitCount: commitCount,
      contributorCount: contributorCount,
      firstCommitDate: firstCommit,
      lastCommitDate: lastCommit,
      tagCount: tagCount,
      scannedCommitShare: share
    )
  }

  // MARK: - Commit lists

  /// Returns the commit history, newest first, optionally bounded.
  func commits(
    since: Date? = nil,
    until: Date? = nil,
    max: Int? = nil
  ) throws -> [Commit] {
    var args: [String] = [
      "log",
      "--no-color",
      "-z",
      "--pretty=format:\(GitParsers.logFormat)",
      "--numstat",
    ]
    if let since {
      args.append("--since=\(formatGitDate(since))")
    }
    if let until {
      args.append("--until=\(formatGitDate(until))")
    }
    if let max {
      args.append("--max-count=\(max)")
    }
    let raw = try run(args)
    return GitParsers.parseLogWithNumstat(raw)
  }

  /// Per-commit deltas (numstat tallies) since/until/max-bounded.
  func numstat(
    since: Date? = nil,
    until: Date? = nil,
    max: Int? = nil
  ) throws -> [CommitDelta] {
    let commits = try commits(since: since, until: until, max: max)
    return GitParsers.deltas(from: commits)
  }

  /// `git shortlog -s -n -e` parsed into author tallies, sorted desc by count.
  func shortlog(since: Date? = nil, until: Date? = nil) throws -> [AuthorTally] {
    var args = ["shortlog", "-s", "-n", "-e"]
    if let since {
      args.append("--since=\(formatGitDate(since))")
    }
    if let until {
      args.append("--until=\(formatGitDate(until))")
    }
    args.append("HEAD")
    let raw = try run(args)
    return GitParsers.parseShortlog(raw)
  }

  /// All tags with creation date and annotated-vs-lightweight flag.
  func tags() throws -> [Tag] {
    let raw = try run([
      "for-each-ref",
      "refs/tags",
      "--format=\(GitParsers.tagFormat)",
    ])
    return GitParsers.parseTags(raw)
  }

  /// File change-count ranking (by raw file-touch frequency, like
  /// `git log --diff-filter=AMD --name-only`). Sorted desc by count.
  ///
  /// `-z` makes the paths NUL-terminated and verbatim; without it
  /// `core.quotePath` C-quotes any path holding a control character or a
  /// byte above 0x7F. The empty format prints no header, so the output is
  /// nothing but paths.
  func fileChangeCounts(
    since: Date? = nil,
    until: Date? = nil,
    max: Int? = nil
  ) throws -> [FileTally] {
    var args = [
      "log",
      "--no-color",
      "-z",
      "--diff-filter=AMD",
      "--name-only",
      "--pretty=format:",
    ]
    if let since {
      args.append("--since=\(formatGitDate(since))")
    }
    if let until {
      args.append("--until=\(formatGitDate(until))")
    }
    if let max {
      args.append("--max-count=\(max)")
    }
    let raw = try run(args)
    return GitParsers.parseChangedFileCounts(raw)
  }

  /// Topologically ordered commit DAG, laid out into lanes by `GraphLayout`.
  func revList(
    reachableFrom ref: String = "HEAD",
    max: Int = 200
  ) throws -> GraphLayout.Result {
    let raw = try run([
      "rev-list",
      "--topo-order",
      "--parents",
      "--max-count=\(max)",
      ref,
    ])
    let revList = GitParsers.parseRevListParents(raw)
    // Map sha → subject for the same window. Done in one extra call so we
    // can decouple `rev-list --parents` (graph topology) from `log` (subject
    // formatting), which keeps each parser focused on one shape.
    let subjectsRaw = try run([
      "log",
      "--no-color",
      "--pretty=format:%H\(GitParsers.fieldSeparator)%s\(GitParsers.recordSeparator)",
      "--max-count=\(max)",
      ref,
    ])
    let subjects = parseSubjects(subjectsRaw)
    let rows = revList.map { row in
      (sha: row.sha, parents: row.parents, subject: subjects[row.sha] ?? "")
    }
    return GraphLayout.layout(rows: rows)
  }

  // MARK: - Helpers

  private func run(_ arguments: [String]) throws -> String {
    try runner.run(arguments, in: workingDirectory)
  }

  private func formatGitDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return formatter.string(from: date)
  }

  private func parseSubjects(_ raw: String) -> [String: String] {
    var map: [String: String] = [:]
    for record in raw.components(separatedBy: GitParsers.recordSeparator) {
      let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let fields = trimmed.components(separatedBy: GitParsers.fieldSeparator)
      guard fields.count >= 2 else { continue }
      map[fields[0]] = fields[1]
    }
    return map
  }
}

extension String {
  /// The string without its final newline, if it has one. For output that
  /// is one verbatim value plus a newline, where any other whitespace is
  /// part of the value.
  fileprivate var droppingOneTrailingNewline: String {
    hasSuffix("\n") ? String(dropLast()) : self
  }

  /// First non-empty line, trimmed.
  fileprivate var trimmedLine: String {
    for line in self.split(separator: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty { return trimmed }
    }
    return ""
  }

  /// Count of non-empty lines after trimming.
  fileprivate var lineCount: Int {
    var count = 0
    for line in self.split(separator: "\n") {
      if !line.trimmingCharacters(in: .whitespaces).isEmpty {
        count += 1
      }
    }
    return count
  }
}

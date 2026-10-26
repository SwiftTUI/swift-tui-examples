import Foundation
import Testing

@testable import GitViz

/// Campaign two E1 pass 2: git-viz input contracts (e1s101–e1s126).
///
/// Repository cases drive the real `git` through `ProcessGitRunner`. Every
/// fixture repository is built with no global or system configuration and
/// pinned identities and dates, and pins `core.quotePath` / `diff.renames`
/// locally so a developer's global configuration cannot change what the
/// runner observes. Layout and adapter cases are pure.
///
/// Every expectation is a plain assertion: the findings this file guarded
/// (STUI-1338 through STUI-1341) are repaired.
@Suite("Campaign E1 pass 2 git-viz contracts", .serialized)
struct AdversarialSetAGitVizTests {
  @Test(arguments: Array(101...126))
  func gitViz(id: Int) throws {
    switch id {
    case 101...108: try e1NumstatAndSeparators(id)
    case 109...111: try e1ChangedFileCounts(id)
    case 112...118: try e1RepositoryShapes(id)
    case 119, 120: try e1Windows(id)
    case 121...124: e1Layout(id)
    case 125: e1DailyCounts()
    default: e1Shortlog()
    }
  }
}

// MARK: - numstat and separators (e1s101–e1s108)

private func e1NumstatAndSeparators(_ id: Int) throws {
  let fixture = try E1GitFixture()
  defer { fixture.remove() }
  let repo = fixture.repo
  try fixture.git(["init", "-q", "-b", "main", repo.path])
  try fixture.configure()
  switch id {
  case 101, 102:
    let (before, after) = id == 101 ? ("x\t7", "y\t9") : ("a.txt", "b.txt")
    try fixture.write("one\n", to: before)
    try fixture.commitAll("add", at: "2020-01-01T00:00:00+0000")
    try fixture.git(["mv", before, after], in: repo)
    try fixture.commitAll("rename", at: "2020-01-02T00:00:00+0000")
    let rename = try #require(try fixture.open().commits().first { $0.subject == "rename" })
    // STUI-1338: the -z rename's path entries are consumed as paths, never as
    // counts (git-diff(1) --numstat -z rename framing).
    #expect(rename.insertions == 0 && rename.deletions == 0)
  case 103:
    try fixture.write(Data([0x00, 0x01, 0x02, 0xFF]), to: "bin.dat")
    try fixture.commitAll("binary", at: "2020-01-01T00:00:00+0000")
    let commit = try #require(try fixture.open().commits().first)
    #expect(commit.subject == "binary")
    #expect(commit.insertions == 0 && commit.deletions == 0)
  case 104, 105, 106, 107:
    try fixture.write("base\n", to: "f.txt")
    try fixture.commitAll("base", at: "2020-01-01T00:00:00+0000")
    try fixture.write("base\nmore\n", to: "f.txt")
    let subject: String
    var author = "Alice"
    switch id {
    case 104: subject = "fix: a\u{1F}b"
    case 105: subject = "feat: c\u{1E}d"
    case 106:
      subject = "docs: author"
      author = "Al\u{1F}ice"
    default: subject = "feat: 界 👨‍👩‍👧"
    }
    try fixture.commitAll(subject, at: "2020-01-02T00:00:00+0000", author: author)
    let commits = try fixture.open().commits()
    // Precondition from git itself: the subject and author survived intact.
    #expect(try fixture.gitText(["log", "-1", "--format=%s"]) == subject)
    #expect(try fixture.gitText(["log", "-1", "--format=%aN"]) == author)
    let newest = try #require(commits.first)
    // STUI-1338: fields are NUL-framed, so RS and US in %s or %aN stay
    // content (GitParsers.swift logFormat).
    #expect(newest.subject == subject && newest.insertions == 1)
    #expect(newest.authorName == author && newest.authorEmail == "a@example.com")
  default:
    try fixture.commitAll("root", at: "2020-01-01T00:00:00+0000", allowEmpty: true)
    try fixture.git(["checkout", "-q", "-b", "side"], in: repo)
    try fixture.write("side\n", to: "side.txt")
    try fixture.commitAll("side work", at: "2020-01-02T00:00:00+0000")
    try fixture.git(["checkout", "-q", "main"], in: repo)
    try fixture.write("main\n", to: "main.txt")
    try fixture.commitAll("main work", at: "2020-01-03T00:00:00+0000")
    try fixture.git(
      ["merge", "-q", "--no-ff", "side", "-m", "Merge side"], in: repo,
      date: "2020-01-04T00:00:00+0000")
    let merge = try #require(try fixture.open().commits().first)
    #expect(merge.subject == "Merge side")
    #expect(merge.parents.count == 2)
    #expect(merge.insertions == 0 && merge.deletions == 0)
  }
}

// MARK: - changed-file tallies (e1s109–e1s111)

private func e1ChangedFileCounts(_ id: Int) throws {
  let fixture = try E1GitFixture()
  defer { fixture.remove() }
  try fixture.git(["init", "-q", "-b", "main", fixture.repo.path])
  try fixture.configure()
  let names: [String]
  switch id {
  case 109: names = ["é.txt"]
  case 110: names = [" lead.txt", "lead.txt"]
  default: names = ["a\tb.txt"]
  }
  for name in names { try fixture.write("x\n", to: name) }
  try fixture.commitAll("names", at: "2020-01-01T00:00:00+0000")
  // Precondition from git itself, in its unquoted -z spelling.
  let listed = try fixture.git(["ls-files", "-z"], in: fixture.repo)
  #expect(
    Set(String(decoding: listed, as: UTF8.self).split(separator: "\0").map(String.init))
      == Set(names))
  let tallies = try fixture.open().fileChangeCounts()
  // STUI-1338: --name-only runs under -z, so paths are neither C-quoted by
  // core.quotePath nor trimmed; one tally per changed path.
  #expect(Set(tallies) == Set(names.map { FileTally(path: $0, changeCount: 1) }))
}

// MARK: - repository shapes (e1s112–e1s118)

private func e1RepositoryShapes(_ id: Int) throws {
  let fixture = try E1GitFixture(
    repositoryName: id == 112 ? "trail " : id == 113 ? "a b/界" : "repo")
  defer { fixture.remove() }
  let repo = fixture.repo
  try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
  try fixture.git(["init", "-q", "-b", id == 116 ? "trunk" : "main", repo.path])
  try fixture.configure()
  switch id {
  case 112, 113:
    try fixture.write("x\n", to: "deep/f.txt")
    try fixture.commitAll("one", at: "2020-01-01T00:00:00+0000")
    let start = id == 113 ? repo.appendingPathComponent("deep", isDirectory: true) : repo
    let opened = try GitRepo(workingDirectory: start)
    let expected = e1RealPath(repo)
    #expect(expected.hasSuffix(id == 112 ? "trail " : "a b/界"))
    let commitCount = (try? opened.commits().count) ?? -1
    // STUI-1339: the --show-toplevel path is kept verbatim (one newline
    // stripped), so `trail ` keeps its trailing space.
    #expect(opened.workingDirectory.path == expected)
    #expect(commitCount == 1)
  case 114:
    try fixture.write("x\n", to: "f.txt")
    try fixture.commitAll("one", at: "2020-01-01T00:00:00+0000")
    let bare = fixture.root.appendingPathComponent("bare.git")
    try fixture.git(["clone", "-q", "--bare", repo.path, bare.path])
    // Precondition from git itself: history is readable in the bare repository.
    #expect(try fixture.gitText(["log", "--format=%s"], in: bare) == "one")
    // STUI-1339: a bare repository opens at its git directory.
    let opened = try GitRepo(workingDirectory: bare)
    #expect(try opened.commits().count == 1)
  case 115:
    try fixture.write("x\n", to: "f.txt")
    try fixture.commitAll("one", at: "2020-01-01T00:00:00+0000")
    try fixture.write("y\n", to: "f.txt")
    try fixture.commitAll("two", at: "2020-01-02T00:00:00+0000")
    try fixture.git(["checkout", "-q", "--detach", "HEAD~1"], in: repo)
    #expect(try fixture.gitText(["branch", "--show-current"]) == "")
    let info = try fixture.open().info()
    // STUI-1339: the branch comes from branch --show-current; detached is nil
    // and is said explicitly.
    #expect(info.branch == nil)
    #expect(info.isDetached && info.headLabel == "detached HEAD")
  case 116, 117:
    let info = try fixture.open().info()
    if id == 116 {
      #expect(try fixture.gitText(["branch", "--show-current"]) == "trunk")
      // STUI-1339: an unborn branch is still named.
      #expect(info.branch == "trunk")
      #expect(!info.isDetached && info.headLabel == "branch trunk")
    } else {
      #expect(info.commitCount == 0 && info.contributorCount == 0 && info.tagCount == 0)
      #expect(info.firstCommitDate == nil && info.lastCommitDate == nil)
      #expect(info.scannedCommitShare == 1)
    }
  default:
    let blob = try fixture.gitText(["hash-object", "-w", "--stdin"], input: Data("x\n".utf8))
    var entry = Data("100644 blob \(blob)\t".utf8)
    entry.append(contentsOf: [0xE9] + Array(".txt\n".utf8))
    let tree = try fixture.gitText(["mktree"], input: entry)
    let commit = try fixture.gitText(
      ["commit-tree", tree, "-m", "latin1 path"], date: "2020-01-01T00:00:00+0000")
    try fixture.git(["update-ref", "refs/heads/main", commit], in: repo)
    #expect(throws: GitProcessError.self) { try fixture.open().commits() }
    do {
      _ = try fixture.open().commits()
    } catch let error as GitProcessError {
      guard case .decodingFailed = error else {
        Issue.record("expected decodingFailed, got \(error)")
        return
      }
    }
  }
}

// MARK: - history windows (e1s119, e1s120)

private func e1Windows(_ id: Int) throws {
  let fixture = try E1GitFixture()
  defer { fixture.remove() }
  try fixture.git(["init", "-q", "-b", "main", fixture.repo.path])
  try fixture.configure()
  if id == 119 {
    // A(1000) <- B(2000) <- C(4000) on main; A <- X(3000) <- Y(5000) on side;
    // M(6000) merges side. Topological order is M,Y,X,C,B,A; date order is
    // M,Y,C,X,B,A — so the first three differ.
    try fixture.commitAll("A", at: "@1000 +0000", allowEmpty: true)
    try fixture.commitAll("B", at: "@2000 +0000", allowEmpty: true)
    try fixture.git(["checkout", "-q", "-b", "side", "HEAD~1"], in: fixture.repo)
    try fixture.commitAll("X", at: "@3000 +0000", allowEmpty: true)
    try fixture.commitAll("Y", at: "@5000 +0000", allowEmpty: true)
    try fixture.git(["checkout", "-q", "main"], in: fixture.repo)
    try fixture.commitAll("C", at: "@4000 +0000", allowEmpty: true)
    try fixture.git(
      ["merge", "-q", "--no-ff", "side", "-m", "M"], in: fixture.repo, date: "@6000 +0000")
    let topological = try fixture.gitText(["log", "--topo-order", "--format=%s", "-3"])
    #expect(topological == "M\nY\nX")
    let rows = try fixture.open().revList(max: 3).commits
    #expect(rows.count == 3)
    // STUI-1340: topology and subjects come from one topological walk.
    #expect(rows.map(\.subject) == ["M", "Y", "X"])
  } else {
    // Local-time dates without an offset, interpreted by git in the same
    // time zone the bounds are later interpreted in.
    try fixture.commitAll("before", at: "2020-01-01 12:00:00", allowEmpty: true)
    try fixture.commitAll("early", at: "2020-01-02 00:00:01", allowEmpty: true)
    try fixture.commitAll("late", at: "2020-01-02 23:59:59", allowEmpty: true)
    try fixture.commitAll("after", at: "2020-01-03 12:00:00", allowEmpty: true)
    let day = try #require(CalendarDay(argument: "2020-01-02")).date
    let subjects = try fixture.open().commits(since: day, until: day).map(\.subject)
    // STUI-1340: the bounds carry the day's explicit local start and end.
    #expect(Set(subjects) == ["early", "late"])
  }
}

// MARK: - DAG layout (e1s121–e1s124)

private func e1Layout(_ id: Int) {
  typealias Row = (sha: String, parents: [String], subject: String)
  func rows(_ spec: [(String, [String])]) -> [Row] {
    spec.map { (sha: $0.0, parents: $0.1, subject: $0.0) }
  }
  switch id {
  case 121:
    let result = GraphLayout.layout(
      rows: rows([("m", ["a", "b", "c"]), ("a", ["r"]), ("b", ["s"]), ("c", ["r"])]))
    let c = result.commits[3]
    #expect(c.lane == 2)
    // STUI-1341: the join targets the lane waiting for the parent, by id.
    #expect(c.connectorBelow == "├─┼─╯")
  case 122:
    let result = GraphLayout.layout(rows: rows([("m", ["a", "b"]), ("a", ["b", "x"])]))
    // STUI-1341: every already-waited parent gets a join.
    #expect(result.commits[1].connectorBelow != nil)
  case 123:
    let result = GraphLayout.layout(
      rows: rows(
        [("m", (1...5).map { "p\($0)" })] + (1...5).map { ("p\($0)", [String]()) }),
      maxLanes: 3)
    #expect(result.bailed)
    let widest =
      result.commits.flatMap { [$0.glyphRow, $0.connectorBelow ?? ""] }
      .map(\.count).max() ?? 0
    // STUI-1341: the lane bound is checked before a connector is emitted.
    #expect(widest <= 2 * 3 - 1)
  default:
    let result = GraphLayout.layout(rows: rows([("m", ["a", "z"]), ("a", [])]))
    #expect(result.commits[1].glyphRow == "● │")
  }
}

// MARK: - adapters and shortlog (e1s125, e1s126)

private func e1DailyCounts() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  let lower = GitParsers.parseISODate("2024-03-10T10:00:00+00:00")!
  let upper = GitParsers.parseISODate("2024-03-12T00:00:00+00:00")!
  let inside = GitParsers.parseISODate("2024-03-10T15:00:00+00:00")!
  let commit = Commit(
    sha: "c", date: inside, authorName: "A", authorEmail: "a@x", subject: "s", parents: [],
    insertions: 0, deletions: 0)
  let days = DateValueAdapters.dailyCommitCounts(
    commits: [commit], in: lower...upper, calendar: calendar)
  #expect(days.count == 3)
  #expect((lower...upper).contains(inside))
  // STUI-1340: the filter's lower bound is the start of the first day.
  #expect(days.first?.value == 1)
}

private func e1Shortlog() {
  let tallies = GitParsers.parseShortlog("     3\tA <b> C <c@x>\n")
  #expect(tallies == [AuthorTally(name: "A <b> C", email: "c@x", commits: 3)])
}

// MARK: - fixtures

private func e1RealPath(_ url: URL) -> String {
  guard let resolved = realpath(url.path, nil) else { return url.path }
  defer { free(resolved) }
  return String(cString: resolved)
}

/// A throwaway directory holding one fixture repository, removed by `remove()`.
private struct E1GitFixture {
  let root: URL
  let repo: URL

  init(repositoryName: String = "repo") throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("e1-gitviz-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    repo = root.appendingPathComponent(repositoryName, isDirectory: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  func open() throws -> GitRepo {
    try GitRepo(workingDirectory: repo)
  }

  /// Pins the settings this suite's oracles depend on, in the repository's
  /// own configuration, which outranks a developer's global one.
  func configure() throws {
    for (key, value) in [
      ("core.quotePath", "true"), ("diff.renames", "true"), ("log.showSignature", "false"),
      ("commit.gpgSign", "false"), ("core.precomposeUnicode", "true"),
    ] {
      try git(["config", key, value], in: repo)
    }
  }

  func write(_ text: String, to name: String) throws {
    try write(Data(text.utf8), to: name)
  }

  func write(_ data: Data, to name: String) throws {
    let url = repo.appendingPathComponent(name)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
  }

  func commitAll(
    _ message: String, at date: String, author: String = "Alice", allowEmpty: Bool = false
  ) throws {
    try git(["add", "-A"], in: repo)
    try git(
      ["commit", "-q", "--allow-empty-message"] + (allowEmpty ? ["--allow-empty"] : [])
        + ["-m", message], in: repo, date: date, author: author)
  }

  func gitText(
    _ arguments: [String], in directory: URL? = nil, date: String? = nil, input: Data? = nil
  ) throws -> String {
    let output = try git(arguments, in: directory ?? repo, date: date, input: input)
    var text = String(decoding: output, as: UTF8.self)
    while text.hasSuffix("\n") { text.removeLast() }
    return text
  }

  @discardableResult
  func git(
    _ arguments: [String], in directory: URL? = nil, date: String? = nil,
    author: String = "Alice", input: Data? = nil
  ) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = directory ?? root
    var environment = ProcessInfo.processInfo.environment
    for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY"] {
      environment[key] = nil
    }
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_AUTHOR_NAME"] = author
    environment["GIT_AUTHOR_EMAIL"] = "a@example.com"
    environment["GIT_COMMITTER_NAME"] = "Committer"
    environment["GIT_COMMITTER_EMAIL"] = "c@example.com"
    if let date {
      environment["GIT_AUTHOR_DATE"] = date
      environment["GIT_COMMITTER_DATE"] = date
    }
    process.environment = environment
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    let inputPipe = Pipe()
    process.standardInput = input == nil ? FileHandle.nullDevice : inputPipe
    try process.run()
    if let input {
      inputPipe.fileHandleForWriting.write(input)
      try inputPipe.fileHandleForWriting.close()
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw E1GitFixtureError(arguments: arguments, status: process.terminationStatus)
    }
    return data
  }
}

private struct E1GitFixtureError: Error, CustomStringConvertible {
  var arguments: [String]
  var status: Int32
  var description: String { "fixture git \(arguments) exited \(status)" }
}

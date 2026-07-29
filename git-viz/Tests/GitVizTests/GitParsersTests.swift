import Foundation
import Testing

@testable import GitViz

/// Parser tests, run against bytes recorded from a real `git` by
/// `Scripts/record_git_fixtures.sh`. Focused on the parsers themselves — the
/// argv that produced these bytes is asserted in `GitRepoTests`, and both read
/// the same recordings so they cannot disagree about what git emits.
///
/// The recorded repository deliberately contains a merge (no numstat block), a
/// rename (a three-token NUL entry), a unicode subject, a root commit with no
/// parents, and both tag kinds. See `Fixtures/PROVENANCE.md`.
struct GitParsersTests {
  @Test("parseLogWithNumstat decodes the recorded history newest-first")
  func parsesLogWithNumstat() throws {
    let raw = try loadFixture(named: "log-numstat.txt")
    let commits = GitParsers.parseLogWithNumstat(raw)
    #expect(commits.count == 6)

    #expect(commits[0].subject == "refactor: rename the first file")
    #expect(commits[0].authorName == "Bob Dylan")
    #expect(commits[0].authorEmail == "bob@example.com")
    #expect(commits[0].parents.count == 1)

    #expect(commits.last?.subject == "feat: add the first file")
    #expect(commits.last?.authorName == "Alice Cooper")
    #expect(commits.last?.insertions == 1)
  }

  @Test("a merge commit's subject carries no trailing NUL")
  func mergeSubjectHasNoTrailingNul() throws {
    let raw = try loadFixture(named: "log-numstat.txt")
    let commits = GitParsers.parseLogWithNumstat(raw)

    let merge = try #require(commits.first { $0.parents.count > 1 })

    // A merge emits no numstat block, so under `-z` its subject is followed
    // directly by NUL with no newline. `trimmingCharacters(in:
    // .whitespacesAndNewlines)` does not strip NUL (it is a control
    // character, not whitespace), so the terminator used to survive into the
    // subject.
    #expect(merge.subject == "Merge branch 'side' into main")
    #expect(!merge.subject.unicodeScalars.contains("\u{0}"))
    #expect(merge.insertions == 0)
    #expect(merge.deletions == 0)
  }

  @Test("a rename entry does not corrupt the surrounding numstat block")
  func renameEntryParsesCleanly() throws {
    let raw = try loadFixture(named: "log-numstat.txt")
    let commits = GitParsers.parseLogWithNumstat(raw)

    let rename = try #require(commits.first { $0.subject.hasPrefix("refactor:") })

    // Under `-z` a rename emits `0\t0\0<old>\0<new>\0` — three NUL tokens for
    // one entry. The two bare path tokens carry no tab, so they are skipped
    // rather than counted as deltas.
    #expect(rename.insertions == 0)
    #expect(rename.deletions == 0)
  }

  @Test("a unicode subject survives the record/field split")
  func unicodeSubjectSurvives() throws {
    let raw = try loadFixture(named: "log-numstat.txt")
    let commits = GitParsers.parseLogWithNumstat(raw)

    let unicode = try #require(commits.first { $0.subject.hasPrefix("docs:") })
    #expect(unicode.subject == "docs: café ünïcode subject — em dash and é")
  }

  @Test("the root commit parses with no parents")
  func rootCommitHasNoParents() throws {
    let raw = try loadFixture(named: "log-numstat.txt")
    let commits = GitParsers.parseLogWithNumstat(raw)

    let root = try #require(commits.last)
    #expect(root.parents.isEmpty)
  }

  @Test("parseShortlog returns one tally per row, descending count")
  func parsesShortlog() throws {
    let raw = try loadFixture(named: "shortlog.txt")
    let tallies = GitParsers.parseShortlog(raw)
    #expect(tallies.count == 2)
    #expect(tallies[0].name == "Alice Cooper")
    #expect(tallies[0].email == "alice@example.com")
    #expect(tallies[0].commits == 3)
    #expect(tallies[1].name == "Bob Dylan")
    #expect(tallies[1].commits == 3)
  }

  @Test("parseTags distinguishes annotated from lightweight tags")
  func parsesTags() throws {
    let raw = try loadFixture(named: "for-each-ref-tags.txt")
    let tags = GitParsers.parseTags(raw)
    #expect(tags.count == 2)

    let annotated = try #require(tags.first { $0.isAnnotated })
    let lightweight = try #require(tags.first { !$0.isAnnotated })
    #expect(annotated.name == "v1.0.0")
    #expect(lightweight.name == "v1.1.0")

    // The lightweight tag has an empty taggerdate and falls back to
    // committerdate; without that fallback it would be dropped entirely.
    #expect(lightweight.date == GitParsers.parseISODate("2020-01-06T09:00:00Z"))
  }

  @Test("parseRevListParents records each commit's parents")
  func parsesRevListParents() throws {
    let raw = try loadFixture(named: "rev-list-parents.txt")
    let rows = GitParsers.parseRevListParents(raw)
    #expect(rows.count == 6)

    // Topological order: HEAD first, root last.
    #expect(rows[0].parents.count == 1)
    #expect(rows.last?.parents.isEmpty == true)

    let merge = try #require(rows.first { $0.parents.count == 2 })
    #expect(merge.sha == rows[0].parents[0])
  }

  @Test("parseChangedFileCounts ranks paths by frequency")
  func parsesChangedFileCounts() throws {
    let raw = try loadFixture(named: "name-only.txt")
    let counts = GitParsers.parseChangedFileCounts(raw)
    // a.txt is touched by both of the first two commits.
    #expect(counts.first?.path == "a.txt")
    #expect(counts.first?.changeCount == 2)
    #expect(counts.count == 3)
  }

  @Test("parseInteger handles trailing whitespace")
  func parsesInteger() {
    #expect(GitParsers.parseInteger("42\n") == 42)
    #expect(GitParsers.parseInteger("  7  ") == 7)
    #expect(GitParsers.parseInteger("nope") == nil)
  }

  // MARK: - Helpers

  private func loadFixture(named name: String) throws -> String {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
    else {
      throw FixtureError.notFound(name)
    }
    return try String(contentsOf: url, encoding: .utf8)
  }
}

private enum FixtureError: Error, CustomStringConvertible {
  case notFound(String)
  var description: String {
    switch self {
    case .notFound(let name): "fixture not found: \(name)"
    }
  }
}

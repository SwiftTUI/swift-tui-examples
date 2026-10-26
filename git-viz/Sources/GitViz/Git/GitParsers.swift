import Foundation

/// Parsers for the canned `git` output formats `GitRepo` consumes.
///
/// All parsers are pure functions over `String` so they can be exercised with
/// fixture files without spawning a subprocess.
enum GitParsers {
  // MARK: - log --pretty=format

  /// Format string we always pass to `git log`. Every field is terminated by
  /// NUL (`%x00`, which git expands; an argv cannot carry the byte itself).
  /// NUL is the one byte git never puts in a commit header field or subject,
  /// so a subject or author name holding any other character — RS and US
  /// included — keeps its fields in place.
  static let logFormat = "%H%x00%aI%x00%aN%x00%aE%x00%P%x00%s%x00"

  /// The number of NUL-terminated fields `logFormat` emits per commit.
  private static let logFieldCount = 6

  /// Parses output of `git log -z --pretty=format:<logFormat> --numstat`.
  ///
  /// Under `-z` the output is one NUL-separated token stream. Each commit is
  /// its six header fields, then — only when it has a diff — a newline and
  /// its numstat entries, then an empty token (the NUL git puts between
  /// commits). An entry is `<ins>\t<del>\t<path>\0`, either count `-` for a
  /// binary diff. A rename or copy is `<ins>\t<del>\t\0<old>\0<new>\0`: its
  /// path is empty and the two paths follow as tokens of their own, which
  /// are consumed as paths and never read as counts.
  static func parseLogWithNumstat(_ raw: String) -> [Commit] {
    var tokens = nulTokens(raw)
    var commits: [Commit] = []
    while true {
      // Commit separators. A sha is never empty, so an empty token here is
      // never a header field.
      while tokens.first?.isEmpty == true { tokens.removeFirst() }
      guard tokens.count >= logFieldCount else { break }
      let fields = tokens.prefix(logFieldCount).map(String.init)
      tokens.removeFirst(logFieldCount)
      let (insertions, deletions) = consumeNumstat(&tokens)

      guard let date = parseISODate(fields[1]) else { continue }
      commits.append(
        Commit(
          sha: fields[0],
          date: date,
          authorName: fields[2],
          authorEmail: fields[3],
          subject: fields[5],
          parents: fields[4].split(separator: " ").map(String.init),
          insertions: insertions,
          deletions: deletions
        )
      )
    }
    return commits
  }

  /// Splits `-z` output into its NUL-separated tokens, keeping empty ones.
  ///
  /// NUL is a grapheme of its own (a control character always breaks a
  /// cluster), so splitting on the `Character` never merges a token with
  /// its neighbour.
  private static func nulTokens(_ raw: String) -> ArraySlice<Substring> {
    raw.split(separator: "\u{0}", omittingEmptySubsequences: false)[...]
  }

  /// Consumes one commit's numstat entries from the front of `tokens` and
  /// sums them. Stops at the empty separator token, at the end of the
  /// output, or at a token that is not a numstat entry (the next header).
  private static func consumeNumstat(
    _ tokens: inout ArraySlice<Substring>
  ) -> (insertions: Int, deletions: Int) {
    var insertions = 0
    var deletions = 0
    var isFirstEntry = true
    while let token = tokens.first, !token.isEmpty {
      // The block is introduced by one newline after the header.
      let entry = isFirstEntry && token.first == "\n" ? token.dropFirst() : token
      isFirstEntry = false
      let parts = entry.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
      guard parts.count == 3 else { break }
      tokens.removeFirst()
      if parts[2].isEmpty {
        // A rename or copy: its old and new paths are the next two tokens.
        tokens = tokens.dropFirst(2)
      }
      insertions += Int(parts[0]) ?? 0
      deletions += Int(parts[1]) ?? 0
    }
    return (insertions, deletions)
  }

  /// Reduces a list of commits into per-commit deltas. Drops the parent and
  /// subject fields so downstream code can be pure-numeric.
  static func deltas(from commits: [Commit]) -> [CommitDelta] {
    commits.map { commit in
      CommitDelta(
        sha: commit.sha,
        date: commit.date,
        insertions: commit.insertions,
        deletions: commit.deletions,
        filesChanged: 0  // populated when needed by `--numstat` counts.
      )
    }
  }

  // MARK: - shortlog -s -n -e

  /// Parses `git shortlog -s -n -e` output: `   N\tName <email>`.
  static func parseShortlog(_ raw: String) -> [AuthorTally] {
    var tallies: [AuthorTally] = []
    for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      // Split into "<commits>\t<rest>". `\t` may be replaced by runs of
      // whitespace, so be lenient.
      let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true) {
        $0 == "\t" || $0 == " "
      }
      guard parts.count == 2, let count = Int(parts[0]) else { continue }
      let rest = String(parts[1])
      let (name, email) = parseNameEmail(rest)
      tallies.append(AuthorTally(name: name, email: email, commits: count))
    }
    return tallies
  }

  private static func parseNameEmail(_ rest: String) -> (String, String) {
    if let open = rest.lastIndex(of: "<"),
      let close = rest.lastIndex(of: ">"),
      open < close
    {
      let name = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
      let email = String(rest[rest.index(after: open)..<close])
      return (name, email)
    }
    return (rest.trimmingCharacters(in: .whitespaces), "")
  }

  // MARK: - for-each-ref refs/tags

  /// Record (RS, 0x1E) and field (US, 0x1F) separators of `tagFormat`.
  /// Safe there, unlike in commit text: a ref name cannot contain a control
  /// character (git-check-ref-format(1)), and the other fields are an object
  /// name, dates and an object type.
  static let recordSeparator = "\u{1E}"
  static let fieldSeparator = "\u{1F}"

  /// Format string for `git for-each-ref refs/tags`. Fields are separated by
  /// US, records by RS.
  static let tagFormat =
    "%(refname:short)\u{1F}%(objectname)\u{1F}%(taggerdate:iso-strict)\u{1F}%(committerdate:iso-strict)\u{1F}%(objecttype)\u{1E}"

  /// Parses `git for-each-ref refs/tags --format=<tagFormat>` output.
  ///
  /// Annotated tags carry their own `taggerdate` and `objecttype=tag`;
  /// lightweight tags point straight at the commit, so `taggerdate` is
  /// empty and we fall back to `committerdate`.
  static func parseTags(_ raw: String) -> [Tag] {
    var tags: [Tag] = []
    for record in raw.components(separatedBy: recordSeparator) {
      let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let fields = trimmed.components(separatedBy: fieldSeparator)
      guard fields.count >= 5 else { continue }
      let name = fields[0]
      let sha = fields[1]
      let taggerDate = fields[2]
      let committerDate = fields[3]
      let objectType = fields[4]
      let dateString = taggerDate.isEmpty ? committerDate : taggerDate
      guard let date = parseISODate(dateString) else { continue }
      tags.append(
        Tag(
          name: name,
          sha: sha,
          date: date,
          isAnnotated: objectType == "tag"
        )
      )
    }
    return tags
  }

  // MARK: - log --topo-order (DAG rows)

  /// Format string for the DAG walk: sha, parents and subject, each
  /// NUL-terminated, so topology and subject come from one walk.
  static let graphFormat = "%H%x00%P%x00%s%x00"

  /// Parses `git log --topo-order -z --pretty=format:<graphFormat>` into
  /// `(sha, parents, subject)` rows in walk order.
  ///
  /// Each commit is three NUL-terminated fields (a root commit's parents and
  /// an empty subject are empty fields), then the NUL git puts between
  /// commits.
  static func parseGraphRows(_ raw: String) -> [(sha: String, parents: [String], subject: String)] {
    var tokens = nulTokens(raw)
    var rows: [(sha: String, parents: [String], subject: String)] = []
    while true {
      // Commit separators; a sha is never empty.
      while tokens.first?.isEmpty == true { tokens.removeFirst() }
      guard tokens.count >= 3 else { break }
      let fields = tokens.prefix(3).map(String.init)
      tokens.removeFirst(3)
      rows.append(
        (
          sha: fields[0],
          parents: fields[1].split(separator: " ").map(String.init),
          subject: fields[2]
        )
      )
    }
    return rows
  }

  // MARK: - log --diff-filter=AMD --name-only

  /// Parses `git log -z --diff-filter=AMD --name-only --pretty=format:` and
  /// returns per-file change counts.
  ///
  /// Under `-z` every changed path is NUL-terminated and verbatim — never
  /// C-quoted by `core.quotePath`, never trimmed — and the empty format
  /// prints no header, so every non-empty token is one path. Empty tokens are
  /// the separators git puts between commits.
  static func parseChangedFileCounts(_ raw: String) -> [FileTally] {
    var counts: [String: Int] = [:]
    for token in nulTokens(raw) where !token.isEmpty {
      counts[String(token), default: 0] += 1
    }
    return
      counts
      .map { FileTally(path: $0.key, changeCount: $0.value) }
      .sorted { lhs, rhs in
        if lhs.changeCount != rhs.changeCount {
          return lhs.changeCount > rhs.changeCount
        }
        return lhs.path < rhs.path
      }
  }

  // MARK: - rev-list --count

  /// Parses a single-line integer output (e.g. `git rev-list --count HEAD`).
  static func parseInteger(_ raw: String) -> Int? {
    Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  // MARK: - date helpers

  /// Parses an ISO-8601 timestamp from git (`%aI` / `iso-strict`).
  static func parseISODate(_ value: String) -> Date? {
    if let parsed = isoDateFormatter(formatOptions: [.withInternetDateTime]).date(from: value) {
      return parsed
    }
    // git sometimes emits "1970-01-01T00:00:00+00:00" — accept the common
    // variants without timezone fractional seconds.
    if let parsed = isoDateFormatter(
      formatOptions: [
        .withYear, .withMonth, .withDay,
        .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate,
        .withTimeZone, .withColonSeparatorInTimeZone,
        .withSpaceBetweenDateAndTime,
      ]
    ).date(from: value) {
      return parsed
    }
    return nil
  }

  private static func isoDateFormatter(
    formatOptions: ISO8601DateFormatter.Options
  ) -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = formatOptions
    return formatter
  }
}

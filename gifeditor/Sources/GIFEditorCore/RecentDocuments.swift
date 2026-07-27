import Foundation

/// The most-recently-opened document list, and the small state file it
/// lives in.
///
/// Two things this type deliberately does *not* do.
///
/// It does not know where its file goes. `GIFEditorCore` is the layer a
/// SwiftUI or web port reuses verbatim, so nothing in it reads
/// `NSHomeDirectory`, a `FileManager` convenience directory, or an
/// environment variable. Every entry point takes the URL, and the UI
/// layer owns the `~/.config/halfcell/` convention.
///
/// It does not throw on read. A recents list is a convenience: absent
/// (first launch), truncated (a crash mid-write, which
/// ``AtomicFileWrite`` now prevents but older files may still show),
/// written by a future build, or hand-edited into nonsense all degrade
/// to an empty list. Losing the list costs the user a menu section;
/// refusing to launch over it costs them the app.
///
/// The value is immutable in the usual sense — ``inserting(_:)`` and
/// ``removing(_:)`` return new lists — and every construction routes
/// through ``init(urls:limit:)``, so "de-duplicated, most-recent-first,
/// no longer than `limit`" is an invariant of the type rather than
/// something each call site remembers to re-establish.
public struct RecentDocuments: Hashable, Sendable {
  /// The state file's name, declared here so the writer, the reader,
  /// and the UI that composes it onto the state directory cannot drift.
  public static let defaultFileName = "recents.json"

  /// How many entries to keep. Ten is a menu's worth: long enough to
  /// span a work session, short enough to read without scrolling.
  public static let defaultLimit = 10

  /// The state file's own version, independent of the project format's.
  /// A reader that meets a version it does not know returns an empty
  /// list rather than guessing at unfamiliar fields.
  public static let currentStateVersion = 1

  /// Most-recent first. Every URL is standardized and unique.
  public private(set) var urls: [URL]

  /// The cap this list enforces. Not part of the file — it is the
  /// running build's policy, not the user's data — so a hand-edited
  /// state file cannot talk this build into holding a thousand entries.
  public let limit: Int

  public init(urls: [URL] = [], limit: Int = RecentDocuments.defaultLimit) {
    let cap = max(0, limit)
    self.limit = cap

    // De-duplication runs on the standardized path so `~/art/../art/a`
    // and `/Users/me/art/a` are one entry, not two. Symlinks are
    // deliberately *not* resolved: on macOS that would rewrite the
    // user's `/tmp/…` into `/private/tmp/…` and show them a path they
    // never typed.
    var seen = Set<String>()
    var kept: [URL] = []
    kept.reserveCapacity(Swift.min(urls.count, cap))
    for url in urls where kept.count < cap {
      let standardized = url.standardizedFileURL
      guard seen.insert(standardized.path).inserted else { continue }
      kept.append(standardized)
    }
    self.urls = kept
  }

  public var isEmpty: Bool { urls.isEmpty }
  public var count: Int { urls.count }

  /// Records `url` as the most recent document.
  ///
  /// Re-opening a file *moves* it to the front rather than adding a
  /// second entry: prepending and re-running the initializer drops the
  /// older occurrence, because the initializer keeps the first sighting
  /// of each path and it is now the new one.
  public func inserting(_ url: URL) -> RecentDocuments {
    RecentDocuments(urls: [url] + urls, limit: limit)
  }

  public mutating func insert(_ url: URL) {
    self = inserting(url)
  }

  /// Drops `url`, for when the user asks to forget a document (or the
  /// UI discovers it has gone while trying to open it).
  public func removing(_ url: URL) -> RecentDocuments {
    let key = url.standardizedFileURL.path
    return RecentDocuments(urls: urls.filter { $0.path != key }, limit: limit)
  }

  public mutating func remove(_ url: URL) {
    self = removing(url)
  }

  // MARK: - Storage

  /// Reads the list from `url`, degrading to empty rather than failing.
  ///
  /// `pruningMissingFiles` drops entries whose file is no longer there,
  /// and defaults on. Pruning happens **at load, never at insert**: a
  /// document that was deleted or lives on a volume that is not mounted
  /// at launch is not worth offering, so the list self-heals each
  /// session; but a file that goes briefly unreachable *during* a
  /// session — a network volume, a rebuild that replaces a directory —
  /// must not silently erase the user's history from under them. The
  /// file on disk is untouched by the prune; it only changes when
  /// something calls ``write(to:)`` next.
  public static func load(
    from url: URL,
    limit: Int = RecentDocuments.defaultLimit,
    pruningMissingFiles: Bool = true
  ) -> RecentDocuments {
    guard
      let data = try? Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode(RecentDocuments.self, from: data)
    else {
      return RecentDocuments(urls: [], limit: limit)
    }

    let candidates =
      pruningMissingFiles
      ? decoded.urls.filter { FileManager.default.fileExists(atPath: $0.path) }
      : decoded.urls
    // Re-run the initializer with the caller's cap: the decoder had no
    // way to know it, so this is where the running build's policy is
    // applied to whatever the file happened to hold.
    return RecentDocuments(urls: candidates, limit: limit)
  }

  /// Writes the list to `url`, creating the state directory if needed.
  ///
  /// Throws so a caller *can* report a failure, but losing this file is
  /// cosmetic — the editor's own callers are expected to swallow it.
  public func write(to url: URL) throws {
    let encoder = JSONEncoder()
    // Pretty-printed and sorted: this file is tiny, and being readable
    // (and diffable) in a terminal is worth more than the bytes.
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try AtomicFileWrite.write(try encoder.encode(self), to: url)
  }
}

// MARK: - State-file coding

extension RecentDocuments: Codable {
  private enum CodingKeys: String, CodingKey {
    case version
    case paths
  }

  /// Paths are written as plain strings rather than as `URL`s.
  ///
  /// `URL`'s own `Codable` conformance has spelled itself differently
  /// across Foundation versions (a bare string in some, a
  /// `{relative:, base:}` object in others), and this file is meant to
  /// be readable by a person and portable between a macOS and a Linux
  /// build of the same app. A list of absolute paths is unambiguous in
  /// both directions.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.currentStateVersion, forKey: .version)
    try container.encode(urls.map(\.path), forKey: .paths)
  }

  /// Note that ``limit`` is not in the file, so a value decoded through
  /// `Codable` directly carries ``defaultLimit``; ``load(from:limit:pruningMissingFiles:)``
  /// re-applies the caller's cap. Every failure here is swallowed by
  /// `load`, which is the only intended entry point.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .version)
    guard version == Self.currentStateVersion else {
      throw DecodingError.dataCorruptedError(
        forKey: .version,
        in: container,
        debugDescription:
          "recents state version \(version) is not supported (this build reads version \(Self.currentStateVersion))"
      )
    }
    let paths = try container.decode([String].self, forKey: .paths)
    self.init(
      urls: paths.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) },
      limit: Self.defaultLimit
    )
  }
}

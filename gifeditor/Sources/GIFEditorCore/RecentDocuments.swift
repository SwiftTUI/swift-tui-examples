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

  /// Most-recent first. Every URL is standardized and unique: no two name
  /// the same document (see `identity(of:)`).
  public private(set) var urls: [URL]

  /// The cap this list enforces. Not part of the file — it is the
  /// running build's policy, not the user's data — so a hand-edited
  /// state file cannot talk this build into holding a thousand entries.
  public let limit: Int

  public init(urls: [URL] = [], limit: Int = RecentDocuments.defaultLimit) {
    self.init(collecting: urls, limit: limit)
  }

  /// The one place the invariant is established. It takes any sequence
  /// and stops reading it at the cap, so ``load(from:limit:pruningMissingFiles:)``
  /// can hand it a lazily pruned list and stat only the entries it keeps.
  init(collecting urls: some Sequence<URL>, limit: Int) {
    let cap = max(0, limit)
    self.limit = cap

    // De-duplication runs on the standardized path so `~/art/../art/a`
    // and `/Users/me/art/a` are one entry, not two. Symlinks are
    // deliberately *not* resolved: on macOS that would rewrite the
    // user's `/tmp/…` into `/private/tmp/…` and show them a path they
    // never typed.
    var seen = Set<[UInt8]>()
    var kept: [URL] = []
    for url in urls {
      guard kept.count < cap else { break }
      let standardized = url.standardizedFileURL
      guard seen.insert(Self.identity(of: standardized)).inserted else { continue }
      kept.append(standardized)
    }
    self.urls = kept
  }

  /// What two entries must share to be the same document: the bytes of
  /// the standardized path.
  ///
  /// Not the path `String`. Swift compares strings by canonical
  /// equivalence, so `é` (U+00E9) and `e` + U+0301 are equal strings — but
  /// POSIX file names are byte strings, and on Linux those two spellings
  /// name two different files. Darwin's own filesystems (APFS, HFS+) do
  /// treat canonically equivalent names as one file, so there the bytes
  /// are taken from the canonical decomposition and the two spellings stay
  /// one entry, as they are one document.
  static func identity(of standardized: URL) -> [UInt8] {
    #if canImport(Darwin)
      Array(standardized.path.decomposedStringWithCanonicalMapping.utf8)
    #else
      Array(standardized.path.utf8)
    #endif
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
    let key = Self.identity(of: url.standardizedFileURL)
    return RecentDocuments(urls: urls.filter { Self.identity(of: $0) != key }, limit: limit)
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
      let stored = try? JSONDecoder().decode(StateFile.self, from: data)
    else {
      return RecentDocuments(urls: [], limit: limit)
    }

    // The file's whole list, uncapped: decoding through `RecentDocuments`
    // itself would apply ``defaultLimit`` first, and a caller's larger cap
    // or a prune of the first entries could then never reach the rest.
    // This is where the running build's policy — the caller's cap, after
    // the prune — is applied to whatever the file happened to hold. The
    // prune is lazy, and the initializer stops at the cap, so only the
    // entries it needs are checked on disk.
    let candidates = stored.urls.lazy.filter {
      !pruningMissingFiles || FileManager.default.fileExists(atPath: $0.path)
    }
    return RecentDocuments(collecting: candidates, limit: limit)
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
  fileprivate enum CodingKeys: String, CodingKey {
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
  /// `Codable` directly carries ``defaultLimit``.
  /// ``load(from:limit:pruningMissingFiles:)`` does not decode through
  /// here: it reads the whole list and applies the caller's cap itself.
  public init(from decoder: any Decoder) throws {
    self.init(urls: try StateFile(from: decoder).urls, limit: Self.defaultLimit)
  }
}

/// The state file as written: a version and every path, before any cap.
///
/// Both readers decode through this, so the version check is written once.
private struct StateFile: Decodable {
  let urls: [URL]

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: RecentDocuments.CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .version)
    guard version == RecentDocuments.currentStateVersion else {
      throw DecodingError.dataCorruptedError(
        forKey: .version,
        in: container,
        debugDescription:
          "recents state version \(version) is not supported (this build reads version \(RecentDocuments.currentStateVersion))"
      )
    }
    let paths = try container.decode([String].self, forKey: .paths)
    urls = paths.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) }
  }
}

import Foundation

/// What ``AutosaveStore/recover(from:)`` found: the work itself, plus
/// the two facts a recovery prompt needs to be worth showing — *which*
/// document this was, and *when* it was last touched.
///
/// A prompt that can only say "there is unsaved work" makes the user
/// guess whether it is worth taking; one that says "unsaved changes to
/// `nyan.halfcell` from 14 minutes ago" is a decision they can make.
public struct AutosaveSnapshot: Hashable, Sendable {
  /// Recovered artwork. Filing information remains separate in
  /// ``originalPath`` so document content never acquires write authority.
  public var document: GIFDocument

  /// Where the document lived when the snapshot was taken, or `nil` if
  /// it had never been saved.
  public var originalPath: URL?

  /// When the snapshot was taken, as supplied by the caller.
  public var savedAt: Date

  public init(document: GIFDocument, originalPath: URL?, savedAt: Date) {
    self.document = document
    self.originalPath = originalPath
    self.savedAt = savedAt
  }
}

/// Why recovery reports failures instead of returning `nil` for them.
///
/// "There is no recovery file" and "there is one and it is damaged" are
/// different answers to the user. The first is the normal case and
/// deserves no UI at all; the second means work existed and this build
/// cannot get it back, which the user should hear about rather than
/// have silently swallowed into a clean-looking launch.
public enum AutosaveError: Error, Hashable, Sendable, CustomStringConvertible {
  /// The file exists but could not be read at all — permissions, a
  /// directory where a file was expected, a vanished volume.
  case unreadable(String)

  /// The snapshot envelope declares a version this build does not know.
  case unsupportedSnapshotVersion(found: Int, supported: Int)

  /// The bytes are not the snapshot envelope: truncated by a crash
  /// mid-write, or not this app's file at all.
  case damagedSnapshot(String)

  /// The envelope parsed, but the project inside it did not. Carries
  /// the underlying ``ProjectDecodeError`` so a caller that wants to
  /// distinguish "wrong format version" from "corrupt pixel plane"
  /// still can.
  case damagedDocument(ProjectDecodeError)

  public var description: String {
    switch self {
    case .unreadable(let detail):
      return "recovery file could not be read: \(detail)"
    case .unsupportedSnapshotVersion(let found, let supported):
      return
        "recovery file version \(found) is not supported (this build reads version \(supported))"
    case .damagedSnapshot(let detail):
      return "recovery file is damaged or not a recovery file: \(detail)"
    case .damagedDocument(let error):
      return "recovery file holds a damaged project: \(error.description)"
    }
  }
}

/// Periodic, crash-survivable snapshots of the document being edited.
///
/// The payload is the ``ProjectFile`` envelope, which is the entire
/// point of sequencing the project format ahead of this: autosaving
/// through the GIF encoder would flatten every layer, so the file left
/// behind by a crash would "recover" a document whose layer names,
/// visibility, stacking, and palette order had all been thrown away.
/// Recovery has to be lossless or it is a second data-loss bug wearing
/// a helpful hat.
///
/// The snapshot wraps the project rather than sitting beside it in a
/// sidecar so that the document and the metadata describing it land in
/// **one** atomic write. Two files can disagree after a crash; one
/// cannot.
///
/// Like ``RecentDocuments``, the store takes its path as a parameter
/// and reads no clock: the timestamp is an argument, so a test can
/// assert on an exact instant instead of racing `Date()`.
public enum AutosaveStore {
  /// The recovery file's name. Not `.halfcell`: the bytes are the
  /// snapshot envelope *around* a project, so naming it as a project
  /// would invite `Open` to choke on a file it half-recognizes.
  public static let defaultFileName = "autosave.json"

  /// The snapshot envelope's version, independent of the project
  /// format's. The nested project carries its own.
  public static let currentSnapshotVersion = 1

  /// Writes `document` to `url` as a recovery snapshot stamped with
  /// `timestamp`.
  ///
  /// `timestamp` is required rather than defaulted to `Date()` on
  /// purpose. A default argument is evaluated at the call site, which
  /// reads well but leaves every test at the mercy of the wall clock;
  /// making it explicit costs the one caller that has a clock a single
  /// `Date()` and buys every other caller determinism.
  ///
  public static func snapshot(
    document: GIFDocument,
    originalPath: URL?,
    to url: URL,
    at timestamp: Date
  ) throws {
    let envelope = Envelope(
      snapshotVersion: currentSnapshotVersion,
      savedAt: timestamp.timeIntervalSince1970,
      originalPath: originalPath?.path,
      project: ProjectFile(document: document)
    )
    let encoder = JSONEncoder()
    // Same options the project format writes with, for the same
    // reasons: stable key order, and no `\/` tax on the base64 planes.
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    try AtomicFileWrite.write(try encoder.encode(envelope), to: url)
  }

  /// Reads the recovery snapshot at `url`.
  ///
  /// Returns `nil` when there is nothing to recover — no file, which is
  /// every normal launch — and throws when a file is there but cannot
  /// be turned back into a document.
  public static func recover(from url: URL) throws -> AutosaveSnapshot? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
      // Cleared between the existence check and the read. Nothing to
      // recover is still the honest answer.
      return nil
    } catch {
      throw AutosaveError.unreadable(String(describing: error))
    }

    let envelope: Envelope
    do {
      envelope = try JSONDecoder().decode(Envelope.self, from: data)
    } catch let error as AutosaveError {
      throw error
    } catch let error as ProjectDecodeError {
      throw AutosaveError.damagedDocument(error)
    } catch {
      throw AutosaveError.damagedSnapshot(String(describing: error))
    }

    let originalPath = envelope.originalPath.map { URL(fileURLWithPath: $0) }
    return AutosaveSnapshot(
      document: envelope.project.document,
      originalPath: originalPath,
      savedAt: Date(timeIntervalSince1970: envelope.savedAt)
    )
  }

  /// True when a recovery file is present. Cheap enough to call on a
  /// launch path that has not decided whether to prompt yet.
  public static func snapshotExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  /// Discards the recovery file, for after a successful save (or after
  /// the user declines a recovery offer).
  ///
  /// Idempotent: clearing what is not there succeeds, because "make
  /// sure there is no stale recovery file" is the caller's actual
  /// intent and it should not have to check first.
  public static func clear(at url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
      try FileManager.default.removeItem(at: url)
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
      return
    }
  }

  /// The on-disk shape:
  ///
  /// ```json
  /// {
  ///   "snapshotVersion": 1,
  ///   "savedAt": 1753574400.0,
  ///   "originalPath": "/Users/…/nyan.halfcell",
  ///   "project": { "formatVersion": 1, "document": { … } }
  /// }
  /// ```
  ///
  /// `savedAt` is seconds since 1970 rather than `Date`'s own `Codable`
  /// spelling (seconds since 2001) so the number means what a reader
  /// looking at the file assumes it means.
  private struct Envelope: Codable {
    let snapshotVersion: Int
    let savedAt: TimeInterval
    let originalPath: String?
    let project: ProjectFile

    init(snapshotVersion: Int, savedAt: TimeInterval, originalPath: String?, project: ProjectFile) {
      self.snapshotVersion = snapshotVersion
      self.savedAt = savedAt
      self.originalPath = originalPath
      self.project = project
    }

    /// Version first, deliberately, matching ``ProjectFile``: a file
    /// from a future build is refused before any of its other fields
    /// are read under today's rules.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let version = try container.decode(Int.self, forKey: .snapshotVersion)
      guard version == AutosaveStore.currentSnapshotVersion else {
        throw AutosaveError.unsupportedSnapshotVersion(
          found: version,
          supported: AutosaveStore.currentSnapshotVersion
        )
      }
      self.snapshotVersion = version
      self.savedAt = try container.decode(TimeInterval.self, forKey: .savedAt)
      self.originalPath = try container.decodeIfPresent(String.self, forKey: .originalPath)
      self.project = try container.decode(ProjectFile.self, forKey: .project)
    }
  }
}

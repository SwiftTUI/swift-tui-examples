import Foundation

/// The one way this module puts bytes on disk.
///
/// Both state files it owns — the recents list and the autosave
/// recovery snapshot — are written *while* the thing they describe is
/// still in use, and the autosave one is written specifically so that a
/// process which dies unexpectedly leaves something recoverable behind.
/// A plain `write(to:)` truncates the destination and then streams into
/// it, so the window where the file exists but is short is exactly the
/// window autosave exists to cover: the recovery file that survives the
/// crash is the truncated one, and it fails to decode.
///
/// `.atomic` writes a sibling temporary and renames it over the target,
/// so a reader — this build on the next launch, or a person with `cat` —
/// sees either the whole previous file or the whole new one, never a
/// prefix of either.
///
/// The directory is created first because the caller supplies a full
/// file URL inside a state directory (`~/.config/halfcell/`) that does
/// not exist until something writes into it, and "first launch fails to
/// remember anything" is not a good first launch.
enum AtomicFileWrite {
  static func write(_ data: Data, to url: URL) throws {
    let directory = url.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    }
    try data.write(to: url, options: .atomic)
  }
}

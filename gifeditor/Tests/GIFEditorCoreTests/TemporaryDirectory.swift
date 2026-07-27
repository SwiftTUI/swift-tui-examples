import Foundation

/// Runs `body` against a fresh, uniquely named directory under the
/// system temporary directory, and removes it afterwards.
///
/// Filesystem tests write real files — that is the point of them, since
/// the failure modes being covered (truncated state file, missing
/// entry, atomic overwrite) only exist on a real filesystem. They must
/// not write into the package directory: a test that leaves debris
/// beside `Sources/` shows up as a dirty working tree, and one that
/// reuses a fixed path races the next test to run.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  return try body(directory)
}

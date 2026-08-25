import Foundation
@_spi(Testing) import SwiftTUI

/// Writes the frames a runtime test recorded as a plain-text film strip:
/// one block per presented frame with its timestamp and the section's
/// `state:` line in the header, human-reviewable in an editor or a PR diff
/// with no terminal involved.
///
/// Strips are only written when `GALLERY_FRAME_STRIP_DIR` names a directory
/// (created on demand); otherwise ``write(name:host:stateNeedle:)`` is a
/// no-op, so the runtime suites cost nothing extra by default.
enum GalleryFrameStrip {
  static let directoryVariable = "GALLERY_FRAME_STRIP_DIR"

  /// The directory strips go to, or `nil` when the variable is unset.
  static var directory: URL? {
    guard let path = ProcessInfo.processInfo.environment[directoryVariable], !path.isEmpty
    else {
      return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  struct Frame {
    let elapsed: Duration
    let surface: RasterSurface
  }

  /// The strip text for `frames`. `stateNeedle` picks the section's `state:`
  /// line out of each frame (the first line containing it) for the header.
  static func render(name: String, frames: [Frame], stateNeedle: String) -> String {
    var text = "# gallery frame strip: \(name)\n"
    let size = frames.first?.surface.size
    let sizeText = size.map { "\($0.width)x\($0.height)" } ?? "empty"
    text += "# frames: \(frames.count)  size: \(sizeText)  state line: \"\(stateNeedle)\"\n"
    for (index, frame) in frames.enumerated() {
      let seconds = frame.elapsed.totalSeconds
      let state =
        frame.surface.lines.first { $0.contains(stateNeedle) }.map(trimmingTrailingSpaces)
        ?? "(no \(stateNeedle) line)"
      text += "=== frame \(index)  t=+\(String(format: "%.3f", seconds))s  \(state)\n"
      for line in frame.surface.lines {
        text += trimmingTrailingSpaces(line) + "\n"
      }
    }
    return text
  }

  /// Writes `host`'s recording as `<name>.txt` under ``directory`` and
  /// returns the file, or returns `nil` without writing when the variable is
  /// unset.
  @discardableResult
  static func write(
    name: String,
    host: AnimationRegressionRecordingHost,
    stateNeedle: String
  ) throws -> URL? {
    guard let directory else {
      return nil
    }
    let frames = zip(host.presentedAt, host.surfaces).map { elapsed, surface in
      Frame(elapsed: elapsed, surface: surface)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("\(name).txt")
    try render(name: name, frames: frames, stateNeedle: stateNeedle)
      .write(to: file, atomically: true, encoding: .utf8)
    return file
  }

  static func trimmingTrailingSpaces(_ line: String) -> String {
    String(line.reversed().drop(while: { $0 == " " }).reversed())
  }
}

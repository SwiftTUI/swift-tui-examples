import Foundation
import GIFEditorCore

/// Everything `info` reports, independent of how it is rendered.
///
/// The type is the seam. `info` has two output modes that must never
/// disagree — a human-readable block and `--json` — so both are functions
/// of this one value rather than two independent walks over the document,
/// and the JSON schema is something that can be read off a declaration
/// instead of reconstructed from string interpolation.
public struct FileInfoReport: Hashable, Sendable, Codable {

  /// One frame's line in the report.
  ///
  /// `delayMilliseconds` is redundant with `delayCentiseconds` and is
  /// written for the same reason ``SpritesheetMetadata`` writes it: every
  /// consumer's animation API is in milliseconds, and a ×10 slip is
  /// exactly the bug that survives review.
  public struct FrameInfo: Hashable, Sendable, Codable {
    public let index: Int
    public let delayCentiseconds: Int
    public let delayMilliseconds: Int
    /// Always 1 for a GIF — the importer flattens each frame to one
    /// layer — and the authored stack depth for a project. Reported for
    /// both so a script does not have to branch on `format` to read it.
    public let layerCount: Int
  }

  public let path: String
  public let format: HeadlessInput.FileKind
  public let byteCount: Int
  public let canvas: PixelSize
  public let frameCount: Int
  /// Zero means forever, matching ``GIFDocument/loopCount``. For a GIF
  /// with no `NETSCAPE2.0` block this is `1`: the format defines such an
  /// animation as playing through once.
  public let loopCount: Int
  /// How many colors the document's palette actually uses. For a GIF
  /// this is the palette *after* import, which is the union of every
  /// composited frame median-cut down to at most 255 opaque entries plus
  /// the reserved transparent slot — not a count of the color tables the
  /// file happens to carry.
  public let paletteColorCount: Int
  /// The project envelope's `formatVersion`, absent for a GIF.
  public let formatVersion: Int?
  public let frames: [FrameInfo]
}

/// The `info` subcommand's logic, with no argument parsing and no I/O in
/// it: bytes in, a report out, and two renderers over the report.
public enum HeadlessInfo {

  /// Builds the report for an already-loaded file.
  public static func report(for loaded: HeadlessInput.Loaded) -> FileInfoReport {
    let document = loaded.document
    return FileInfoReport(
      path: loaded.url.path,
      format: loaded.kind,
      byteCount: loaded.byteCount,
      canvas: document.size,
      frameCount: document.frames.count,
      loopCount: document.loopCount,
      paletteColorCount: document.palette.usedColors.count,
      // A project that decoded at all carries the version this build
      // reads: `ProjectFile.init(from:)` refuses every other one before
      // a single field is interpreted.
      formatVersion: loaded.kind == .project ? ProjectFile.currentFormatVersion : nil,
      frames: document.frames.enumerated().map { index, frame in
        FileInfoReport.FrameInfo(
          index: index,
          delayCentiseconds: frame.delayCentiseconds,
          delayMilliseconds: frame.delayCentiseconds * 10,
          layerCount: frame.layers.count
        )
      }
    )
  }

  /// Reads, decodes and reports in one step — what the subcommand calls.
  public static func report(contentsOf url: URL) throws(HeadlessError) -> FileInfoReport {
    report(for: try HeadlessInput.load(contentsOf: url))
  }

  /// The human-readable rendering: a labelled block, then one line per
  /// frame.
  ///
  /// Columns are padded rather than tab-separated because the frame table
  /// is the part someone reads down, and a tab stop that moves with the
  /// widest delay is exactly what makes a 60-frame listing unreadable.
  public static func text(for report: FileInfoReport) -> String {
    var lines: [String] = [URL(fileURLWithPath: report.path).lastPathComponent]
    lines.append(field("format", report.format == .gif ? "GIF" : "halfcell project"))
    if let formatVersion = report.formatVersion {
      lines.append(field("version", String(formatVersion)))
    }
    lines.append(field("bytes", String(report.byteCount)))
    lines.append(field("canvas", "\(report.canvas.width)x\(report.canvas.height)"))
    lines.append(field("frames", String(report.frameCount)))
    lines.append(field("loop", loopDescription(report.loopCount)))
    lines.append(field("palette", "\(report.paletteColorCount) colors"))

    lines.append("")
    lines.append("  " + row(index: "#", delay: "delay", layers: "layers"))
    for frame in report.frames {
      lines.append(
        "  "
          + row(
            index: String(frame.index),
            delay: "\(frame.delayMilliseconds) ms",
            layers: String(frame.layerCount)
          )
      )
    }
    return lines.joined(separator: "\n")
  }

  /// How a loop count reads in prose. Zero is the document model's
  /// "forever", and the two finite cases differ by a plural that a
  /// generated report should not get wrong.
  static func loopDescription(_ loopCount: Int) -> String {
    switch loopCount {
    case 0:
      return "forever"
    case 1:
      return "once"
    default:
      return "\(loopCount) times"
    }
  }

  private static func field(_ label: String, _ value: String) -> String {
    "  " + label.padding(toLength: 10, withPad: " ", startingAt: 0) + value
  }

  private static func row(index: String, delay: String, layers: String) -> String {
    HeadlessText.rightAligned(index, width: 4)
      + "  " + HeadlessText.rightAligned(delay, width: 9)
      + "  " + HeadlessText.rightAligned(layers, width: 6)
  }
}

/// Formatting shared by the subcommands' human-readable output.
enum HeadlessText {
  static func rightAligned(_ text: String, width: Int) -> String {
    guard text.count < width else { return text }
    return String(repeating: " ", count: width - text.count) + text
  }
}

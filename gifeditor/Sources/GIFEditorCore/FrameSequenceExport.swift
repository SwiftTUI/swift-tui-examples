import Foundation

/// One PNG per frame — the export a pipeline wants when the frames go
/// into a texture packer, a diff, or a version-controlled asset folder
/// rather than into a sheet.
///
/// The only decision here that outlives the call is the *file name*, and
/// it is a decision: names are zero-padded to a fixed width so a
/// lexicographic listing — `ls`, a Finder sort, a glob handed to
/// `ffmpeg`, a texture packer's directory scan — is also the frame order.
/// `frame-9.png` sorting after `frame-10.png` is the classic way a
/// 12-frame walk cycle imports out of order, and it is silent.
public enum FrameSequenceExport {
  /// Minimum digits in a frame's index. Three is the smallest width that
  /// covers every animation anyone would author by hand, and it keeps the
  /// common case reading as `walk-000.png` rather than `walk-0.png`.
  /// Longer documents widen past it rather than truncating.
  public static let minimumIndexDigits = 3

  /// Encodes every frame as a standalone still PNG, in frame order.
  public static func pngs(
    document: GIFDocument,
    flattenedColors: [[EditorColor?]]? = nil
  ) -> [[UInt8]] {
    let frames =
      flattenedColors
      ?? (0..<document.frames.count).map { document.flattenedColors(frameIndex: $0) }
    precondition(frames.count == document.frames.count, "one color plane per frame")
    return frames.map { PNGEncoder.encode(colors: $0, size: document.size) }
  }

  /// `<baseName>-<zero-padded index>.png`.
  ///
  /// The padding width comes from `frameCount`, not from the index, so
  /// every name in one export is the same length.
  public static func fileName(baseName: String, frameIndex: Int, frameCount: Int) -> String {
    let width = max(minimumIndexDigits, String(max(0, frameCount - 1)).count)
    var digits = String(frameIndex)
    if digits.count < width {
      digits = String(repeating: "0", count: width - digits.count) + digits
    }
    return "\(baseName)-\(digits).png"
  }

  /// Writes one PNG per frame into `directory`, creating it if needed,
  /// and returns the written URLs in frame order.
  @discardableResult
  public static func write(
    document: GIFDocument,
    toDirectory directory: URL,
    baseName: String,
    flattenedColors: [[EditorColor?]]? = nil
  ) throws -> [URL] {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let encoded = pngs(document: document, flattenedColors: flattenedColors)
    return try encoded.enumerated().map { index, bytes in
      let url = directory.appendingPathComponent(
        fileName(baseName: baseName, frameIndex: index, frameCount: encoded.count)
      )
      try Data(bytes).write(to: url)
      return url
    }
  }
}

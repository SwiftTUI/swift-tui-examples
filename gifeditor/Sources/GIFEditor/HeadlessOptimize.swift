import Foundation
import GIFEditorCore

/// How a re-encode lays frames out inside the emitted GIF, as a value the
/// command line can spell.
///
/// ``GIFEncoder/FrameCoding`` is not `ExpressibleByArgument` and giving it
/// that conformance from here would be a retroactive conformance on a type
/// this module does not own. A small mapped enum also lets the flag use the
/// words a user would type (`delta`, `full`) rather than the API's.
public enum FrameCodingOption: String, Hashable, Sendable, Codable, CaseIterable {
  /// The encoder default: frames after the first carry only the rectangle
  /// that changed.
  case delta
  /// Every frame full-canvas, carrying the authored disposal sequence.
  case full

  public var frameCoding: GIFEncoder.FrameCoding {
    switch self {
    case .delta:
      return .deltaFrames
    case .full:
      return .fullFrames
    }
  }
}

/// What `optimize` did, in numbers.
///
/// `savedByteCount` and `savedPercent` are stored rather than computed so
/// they appear in `--json` alongside the two counts they are derived from.
/// A script that has to recompute a percentage the tool already printed
/// will eventually recompute it differently.
public struct OptimizeReport: Hashable, Sendable, Codable {
  public let inputByteCount: Int
  public let outputByteCount: Int
  public let frameCoding: FrameCodingOption
  public let frameCount: Int
  /// Negative when the re-encode grew the file. Delta coding is not
  /// unconditionally smaller: a short animation whose bytes are mostly
  /// palette pays for the extra image descriptors without a run of
  /// unchanged pixels long enough to earn them back.
  public let savedByteCount: Int
  /// `savedByteCount` as a percentage of the input, negative when the
  /// file grew, zero for an empty input.
  public let savedPercent: Double

  public init(
    inputByteCount: Int,
    outputByteCount: Int,
    frameCoding: FrameCodingOption,
    frameCount: Int
  ) {
    self.inputByteCount = inputByteCount
    self.outputByteCount = outputByteCount
    self.frameCoding = frameCoding
    self.frameCount = frameCount
    self.savedByteCount = inputByteCount - outputByteCount
    self.savedPercent =
      inputByteCount > 0
      ? Double(inputByteCount - outputByteCount) / Double(inputByteCount) * 100
      : 0
  }
}

/// The `optimize` subcommand's logic: decode a GIF, re-encode it, and say
/// what that cost or saved.
///
/// The round trip is deliberately not a byte-level rewrite. It goes through
/// the same importer the editor uses and back out through the same encoder,
/// so the output is whatever this build would have written for that
/// animation — which is the only claim the tool can honestly make about it.
/// Both codings are render-identical to each other by construction (see
/// ``GIFEncoder``), so the choice is purely about size.
public enum HeadlessOptimize {

  /// Re-encodes already-read GIF bytes.
  ///
  /// Rejects a project file: `optimize` reports a percentage saved, and
  /// comparing a JSON envelope's size against a GIF's would produce a
  /// number that looks like a saving and means nothing. `export` is the
  /// verb for turning a project into something else.
  public static func optimize(
    data: Data,
    url: URL,
    frameCoding: FrameCodingOption = .delta,
    dithering: Quantizer.Dithering = .none
  ) throws(HeadlessError) -> (bytes: [UInt8], report: OptimizeReport) {
    let loaded = try HeadlessInput.decode(data: data, url: url, dithering: dithering)
    guard loaded.kind == .gif else {
      throw .wrongFormat(url, expected: "a GIF", found: loaded.kind.article)
    }

    let document = loaded.document
    let bytes: [UInt8]
    do {
      bytes = try GIFEncoder.encode(document: document, frameCoding: frameCoding.frameCoding)
    } catch {
      throw .operationFailed(
        detail: "\(url.lastPathComponent): re-encode failed — \(String(describing: error))"
      )
    }

    return (
      bytes,
      OptimizeReport(
        inputByteCount: data.count,
        outputByteCount: bytes.count,
        frameCoding: frameCoding,
        frameCount: document.frames.count
      )
    )
  }

  /// Reads, re-encodes and writes — what the subcommand calls.
  @discardableResult
  public static func run(
    input: URL,
    output: URL,
    frameCoding: FrameCodingOption = .delta,
    dithering: Quantizer.Dithering = .none
  ) throws(HeadlessError) -> OptimizeReport {
    let data = try HeadlessInput.read(contentsOf: input)
    let (bytes, report) = try optimize(
      data: data,
      url: input,
      frameCoding: frameCoding,
      dithering: dithering
    )
    try HeadlessWrite.write(bytes: bytes, to: output)
    return report
  }

  /// The human-readable rendering.
  public static func text(for report: OptimizeReport, input: URL, output: URL) -> String {
    let change: String
    if report.savedByteCount > 0 {
      change = "saved \(report.savedByteCount) bytes, \(percent(report.savedPercent))"
    } else if report.savedByteCount < 0 {
      change = "grew by \(-report.savedByteCount) bytes, \(percent(-report.savedPercent))"
    } else {
      change = "no change"
    }
    return """
      \(input.lastPathComponent) -> \(output.lastPathComponent)
        coding    \(report.frameCoding.rawValue) frames
        frames    \(report.frameCount)
        before    \(report.inputByteCount) bytes
        after     \(report.outputByteCount) bytes
        result    \(change)
      """
  }

  /// One decimal place, and no locale: this number is as likely to be
  /// parsed by the next command in a pipeline as read by a person.
  static func percent(_ value: Double) -> String {
    String(format: "%.1f%%", value)
  }
}

/// Writing bytes where a subcommand was told to put them.
enum HeadlessWrite {
  /// Creates the destination's parent directory if it does not exist, then
  /// writes atomically — a subcommand that is interrupted must not leave a
  /// half-file where the caller expects a complete one.
  static func write(bytes: [UInt8], to url: URL) throws(HeadlessError) {
    do {
      let directory = url.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data(bytes).write(to: url, options: .atomic)
    } catch {
      throw .operationFailed(
        detail: "could not write \(url.path) — \(String(describing: error))"
      )
    }
  }

  /// The size of a file just written, so a report states what landed on
  /// disk rather than what was handed to the writer.
  static func byteCount(of url: URL) throws(HeadlessError) -> Int {
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      guard let size = values.fileSize else {
        throw HeadlessError.operationFailed(detail: "could not size \(url.path)")
      }
      return size
    } catch let error as HeadlessError {
      throw error
    } catch {
      throw .operationFailed(detail: "could not size \(url.path) — \(String(describing: error))")
    }
  }
}

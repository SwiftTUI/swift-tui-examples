import Foundation

@testable import GIFEditorCore

/// Independent decoders for the artifacts ``PNGEncoder``, ``APNGEncoder``
/// and ``SpritesheetExport`` produce.
///
/// A hand-rolled PNG writer that is only ever read back by its own
/// author's code proves nothing: the two halves agree on whatever the
/// author got wrong. Every export test therefore asserts against
/// software this package did not write —
///
/// - **Pillow** (`python3` + `PIL`), which gives exact RGBA pixel data
///   and, for APNG, the frame count and per-frame delays as a real
///   animation decoder sees them;
/// - **ImageMagick** (`magick`), a second, unrelated implementation, used
///   for format/geometry and for a second pixel opinion.
///
/// Both were checked to be *strict* before being trusted here: each one
/// rejects a PNG whose IDAT bytes have been flipped, whose stream has
/// been truncated, and — the case that matters most for a stored-block
/// writer — whose zlib Adler-32 disagrees with the data it covers.
/// `magick identify` alone does **not** qualify: it reads the header and
/// exits 0 on a file whose pixels are corrupt, which is why the pixel
/// path here decodes through `magick file -depth 8 RGBA:-` instead.
///
/// **Availability is decided once, out loud.** ``isAvailable`` is what
/// gates `ExportExternalDecoderTests`, so a machine without the tools
/// reports that suite as skipped *with the reason printed* rather than
/// failing it or — the thing this package was recently bitten by —
/// silently passing it. Inside the suite there is no second soft path: a
/// tool that disappears between the gate and the call throws
/// ``ToolUnavailable``, and a tool that misbehaves throws
/// ``ToolFailure``. Never add a `guard … else { return }` here; that is
/// the exact pattern that turned two suites into no-ops while still
/// reporting green.
enum ExternalImage {
  /// True when both decoders are usable: `magick` on `PATH`, and a
  /// `python3` that can `import PIL`.
  ///
  /// Computed once per process — it costs two subprocesses — and read by
  /// the `.enabled(if:)` trait on the tier-3 suite. Pillow is probed by
  /// actually importing it rather than by looking for the interpreter,
  /// because a `python3` without Pillow is the more common shape of
  /// "not available" and it fails much later and less clearly.
  static let isAvailable: Bool = {
    let scratch = FileManager.default.temporaryDirectory
    guard (try? locate("magick", hint: "")) != nil else { return false }
    guard let python = try? locate("python3", hint: "") else { return false }
    let probe = try? run(python, ["-c", "import PIL"], scratch: scratch)
    return probe?.status == 0
  }()

  /// One frame as an external decoder sees it.
  struct DecodedFrame {
    let rgba: [UInt8]
    /// Milliseconds, as the decoder computed them from the file's own
    /// delay fraction — not as this package believes it wrote them.
    let durationMilliseconds: Double
  }

  /// A whole image (still or animated) as an external decoder sees it.
  struct DecodedImage {
    let format: String
    let size: PixelSize
    /// APNG `num_plays`, when the decoder reports one. Zero is "forever".
    let loopCount: Int?
    let frames: [DecodedFrame]
  }

  /// What `magick identify` reports without decoding pixels.
  struct Identity {
    let format: String
    let size: PixelSize
    /// e.g. `srgba` — the presence of the alpha channel.
    let channels: String
    /// Images in the sequence, as this decoder counts them.
    let imageCount: Int
  }

  struct ToolUnavailable: Error, CustomStringConvertible {
    let tool: String
    let hint: String

    var description: String {
      """
      required external decoder '\(tool)' is not on PATH. \(hint)
      These tests verify hand-written PNG/APNG bytes against an independent \
      decoder; without one they would assert nothing, so a missing tool is a \
      failure rather than a skip.
      """
    }
  }

  struct ToolFailure: Error, CustomStringConvertible {
    let tool: String
    let arguments: [String]
    let status: Int32
    let standardError: String

    var description: String {
      "\(tool) \(arguments.joined(separator: " ")) exited \(status): \(standardError)"
    }
  }

  // MARK: - Pillow

  /// Decodes with Pillow, writing each frame's RGBA bytes into `scratch`
  /// and reading them back, so nothing large has to survive a pipe.
  static func pillow(_ url: URL, scratch: URL) throws -> DecodedImage {
    let python = try locate("python3", hint: "Install Python 3 with Pillow (`pip install pillow`).")
    let frameDirectory = scratch.appendingPathComponent("pillow-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true)

    let output = try checkedRun(
      python,
      [
        "-c", pillowScript, url.path, frameDirectory.path,
      ],
      scratch: scratch
    )

    guard
      let report = try JSONSerialization.jsonObject(with: output) as? [String: Any],
      let format = report["format"] as? String,
      let width = report["width"] as? Int,
      let height = report["height"] as? Int,
      let frames = report["frames"] as? [[String: Any]]
    else {
      throw ToolFailure(
        tool: "python3",
        arguments: ["<pillow probe>"],
        status: 0,
        standardError: "unreadable probe report: \(String(decoding: output, as: UTF8.self))"
      )
    }

    let decodedFrames = try frames.map { frame -> DecodedFrame in
      guard let path = frame["path"] as? String else {
        throw ToolFailure(
          tool: "python3",
          arguments: ["<pillow probe>"],
          status: 0,
          standardError: "probe report frame has no path"
        )
      }
      let duration = (frame["duration"] as? Double) ?? Double(frame["duration"] as? Int ?? 0)
      return DecodedFrame(
        rgba: [UInt8](try Data(contentsOf: URL(fileURLWithPath: path))),
        durationMilliseconds: duration
      )
    }

    return DecodedImage(
      format: format,
      size: PixelSize(width: width, height: height),
      loopCount: report["loop"] as? Int,
      frames: decodedFrames
    )
  }

  /// Inflates a raw zlib stream with Python's `zlib`, which is the
  /// reference implementation the format is specified against. Used to
  /// check the stored-block framing directly, without a PNG wrapped
  /// around it.
  static func inflate(_ stream: [UInt8], scratch: URL) throws -> [UInt8] {
    let python = try locate("python3", hint: "Install Python 3.")
    let input = scratch.appendingPathComponent("stream-\(UUID().uuidString).zlib")
    let output = scratch.appendingPathComponent("stream-\(UUID().uuidString).raw")
    try Data(stream).write(to: input)
    _ = try checkedRun(
      python,
      ["-c", inflateScript, input.path, output.path],
      scratch: scratch
    )
    return [UInt8](try Data(contentsOf: output))
  }

  // MARK: - ImageMagick

  static func magickIdentify(_ url: URL, scratch: URL) throws -> Identity {
    let magick = try locate("magick", hint: "Install ImageMagick (`brew install imagemagick`).")
    // `%[channels]` expands to more than one whitespace-separated token
    // (`srgba 4.0`), so it goes last and the fixed fields stay
    // positional.
    let output = try checkedRun(
      magick,
      ["identify", "-format", "%m %w %h %n %[channels]\\n", url.path],
      scratch: scratch
    )
    let firstLine =
      String(decoding: output, as: UTF8.self)
      .split(separator: "\n", omittingEmptySubsequences: true)
      .first
      .map(String.init) ?? ""
    let fields = firstLine.split(separator: " ").map(String.init)
    guard
      fields.count >= 5,
      let width = Int(fields[1]),
      let height = Int(fields[2]),
      let imageCount = Int(fields[3])
    else {
      throw ToolFailure(
        tool: "magick",
        arguments: ["identify"],
        status: 0,
        standardError: "unparsable identify output: \(firstLine)"
      )
    }
    return Identity(
      format: fields[0],
      size: PixelSize(width: width, height: height),
      channels: fields[4...].joined(separator: " "),
      imageCount: imageCount
    )
  }

  /// Full RGBA decode through ImageMagick. Unlike `identify`, this walks
  /// the whole IDAT, so a bad stored-block length, a wrong complement, or
  /// a wrong Adler-32 all surface here as a non-zero exit.
  static func magickRGBA(_ url: URL, imageIndex: Int? = nil, scratch: URL) throws -> [UInt8] {
    let magick = try locate("magick", hint: "Install ImageMagick (`brew install imagemagick`).")
    let source = imageIndex.map { "\(url.path)[\($0)]" } ?? url.path
    let output = try checkedRun(
      magick,
      [source, "-depth", "8", "RGBA:-"],
      scratch: scratch
    )
    return [UInt8](output)
  }

  // MARK: - Process plumbing

  /// Resolves a tool on `PATH`, or throws ``ToolUnavailable``.
  private static func locate(_ tool: String, hint: String) throws -> String {
    let result = try run(
      "/bin/sh",
      ["-c", "command -v \(tool)"],
      scratch: FileManager.default.temporaryDirectory
    )
    let path = String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard result.status == 0, !path.isEmpty else {
      throw ToolUnavailable(tool: tool, hint: hint)
    }
    return path
  }

  private static func checkedRun(
    _ executable: String,
    _ arguments: [String],
    scratch: URL
  ) throws -> Data {
    let result = try run(executable, arguments, scratch: scratch)
    guard result.status == 0 else {
      throw ToolFailure(
        tool: executable,
        arguments: arguments,
        status: result.status,
        standardError: String(decoding: result.standardError, as: UTF8.self)
      )
    }
    return result.standardOutput
  }

  /// Runs a subprocess with both streams redirected to files rather than
  /// pipes. A raw RGBA dump of a 200x100 image is 80 KB — more than a
  /// pipe buffer holds — and draining one pipe while the child blocks
  /// writing to the other is the classic way a test harness hangs instead
  /// of failing.
  private static func run(
    _ executable: String,
    _ arguments: [String],
    scratch: URL
  ) throws -> (status: Int32, standardOutput: Data, standardError: Data) {
    let identifier = UUID().uuidString
    let outURL = scratch.appendingPathComponent("stdout-\(identifier)")
    let errURL = scratch.appendingPathComponent("stderr-\(identifier)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    FileManager.default.createFile(atPath: errURL.path, contents: nil)
    let outHandle = try FileHandle(forWritingTo: outURL)
    let errHandle = try FileHandle(forWritingTo: errURL)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = outHandle
    process.standardError = errHandle
    try process.run()
    process.waitUntilExit()
    try? outHandle.close()
    try? errHandle.close()

    defer {
      try? FileManager.default.removeItem(at: outURL)
      try? FileManager.default.removeItem(at: errURL)
    }
    return (
      process.terminationStatus,
      try Data(contentsOf: outURL),
      try Data(contentsOf: errURL)
    )
  }

  /// Dumps every frame's RGBA to a file and reports geometry, loop count
  /// and per-frame duration as JSON. `convert("RGBA")` forces a full
  /// decode, so a corrupt stream raises here rather than passing.
  private static let pillowScript = """
    import json, os, sys
    from PIL import Image, ImageSequence

    source, destination = sys.argv[1], sys.argv[2]
    image = Image.open(source)
    report = {
        "format": image.format,
        "width": image.width,
        "height": image.height,
        "loop": image.info.get("loop"),
        "frames": [],
    }
    for index, frame in enumerate(ImageSequence.Iterator(image)):
        rgba = frame.convert("RGBA")
        path = os.path.join(destination, "frame-%04d.rgba" % index)
        with open(path, "wb") as handle:
            handle.write(rgba.tobytes())
        report["frames"].append({
            "path": path,
            "duration": float(frame.info.get("duration", 0)),
        })
    print(json.dumps(report))
    """

  private static let inflateScript = """
    import sys, zlib

    source, destination = sys.argv[1], sys.argv[2]
    with open(source, "rb") as handle:
        raw = zlib.decompress(handle.read())
    with open(destination, "wb") as handle:
        handle.write(raw)
    """
}

// MARK: - Expected pixels

/// The RGBA bytes a frame *should* decode to, derived from the document
/// model rather than from ``PNGRaster``.
///
/// Spelled out here on purpose: comparing the encoder's output against
/// the encoder's own raster helper would only prove the two agree.
func expectedRGBA(_ document: GIFDocument, frameIndex: Int) -> [UInt8] {
  var bytes = [UInt8]()
  bytes.reserveCapacity(document.size.area * 4)
  for color in document.flattenedColors(frameIndex: frameIndex) {
    guard let color, color.alpha > 0 else {
      bytes += [0, 0, 0, 0]
      continue
    }
    bytes += [color.red, color.green, color.blue, color.alpha]
  }
  return bytes
}

/// A document whose frames are solid slabs of a single palette slot —
/// enough structure to tell frames apart in a decoded sheet or
/// animation, little enough to write the expectation by hand.
func slabDocument(
  size: PixelSize,
  slots: [PaletteIndex?],
  delays: [Int]? = nil,
  loopCount: Int = 0
) -> GIFDocument {
  let palette = ColorPalette(
    colors: [
      .transparent,
      EditorColor(rgbHex: 0xFF0000),
      EditorColor(rgbHex: 0x00FF00),
      EditorColor(rgbHex: 0x0000FF),
      EditorColor(red: 40, green: 60, blue: 80, alpha: 128),
    ]
  )
  let frames = slots.enumerated().map { index, slot in
    EditorFrame(
      layers: [
        EditorLayer(
          name: "Layer \(index + 1)",
          pixels: PixelBuffer(size: size, fill: slot)
        )
      ],
      delayCentiseconds: delays?[index] ?? 10
    )
  }
  return GIFDocument(size: size, palette: palette, frames: frames, loopCount: loopCount)
}
